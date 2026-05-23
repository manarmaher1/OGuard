// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {HAIToken} from "../src/HAIToken.sol";
import {OGuard} from "../src/OGuard.sol";
import {MockDexPool} from "./Mocks.sol";

/**
 * @title OGuardTest
 * @notice Proof of concept demonstrating that OGuard would have
 *         prevented the June 2025 Hacken $HAI bridge key exploit.
 *
 * Real exploit data:
 * - Attacker: 0x2FA1789B009A05921eB64F10B8F0d30684661d2d
 * - Tokens minted: 900,000,000 HAI
 * - Pool depth at time of hack: ~20,000,000 HAI
 * - Actual damage: ~$253,000
 * - Price impact: -98%
 *
 * With OGuard:
 * - Dynamic ceiling: 1,000,000 HAI (5% of 20M pool)
 * - 900M mint attempt: BLOCKED
 * - Damage: $0
 */
contract OGuardTest is Test {

    HAIToken public token;
    MockDexPool public pool;
    OGuard public oGuard;

    // Multisig owner — in production a Gnosis Safe address
    address public multisig = address(0x1111);

    // Legitimate bridge server key
    address public bridgeServer = address(0x2222);

    // Normal user receiving bridged tokens
    address public user = address(0x3333);

    // Real attacker address from the Hacken exploit
    address public attacker =
        0x2FA1789B009A05921eB64F10B8F0d30684661d2d;

    function setUp() public {
        vm.startPrank(multisig);

        // Deploy HAI token
        token = new HAIToken();

        // Deploy mock pool simulating real Hacken pool depth
        pool = new MockDexPool(address(token));

        // Deploy OGuard with 5% max pool impact
        oGuard = new OGuard(address(token), address(pool), 500);

        // Transfer minting power from raw key to OGuard
        // This is the single change that would have
        // prevented the Hacken hack
        token.transferOwnership(address(oGuard));

        // Register the bridge server key
        // linked to the exact server named in the exploit report
        oGuard.registerKey(
            bridgeServer,
            "droplet-prod-bridge-02"
        );

        // Set pool reserves to match real hack conditions
        // ~20M HAI tokens in pool at time of exploit
        // Dynamic ceiling = 5% = 1,000,000 HAI max per 24h
        pool.setReserves(
            uint112(20_000_000 * 1e18),
            uint112(250_000 * 1e6)
        );

        vm.stopPrank();
    }

    // --------------------------------------------------------
    // Test 1: Normal bridge operations work perfectly
    // --------------------------------------------------------
    function test_NormalMintSucceeds() public {
        console.log("=== TEST 1: NORMAL OPERATIONS ===");
        console.log("Bridge minting 500,000 HAI for user...");
        console.log("Dynamic ceiling: 1,000,000 HAI");
        console.log("Request: 500,000 HAI");

        vm.prank(bridgeServer);
        oGuard.requestMint(user, 500_000 * 1e18);

        assertEq(token.balanceOf(user), 500_000 * 1e18);
        console.log("RESULT: Mint succeeded. Normal operations unaffected.");
    }

    // --------------------------------------------------------
    // Test 2: The Hacken exploit — blocked by OGuard
    // --------------------------------------------------------
    function test_HackenExploitBlocked() public {
        console.log("=== TEST 2: HACKEN EXPLOIT SIMULATION ===");
        console.log("Attacker: 0x2FA1789B009A05921eB64F10B8F0d30684661d2d");
        console.log("Server: droplet-prod-bridge-02 (decommissioned)");
        console.log("Attempting to mint: 900,000,000 HAI");
        console.log("Pool depth: 20,000,000 HAI");
        console.log("Dynamic ceiling: 1,000,000 HAI (5% of pool)");
        console.log("900,000,000 > 1,000,000 --> BLOCKED");

        // Attacker has the stolen key but must go through OGuard
        vm.prank(bridgeServer);
        vm.expectRevert(OGuard.DynamicLiquidityCeilingBreached.selector);
        oGuard.requestMint(attacker, 900_000_000 * 1e18);

        assertEq(token.balanceOf(attacker), 0);
        console.log("RESULT: 900M mint BLOCKED. $0 stolen. Hack prevented.");
    }

    // --------------------------------------------------------
    // Test 3: Unregistered key cannot mint at all
    // --------------------------------------------------------
    function test_UnregisteredKeyBlocked() public {
        console.log("=== TEST 3: UNREGISTERED KEY ===");
        console.log("Attacker using unknown key...");

        vm.prank(attacker);
        vm.expectRevert(OGuard.KeyNotRegistered.selector);
        oGuard.requestMint(attacker, 1000 * 1e18);

        assertEq(token.balanceOf(attacker), 0);
        console.log("RESULT: Unregistered key rejected immediately.");
    }

    // --------------------------------------------------------
    // Test 4: Manual emergency freeze works instantly
    // --------------------------------------------------------
    function test_FrozenKeyBlocked() public {
        console.log("=== TEST 4: EMERGENCY FREEZE ===");
        console.log("Multisig detects suspicious activity...");
        console.log("Freezing droplet-prod-bridge-02 key...");

        vm.prank(multisig);
        oGuard.freezeKey(bridgeServer);

        vm.prank(bridgeServer);
        vm.expectRevert(OGuard.KeyNotActive.selector);
        oGuard.requestMint(attacker, 1000 * 1e18);

        console.log("RESULT: Frozen key rejected. $0 stolen.");
    }

    // --------------------------------------------------------
    // Test 5: Attacker cannot trickle mint either
    // --------------------------------------------------------
    function test_TrickleMintHitsCeiling() public {
        console.log("=== TEST 5: TRICKLE ATTACK ===");
        console.log("Attacker tries splitting into smaller amounts...");

        // First mint — just under ceiling
        vm.prank(bridgeServer);
        oGuard.requestMint(attacker, 950_000 * 1e18);

        console.log("First mint of 950K: passed (under 1M ceiling)");

        // Second mint — would push over ceiling
        vm.prank(bridgeServer);
        vm.expectRevert(OGuard.DynamicLiquidityCeilingBreached.selector);
        oGuard.requestMint(attacker, 100_000 * 1e18);

        // Attacker only got 950K out of 900M needed
        assertEq(token.balanceOf(attacker), 950_000 * 1e18);
        console.log("Second mint blocked. Daily ceiling exhausted.");
        console.log("RESULT: Attacker got 950K of 900M needed. Attack pointless.");
    }
}