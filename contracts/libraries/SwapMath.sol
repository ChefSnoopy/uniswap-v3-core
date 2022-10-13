// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import './FullMath.sol';
import './SqrtPriceMath.sol';

library SwapMath {
    /// @notice 根据swap的参数，计算swap某些金额的输入amount或输出amount
    /// @dev 如果swap的"amountSpecified"为正数，则费用加上中的金额永远不会超过剩余金额
    /// @param sqrtRatioCurrentX96 池的当前价格平方根
    /// @param sqrtRatioTargetX96 不能超过的价格，据此推断swap方向
    /// @param liquidity 使用的liquidity数量
    /// @param amountRemaining 输入/输出amount还剩余，经过swapped in/out
    /// @param feePips 从输入金额中提取的费用，以百分之一bip表示
    /// @return sqrtRatioNextX96 输入/输出amount后的价格，不得超过目标价格
    /// @return amountIn 根据swap方向，将要swapped in的金额，无论是token0还是token1
    /// @return amountOut 根据swap方向，将收到的金额，无论是token0还是token1
    /// @return feeAmount 将被视为费用的投入金额
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        uint24 feePips
    )
        internal
        pure
        returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn,
            uint256 amountOut,
            uint256 feeAmount
        )
    {
        // 判断交易方向，即价格降低或升高
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        // 判断是否指定了精确的tokenIn数量
        bool exactIn = amountRemaining >= 0;

        if (exactIn) {
            // 先将tokenIn的余额扣除掉最大所需的手续费
            // 此步骤最多需要的手续费的数量
            uint256 amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
            // 通过公式计算出到达目标价格所需的tokenIn数量，这里面对token x和y的计算公式是不一样的
            amountIn = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true);
            // 判断余额是否充足，如果充足那么这次交易可以到达目标交易价格，否则需要计算出当前tokenIn能到达的目标交易价格
            if (amountRemainingLessFee >= amountIn) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                // 当余额不充足时计算能够到达的目标交易价格
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    amountRemainingLessFee,
                    zeroForOne
                );
        } else {
            amountOut = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false);
            if (uint256(-amountRemaining) >= amountOut) sqrtRatioNextX96 = sqrtRatioTargetX96;
            else
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96,
                    liquidity,
                    uint256(-amountRemaining),
                    zeroForOne
                );
        }

        // 判断是否能够到达目标价格
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;

        // 获取输入/输出amounts
        if (zeroForOne) {
            // 根据是否到达目标价格，计算amountIn/amountOut的值
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount0Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false);
        } else {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true);
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false);
        }

        // 封顶output的amount不要超过remaining的output的amount
        // 这里对Output进行cap是因为前面在计算amountOut时，有可能会使用sqrtRatioNextX96来进行计算，而sqrtRatioNextX96
        // 可能被Round之后导致sqrt_P偏大，从而导致计算的amountOut偏大
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }

        // 根据交易是否移动到价格边界来计算手续费的数量
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            // 如果没能到达边界价格，即已经交易结束，剩余的tokenIn将全部作为手续费
            // 为了不让计算进一步复杂化，这里直接将剩余的tokenIn将全部作为手续费
            // 因此会多收取一部分手续费，即按本次交易的最大手续费收取
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}
