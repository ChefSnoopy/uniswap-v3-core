// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3MintCallback {
    /// @dev 在实现时你必须支付Mint Liquidity所需的Token数量
    /// 调用方必须检查是否是UniswapV3Factory部署的一个UniswapV3Pool合约
    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external;
}
