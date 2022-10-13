import { Wallet } from 'ethers';
import { ethers, waffle } from 'hardhat';
import { TestERC20 } from '../typechain/TestERC20';
import { UniswapV3Factory } from '../typechain/UniswapV3Factory';
import { MockTimeUniswapV3Pool } from '../typechain/MockTimeUniswapV3Pool';
import { expect } from './shared/expect';

import { poolFixture } from './shared/fixtures';

import {
    FeeAmount,
    TICK_SPACINGS,
    createPoolFunctions,
    PoolFunctions,
    createMultiPoolFunctions,
    encodePriceSqrt,
    getMinTick,
    getMaxTick,
    expandTo18Decimals,
} from './shared/utilities';
import { TestUniswapV3Router } from '../typechain/TestUniswapV3Router';
import { TestUniswapV3Callee } from '../typechain/TestUniswapV3Callee';

const feeAmount = FeeAmount.MEDIUM;
const tickSpacing = TICK_SPACINGS[feeAmount];

const createFixtureLoader = waffle.createFixtureLoader;

type ThenArg<T> = T extends PromiseLike<infer U> ? U : T;

describe('UniswapV3Pool', () => {
    let wallet: Wallet, other: Wallet;

    let token0: TestERC20;
    let token1: TestERC20;
    let token2: TestERC20;
    let factory: UniswapV3Factory;
    let pool0: MockTimeUniswapV3Pool;
    let pool1: MockTimeUniswapV3Pool;

    let pool0Functions: PoolFunctions;
    let pool1Functions: PoolFunctions;

    let minTick: number;
    let maxTick: number;

    let swapTargetCallee: TestUniswapV3Callee;
    let swapTargetRouter: TestUniswapV3Router;

    let loadFixture: ReturnType<typeof createFixtureLoader>;
    let createPool: ThenArg<ReturnType<typeof poolFixture>>['createPool'];

    before('create fixture loader', async () => {
        ;[wallet, other] = await (ethers as any).getSigners();

        loadFixture = createFixtureLoader([wallet, other]);
    });

    beforeEach('deploy first fixture', async () => {
        ;({ token0, token1, token2, factory, createPool, swapTargetCallee, swapTargetRouter } = await loadFixture(
            poolFixture
        ));

        const createPoolWrapped = async (

        ): Promise<[MockTimeUniswapV3Pool, any]> => {

        }
    });
});