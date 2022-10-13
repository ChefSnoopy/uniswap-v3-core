// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3PoolImmutables {
    /// @notice 用于部署pool的合约
    function factory() external view returns (address);

    /// @notice 指定pool中两个Token中的token0
    function token0() external view returns (address);

    /// @notice 指定pool中两个Token中的token1
    function token1() external view returns (address);

    /// @notice 指定pool中fee
    function fee() external view returns (uint24);

    /// @notice 指定pool中TickSpacing
    function tickSpacing() external view returns (int24);

    /// @notice 在范围内可以使用的最大的头寸的liquidity的Tick
    /// @dev 这个参数被强制在每个Tick上防止liquidity不会从uint128中溢出，并且防止范围外的liquidity被用于避免添加in-range的liquidity到pool中
    function maxLiquidityPerTick() external view returns (uint128);
}
