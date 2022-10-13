// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.6.0;

import '../interfaces/IERC20Minimal.sol';

library TransferHelper {
    /// @notice 在Token合约里面从msg.sender到recipient发送Token
    /// @dev 在token合约中调用，如果转移失败会报TF错误
    /// @param token 将被转移的token的合约地址
    /// @param to 接受者的地址
    /// @param value 转移的金额
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
        token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }
}
