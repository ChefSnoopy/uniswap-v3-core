// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @notice 包含可以提供pool计算而非存储在区块链上的信息的view函数，这些函数可能会造成Gas的消耗
interface IUniswapV3PoolDerivedState {
    /// @notice 返回累积的Tick和Liquidity，基于当前区块的时间戳往前'secondsAgo'
    /// @dev 想要获取一个时间加权平均的Tick或者Liquidity-in-range，你必须包含2个参数来调用这个函数，其一是period的起点，其二是period的终点
    /// E.g.,想要获取上个小时的时间加权平均Tick，你必须传入的 seconddsAgo=[3600,0]
    function observe(uint32[] calldata secondsAgos)
    external
    view
    returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s);

    /// @notice 返回Tick累积的快照，每个liquidity的秒数和Tick范围内的秒数
    /// @dev 快照只能和其它快照进行比较，接管一个头寸存在的period
    /// 例如，当一个头寸在第一个快照和第二个快照之间没有保持住的时候，快照不能被比较
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
    external
    view
    returns (
        int56 tickCumulativeInside,
        uint160 secondsPerLiquidityInsideX128,
        uint32 secondsInside
    );
}
