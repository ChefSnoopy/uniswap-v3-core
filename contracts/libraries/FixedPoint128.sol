// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.4.0;

/// @notice 一个处理二进制定点数的库，请看https://en.wikipedia.org/wiki/Q_(number_format)
library FixedPoint128 {
    uint256 internal constant Q128 = 0x100000000000000000000000000000000;
}
