// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @notice 以下这些函数方法构成了pool的状态，可以在每个transaction中被以任意频率的改变任意的次数
interface IUniswapV3PoolState {
    /// @notice 在pool中存储的第0位的slot，存储了很多的值，从外部访问时作为单独的函数暴露出来以节省Gas
    /// @return sqrtPriceX96 pool中的当前价格的平方根(token1/token0) 定位数 Q64.96
    /// tick pool中的当前tick, i.e. 基于最新的tick transition.
    /// 如果此时的tick处在边界上，可能和SqrtTickMath.getTickAtSqrtRatio(sqrtPriceX96)的值并不相等
    /// observationIndex 最新的oracle observation的index
    /// observationCardinality pool中存储的最大观察次数
    /// observationCardinalityNext 下一个最大观察次数，在观察时被更新
    /// feeProtocol pool中两个Token的protocol费用
    /// unlocked 当前的pool是已经锁定状态
    function slot0()
    external
    view
    returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );

    /// @notice 这个fee growth作为token0的一个定位数 Q128.128，在pool的整个生命周期中表示每个单位的liquidity可被收集的费用
    /// @dev 这个值可能会溢出uint256
    function feeGrowthGlobal0X128() external view returns (uint256);

    /// @notice 这个fee growth作为token1的一个定位数 Q128.128，在pool的整个生命周期中表示每个单位的liquidity可被收集的费用
    /// @dev 这个值可能会溢出uint256
    function feeGrowthGlobal1X128() external view returns (uint256);

    /// @notice 所包含的protocol费用的token0和token1的数量
    /// @dev 每种protocol费用将不会超过uint128的最大值
    function protocolFees() external view returns (uint128 token0, uint128 token1);

    /// @notice pool中当前区间下的liquidity
    /// @dev 这个值与穿过整个tick的总体的liquidity无关
    function liquidity() external view returns (uint128);

    /// @notice 查询指定tick的信息
    /// @param tick 需要查询的tick
    /// @return liquidityGross 无论作为tick lower或者tick upper的头寸的liquidity的总数
    /// liquidityNet 价格穿过tick时多少的liquidity将会改变
    /// feeGrowthOutside0X128 token0中另一侧的fee的增涨
    /// feeGrowthOutside1X128 token1中另一侧的fee的增涨
    /// tickCumulativeOutside 当前tick另一侧的累积tick的值
    /// secondsPerLiquidityOutsideX128 当前tick在另一侧每种liquidity花费的秒数
    /// secondsOutside 从tick另一侧到当前tick花费的秒数
    /// initialized 如果tick已经初始化则设置为true，例如liquidityGross已经大于0时，否则为false
    /// 此外，这些值只是相对值，只能与特定位置的先前快照进行比较。
    function ticks(int24 tick)
    external
    view
    returns (
        uint128 liquidityGross,
        int128 liquidityNet,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        int56 tickCumulativeOutside,
        uint160 secondsPerLiquidityOutsideX128,
        uint32 secondsOutside,
        bool initialized
    );

    /// @notice 返回256位打包好的tick初始化的布尔值
    function tickBitmap(int16 wordPosition) external view returns (uint256);

    /// @notice 根据头寸的key返回头寸的相关信息
    /// @param key 它是一种hash值，由owner， tickLower和tickUpper组成
    /// @return _liquidity 头寸的liquidity数量
    /// Returns feeGrowthInside0LastX128 最新的 mint/burn/poke, 在tick范围内token0的fee的增涨
    /// Returns feeGrowthInside1LastX128 最新的 mint/burn/poke, 在tick范围内token1的fee的增涨
    /// Returns tokensOwed0 最新的 mint/burn/poke, 对应头寸中的token0的数量
    /// Returns tokensOwed1 最新的 mint/burn/poke, 对应头寸中的token1的数量
    function positions(bytes32 key)
    external
    view
    returns (
        uint128 _liquidity,
        uint256 feeGrowthInside0LastX128,
        uint256 feeGrowthInside1LastX128,
        uint128 tokensOwed0,
        uint128 tokensOwed1
    );

    /// @notice 返回指定index的observation
    /// @param index 指定的index
    /// @dev 你可能更希望用#observe()来代替这个方法获取一个在若干时间之前的observation，而不是使用index
    /// @return blockTimestamp 时间戳
    /// Returns tickCumulative 用tick乘以pool中流逝的秒数作为observation的时间戳
    /// Returns secondsPerLiquidityCumulativeX128 截至observation时间戳，pool的生命周期内每liquidity的秒数，
    /// Returns initialized 是否此observation已经初始化并可被安全使用
    function observations(uint256 index)
    external
    view
    returns (
        uint32 blockTimestamp,
        int56 tickCumulative,
        uint160 secondsPerLiquidityCumulativeX128,
        bool initialized
    );
}
