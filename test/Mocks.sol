// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockDexPool
 * @notice Simulates a Uniswap V2 style liquidity pool for testing.
 *         Reserves are set to match real Hacken $HAI pool depth
 *         at time of the June 2025 exploit (~20M HAI tokens).
 */
contract MockDexPool {
    address public token0;
    uint112 private reserve0;
    uint112 private reserve1;

    constructor(address _token0) {
        token0 = _token0;
    }

    function setReserves(uint112 _r0, uint112 _r1) external {
        reserve0 = _r0;
        reserve1 = _r1;
    }

    function getReserves() external view returns (
        uint112,
        uint112,
        uint32
    ) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }
}