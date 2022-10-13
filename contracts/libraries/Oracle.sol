// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;
import 'hardhat/console.sol';

/// @title Oracle
/// @notice 提供价格和liquidity数据对广泛多样的系统设计提供帮助
/// @dev 存储oracle数据, "observations", 并将其放在一个数组中
/// 每个pool都使用长度为1的oracle数组进行初始化，任何人都可以支持SSTORE来增加oracle数组的最大长度，当数组中已经存满后新的插槽将会添加进来
/// Observations 当数组填满后将会循环覆盖存储
/// 传入0可以获得最近的observation，与oracle数组的长度无关
library Oracle {
    struct Observation {
        // 所观察区块的时间戳
        uint32 blockTimestamp;
        // tick index的时间加权累积值，i.e. 即pool自初始化以来tick * time的流逝
        int56 tickCumulative;
        // 价格所在区间的流动性liquidity的时间加权累积值, i.e. pool中秒数/max(1, liquidity)
        uint160 secondsPerLiquidityCumulativeX128;
        // 此observation是否已经初始化
        bool initialized;
    }

    /// @notice 传入区块时间戳、当前的tick和liquidity，将上一个observation转换为新的observation
    /// @dev blockTimestamp 必须大于或等于上一个时间，对0或1溢出安全
    /// @param last 指定要转移的observation
    /// @param blockTimestamp 新observation的时间戳
    /// @param tick 新observation的活跃tick
    /// @param liquidity 新observation的liquidity区间
    /// @return Observation 新observation
    function transform(
        Observation memory last,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity
    ) private pure returns (Observation memory) {
        // 上次Oracle数据和本次的时间差
        uint32 delta = blockTimestamp - last.blockTimestamp;
        return
            Observation({
                blockTimestamp: blockTimestamp,
                // 计算tick index的时间加权累积值
                tickCumulative: last.tickCumulative + int56(tick) * delta,
                // 计算流动性的时间加权累积值
                secondsPerLiquidityCumulativeX128: last.secondsPerLiquidityCumulativeX128 + 
		            ((uint160(delta) << 128) / (liquidity > 0 ? liquidity : 1)),
                initialized: true
            });
    }

    /// @notice 初始化过程是写入第一个插槽，在observation数组整个生命周期中只被调用一次
    /// @param self 存储的oracle数组
    /// @param time 初始化时的时间为区块时间戳 uint32
    /// @return cardinality oracle数组中填充的元素长度
    /// @return cardinalityNext oracle数组中的新长度，与填充的元素无关
    function initialize(Observation[65535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({
            blockTimestamp: time,
            tickCumulative: 0,
            secondsPerLiquidityCumulativeX128: 0,
            initialized: true
        });
        return (1, 1);
    }

    /// @notice 将一个observation写入数组
    /// @dev 每区块最多写一次，索引表示最近写入的元素，cardinality和index必须被外部可追踪
    /// 如果index处于允许的数组长度的结尾（根据cardinality），并且next cardinality大于当前值，cardinality将会增加，创建这个限制是保持顺序
    /// @param self 存储的oracle数组
    /// @param index 最近被写入数组的observation的index
    /// @param blockTimestamp 新observation的区块时间戳
    /// @param tick 新observation此时所在的tick
    /// @param liquidity 新observation此时所在的liquidity区间
    /// @param cardinality oracle数组已经填充的元素的长度
    /// @param cardinalityNext oracle数组中的新长度，与填充的元素无关
    /// @return indexUpdated 最近被写入数组的observation的新index
    /// @return cardinalityUpdated 更新后的cardinality
    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 blockTimestamp,
        int24 tick,
        uint128 liquidity,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        // 获取当前的Oracle数据
        Observation memory last = self[index];

        // 如果当前的区块已经写入了一个observation直接返回，只会在第一笔交易中写入Oracle数据
        if (last.blockTimestamp == blockTimestamp) return (index, cardinality);

        // 检查是否需要使用新的数组空间
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        // 本次写入的index（索引），使用余数实现ring buffer
        indexUpdated = (index + 1) % cardinalityUpdated;
        // 写入Oracle数据
        self[indexUpdated] = transform(last, blockTimestamp, tick, liquidity);
    }

    /// @notice 准备好oracle数组以存储`next`的observations
    /// @param self 存储的oracle数组
    /// @param current 当前的next cardinality
    /// @param next 填充到oracle数组中的建议的next cardinality
    /// @return next 填充到oracle数组中的next cardinality
    function grow(
        Observation[65535] storage self,
        uint16 current,
        uint16 next
    ) internal returns (uint16) {
        require(current > 0, 'I');
        // 如果传入的next的值没有比当前next的值更大则返回
        if (next <= current) return current;
        // 对数组中将来可能会用到的槽位进行写入，以初始化其空间，避免在swap中初始化
        for (uint16 i = current; i < next; i++) self[i].blockTimestamp = 1;
        return next;
    }

    /// @notice 32-bit 时间戳比较器
    /// @dev 对0或1安全, a和b必须早于或等于此时间戳
    /// @param time 一个32-bit裁剪后的时间戳
    /// @param a 一个用于确定相对位置的比较`时间戳`
    /// @param b 一个用于确定相对位置的比较`时间戳`
    /// @return bool 是否`a`按照年代次序小于`b`
    function lte(
        uint32 time,
        uint32 a,
        uint32 b
    ) private pure returns (bool) {
        // 如果还没有溢出，不需要判断
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2**32;
        uint256 bAdjusted = b > time ? b : b + 2**32;

        return aAdjusted <= bAdjusted;
    }

    /// @notice 获取目标observations的beforeOrAt和atOrAfter, i.e. 其中 [beforeOrAt, atOrAfter] 满足条件.
    /// 结果可能是相同的observation，也可以是相邻的observations
    /// @dev 答案必须包含在数组中，当目标定位在已存储的observation边界内时使用：比最近的observation老，比最早的observation小，或者与最早的observation相同
    /// @param self 当前存储的oracle数组
    /// @param time 当前的区块时间戳
    /// @param target 应该存储observation的时间戳
    /// @param index 最近写入数组的observation的index
    /// @param cardinality oracle数组已经填充的元素的长度
    /// @return beforeOrAt 目标更早或当前的observation
    /// @return atOrAfter 目标更晚或当前的observation
    function binarySearch(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        uint256 l = (index + 1) % cardinality; // 最早的observation
        uint256 r = l + cardinality - 1; // 最新的observation
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            // 如果找到一个未初始化的tick，保持搜索更高的（更接近的）
            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.blockTimestamp, target);
            
            // 判断我们是否得到答案
            if (targetAtOrAfter && lte(time, target, atOrAfter.blockTimestamp)) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    /// @notice 获取目标observations的beforeOrAt和atOrAfter, i.e. 其中 [beforeOrAt, atOrAfter] 满足条件.
    /// @dev 假设至少存在一个已经初始化过的observation
    /// 用于observeSingle() 计算指定区块时间戳的反事实的累加器值
    /// @param self 当前存储的oracle数组
    /// @param time 当前的区块时间戳
    /// @param target 应该存储observation的时间戳
    /// @param tick 被返回的或者被模拟的此observation时间上的活跃tick
    /// @param index 最近写入数组的observation的index
    /// @param liquidity 调用时的全部liquidity
    /// @param cardinality oracle数组已经填充的元素的长度
    /// @return beforeOrAt 目标更早或当前的observation
    /// @return atOrAfter 目标更晚或当前的observation
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // 先将beforeOrAt设置为当前最新数据
        beforeOrAt = self[index];

        // 检查beforeOrAt是否 <= target
        if (lte(time, beforeOrAt.blockTimestamp, target)) {
            if (beforeOrAt.blockTimestamp == target) {
                // 如果时间戳相等，那么可以忽略atOrAfter直接返回
                return (beforeOrAt, atOrAfter);
            } else {
                // 当前区块中发生代币对的交易之间请求此函数时可能会发生这种情况
                // 需将当前还未持久化的数据，封闭成一个Oracle数据并返回
                return (beforeOrAt, transform(beforeOrAt, target, tick , liquidity));
            }
        }

        // 将beforeOrAt调整为Oracle数组中最老的数据
        // 即为当前的index的下一个数据，或index为0的数据
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        // 保证target是按时间次序at or after最老的observation
        require(lte(time, beforeOrAt.blockTimestamp, target), 'OLD');

        // 然后通过二分查找的方式找到离目标时间点最近的前后两个Oracle数据
        return binarySearch(self, time, target, index, cardinality);
    }

    /// @dev 如果一个observation在更早或者当前期望得到的observation时间戳不存在则revert
    /// 返回当前累积值可以传入secondsAgo为0
    /// 如果调用一个时间戳落于两个observations之间，则返回精确的时间戳在两个observations的反事实的累积值
    /// @param self 当前存储的oracle数组
    /// @param time 当前的区块时间戳
    /// @param secondsAgo 返回observation的回溯时间（seconds）
    /// @param tick 当前的tick
    /// @param index 最近写入数组的observation的index
    /// @param liquidity pool中当前范围内的liquidity
    /// @param cardinality oracle数组已经填充的元素的长度
    /// @return tickCumulative 类似`secondsAgo`，pool中从初始化至今的tick * time的流逝
    /// @return secondsPerLiquidityCumulativeX128 类似`secondsAgo`，pool中从初始化至今的time流逝 max(1, liquidity)
    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) {
        // secondsAgo为0表示当前最新的Oracle数据
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            if (last.blockTimestamp != time) last = transform(last, time, tick, liquidity);
            return (last.tickCumulative, last.secondsPerLiquidityCumulativeX128);
        }

        // 计算出请求时间戳
        uint32 target = time - secondsAgo;

        // 计算出请求时间戳最近的两个Oracle数据
        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, liquidity, cardinality);

        // 如果请求时间戳和返回的左侧时间戳相等，那么可以直接使用
        if (target == beforeOrAt.blockTimestamp) {
            return (beforeOrAt.tickCumulative, beforeOrAt.secondsPerLiquidityCumulativeX128);
        // 如果请求时间戳和返回的右侧时间戳相等，那么可以直接使用
        } else if (target == atOrAfter.blockTimestamp) {
            return (atOrAfter.tickCumulative, atOrAfter.secondsPerLiquidityCumulativeX128);
        } else {
            // 如果请求时间戳处于中间，计算根据增长率得出的请求时间点的Oracle值并返回
            uint32 observationTimeDelta = atOrAfter.blockTimestamp - beforeOrAt.blockTimestamp;
            uint32 targetDelta = target - beforeOrAt.blockTimestamp;
            return (
                beforeOrAt.tickCumulative +
                    ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / observationTimeDelta) *
                    targetDelta,
                beforeOrAt.secondsPerLiquidityCumulativeX128 +
                    uint160(
                        (uint256(
                            atOrAfter.secondsPerLiquidityCumulativeX128 - beforeOrAt.secondsPerLiquidityCumulativeX128
                        ) * targetDelta) / observationTimeDelta
                    )
            );
        }
    }

    /// @notice `secondsAgos`数组中返回从给定时间开始的每秒钟的累加器值
    /// @dev 如果 `secondsAgos` > 最早的observation
    /// @param self 当前存储的oracle数组
    /// @param time 当前的区块时间戳
    /// @param secondsAgos 返回observation的回溯时间（秒）
    /// @param tick 当前的tick
    /// @param index 最近写入数组的observation的index
    /// @param liquidity pool中当前范围内的liquidity
    /// @param cardinality oracle数组已经填充的元素的长度
    /// @return tickCumulatives 类似`secondsAgo`，pool中从初始化至今的tick * time的流逝
    /// @return secondsPerLiquidityCumulativeX128s 类似`secondsAgo`，pool中从初始化至今的time流逝 max(1, liquidity)
    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint128 liquidity,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) {
        require(cardinality > 0, 'I');

        tickCumulatives = new int56[](secondsAgos.length);
        secondsPerLiquidityCumulativeX128s = new uint160[](secondsAgos.length);
        // 遍历传入的时间参数，获取结果
        for (uint256 i = 0; i < secondsAgos.length; i++) {
            (tickCumulatives[i], secondsPerLiquidityCumulativeX128s[i]) = observeSingle(
                self,
                time,
                secondsAgos[i],
                tick,
                index,
                liquidity,
                cardinality
            );
        }
    }
}
