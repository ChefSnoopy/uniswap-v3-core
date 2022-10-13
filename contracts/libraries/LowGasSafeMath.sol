// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

/// @title 优化了溢出和下漏安全数学操作
/// @notice 包含了处理数学操作时发生溢出和下漏状况时最小的Gas消耗
library LowGasSafeMath {
    /// @notice 返回x + y, 但结果溢出时revert
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    /// @notice 返回x - y, 但结果下漏时revert
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    /// @notice 返回x * y, 但结果溢出时revert
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(x == 0 || (z = x * y) / x == y);
    }

    /// @notice 返回x * y, 但结果溢出或者下漏时revert
    function add(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x + y) >= x == (y >= 0));
    }

    /// @notice 返回x - y, 但结果溢出或者下漏时revert
    function sub(int256 x, int256 y) internal pure returns (int256 z) {
        require((z = x - y) <= x == (y >= 0));
    }
}
