// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Permissionless pool actions
/// @notice Contains pool methods that can be called by anyone
interface IUniswapV3PoolActions {
    /// @notice 为pool设置初始价格
    /// @dev 价格展示为(amountToken1/amountToken0)的平方根，定位数 Q64.96
    /// @param sqrtPriceX96 pool中初始价格的平方根，定位数 Q64.96
    function initialize(uint160 sqrtPriceX96) external;

    /// @notice 为指定的recipient/tickLower/tickUpper头寸添加Liquidity
    /// @dev 此方法的调用者接收IUniswapV3MintCallback#uniswapV3MintCallback的回调，其中必须支付所需的Token0或者Token1的数量
    /// 其中Token0或者Token1的数量取决于tickLower, tickUpper和liquidity的值，以及当前的价格
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice 收集指定头寸的Token（手续费）
    /// @dev 不会重复计算赚取的手续费，通过Mint或者Burn任意数额的Liquidity来完成
    /// 收集只能被头寸的所有者调用，只提现Token0或者Token1时，可以把amount0Requested或者amount1Requested设置为零
    /// 提现所有手续费，只需要传入任何大于实际数额的值，比如uint128的最大值，手续费可能来自于积累的Swap手续费或者Burn Liquidity
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    /// @notice Burn liquidity并将头寸对应的Token归还给发送方
    /// @dev 可以用于触发指定头寸的手续费的重新计算，通过将数额设置为0
    /// 必须通过调用#collect单独执行手续费的收集
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swap token0 for token1, 或 token1 for token0
    /// @dev 这个函数的调用方将会收到一个回调来自于IUniswapV3SwapCallback#uniswapV3SwapCallback
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    /// @notice 接收 token0 并且/或者 token1 然后偿还，并付上相关的费用
    /// @dev 这个函数的调用方将会收到一个回调来自于IUniswapV3FlashCallback#uniswapV3FlashCallback
    /// @dev 可用于按照比例向当前范围内的Liquidity提供方捐赠Tokens，方法是调用数额{0, 1}，然后在回调函数中发送捐赠金额
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;

    /// @notice 增加pool中存储的最大价格和liquidity的observation数量
    /// @dev 如果pool的observationCardinalityNext >= 传入的参数，则此方法不可调用
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}
