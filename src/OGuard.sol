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
 * @notice An on-chain execution firewall for privileged token actions.
 */
contract OGuard {

    // --- Immutable State ---
    IHAIToken public immutable token;
    address public immutable dexPool;

    // --- Owner ---
    address public owner;

    // --- Dynamic Safety Parameter ---
    uint256 public maxPoolImpactBps;
    uint256 public constant BPS_DENOMINATOR = 10000;

    // --- Epoch Volume Tracking ---
    // Tracks total volume minted inside a strict Unix calendar day
    mapping(uint256 => uint256) public epochDailyVolume;

    // --- Key Registry ---
    enum KeyStatus { UNREGISTERED, ACTIVE, FROZEN }

    struct KeyInfo {
        KeyStatus status; // Fits cleanly into a single uint8 slot
    }

    // Pack validation data tightly for cheap EVM SLOAD execution
    mapping(address => KeyInfo) public keys;
    
    // Separate metadata to separate mapping so validation loops ignore gas-heavy reads
    mapping(address => string) public keyMetadata;

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
    }

    // --- Owner Functions ---

    function registerKey(
        address key,
        string calldata infrastructureTag
    ) external onlyOwner {
        if (key == address(0)) revert ZeroAddress();
        
        keys[key] = KeyInfo({ status: KeyStatus.ACTIVE });
        keyMetadata[key] = infrastructureTag; // Stored separately
        
        emit KeyRegistered(key, infrastructureTag);
    }

    function freezeKey(address key) external onlyOwner {
        keys[key].status = KeyStatus.FROZEN;
        emit KeyFrozen(key);
    }

    function updateMaxPoolImpact(uint256 newBps) external onlyOwner {
        maxPoolImpactBps = newBps;
        emit ParameterUpdated("maxPoolImpactBps", newBps);
    }

    // --- Core Firewall ---

    function requestMint(address to, uint256 amount) external {
        KeyStatus status = keys[msg.sender].status;

        // Rule 1: Key must be registered
        if (status == KeyStatus.UNREGISTERED) {
            emit MintBlocked(msg.sender, amount, "Key not registered");
            revert KeyNotRegistered();
        }

        // Rule 2: Key must be active
        if (status != KeyStatus.ACTIVE) {
            emit MintBlocked(msg.sender, amount, "Key frozen");
            revert KeyNotActive();
        }

        // Rule 3: Strict Epoch-Based Cumulative Volume Cap
        uint256 currentDayEpoch = block.timestamp / 1 days; // Immutably locks reset boundaries
        uint256 global24hMintedVolume = epochDailyVolume[currentDayEpoch];

        // Read live pool depth
        (uint112 reserve0, uint112 reserve1, ) = IMockDexPool(dexPool).getReserves();

        uint256 currentPoolLiquidity = IMockDexPool(dexPool).token0() == address(token)
            ? uint256(reserve0)
            : uint256(reserve1);

        // Calculate dynamic ceiling based on live pool depth
        uint256 dynamicCeiling = (currentPoolLiquidity * maxPoolImpactBps) / BPS_DENOMINATOR;

        // Enforce ceiling
        if (global24hMintedVolume + amount > dynamicCeiling) {
            emit MintBlocked(msg.sender, amount, "Dynamic liquidity ceiling breached");
            revert DynamicLiquidityCeilingBreached();
        }

        // All checks passed — execute mint
        epochDailyVolume[currentDayEpoch] = global24hMintedVolume + amount;
        token.mint(to, amount);
        emit MintExecuted(msg.sender, to, amount);
    }

    // --- View Helpers ---

    function getKeyStatus(address key) external view returns (KeyStatus) {
        return keys[key].status;
    }

    function getDynamicCeiling() external view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IMockDexPool(dexPool).getReserves();
        uint256 liquidity = IMockDexPool(dexPool).token0() == address(token)
            ? uint256(reserve0)
            : uint256(reserve1);
        return (liquidity * maxPoolImpactBps) / BPS_DENOMINATOR;
    }
}
