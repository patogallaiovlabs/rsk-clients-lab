# Proposal: map every rskj test to a rustock test by name

For SergioDemianLerner/rustock. Follows the two issues found by rsk-clients-lab on
2026-10-29 (the miner and the RSKIP252 cap; `eth_gasPrice` and the fee-market gate).

## Why

Both bugs have an rskj unit test that names the behaviour:

| behaviour | rskj test | rustock's nearest test |
|---|---|---|
| miner leaves out transactions over 100x the minimum | `MinerUtilsTest.filterTransactions_whenRskip252EnabledThenTxWithMoreGasPriceThanCapExcluded` | none; `block_txs_max_gas_price_enforces_the_100x_cap_from_rskip252` covers import only |
| `eth_gasPrice` ignores the tracker while the fee market is not working | `EthereumImplTest.getGasPrice_returns_correctedBestBlockValue_when_feeMarketWorking_is_false` | `test_eth_gas_price_uses_the_tracker`, `test_eth_gas_price_falls_back_to_the_block_minimum`: tracker present or absent, never the flag |

The port was organised by rskj class: the validator package came in one commit
(94194c0, "the eight mainnet block-validity rules"), the miner the day before (892ea1f), the
gas price tracker two days later (b086158, "port rskj's GasPriceTracker, and use it"). Each
ported its class and the tests of that class. A rule rskj enforces in two classes (the cap,
in `BlockTxsMaxGasPriceRule` and again in `MinerUtils`) or a check that lives in the caller
of the ported class (the gate, in `EthereumImpl` rather than in the tracker) falls between
the slices. The rustock tests that exist in those areas follow rustock's own structure,
which is what tests written after the code look like; translated tests would have had
rskj's shape and would have failed.

Neither bug shows on mainnet, where the minimum tracks the market, nor on regtest, where
the minimum is 0 and the cap does not apply. Sync and regtest checks cannot find this class
of gap. The rskj test names can.

## What

One pass over rskj's test tree (`rskj-core/src/test/java`, 6869 `@Test` methods at
e507f45; rustock has 2517 `#[test]`/`#[tokio::test]` functions at 1909b1c), producing a table
with one row per rskj test: the rustock test that covers it, or one of three verdicts.

1. **Covered**: a rustock test asserts the same behaviour, named in the row.
2. **Not applicable**: the behaviour does not exist in rustock by design (a Java-side
   concern, a removed feature, a config format), with the reason.
3. **Gap**: rustock has the feature and no test of that case. Each gap is then checked
   against the code before anything is written, since a gap in tests is not yet a bug.

Order by risk, since 6869 rows is weeks of work if done uniformly: consensus and
block-validity packages first (`co.rsk.validators`, 75 tests; `co.rsk.mine`, 132;
`co.rsk.net.handler.txvalidator`, 21; `org.ethereum.facade`, 2; then `co.rsk.core.bc`,
`co.rsk.peg`, `org.ethereum.core`, the VM). The table is a file in the repository, so the
next port of an rskj change updates its rows.

The two issues above are the first two rows with verdict 3. A pass over the four packages
named here is a few days and would say whether they are the only two.
