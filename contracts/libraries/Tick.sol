// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './TickMath.sol';
import './LiquidityMath.sol';

/// @title Tick
/// @notice 包含管理tick流程的管理函数和相关计算
library Tick {
    using LowGasSafeMath for int256;
    using SafeCast for int256;

    // 为每个独立的tick初始化时存储相关信息
    struct Info {
        // 记录了所有引用此tick的position的liquidity的总和
        uint128 liquidityGross;
        // 从左往右（从右往左）时增加（减少）pool中整体的liquidity需要变化的值
        int128 liquidityNet;
        // 此tick另一侧手续费每单位liquidity的增涨（相对于当前的tick）
        // 只有相对意义，不是绝对 - 该值取决于tick初始化的时机
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        // 此tick另一侧的tick的累积值
        int56 tickCumulativeOutside;
        // 此tick另一侧的每单位liquidity的秒数（相对于当前的tick）
        // 只有相对意义，不是绝对 - 该值取决于tick初始化的时机
        uint160 secondsPerLiquidityOutsideX128;
        // 此tick另一侧的所花费的秒数（相对于当前的tick）
        // 只有相对意义，不是绝对 - 该值取决于tick初始化的时机
        uint32 secondsOutside;
        // 此tick已经初始化的时候为true，i.e. 此值将会和liquidityGross != 0保持一致
        // 只有相对意义，不是绝对 - 该值取决于tick初始化的时机
        bool initialized;
    }

    /// @notice 根据指定的tickSpacing导出每个tick的最大liquidity
    /// @dev 由pool的构建者来执行
    /// @param tickSpacing 要求的tick间隔数量，由`tickSpacing`的倍数决定
    ///     e.g., 当tickSpacing为3时，需要每隔3个tick进行初始化 i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return 每tick的最大liquidity
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        return type(uint128).max / numTicks;
    }

    /// @notice 检索手续费的增涨数据
    /// @param self 包含所有已经初始化过的ticks的一个mapping
    /// @param tickLower 头寸的下边界
    /// @param tickUpper 头寸的上边界
    /// @param tickCurrent 当前的tick
    /// @param feeGrowthGlobal0X128 token0中每单位的liquidity全局手续费的增涨
    /// @param feeGrowthGlobal1X128 token1中每单位的liquidity全局手续费的增涨
    /// @return feeGrowthInside0X128 token0中每单位的liquidity内部手续费的增涨，源自头寸内部tick的边界
    /// @return feeGrowthInside1X128 token1中每单位的liquidity内部手续费的增涨，源自头寸内部tick的边界
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 tickLower,
        int24 tickUpper,
        int24 tickCurrent,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Info storage lower = self[tickLower];
        Info storage upper = self[tickUpper];

        // 计算手续费的增涨的下端 f_b(i)
        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (tickCurrent >= tickLower) {
            feeGrowthBelow0X128 = lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lower.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128;
        }

        // 计算手续费的增涨的上端 f_a(i)
        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (tickCurrent < tickUpper) {
            feeGrowthAbove0X128 = upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upper.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upper.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upper.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }

    /// @notice 更新一个tick并在此tick从初始化状态变为非初始化状态时返回true，反之亦然
    /// @param self 包含所有已经初始化过的ticks的一个mapping
    /// @param tick 将要被更新的tick
    /// @param tickCurrent 当前的tick
    /// @param liquidityDelta 当价格从左往右（从右往左）穿过此tick时的liquidityDelta的增加（减少）
    /// @param feeGrowthGlobal0X128 token0中每单位的liquidity全局手续费的增涨
    /// @param feeGrowthGlobal1X128 token1中每单位的liquidity全局手续费的增涨
    /// @param secondsPerLiquidityCumulativeX128 pool中每个max(1, liquidity)的所有秒数
    /// @param tickCumulative 从pool初始化开始，tick * time的流逝
    /// @param time 当前区块的时间戳uint32
    /// @param upper 如果更新的是一个头寸的上边界则为true，如果更新的是一个头寸的下边界则为false
    /// @param maxLiquidity 单个tick所分配到的最大的liquidity
    /// @return flipped 此tick从初始化状态变为非初始化状态时返回true，反之亦然
    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 tickCurrent,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Tick.Info storage info = self[tick];

        // 获取此tick更新之前的流动性
        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, 'LO');

        // 通过liquidityGross在进行position变化前后的值
        // 来判断tick是否被引用
        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        // 如果此tick在更新之前的liquidityGross为0，那么表示我们本次为初始化操作
        // 这里面会初始化tick中的f_o
        if (liquidityGrossBefore == 0) {
            // 按照惯例，我们假设一个tick在初始化之前所有的增涨都发生在tick之下
            if (tick <= tickCurrent) {
                info.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
                info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128;
                info.tickCumulativeOutside = tickCumulative;
                info.secondsOutside = time;
            }
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // 当价格从左往右（从右往左）穿过此tick时的liquidity的增加（减少）
        info.liquidityNet = upper
            ? int256(info.liquidityNet).sub(liquidityDelta).toInt128()
            : int256(info.liquidityNet).add(liquidityDelta).toInt128();
    }

    /// @notice 清空tick的数据
    /// @param self 包含所有已经初始化过的ticks的一个mapping
    /// @param tick 将被清空的tick
    function clear(mapping(int24 => Tick.Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    /// @notice Transitions to next tick as needed by price movement
    /// @param self 包含所有已经初始化过的ticks的一个mapping
    /// @param tick 这个transaction中的目标tick
    /// @param feeGrowthGlobal0X128 token0中每单位的liquidity全局手续费的增涨
    /// @param feeGrowthGlobal1X128 token1中每单位的liquidity全局手续费的增涨
    /// @param secondsPerLiquidityCumulativeX128 pool中每个max(1, liquidity)的所有秒数
    /// @param tickCumulative 从pool初始化开始，tick * time的流逝
    /// @param time 当前区块的时间戳
    /// @return liquidityNet 当价格从左往右（从右往左）穿过此tick时的liquidityDelta的增加（减少）
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        uint160 secondsPerLiquidityCumulativeX128,
        int56 tickCumulative,
        uint32 time
    ) internal returns (int128 liquidityNet) {
        Tick.Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        info.secondsPerLiquidityOutsideX128 = secondsPerLiquidityCumulativeX128 - info.secondsPerLiquidityOutsideX128;
        info.tickCumulativeOutside = tickCumulative - info.tickCumulativeOutside;
        info.secondsOutside = time - info.secondsOutside;
        liquidityNet = info.liquidityNet;
    }
}