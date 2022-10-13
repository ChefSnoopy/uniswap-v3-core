// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3SwapCallback {
    /// @dev 在实现时你必须支付Swap所需的Token数量
    /// 调用方必须检查是否是UniswapV3Factory部署的一个UniswapV3Pool合约
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}
