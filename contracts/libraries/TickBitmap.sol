// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './BitMath.sol';

/// @title 打包tick初始化状态的库
/// @notice 存储tick索引和初始化状态的一个压缩后的mapping
/// @dev 这个mapping采用int16作为键，所有的ticks表现为int24，每个word有256(2^8)个值
library TickBitmap {
    /// @notice 计算tick的初始化bit在mapping中的位置
    /// @param tick 此tick用于计算位置
    /// @return wordPos 此mapping中包含存储bit的word
    /// @return bitPos 在word中存储标志的bit位置
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(tick % 256);
    }

    /// @notice 将指定tick的初始化状态从false转换为true，反之亦然
    /// @param self 待转换tick所在的mapping
    /// @param tick 待转换tick
    /// @param tickSpacing 此ticks的间隔
    function flipTick(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing
    ) internal {
        require(tick % tickSpacing == 0); // 确保此tick是有间隔的
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice 返回下一个初始化过的tick所在相同的word，指定tick左侧（小于或等于）或右侧（大于或等于）
    /// @param self 下一个初始化过的tick所在的mapping
    /// @param tick 开始的tick
    /// @param tickSpacing 可用ticks的间隔空间
    /// @param lte 是否检索下一个tick的左侧（小于或等于开始的tick）
    /// @return next 下一个初始化或者未初始化的tick距离当前的tick最多不超过256个
    /// @return initialized 下一个tick是否初始化，正如函数只会检索256个
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // 朝着负无穷趋近

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // 所有当前的tick或者右侧的bitPos的1s
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            // 如果当前tick右侧或者当前的tick没有初始化过的tick，则返回最右边的tick
            initialized = masked != 0;
            // 溢出/下漏是可能存在的，但通过限制tick和tickSpacing从外部防止了
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // 开始于word中下一个tick的位置，因为当前tick的状态无关紧要
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // 所有当前的tick或者左侧的bitPos的1s
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            // 如果当前tick左侧或者当前的tick没有初始化过的tick，则返回最左边的tick
            initialized = masked != 0;
            // 溢出/下漏是可能存在的，但通过限制tick和tickSpacing从外部防止了
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }
}
