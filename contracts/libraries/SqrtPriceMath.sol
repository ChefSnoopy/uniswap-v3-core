// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './LowGasSafeMath.sol';
import './SafeCast.sol';

import './FullMath.sol';
import './UnsafeMath.sol';
import './FixedPoint96.sol';

/// @title 函数基于Q64.96的平方根和liquidity
/// @notice 包含使用价格Q64.96的平方根和liquidity计算有力a的数学公式
library SqrtPriceMath {
    using LowGasSafeMath for uint256;
    using SafeCast for uint256;

    /// @notice 获取给定delta的token0的下一个价格平方根
    /// @dev 总是四舍五入，因为在精确的output情况下（increasing price），
    /// 我们需要将价格移动至少足够远，以获得desired output amount，而在精确的输入情况下（decreasing price），为了不发送太多的output，我们需要降低价格
    /// 这个最精确的公式是 liquidity * sqrtPX96 / (liquidity +- amount * sqrtPX96),
    /// 如果因为溢出的原因, 我们可以计算 liquidity / (liquidity / sqrtPX96 +- amount).
    /// @param sqrtPX96 起始价格, i.e. 在计算token0的增量之前
    /// @param liquidity 使用到的liquidity的数量
    /// @param amount 需要增加/减少多少token0，来自于虚拟存量
    /// @param add 标识是增加/减少token0
    /// @return 添加或删除金额后的价格，取决于add
    function getNextSqrtPriceFromAmount0RoundingUp(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // 我们短路amount == 0，因为结果不能保证相等于输入价格
        if (amount == 0) return sqrtPX96;
        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;

        if (add) {
            uint256 product;
            if ((product = amount * sqrtPX96) / amount == sqrtPX96) {
                uint256 denominator = numerator1 + product;
                if (denominator >= numerator1)
                    // 总是存在 160 bits
                    return uint160(FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator));
            }

            return uint160(UnsafeMath.divRoundingUp(numerator1, (numerator1 / sqrtPX96).add(amount)));
        } else {
            uint256 product;
            // 如果产品溢出，我们知道分母下漏
            // 此外，我们必须检查分母是否下漏
            require((product = amount * sqrtPX96) / amount == sqrtPX96 && numerator1 > product);
            uint256 denominator = numerator1 - product;
            return FullMath.mulDivRoundingUp(numerator1, sqrtPX96, denominator).toUint160();
        }
    }

    /// @notice 获取给定delta的token1的下一个价格平方根
    /// @dev 总是四舍五入，因为在精确的输出情况下（decreasing price）
    /// 我们需要将价格移动至少足够远，以获得desired output amount，而在精确的输入情况下（increasing price），我们要将价格移动得更小，以避免output过多
    /// 我们的计算公式为 within <1 wei 无损版本的: sqrtPX96 +- amount / liquidity
    /// @param sqrtPX96 起始价格, i.e. 在计算token1的增量之前
    /// @param liquidity 使用到的liquidity的数量
    /// @param amount 需要增加/减少多少token1，来自于虚拟存量
    /// @param add 标识是增加/减少token1
    /// @return 添加或删除金额后的价格，取决于add
    function getNextSqrtPriceFromAmount1RoundingDown(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amount,
        bool add
    ) internal pure returns (uint160) {
        // 如果我们是加法（减法），四舍五入要求商向下（向上）取整
        // 在这两种情况下，避免对大多数输入使用mulDiv
        if (add) {
            uint256 quotient =
            (
            amount <= type(uint160).max
            ? (amount << FixedPoint96.RESOLUTION) / liquidity
            : FullMath.mulDiv(amount, FixedPoint96.Q96, liquidity)
            );

            return uint256(sqrtPX96).add(quotient).toUint160();
        } else {
            uint256 quotient =
            (
            amount <= type(uint160).max
            ? UnsafeMath.divRoundingUp(amount << FixedPoint96.RESOLUTION, liquidity)
            : FullMath.mulDivRoundingUp(amount, FixedPoint96.Q96, liquidity)
            );

            require(sqrtPX96 > quotient);
            // always fits 160 bits
            return uint160(sqrtPX96 - quotient);
        }
    }

    /// @notice 获取给定输入量token0或token1的下一个价格平方根
    /// @dev 如果价格或liquidity为0，或者如果下一个价格超出界限，则抛出
    /// @param sqrtPX96 起始价格, i.e. 在计算token1的增量之前
    /// @param liquidity 使用到的liquidity的数量
    /// @param amountIn 输入多少数量的token0或者token1
    /// @param zeroForOne 数量为token0还是token1
    /// @return sqrtQX96 添加token0或者token1若干数量后的价格
    function getNextSqrtPriceFromInput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountIn,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 四舍五入以确保我们不会超过目标价格
        return
        zeroForOne
        ? getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountIn, true)
        : getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountIn, true);
    }

    /// @notice 获取给定输出量token0或token1的下一个价格平方根
    /// @dev 如果价格或liquidity为0，或者如果下一个价格超出界限，则抛出
    /// @param sqrtPX96 起始价格, i.e. 在计算token1的增量之前
    /// @param liquidity 使用到的liquidity的数量
    /// @param amountOut 输出多少数量的token0或者token1
    /// @param zeroForOne 数量为token0还是token1
    /// @return sqrtQX96 移除token0或者token1若干数量后的价格
    function getNextSqrtPriceFromOutput(
        uint160 sqrtPX96,
        uint128 liquidity,
        uint256 amountOut,
        bool zeroForOne
    ) internal pure returns (uint160 sqrtQX96) {
        require(sqrtPX96 > 0);
        require(liquidity > 0);

        // 四舍五入以确保我们通过目标价格
        return
        zeroForOne
        ? getNextSqrtPriceFromAmount1RoundingDown(sqrtPX96, liquidity, amountOut, false)
        : getNextSqrtPriceFromAmount0RoundingUp(sqrtPX96, liquidity, amountOut, false);
    }

    /// @notice 获取两个价格之间amount0的增量
    /// @dev 计算 liquidity / sqrt(lower) - liquidity / sqrt(upper),
    /// i.e. liquidity * (sqrt(upper) - sqrt(lower)) / (sqrt(upper) * sqrt(lower))
    /// @param sqrtRatioAX96 一个价格平方根
    /// @param sqrtRatioBX96 另一个价格平方根
    /// @param liquidity 使用到的liquidity的数量
    /// @param roundUp 是向上舍入还是向下舍入金额
    /// @return amount0 覆盖两个通过价格之间的规模流动性头寸所需的token0金额
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount0) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        uint256 numerator1 = uint256(liquidity) << FixedPoint96.RESOLUTION;
        uint256 numerator2 = sqrtRatioBX96 - sqrtRatioAX96;

        require(sqrtRatioAX96 > 0);

        return
            roundUp
            ? UnsafeMath.divRoundingUp(
                FullMath.mulDivRoundingUp(numerator1, numerator2, sqrtRatioBX96),
                sqrtRatioAX96
            )
            : FullMath.mulDiv(numerator1, numerator2, sqrtRatioBX96) / sqrtRatioAX96;
    }

    /// @notice 获取两个价格之间amount1的增量
    /// @dev 计算 liquidity * (sqrt(upper) - sqrt(lower))
    /// @param sqrtRatioAX96 一个价格平方根
    /// @param sqrtRatioBX96 另一个价格平方根
    /// @param liquidity 使用到的liquidity的数量
    /// @param roundUp 是向上舍入还是向下舍入金额
    /// @return amount1 覆盖两个通过价格之间的规模流动性头寸所需的token1金额
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        uint128 liquidity,
        bool roundUp
    ) internal pure returns (uint256 amount1) {
        if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

        return
        roundUp
        ? FullMath.mulDivRoundingUp(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96)
        : FullMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, FixedPoint96.Q96);
    }

    /// @notice 获取有向token0数量的助手方法
    /// @param sqrtRatioAX96 一个价格平方根
    /// @param sqrtRatioBX96 另一个价格平方根
    /// @param liquidity 要计算金额的流动性amount0 delta
    /// @return amount0 两个价格之间传递的liquidityDelta对应的token0的amount
    function getAmount0Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount0) {
        return
        liquidity < 0
        ? -getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
        : getAmount0Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }

    /// @notice 获取有向token1数量的助手方法
    /// @param sqrtRatioAX96 一个价格平方根
    /// @param sqrtRatioBX96 另一个价格平方根
    /// @param liquidity 要计算金额的流动性amount1 delta
    /// @return amount1 两个价格之间传递的liquidityDelta对应的token1的amount
    function getAmount1Delta(
        uint160 sqrtRatioAX96,
        uint160 sqrtRatioBX96,
        int128 liquidity
    ) internal pure returns (int256 amount1) {
        return
        liquidity < 0
        ? -getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(-liquidity), false).toInt256()
        : getAmount1Delta(sqrtRatioAX96, sqrtRatioBX96, uint128(liquidity), true).toInt256();
    }
}
