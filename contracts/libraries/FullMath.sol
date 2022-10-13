// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.8.0;

/// @title Contains 512-bit math functions
/// @notice 便于在不损失精度的情况下实现中间值溢出的乘法和除法
/// @dev 处理“phantom overflow"，即允许在中间值溢出256位的情况下进行乘除
library FullMath {
    /// @notice 保持精度的情况下计算 floor(a×b÷denominator)，如果溢出或者除数为0返回0
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result The 256-bit result
    /// @dev Credit to Remco Bloemen under MIT license https://xn--2-umb.com/21/muldiv
    function mulDiv(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        // 512-bit multiply [prod1 prod0] = a * b
        // 计算产品的同余整数 mod 2**256 和 mod 2**256 - 1，然后用中国余数定理重构512位的结果
        // 这个结果存储在两个256变量中，例如 product = prod1 * 2**256 + prod0
        uint256 prod0;
        uint256 prod1;
        assembly {
            let mm := mulmod(a, b, not(0))
            prod0 := mul(a, b)
            prod1 := sub(sub(mm, prod0), lt(mm, prod0))
        }

        // 处理非溢出情况，256乘256除法
        if (prod1 == 0) {
            require(denominator > 0);
            assembly {
                result := div(prod0, denominator)
            }
            return result;
        }

        // 确保结果小于2**256
        // 并避免denominator == 0
        require(denominator > prod1);

        ///////////////////////////////////////////////
        // 512乘256除法
        ///////////////////////////////////////////////

        // 通过减去余数使除法精确 [prod1 prod0]
        // 使用mulmod计算余数
        uint256 remainder;
        assembly {
            remainder := mulmod(a, b, denominator)
        }
        // 从512位数字中减去256位数字
        assembly {
            prod1 := sub(prod1, gt(remainder, prod0))
            prod0 := sub(prod0, remainder)
        }

        // 分母中两个的因子幂
        // 计算分母的两个除数的最大幂
        // 总是 >= 1.
        uint256 twos = -denominator & denominator;
        // Divide denominator by power of two
        assembly {
            denominator := div(denominator, twos)
        }

        // 除以 [prod1 prod0]， 用2的因子幂
        assembly {
            prod0 := div(prod0, twos)
        }
        // 将位从prod1移到prod0。为此，我们需要翻转"twos"，使其为2**256/twos。如果twos为0，则它变为1
        assembly {
            twos := add(div(sub(0, twos), twos), 1)
        }
        prod0 |= prod1 * twos;

        // 反向分母模 2**256
        // 既然分母是奇数，它就有了一个反比
        // 模 2**256 such that denominator * inv = 1 mod 2**256.
        // 通过从正确的种子开始计算倒数
        // 修正为四位。那就是， denominator * inv = 1 mod 2**4
        uint256 inv = (3 * denominator) ^ 2;
        // 现在使用 Newton-Raphson 迭代法来提高精度
        // 由于Hensel的提升引理，这也适用于模运算，在每一步中将正确位加倍
        inv *= 2 - denominator * inv; // inverse mod 2**8
        inv *= 2 - denominator * inv; // inverse mod 2**16
        inv *= 2 - denominator * inv; // inverse mod 2**32
        inv *= 2 - denominator * inv; // inverse mod 2**64
        inv *= 2 - denominator * inv; // inverse mod 2**128
        inv *= 2 - denominator * inv; // inverse mod 2**256

        // 因为现在除法是精确的，我们可以用分母的模逆相乘来除法。这将给出模2**256的正确结果。
        // 由于预条件保证结果小于2**256。这是最终结果。
        // 我们不需要计算结果的高位，不再需要prod1。
        result = prod0 * inv;
        return result;
    }

    /// @notice 保持精度的情况下计算 ceil(a×b÷denominator)，如果溢出或者除数为0返回0
    /// @param a 被乘数
    /// @param b 乘数
    /// @param denominator 除数
    /// @return result The 256-bit result
    function mulDivRoundingUp(
        uint256 a,
        uint256 b,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = mulDiv(a, b, denominator);
        if (mulmod(a, b, denominator) > 0) {
            require(result < type(uint256).max);
            result++;
        }
    }
}
