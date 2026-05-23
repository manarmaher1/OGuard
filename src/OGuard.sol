// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IHAIToken {
    function mint(address to, uint256 amount) external;
}

interface IMockDexPool {
    function getReserves() external view returns (
        uint112 reserve0,
        uint112 reserve1,
        uint32 blockTimestampLast
    );
    function token0() external view returns (address);
}

/**
 * @title OGuard
 * @notice A post-deployment execution firewall for privileged token actions.
 * @dev Sits between privileged keys and the token contract they control.
 *      Enforces a dynamic liquidity-aware mint ceiling to prevent
 *      catastrophic supply inflation from compromised keys.
 *      Designed to prevent the class of exploit demonstrated in the
 *      June 2025 Hacken $HAI bridge key compromise.
 */
contract OGuard {

    // --- Immutable State ---
    IHAIToken public immutable token;
    address public immutable dexPool;

    // --- Owner ---
    // In production this should be a Gnosis Safe multisig address
    address public owner;

    // --- Dynamic Safety Parameter ---
    // Configurable by owner only. Default 1000 = 10% of pool liquidity.
    // Owner adjusts this based on actual bridge operational needs.
    uint256 public maxPoolImpactBps;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // --- Rolling 24h Window Tracking ---
    uint256 public global24hMintedVolume;
    uint256 public lastGlobalResetTimestamp;

    // --- Key Registry ---
    enum KeyStatus { UNREGISTERED, ACTIVE, FROZEN }

    struct KeyInfo {
        KeyStatus status;
        string infrastructureTag; // e.g. "droplet-prod-bridge-02"
    }

    mapping(address => KeyInfo) public keys;

    // --- Errors ---
    error NotOwner();
    error KeyNotRegistered();
    error KeyNotActive();
    error DynamicLiquidityCeilingBreached();
    error ZeroAddress();

    // --- Events ---
    event KeyRegistered(address indexed key, string infrastructureTag);
    event KeyFrozen(address indexed key);
    event MintExecuted(address indexed key, address to, uint256 amount);
    event MintBlocked(address indexed key, uint256 amount, string reason);
    event ParameterUpdated(string param, uint256 newValue);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address _token,
        address _dexPool,
        uint256 _maxPoolImpactBps
    ) {
        if (_token == address(0)) revert ZeroAddress();
        if (_dexPool == address(0)) revert ZeroAddress();
        token = IHAIToken(_token);
        dexPool = _dexPool;
        owner = msg.sender;
        maxPoolImpactBps = _maxPoolImpactBps;
        lastGlobalResetTimestamp = block.timestamp;
    }

    // --- Owner Functions ---

    /**
     * @notice Register a privileged key with its infrastructure tag.
     * @param key The address of the privileged key.
     * @param infrastructureTag Human-readable infrastructure identifier.
     */
    function registerKey(
        address key,
        string calldata infrastructureTag
    ) external onlyOwner {
        if (key == address(0)) revert ZeroAddress();
        keys[key] = KeyInfo({
            status: KeyStatus.ACTIVE,
            infrastructureTag: infrastructureTag
        });
        emit KeyRegistered(key, infrastructureTag);
    }

    /**
     * @notice Freeze a compromised or decommissioned key immediately.
     * @param key The address to freeze.
     */
    function freezeKey(address key) external onlyOwner {
        keys[key].status = KeyStatus.FROZEN;
        emit KeyFrozen(key);
    }

    /**
     * @notice Update the maximum allowed pool impact.
     * @param newBps New basis points value. 1000 = 10%.
     */
    function updateMaxPoolImpact(uint256 newBps) external onlyOwner {
        maxPoolImpactBps = newBps;
        emit ParameterUpdated("maxPoolImpactBps", newBps);
    }

    // --- Core Firewall ---

    /**
     * @notice The only way to mint tokens. All requests pass through
     *         this firewall before execution.
     * @param to Recipient of minted tokens.
     * @param amount Amount of tokens to mint.
     */
    function requestMint(address to, uint256 amount) external {
        KeyInfo memory info = keys[msg.sender];

        // Rule 1: Key must be registered
        if (info.status == KeyStatus.UNREGISTERED) {
            emit MintBlocked(msg.sender, amount, "Key not registered");
            revert KeyNotRegistered();
        }

        // Rule 2: Key must be active
        if (info.status != KeyStatus.ACTIVE) {
            emit MintBlocked(msg.sender, amount, "Key frozen");
            revert KeyNotActive();
        }

        // Rule 3: Dynamic liquidity ceiling
        // Reset 24h window if needed
        if (block.timestamp >= lastGlobalResetTimestamp + 1 days) {
            global24hMintedVolume = 0;
            lastGlobalResetTimestamp = block.timestamp;
        }

        // Read live pool depth
        (uint112 reserve0, uint112 reserve1, ) =
            IMockDexPool(dexPool).getReserves();

        uint256 currentPoolLiquidity =
            IMockDexPool(dexPool).token0() == address(token)
                ? uint256(reserve0)
                : uint256(reserve1);

        // Calculate dynamic ceiling based on live pool depth
        uint256 dynamicCeiling =
            (currentPoolLiquidity * maxPoolImpactBps) / BPS_DENOMINATOR;

        // Enforce ceiling
        if (global24hMintedVolume + amount > dynamicCeiling) {
            emit MintBlocked(
                msg.sender,
                amount,
                "Dynamic liquidity ceiling breached"
            );
            revert DynamicLiquidityCeilingBreached();
        }

        // All checks passed — execute mint
        global24hMintedVolume += amount;
        token.mint(to, amount);
        emit MintExecuted(msg.sender, to, amount);
    }

    // --- View Helpers ---

    function getKeyStatus(address key) external view returns (KeyStatus) {
        return keys[key].status;
    }

    function getDynamicCeiling() external view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) =
            IMockDexPool(dexPool).getReserves();
        uint256 liquidity =
            IMockDexPool(dexPool).token0() == address(token)
                ? uint256(reserve0)
                : uint256(reserve1);
        return (liquidity * maxPoolImpactBps) / BPS_DENOMINATOR;
    }
}