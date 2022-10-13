// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import './interfaces/IUniswapV3Pool.sol';

import './NoDelegateCall.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SafeCast.sol';
import './libraries/Tick.sol';
import './libraries/TickBitmap.sol';
import './libraries/Position.sol';
import './libraries/Oracle.sol';

import './libraries/FullMath.sol';
import './libraries/FixedPoint128.sol';
import './libraries/TransferHelper.sol';
import './libraries/TickMath.sol';
import './libraries/LiquidityMath.sol';
import './libraries/SqrtPriceMath.sol';
import './libraries/SwapMath.sol';

import './interfaces/IUniswapV3PoolDeployer.sol';
import './interfaces/IUniswapV3Factory.sol';
import './interfaces/IERC20Minimal.sol';
import './interfaces/callback/IUniswapV3MintCallback.sol';
import './interfaces/callback/IUniswapV3SwapCallback.sol';
import './interfaces/callback/IUniswapV3FlashCallback.sol';

contract UniswapV3Pool is IUniswapV3Pool, NoDelegateCall {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;
    using Oracle for Oracle.Observation[65535];

    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override factory;
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token0;
    /// @inheritdoc IUniswapV3PoolImmutables
    address public immutable override token1;
    /// @inheritdoc IUniswapV3PoolImmutables
    uint24 public immutable override fee;

    /// @inheritdoc IUniswapV3PoolImmutables
    int24 public immutable override tickSpacing;

    /// @inheritdoc IUniswapV3PoolImmutables
    uint128 public immutable override maxLiquidityPerTick;

    struct Slot0 {
        // 当前的价格
        uint160 sqrtPriceX96;
        // 当前的tick
        int24 tick;
        // 最近更新的在observations数组中的index（索引）
        uint16 observationIndex;
        // 已存储的Oracle数量
        uint16 observationCardinality;
        // 可用的Oracle的空间，此值初始化时会被设置为1，后续根据需要来可以扩展
        uint16 observationCardinalityNext;
        // 当前的协议fee占全部手续费的百分比，展示为一个整形的分母
        uint8 feeProtocol;
        // 是否被锁定
        bool unlocked;
    }
    /// @inheritdoc IUniswapV3PoolState
    Slot0 public override slot0;

    /// @inheritdoc IUniswapV3PoolState
    uint256 public override feeGrowthGlobal0X128;
    /// @inheritdoc IUniswapV3PoolState
    uint256 public override feeGrowthGlobal1X128;

    // token0/token1累积的协议fee
    struct ProtocolFees {
        uint128 token0;
        uint128 token1;
    }
    /// @inheritdoc IUniswapV3PoolState
    ProtocolFees public override protocolFees;

    /// @inheritdoc IUniswapV3PoolState
    uint128 public override liquidity;

    /// @inheritdoc IUniswapV3PoolState
    mapping(int24 => Tick.Info) public override ticks; // 记录每个tick包含的元数据，这里只会包含所有position的lower/upper ticks
    /// @inheritdoc IUniswapV3PoolState
    mapping(int16 => uint256) public override tickBitmap; // 共有今天887272X2个位，大部分的位不需要初始化，每256个为一个单位称为word，mapping的键就是word的索引
    /// @inheritdoc IUniswapV3PoolState
    mapping(bytes32 => Position.Info) public override positions;
    /// @inheritdoc IUniswapV3PoolState
    Oracle.Observation[65535] public override observations;

    /// @dev 为pool中的函数方法增加锁定防止重入攻击
    /// 此方法还可以防止在初始化函数之前执行函数
    /// 整个合同中都需要重入保护，因为我们使用余额检查来确定Mint，Swap和Flash等交互的支付状态
    modifier lock() {
        require(slot0.unlocked, 'LOK');
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

    /// @dev 保证函数只能被Factory的owner调用
    modifier onlyFactoryOwner() {
        require(msg.sender == IUniswapV3Factory(factory).owner());
        _;
    }

    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    /// @dev 输入有效性判断
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        require(tickLower < tickUpper, 'TLU');
        require(tickLower >= TickMath.MIN_TICK, 'TLM');
        require(tickUpper <= TickMath.MAX_TICK, 'TUM');
    }

    /// @dev 返回区块的时间戳，32bits，i.e. mod 2**32 这个函数在tests中被重写
    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    /// @dev 获取pool中token0的余额
    /// @dev 这个函数做过Gas优化处理，避免了重复的extcodesize检查和returndatasize检查
    function balance0() private view returns (uint256) {
        (bool success, bytes memory data) =
        token0.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev 获取pool中token1的余额
    /// @dev 这个函数做过Gas优化处理，避免了重复的extcodesize检查和returndatasize检查
    function balance1() private view returns (uint256) {
        (bool success, bytes memory data) =
        token1.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, address(this)));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        override
        noDelegateCall
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        )
    {
        checkTicks(tickLower, tickUpper);

        int56 tickCumulativeLower;
        int56 tickCumulativeUpper;
        uint160 secondsPerLiquidityOutsideLowerX128;
        uint160 secondsPerLiquidityOutsideUpperX128;
        uint32 secondsOutsideLower;
        uint32 secondsOutsideUpper;

        {
            Tick.Info storage lower = ticks[tickLower];
            Tick.Info storage upper = ticks[tickUpper];
            bool initializedLower;
            (tickCumulativeLower, secondsPerLiquidityOutsideLowerX128, secondsOutsideLower, initializedLower) = (
                lower.tickCumulativeOutside,
                lower.secondsPerLiquidityOutsideX128,
                lower.secondsOutside,
                lower.initialized
            );
            require(initializedLower);

            bool initializedUpper;
            (tickCumulativeUpper, secondsPerLiquidityOutsideUpperX128, secondsOutsideUpper, initializedUpper) = (
                upper.tickCumulativeOutside,
                upper.secondsPerLiquidityOutsideX128,
                upper.secondsOutside,
                upper.initialized
            );
            require(initializedUpper);
        }
        Slot0 memory _slot0 = slot0;

        if (_slot0.tick < tickLower) {
            return (
                tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityOutsideLowerX128 - secondsPerLiquidityOutsideUpperX128,
                secondsOutsideLower - secondsOutsideUpper
            );
        } else if (_slot0.tick < tickUpper) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) =
                observations.observeSingle(
                    time,
                    0,
                    _slot0.tick,
                    _slot0.observationIndex,
                    liquidity,
                    _slot0.observationCardinality
                );
            return (
                tickCumulative - tickCumulativeLower - tickCumulativeUpper,
                secondsPerLiquidityCumulativeX128 -
                    secondsPerLiquidityOutsideLowerX128 -
                    secondsPerLiquidityOutsideUpperX128,
                time - secondsOutsideLower - secondsOutsideUpper
            );
        } else {
            return (
                tickCumulativeUpper - tickCumulativeLower,
                secondsPerLiquidityOutsideUpperX128 - secondsPerLiquidityOutsideLowerX128,
                secondsOutsideUpper - secondsOutsideLower
            );
        }
    }

    /// @inheritdoc IUniswapV3PoolDerivedState
    function observe(uint32[] calldata secondsAgos)
        external
        view
        override
        noDelegateCall
        returns (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s)
    {
        return
            observations.observe(
                _blockTimestamp(),
                secondsAgos,
                slot0.tick,
                slot0.observationIndex,
                liquidity,
                slot0.observationCardinality
            );
    }

    /// @inheritdoc IUniswapV3PoolActions
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external
        override
        lock
        noDelegateCall
    {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext; // for the event
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);
        slot0.observationCardinalityNext = observationCardinalityNextNew;
        if (observationCardinalityNextOld != observationCardinalityNextNew)
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev 不需要加上锁定修饰符因为它初始化了锁定标志位
    function initialize(uint160 sqrtPriceX96) external override {
        require(slot0.sqrtPriceX96 == 0, 'AI');

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext,
            feeProtocol: 0,
            unlocked: true
        });

	    emit Initialize(sqrtPriceX96, tick);
    }

    struct ModifyPositionParams {
        // 此position的owner地址
        address owner;
        // 此position的lower和upper的tick
        int24 tickLower;
        int24 tickUpper;
        // liquidity的任何改变
        int128 liquidityDelta;
    }

    /// @dev 对position进行一些更新
    /// @param params 此position的详情和liquidity的变化
    /// @return position 一个storage的指针通过owner和tick边界确定的position
    /// @return amount0 此pool欠token0的金额，如果pool应该支付给recipient则此值为负数
    /// @return amount1 此pool欠token1的金额，如果pool应该支付给recipient则此值为负数
    function _modifyPosition(ModifyPositionParams memory params)
        private
        noDelegateCall
        returns (
            Position.Info storage position,
            int256 amount0,
            int256 amount1
        )
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0; // SLOAD for gas optimization

        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        if (params.liquidityDelta != 0) {
            // 计算三种情况下的amount0和amount1的值，即token x和y的数量
            if (_slot0.tick < params.tickLower) {
                // 当前tick低于传入的区间; liquidity只能当从左向右穿过时才能在区间当中
                // when we'll need _more_ token0 (it's becoming more valuable) so user must provide it
                amount0 = SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            } else if (_slot0.tick < params.tickUpper) {
                // 当前tick正在区间传入的区间当中
                uint128 liquidityBefore = liquidity; // SLOAD for gas optimization

                // 准备一个oracle的入口
                (slot0.observationIndex, slot0.observationCardinality) = observations.write(
                    _slot0.observationIndex,
                    _blockTimestamp(),
                    _slot0.tick,
                    liquidityBefore,
                    _slot0.observationCardinality,
                    _slot0.observationCardinalityNext
                );

                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    _slot0.sqrtPriceX96,
                    params.liquidityDelta
                );

                liquidity = LiquidityMath.addDelta(liquidityBefore, params.liquidityDelta);
            } else {
                // 当前tick高于传入的区间; liquidity只能当从右向左穿过时才能在区间当中
                // when we'll need _more_ token1 (it's becoming more valuable) so user must provide it
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),
                    TickMath.getSqrtRatioAtTick(params.tickUpper),
                    params.liquidityDelta
                );
            }
        }
    }

    /// @dev 获取一个position的liquidityDelta或者更新一个position的liquidityDelta
    /// @param owner 此position的owner
    /// @param tickLower 此position的下边界lower tick
    /// @param tickUpper 此position的上边界upper tick
    /// @param tick 当前的tick，传入是为了避免sloads
    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {
        // 获取用户的position
        position = positions.get(owner, tickLower, tickUpper);

        uint256 _feeGrowthGlobal0X128 = feeGrowthGlobal0X128; // SLOAD for gas optimization
        uint256 _feeGrowthGlobal1X128 = feeGrowthGlobal1X128; // SLOAD for gas optimization

        // 根据传入的参数修改position对应的lower/upper tick中的数据
        // 这里可以是增加liquidity，也可以是移除liquidity
        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            uint32 time = _blockTimestamp();
            (int56 tickCumulative, uint160 secondsPerLiquidityCumulativeX128) =
                observations.observeSingle(
                    time,
                    0,
                    slot0.tick,
                    slot0.observationIndex,
                    liquidity,
                    slot0.observationCardinality
                );

            // 更新tickLower和tickUpper
            // flippedLower和flippedUpper变量表示此tick的引用状态是否发生变化，即
            // 被引用 -> 未被引用 或
            // 未被引用 -> 被引用
            // 后续需要根据这个变量的值来更新tickBitmap
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                secondsPerLiquidityCumulativeX128,
                tickCumulative,
                time,
                true,
                maxLiquidityPerTick
            );

            // 如果此tick第一次被引用，或者移除了所有引用
            // 那么更新tickBitmap
            if (flippedLower) {
                tickBitmap.flipTick(tickLower, tickSpacing);
            }
            if (flippedUpper) {
                tickBitmap.flipTick(tickUpper, tickSpacing);
            }
        }

        // 计算出此position的手续费总量
        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
            ticks.getFeeGrowthInside(tickLower, tickUpper, tick, _feeGrowthGlobal0X128, _feeGrowthGlobal1X128);

        // 更新position中的数据
        position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        // 如果移除了此tick的引用，那么清空所有不再使用的tick数据
        // 这只会发生在移除liquidity的操作中
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev noDelegateCall是在——modifyPosition函数中起作用的
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0);
        (, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(amount).toInt128()
                })
            );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;
        // 获取当前pool中的token x和y的余额
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        // 将需要的token x和y的数量传回给回调函数，这里预期回调函数会将指定数量的token发送给合约
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(amount0, amount1, data);
        // 回调完成后，检查发送至合约的token是否复合预期，如果不满足检查则回溯交易
        if (amount0 > 0) require(balance0Before.add(amount0) <= balance0(), 'M0');
        if (amount1 > 0) require(balance1Before.add(amount1) <= balance1(), 'M1');

        emit Mint(msg.sender, recipient, tickLower, tickUpper, amount, amount0, amount1);
    }

    /// @inheritdoc IUniswapV3PoolActions
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock returns (uint128 amount0, uint128 amount1) {
        // 获取position的数据，我们不需要执行checkTicks在这，因为不合格的positions将永远不会有非零的 tokensOwed{0,1}
        Position.Info storage position = positions.get(msg.sender, tickLower, tickUpper);

        // 根据参数调整需要提取的手续费
        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        // 将手续费发送给用户
        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

        emit Collect(msg.sender, recipient, tickLower, tickUpper, amount0, amount1);
    }

    /// @inheritdoc IUniswapV3PoolActions
    /// @dev noDelegateCall是在——modifyPosition函数中起作用的
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external override lock returns (uint256 amount0, uint256 amount1) {
        // 先计算出需要移除的token数量
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: msg.sender,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: -int256(amount).toInt128()
                })
            );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        // 移除liquidity后，将移除的token数量记录到position.tokensOwed上面
        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }

        emit Burn(msg.sender, tickLower, tickUpper, amount, amount0, amount1);
    }

    struct SwapCache {
        // 输入token的协议fee
        uint8 feeProtocol;
        // swap开始时的liquidity
        uint128 liquidityStart;
        // 当前区块的时间戳
        uint32 blockTimestamp;
        // tick accumulator的当前数值，只有当我们穿过一个初始化过的tick时才计算
        int56 tickCumulative;
        // seconds per liquidity accumulator的当前数值，只有当我们穿过一个初始化过的tick时才计算
        uint160 secondsPerLiquidityCumulativeX128;
        // 我们是否已经计算并缓存了上面的两个数值
        bool computedLatestObservation;
    }

    // swap最上层的状态，最终会存储的结果
    struct SwapState {
        // 将被swapped in/out的输入/输出资产的残留值
        int256 amountSpecifiedRemaining;
        // 已被swapped in/out的输出/输入资产的值
        int256 amountCalculated;
        // 当前价格的平方根
        uint160 sqrtPriceX96;
        // 当前价格所对应的tick
        int24 tick;
        // 输入token的手续费增涨的全局变量
        uint256 feeGrowthGlobalX128;
        // 输入token的协议fee
        uint128 protocolFee;
        // 当前价格区间内的liquidity
        uint128 liquidity;
    }

    struct StepComputations {
        // 步骤开始时的价格平方根
        uint160 sqrtPriceStartX96;
        // 下一个将被swap的tick，按照swap方向来说
        int24 tickNext;
        // 是否tickNext是已经初始化过
        bool initialized;
        // 关于tickNext的价格平方根（1/0）
        uint160 sqrtPriceNextX96;
        // 多少在此步骤中被swapped in
        uint256 amountIn;
        // 多少在此步骤中被swapped out
        uint256 amountOut;
        // 多少fee产生
        uint256 feeAmount;
    }

    /// @inheritdoc IUniswapV3PoolActions
    /** 我们假设支付的token是x
     *  1、根据买入/卖出行为，sqrtPriceX96会随着交易上升/下降，即tick增加或者减少
     *  2、在tickBitmap中找到和当前tick对应的i_c在一个word中的下一个tick对应的i_n，根据买入/卖出行为，这里分成向下查找和向上查找两种情况
     *  3、如果当前word中没有记录其它tick index，那么取这个word的最小/最大的tick index，这么做的目的是，让单步交易的tick的跨度不至于太大，
     *  从而减少计算中溢出的可能性（计算中需要使用  Δ sqrtPriceX96）
     *  4、在[i_c, i_n]区间内，流动性L是不变的，我们可以根据L的值计算出交易运行到i_n时需要最多的 Δx的数量
     *  5、根据上一步计算的 Δx的数量，如果满足 Δx < x remaining，那么将i设置为i_n，并将x remaining减去需要支付的 Δx，随后跳至第2步继续计算（这里
     *  需要将i+-tickSpacing使其进入tickBitmap中的下一个word），计算之前还需要根据元数据修改当前的流动性 L = L +- ΔL
     *  6、如果上一步计算 Δx，满足 Δx > x remaining，则表示x token将被耗尽，则交易在此结束
     *  7、记录下结束时的价格sqrtPriceX96，将所有的交易阶段的tokenOut数量总和返回，即为用户得到的token数量
     *  8、上一步的计算过程还需要考虑费率的因素，为了让计算简化，可能会多收费
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external override noDelegateCall returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, 'AS');

        // 将交易前的元数据保存在内存中，后续的访问通过`MLOAD`完成，节省gas
        Slot0 memory slot0Start = slot0;

        require(slot0Start.unlocked, 'LOK');
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 > slot0Start.sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_RATIO,
            'SPL'
        );

        slot0.unlocked = false;

        // 这里也是缓存交易前的数据，节省gas
        SwapCache memory cache =
            SwapCache({
                liquidityStart: liquidity,
                blockTimestamp: _blockTimestamp(),
                feeProtocol: zeroForOne ? (slot0Start.feeProtocol % 16) : (slot0Start.feeProtocol >> 4),
                secondsPerLiquidityCumulativeX128: 0,
                tickCumulative: 0,
                computedLatestObservation: false
            });

        // 判断是否指定了tokenIn的数量
        bool exactInput = amountSpecified > 0;

        // 保存交易过程中计算所需的中间变量，这些值在交易的步骤中可能会发生变化
        SwapState memory state =
            SwapState({
                amountSpecifiedRemaining: amountSpecified,
                amountCalculated: 0,
                sqrtPriceX96: slot0Start.sqrtPriceX96,
                tick: slot0Start.tick,
                feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
                protocolFee: 0,
                liquidity: cache.liquidityStart
            });

        // 持续swapping只要没有用光所有的input/output或者没有达到价格极限
        while (state.amountSpecifiedRemaining != 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            // 交易过程每一次循环的状态变量
            StepComputations memory step;

            // 交易的起始价格
            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            // 通过tickBitmap找到下一个可以选择的交易价格，这里面可能是下一个流动性的边界，也可能还是在当前流动性中
            (step.tickNext, step.initialized) = tickBitmap.nextInitializedTickWithinOneWord(
                state.tick,
                tickSpacing,
                zeroForOne
            );

            // 确保我们不会越过min/max tick，因为tick bitmap并不会警示这些边界
            if (step.tickNext < TickMath.MIN_TICK) {
                step.tickNext = TickMath.MIN_TICK;
            } else if (step.tickNext > TickMath.MAX_TICK) {
                step.tickNext = TickMath.MAX_TICK;
            }

            // 从tick index计算 sqrt(price)
            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.tickNext);

            // 计算当价格到达下一个交易价格时，tokenIn是否被耗尽，如果被耗尽则交易结束，还需要重新计算出tokenIn耗尽时的价格
            // 如果没耗尽，那么还需要继续进入下一个循环
            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            // 更新tokenIn的余额，以及tokenOut的数量，注意当指定tokenIn的数量进行交易时，这里的tokenOut是负数
            if (exactInput) {
                state.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
                state.amountCalculated = state.amountCalculated.sub(step.amountOut.toInt256());
            } else {
                state.amountSpecifiedRemaining += step.amountOut.toInt256();
                state.amountCalculated = state.amountCalculated.add((step.amountIn + step.feeAmount).toInt256());
            }

            // 如果协议fee打开状态，计算多少，减少feeAmount，提升protocolFee
            if (cache.feeProtocol > 0) {
                uint256 delta = step.feeAmount / cache.feeProtocol;
                step.feeAmount -= delta;
                state.protocolFee += uint128(delta);
            }

            // 更新交易的f_g, 这里面需要除以流动性L
            if (state.liquidity > 0)
                state.feeGrowthGlobalX128 += FullMath.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);

            // 当价格到达当前步骤价格区间的边界价格时，可能需要穿过下一个tick
            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                // 查看下一个tick是否已经初始化
                if (step.initialized) {
                    // 检查占位符的值，在第一次swap穿过一个已初始化过的tick的时候我们将其替换成实际的值
                    if (!cache.computedLatestObservation) {
                        (cache.tickCumulative, cache.secondsPerLiquidityCumulativeX128) = observations.observeSingle(
                            cache.blockTimestamp,
                            0,
                            slot0Start.tick,
                            slot0Start.observationIndex,
                            cache.liquidityStart,
                            slot0Start.observationCardinality
                        );
                        cache.computedLatestObservation = true;
                    }
                    // 按需决定是否需要更新流动性L的值
                    int128 liquidityNet =
                        // 这里需要更新tick的f_o
                        ticks.cross(
                            step.tickNext,
                            (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                            (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128),
                            cache.secondsPerLiquidityCumulativeX128,
                            cache.tickCumulative,
                            cache.blockTimestamp
                        );
                    // 如果我们向左移动，我们将liquidityNet解释为相反的符号
                    // 安全是因为liquidityNet不可能变成type(int128).min
                    if (zeroForOne) liquidityNet = -liquidityNet;

                    // 更新流动性
                    state.liquidity = LiquidityMath.addDelta(state.liquidity, liquidityNet);
                }

                // 在这里更新tick的值，使得下一次循环时让tickBitmap进入下一个word中查询
                state.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
            } else if (state.sqrtPriceX96 != step.sqrtPriceNextX96) {
                // 重新计算除非我们在一个下边界上（i.e. 已经转换了ticks），但还没有移动
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        // 此tick改变的时候更新tick并写入一个oracle入口
        if (state.tick != slot0Start.tick) {
            // 写入Oracle的数据
            (uint16 observationIndex, uint16 observationCardinality) =
                observations.write(
                    // 交易前的最新Oracle的index（索引）
                    slot0Start.observationIndex,
                    // 当前区块的时间戳
                    cache.blockTimestamp,
                    // 交易前的价格tick，这样做是为了防止攻击
                    slot0Start.tick,
                    // 交易前的价格对应的流动性
                    cache.liquidityStart,
                    // 当前的Oracle数量
                    slot0Start.observationCardinality,
                    // 可用的Oracle数量
                    slot0Start.observationCardinalityNext
                );
            // 更新最新的Oracle指向的index（索引）信息以及当前的Oracle数据的总量
            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) = (
                state.sqrtPriceX96,
                state.tick,
                observationIndex,
                observationCardinality
            );
        } else {
            // 否则只是更新价格
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        // 如果liquidity改变则更新它
        if (cache.liquidityStart != state.liquidity) liquidity = state.liquidity;

        // 在交易步骤完成后，更新合约的f_g，并且如果有必要也更新 protocol fee
        // 溢出是可以接受的，protocol必须在它达到type(uint128).max之前提现出来
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token0 += state.protocolFee;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
            if (state.protocolFee > 0) protocolFees.token1 += state.protocolFee;
        }

        // 确定最终用户支付的token数量和得到的token数量
        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        // 执行transfers和collect payment，扣除用户需要支付的token
        if (zeroForOne) {
            // 将tokenOut发送给用户，前面说过tokenOut记录的是负数
            if (amount1 < 0) TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            // 还是通过回调的方式，扣除用户需要支付的token
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            // 检查扣除是否成功
            require(balance0Before.add(uint256(amount0)) <= balance0(), 'IIA');
        } else {
            if (amount0 < 0) TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= balance1(), 'IIA');
        }

        // 发送事件记录日志
        emit Swap(msg.sender, recipient, amount0, amount1, state.sqrtPriceX96, state.liquidity, state.tick);
        // 解除防止重入的锁
        slot0.unlocked = true;
    }

    /// @inheritdoc IUniswapV3PoolActions
    function flash(
        address recipient, // 借贷方地址，用于调用回调函数
        uint256 amount0, // 借贷的token0的数量
        uint256 amount1, // 借贷的token1的数量
        bytes calldata data // 回调函数的参数
    ) external override lock noDelegateCall {
        uint128 _liquidity = liquidity;
        require(_liquidity > 0, 'L');

        // 计算借贷所需要扣除的手续费
        uint256 fee0 = FullMath.mulDivRoundingUp(amount0, fee, 1e6);
        uint256 fee1 = FullMath.mulDivRoundingUp(amount1, fee, 1e6);
        // 记录下当前的余额
        uint256 balance0Before = balance0();
        uint256 balance1Before = balance1();

        // 将所需token发送给借贷方
        if (amount0 > 0) TransferHelper.safeTransfer(token0, recipient, amount0);
        if (amount1 > 0) TransferHelper.safeTransfer(token1, recipient, amount1);

        // 调用借贷方地址的回调函数，将函数用户传入的data参数传给这个回调函数
        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        // 记录调用完成后的余额
        uint256 balance0After = balance0();
        uint256 balance1After = balance1();

        // 比对借出代币前和回调函数调用完成后余额的数量，对于每个token，余额只能多不能少
        require(balance0Before.add(fee0) <= balance0After, 'F0');
        require(balance1Before.add(fee1) <= balance1After, 'F1');

        // 手续费相关计算
        uint256 paid0 = balance0After - balance0Before;
        uint256 paid1 = balance1After - balance1Before;

        if (paid0 > 0) {
            uint8 feeProtocol0 = slot0.feeProtocol % 16;
            uint256 fees0 = feeProtocol0 == 0 ? 0 : paid0 / feeProtocol0;
            if (uint128(fees0) > 0) protocolFees.token0 += uint128(fees0);
            feeGrowthGlobal0X128 += FullMath.mulDiv(paid0 - fees0, FixedPoint128.Q128, _liquidity);
        }
        if (paid1 > 0) {
            uint8 feeProtocol1 = slot0.feeProtocol >> 4;
            uint256 fees1 = feeProtocol1 == 0 ? 0 : paid1 / feeProtocol1;
            if (uint128(fees1) > 0) protocolFees.token1 += uint128(fees1);
            feeGrowthGlobal1X128 += FullMath.mulDiv(paid1 - fees1, FixedPoint128.Q128, _liquidity);
        }

        emit Flash(msg.sender, recipient, amount0, amount1, paid0, paid1);
    }

    /// @inheritdoc IUniswapV3PoolOwnerActions
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external override lock onlyFactoryOwner {
        require(
            (feeProtocol0 == 0 || (feeProtocol0 >= 4 && feeProtocol0 <= 10)) &&
            (feeProtocol1 == 0 || (feeProtocol1 >= 4 && feeProtocol1 <= 10))
        );
        uint8 feeProtocolOld = slot0.feeProtocol;
        slot0.feeProtocol = feeProtocol0 + (feeProtocol1 << 4);
        emit SetFeeProtocol(feeProtocolOld % 16, feeProtocolOld >> 4, feeProtocol0, feeProtocol1);
    }

    /// @inheritdoc IUniswapV3PoolOwnerActions
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external override lock onlyFactoryOwner returns (uint128 amount0, uint128 amount1) {
        amount0 = amount0Requested > protocolFees.token0 ? protocolFees.token0 : amount0Requested;
        amount1 = amount1Requested > protocolFees.token1 ? protocolFees.token1 : amount1Requested;

        if (amount0 > 0) {
            if (amount0 == protocolFees.token0) amount0--; // 保证此slot不会被清理掉，节省gas
            protocolFees.token0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            if (amount1 == protocolFees.token1) amount1--; // 保证此slot不会被清理掉，节省gas
            protocolFees.token1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }

	    emit CollectProtocol(msg.sender, recipient, amount0, amount1);
    }
}
