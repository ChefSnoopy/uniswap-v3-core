// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3FlashCallback {
    /// @dev 在实现时你必须支付flash所需偿还的Token数量
    /// 调用方必须检查是否是UniswapV3Factory部署的一个UniswapV3Pool合约
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external;
}
