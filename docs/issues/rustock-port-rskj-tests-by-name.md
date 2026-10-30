# Proposal: check every rskj test has a rustock counterpart

For SergioDemianLerner/rustock. Follows the two issues rsk-clients-lab found on 2026-10-29
(the miner and the RSKIP252 cap; `eth_gasPrice` and the fee-market gate).

## Why

Both bugs have an rskj test that names the missing behaviour:

| rskj test | rustock |
|---|---|
| `MinerUtilsTest.filterTransactions_whenRskip252EnabledThenTxWithMoreGasPriceThanCapExcluded` | no test; the cap is tested on import only |
| `EthereumImplTest.getGasPrice_returns_correctedBestBlockValue_when_feeMarketWorking_is_false` | no test; tracker present or absent is tested, the flag is not |

Both rows are closed as of 2026-10-30 (see the status at the end of each issue); the table
stands as the example of the gap this proposal is about.

The port went class by class: validators in one commit, the miner in another, the gas
price tracker in a third. A rule rskj applies in two classes (the cap: `BlockTxsMaxGasPriceRule`
and `MinerUtils`) or in the caller of the ported class (the gate: `EthereumImpl`, not the
tracker) fell between the slices. Neither bug shows on mainnet or regtest, so syncing cannot
catch this kind of gap. The rskj test names can.

## What

A table with one row per rskj test (6869 at e507f45; rustock has 2517) and one of three
verdicts: **covered** (name the rustock test), **not applicable** (say why), or **gap**. Each
gap is checked against the code before anything is filed.

Start with the consensus packages, a few days of work: `co.rsk.validators` (75 tests),
`co.rsk.mine` (132), `co.rsk.net.handler.txvalidator` (21), `org.ethereum.facade` (2). Keep
the table in the repository so later ports update it. The two issues above are its first
two gaps.
