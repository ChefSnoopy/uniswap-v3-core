// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0 <0.8.0;

import './FullMath.sol';
import './FixedPoint128.sol';
import './LiquidityMath.sol';

/// @title Position
/// @notice Positions代表了owner地址的介于下限和上限之间的liquidity
/// @dev Positions 其中存储了相关position中所跟踪的手续费附加状态
library Position {
    // 用户的position中存储的信息
    struct Info {
        // 此position所拥有的liquidity的amount
        uint128 liquidity;
        // 上一次更新liquidity或手续费时每单位liquidity的手续费增涨
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        // 当前已经拥有的token0/token1的手续费
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    /// @notice 指定边界和owner找到一个position
    /// @param self 所有用户的positions的mapping
    /// @param owner 此position的owner
    /// @param tickLower 此position的下限边界
    /// @param tickUpper 此position的上限边界
    /// @return position 此position的信息数据
    function get(
        mapping(bytes32 => Info) storage self,
        address owner,
        int24 tickLower,
        int24 tickUpper
    ) internal view returns (Position.Info storage position) {
        position = self[keccak256(abi.encodePacked(owner, tickLower, tickUpper))];
    }

    /// @notice 将累积的手续费记入用户的position
    /// @param self 独立的待更新的position
    /// @param liquidityDelta 此position中liquidity的最终变化量
    /// @param feeGrowthInside0X128 在此position内部的tick边界中token0的所有手续费的增涨
    /// @param feeGrowthInside1X128 在此position内部的tick边界中token1的所有手续费的增涨
    function update(
        Info storage self,
        int128 liquidityDelta,
        uint256 feeGrowthInside0X128,
        uint256 feeGrowthInside1X128
    ) internal {
        Info memory _self = self;

        uint128 liquidityNext;
        if (liquidityDelta == 0) {
            require(_self.liquidity > 0, 'NP'); // 禁止向liquidity为0的positions更新
            liquidityNext = _self.liquidity;
        } else {
            liquidityNext = LiquidityMath.addDelta(_self.liquidity, liquidityDelta);
        }

        // 计算token0和token1的手续费总量
        uint128 tokensOwed0 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0X128 - _self.feeGrowthInside0LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );
        uint128 tokensOwed1 =
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1X128 - _self.feeGrowthInside1LastX128,
                    _self.liquidity,
                    FixedPoint128.Q128
                )
            );

        // 更新position
        if (liquidityDelta != 0) self.liquidity = liquidityNext;
        self.feeGrowthInside0LastX128 = feeGrowthInside0X128;
        self.feeGrowthInside1LastX128 = feeGrowthInside1X128;
        if (tokensOwed0 > 0 || tokensOwed1 > 0) {
            // 溢出是可以接受的，必须在达到type(uint128).max最大值前完成提现
            self.tokensOwed0 += tokensOwed0;
            self.tokensOwed1 += tokensOwed1;
        }
    }
}
