// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @notice 包含只能被工厂owner调用的函数方法
interface IUniswapV3PoolOwnerActions {
    /// @notice 设置protocol费用的百分比的分母
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;

    /// @notice 收集累积到pool中的protocol费用
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}
