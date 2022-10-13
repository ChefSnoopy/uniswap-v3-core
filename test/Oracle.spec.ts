import { BigNumber, BigNumberish, Wallet } from 'ethers';
import { ethers, waffle } from 'hardhat';
import { OracleTest } from '../typechain/OracleTest';
import checkObservationEquals from './shared/checkObservationEquals';
import { expect } from './shared/expect';
import { TEST_POOL_START_TIME } from './shared/fixtures';
import snapshotGasCost from './shared/snapshotGasCost';
import { MaxUint128 } from './shared/utilities';

describe('Oracle', () => {
    let wallet: Wallet, other: Wallet;

    let loadFixture: ReturnType<typeof waffle.createFixtureLoader>;
    before('create fixture loader', async () => {
        ;[wallet, other] = await (ethers as any).getSigners();
        loadFixture = waffle.createFixtureLoader([wallet, other]);
    });

    const oracleFixture = async () => {
        const oracleTestFactory = await ethers.getContractFactory('OracleTest');
        return (await oracleTestFactory.deploy()) as OracleTest;
    }

    const initializedOracleFixture = async () => {
        const oracle = await oracleFixture();
        await oracle.initialize({
            time: 0,
            tick: 0,
            liquidity: 0,
        });
        return oracle;
    }

    describe('#initialize', () => {
        let oracle: OracleTest;
        beforeEach('deploy test oracle', async () => {
            oracle = await loadFixture(oracleFixture);
        });
        it('index is 0', async () => {
            await oracle.initialize({ liquidity: 1, tick: 1, time: 1 });
            expect(await oracle.index()).to.eq(0);
        });
        it('cardinality is 1', async () => {
            await oracle.initialize({ liquidity: 1, tick: 1, time: 1 });
            expect(await oracle.cardinality()).to.eq(1);
        });
        it('cardinality next is 1', async () => {
            await oracle.initialize({ liquidity: 1, tick: 1, time: 1 });
            expect(await oracle.cardinalityNext()).to.eq(1);
        });
        it('sets first slot timestamp only', async () => {
            await oracle.initialize({ liquidity: 1, tick: 1, time: 1 });
            checkObservationEquals(await oracle.observations(0), {
                initialized: true,
                blockTimestamp: 1,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
            });
        });
        it('gas', async () => {
            await snapshotGasCost(oracle.initialize({ liquidity: 1, tick: 1, time: 1 }));
        });
    });

    describe('#grow', () => {
        let oracle: OracleTest;
        beforeEach('deploy initialized test oracle', async () => {
            oracle = await loadFixture(initializedOracleFixture);
        });

        it('increases the cardinality next for the first call', async () => {
            await oracle.grow(5);
            expect(await oracle.index()).to.eq(0);
            expect(await oracle.cardinality()).to.eq(1);
            expect(await oracle.cardinalityNext()).to.eq(5);
        });
    });

    describe('#write', () => {
        let oracle: OracleTest;

        beforeEach('deploy initialized test oracle', async () => {
            oracle = await loadFixture(initializedOracleFixture);
        });

        it('single element array gets overwritten', async () => {
            await oracle.update({ advanceTimeBy: 1, tick: 2, liquidity: 5 });
            expect(await oracle.index()).to.eq(0);
            checkObservationEquals(await oracle.observations(0), {
                initialized: true,
                secondsPerLiquidityCumulativeX128: '340282366920938463463374607431768211456',
                tickCumulative: 0,
                blockTimestamp: 1,
            });
            await oracle.update({ advanceTimeBy: 5, tick: -1, liquidity: 8 });
            expect(await oracle.index()).to.eq(0);
            checkObservationEquals(await oracle.observations(0), {
                initialized: true,
                secondsPerLiquidityCumulativeX128: '680564733841876926926749214863536422912',
                tickCumulative: 10,
                blockTimestamp: 6,
            });
            await oracle.update({ advanceTimeBy: 3, tick: 2, liquidity: 3 });
            expect(await oracle.index()).to.eq(0)
            checkObservationEquals(await oracle.observations(0), {
                initialized: true,
                secondsPerLiquidityCumulativeX128: '808170621437228850725514692650449502208',
                tickCumulative: 7,
                blockTimestamp: 9,
            });
        });

        it('does nothing if time has not changed', async () => {
            await oracle.grow(2);
            await oracle.update({ advanceTimeBy: 1, tick: 3, liquidity: 2 });
            expect(await oracle.index()).to.eq(1);
            await oracle.update({ advanceTimeBy: 0, tick: -5, liquidity: 9 });
            expect(await oracle.index()).to.eq(1);
        });

        it('writes an index if time has changed', async () => {
            await oracle.grow(3);
            await oracle.update({ advanceTimeBy: 6, tick: 3, liquidity: 2 });
            expect(await oracle.index()).to.eq(1);
            await oracle.update({ advanceTimeBy: 4, tick: -5, liquidity: 9 });

            expect(await oracle.index()).to.eq(2);
            checkObservationEquals(await oracle.observations(1), {
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: '2041694201525630780780247644590609268736',
                initialized: true,
                blockTimestamp: 6,
            });
        });

        it('grows cardinality when writing past', async () => {
            await oracle.grow(2);
            await oracle.grow(4);
            expect(await oracle.cardinality()).to.eq(1);
            await oracle.update({ advanceTimeBy: 3, tick: 5, liquidity: 6 });
            expect(await oracle.cardinality()).to.eq(4);
            await oracle.update({ advanceTimeBy: 4, tick: 6, liquidity: 4 });
            expect(await oracle.cardinality()).to.eq(4);
            expect(await oracle.index()).to.eq(2);
            checkObservationEquals(await oracle.observations(2), {
                secondsPerLiquidityCumulativeX128: '1247702012043441032699040227249816775338',
                tickCumulative: 20,
                initialized: true,
                blockTimestamp: 7,
            });
        });

        it('wraps around', async () => {
            await oracle.grow(3);
            await oracle.update({ advanceTimeBy: 3, tick: 1, liquidity: 2 });
            await oracle.update({ advanceTimeBy: 4, tick: 2, liquidity: 3 });
            await oracle.update({ advanceTimeBy: 5, tick: 3, liquidity: 4 });

            expect(await oracle.index()).to.eq(0);

            checkObservationEquals(await oracle.observations(0), {
                secondsPerLiquidityCumulativeX128: '2268549112806256423089164049545121409706',
                tickCumulative: 14,
                initialized: true,
                blockTimestamp: 12,
            });
        });

        it('accumulates liquidity', async () => {
            await oracle.grow(4);

            await oracle.update({ advanceTimeBy: 3, tick: 3, liquidity: 2 });
            await oracle.update({ advanceTimeBy: 4, tick: -7, liquidity: 6 });
            await oracle.update({ advanceTimeBy: 5, tick: -2, liquidity: 4 });

            expect(await oracle.index()).to.eq(3);

            checkObservationEquals(await oracle.observations(1), {
                initialized: true,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: '1020847100762815390390123822295304634368',
                blockTimestamp: 3,
            });
            checkObservationEquals(await oracle.observations(2), {
                initialized: true,
                tickCumulative: 12,
                secondsPerLiquidityCumulativeX128: '1701411834604692317316873037158841057280',
                blockTimestamp: 7,
            });
            checkObservationEquals(await oracle.observations(3), {
                initialized: true,
                tickCumulative: -23,
                secondsPerLiquidityCumulativeX128: '1984980473705474370203018543351981233493',
                blockTimestamp: 12,
            });
            checkObservationEquals(await oracle.observations(4), {
                initialized: false,
                tickCumulative: 0,
                secondsPerLiquidityCumulativeX128: 0,
                blockTimestamp: 0,
            });
        });
    });

    describe('#observe', () => {
        describe('before initialization', async () => {
            let oracle: OracleTest;
            beforeEach('deploy test oracle', async () => {
                oracle = await loadFixture(oracleFixture);
            });

            const observeSingle = async (secondsAgo: number) => {
                const {
                    tickCumulatives: [tickCumulative],
                    secondsPerLiquidityCumulativeX128s: [secondsPerLiquidityCumulativeX128],
                } = await oracle.observe([secondsAgo]);
                return { secondsPerLiquidityCumulativeX128, tickCumulative }
            }

            it('fails before initialize', async () => {
                await expect(observeSingle(0)).to.be.revertedWith('I');
            });

            it('fails if an older observation does not exist', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                await expect(observeSingle(1)).to.be.revertedWith('OLD');
            });

            it('does not fail across overflow boundary', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 2 ** 32 - 1 });
                await oracle.advanceTime(2);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(1);
                expect(tickCumulative).to.be.eq(2);
                expect(secondsPerLiquidityCumulativeX128).to.be.eq('85070591730234615865843651857942052864');
            });

            it('interpolates correctly at max liquidity', async () => {
                await oracle.initialize({ liquidity: MaxUint128, tick: 0, time: 0 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 13, tick: 0, liquidity: 0 });
                let { secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(13);
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(6));
                expect(secondsPerLiquidityCumulativeX128).to.eq(7);
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(12));
                expect(secondsPerLiquidityCumulativeX128).to.eq(1);
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(13));
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('interpolates correctly at min liquidity', async () => {
                await oracle.initialize({ liquidity: 0, tick: 0, time: 0 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 13, tick: 0, liquidity: MaxUint128 });
                let { secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(13).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(6));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(7).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(12));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(1).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(13));
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('interpolates the same as 0 liquidity for 1 liquidity', async () => {
                await oracle.initialize({ liquidity: 1, tick: 0, time: 0 });
                await oracle.grow(2)
                await oracle.update({ advanceTimeBy: 13, tick: 0, liquidity: MaxUint128 });
                let { secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(13).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(6));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(7).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(12));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(1).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(13));
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('interpolates correctly across uint32 seconds boundaries', async () => {
                // setup
                await oracle.initialize({ liquidity: 0, tick: 0, time: 0 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 2 ** 32 - 6, tick: 0, liquidity: 0 });
                let { secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(2 ** 32 - 6).shl(128));
                await oracle.update({ advanceTimeBy: 13, tick: 0, liquidity: 0 });
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(0));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(7).shl(128));

                // interpolation checks
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(3));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(4).shl(128));
                ;({ secondsPerLiquidityCumulativeX128 } = await observeSingle(8));
                expect(secondsPerLiquidityCumulativeX128).to.eq(BigNumber.from(2 ** 32 - 1).shl(128));
            });

            it('single observation at current time', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('single observation in past but not earlier than secondsAgo', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                await oracle.advanceTime(3);
                await expect(observeSingle(4)).to.be.revertedWith('OLD');
            });

            it('single observation in past at exactly seconds ago', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                await oracle.advanceTime(3);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(3);
                expect(tickCumulative).to.eq(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('single observation in past counterfactual in past', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                await oracle.advanceTime(3);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(1);
                expect(tickCumulative).to.eq(4);
                expect(secondsPerLiquidityCumulativeX128).to.eq('170141183460469231731687303715884105728');
            });

            it('single observation in past counterfactual now', async () => {
                await oracle.initialize({ liquidity: 4, tick: 2, time: 5 });
                await oracle.advanceTime(3);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(6);
                expect(secondsPerLiquidityCumulativeX128).to.eq('255211775190703847597530955573826158592');
            });

            it('two observations in chronological order 0 seconds ago exact', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(-20);
                expect(secondsPerLiquidityCumulativeX128).to.eq('272225893536750770770699685945414569164');
            });

            it('two observations in chronological order 0 seconds ago counterfactual', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(-13);
                expect(secondsPerLiquidityCumulativeX128).to.eq('1463214177760035392892510811956603309260');
            });

            it('two observations in chronological order seconds ago is exactly on first observation', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(11);
                expect(tickCumulative).to.eq(0);
                expect(secondsPerLiquidityCumulativeX128).to.eq(0);
            });

            it('two observations in chronological order seconds ago is between first and second', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(9);
                expect(tickCumulative).to.eq(-10);
                expect(secondsPerLiquidityCumulativeX128).to.eq('136112946768375385385349842972707284582');
            });

            it('two observations in reverse order 0 seconds ago exact', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.update({ advanceTimeBy: 3, tick: -5, liquidity: 4 });
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(-17);
                expect(secondsPerLiquidityCumulativeX128).to.eq('782649443918158465965761597093066886348');
            });

            it('two observations in reverse order 0 seconds ago counterfactual', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.update({ advanceTimeBy: 3, tick: -5, liquidity: 4 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                expect(tickCumulative).to.eq(-52);
                expect(secondsPerLiquidityCumulativeX128).to.eq('1378143586029800777026667160098661256396');
            });

            it('two observations in reverse order seconds ago is exactly on first observation', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.update({ advanceTimeBy: 3, tick: -5, liquidity: 4 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(10);
                expect(tickCumulative).to.eq(-20);
                expect(secondsPerLiquidityCumulativeX128).to.eq('272225893536750770770699685945414569164');
            });

            it('two observations in reverse order seconds ago is between first and second', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.grow(2);
                await oracle.update({ advanceTimeBy: 4, tick: 1, liquidity: 2 });
                await oracle.update({ advanceTimeBy: 3, tick: -5, liquidity: 4 });
                await oracle.advanceTime(7);
                const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(9);
                expect(tickCumulative).to.eq(-19);
                expect(secondsPerLiquidityCumulativeX128).to.eq('442367076997220002502386989661298674892');
            });

            it('can fetch multiple observations', async () => {
                await oracle.initialize({ time: 5, tick: 2, liquidity: BigNumber.from(2).pow(15) });
                await oracle.grow(4);
                await oracle.update({ advanceTimeBy: 13, tick: 6, liquidity: BigNumber.from(2).pow(12) });
                await oracle.advanceTime(5);

                const { tickCumulatives, secondsPerLiquidityCumulativeX128s } = await oracle.observe([0, 3, 8, 13, 15, 18]);
                expect(tickCumulatives).to.have.lengthOf(6);
                expect(tickCumulatives[0]).to.eq(56);
                expect(tickCumulatives[1]).to.eq(38);
                expect(tickCumulatives[2]).to.eq(20);
                expect(tickCumulatives[3]).to.eq(10);
                expect(tickCumulatives[4]).to.eq(6);
                expect(tickCumulatives[5]).to.eq(0);
                expect(secondsPerLiquidityCumulativeX128s).to.have.lengthOf(6);
                expect(secondsPerLiquidityCumulativeX128s[0]).to.eq('550383467004691728624232610897330176');
                expect(secondsPerLiquidityCumulativeX128s[1]).to.eq('301153217795020002454768787094765568');
                expect(secondsPerLiquidityCumulativeX128s[2]).to.eq('103845937170696552570609926584401920');
                expect(secondsPerLiquidityCumulativeX128s[3]).to.eq('51922968585348276285304963292200960');
                expect(secondsPerLiquidityCumulativeX128s[4]).to.eq('31153781151208965771182977975320576');
                expect(secondsPerLiquidityCumulativeX128s[5]).to.eq(0);
            });

            it('gas for observe since most recent', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.advanceTime(2);
                await snapshotGasCost(oracle.getGasCostOfObserve([1]));
            });

            it('gas for single observation at current time', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await snapshotGasCost(oracle.getGasCostOfObserve([0]));
            });

            it('gas for single observation at current time counterfactually computed', async () => {
                await oracle.initialize({ liquidity: 5, tick: -5, time: 5 });
                await oracle.advanceTime(5);
                await snapshotGasCost(oracle.getGasCostOfObserve([0]));
            });
        });

        for (const startingTime of [5, 2 ** 32 - 5]) {
            describe(`initialized with 5 observations with starting time of ${startingTime}`, () => {
                const oracleFixture5Observations = async () => {
                    const oracle = await oracleFixture();
                    await oracle.initialize({liquidity: 5, tick: -5, time: startingTime});
                    await oracle.grow(5);
                    await oracle.update({advanceTimeBy: 3, tick: 1, liquidity: 2});
                    await oracle.update({advanceTimeBy: 2, tick: -6, liquidity: 4});
                    await oracle.update({advanceTimeBy: 4, tick: -2, liquidity: 4});
                    await oracle.update({advanceTimeBy: 1, tick: -2, liquidity: 9});
                    await oracle.update({advanceTimeBy: 3, tick: 4, liquidity: 2});
                    await oracle.update({advanceTimeBy: 6, tick: 6, liquidity: 7});
                    return oracle;
                }
                let oracle: OracleTest;
                beforeEach('set up observations', async () => {
                    oracle = await loadFixture(oracleFixture5Observations);
                });

                const observeSingle = async (secondsAgo: number) => {
                    const {
                        tickCumulatives: [tickCumulative],
                        secondsPerLiquidityCumulativeX128s: [secondsPerLiquidityCumulativeX128],
                    } = await oracle.observe([secondsAgo]);
                    return {secondsPerLiquidityCumulativeX128, tickCumulative}
                }
                it('index, cardinality, cardinality next', async () => {
                    expect(await oracle.index()).to.eq(1);
                    expect(await oracle.cardinality()).to.eq(5);
                    expect(await oracle.cardinalityNext()).to.eq(5);
                });

                it('latest observation same time as latest', async () => {
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                    expect(tickCumulative).to.eq(-21);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('2104079302127802832415199655953100107502');
                });
                it('latest observation 5 seconds after latest', async () => {
                    await oracle.advanceTime(5);
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(5);
                    expect(tickCumulative).to.eq(-21);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('2104079302127802832415199655953100107502');
                });
                it('current observation 5 seconds after latest', async () => {
                    await oracle.advanceTime(5);
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(0);
                    expect(tickCumulative).to.eq(9);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('2347138135642758877746181518404363115684');
                });
                it('between latest observation and just before latest observation at same time as latest', async () => {
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(3);
                    expect(tickCumulative).to.eq(-33);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('1593655751746395137220137744805447790318');
                });
                it('between latest observation and just before latest observation after the latest observation', async () => {
                    await oracle.advanceTime(5);
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(8);
                    expect(tickCumulative).to.eq(-33);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('1593655751746395137220137744805447790318');
                });
                it('older than oldest reverts', async () => {
                    await expect(observeSingle(15)).to.be.revertedWith('OLD');
                    await oracle.advanceTime(5);
                    await expect(observeSingle(20)).to.be.revertedWith('OLD');
                });
                it('oldest observation', async () => {
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(14);
                    expect(tickCumulative).to.eq(-13);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('544451787073501541541399371890829138329');
                });
                it('oldest observation after some time', async () => {
                    await oracle.advanceTime(6);
                    const { tickCumulative, secondsPerLiquidityCumulativeX128 } = await observeSingle(20);
                    expect(tickCumulative).to.eq(-13);
                    expect(secondsPerLiquidityCumulativeX128).to.eq('544451787073501541541399371890829138329');
                });

                it('fetch many values', async () => {
                    await oracle.advanceTime(6);
                    const { tickCumulatives, secondsPerLiquidityCumulativeX128s } = await oracle.observe([
                        20,
                        17,
                        13,
                        10,
                        5,
                        1,
                        0,
                    ]);
                    expect({
                        tickCumulatives: tickCumulatives.map((tc) => tc.toNumber()),
                        secondsPerLiquidityCumulativeX128s: secondsPerLiquidityCumulativeX128s.map((lc) => lc.toString()),
                    }).to.matchSnapshot();
                });

                it('gas all of last 20 seconds', async () => {
                    await oracle.advanceTime(6);
                    await snapshotGasCost(
                        oracle.getGasCostOfObserve([20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0])
                    );
                });

                it('gas latest equal', async () => {
                    await snapshotGasCost(oracle.getGasCostOfObserve([0]));
                });
                it('gas latest transform', async () => {
                    await oracle.advanceTime(5);
                    await snapshotGasCost(oracle.getGasCostOfObserve([0]));
                });
                it('gas oldest', async () => {
                    await snapshotGasCost(oracle.getGasCostOfObserve([14]));
                });
                it('gas between oldest and oldest + 1', async () => {
                    await snapshotGasCost(oracle.getGasCostOfObserve([13]));
                });
                it('gas middle', async () => {
                    await snapshotGasCost(oracle.getGasCostOfObserve([5]));
                });
            });
        }
    });

    describe('full oracle', () => {

    });
});