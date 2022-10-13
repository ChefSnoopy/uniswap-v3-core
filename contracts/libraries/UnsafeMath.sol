// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

library UnsafeMath {
    /// @notice 返回 ceil(x / y)
    /// @dev 除以0无实际意义，并且必须外部进行有效性检查
    function divRoundingUp(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(div(x, y), gt(mod(x, y), 0))
        }
    }
}
