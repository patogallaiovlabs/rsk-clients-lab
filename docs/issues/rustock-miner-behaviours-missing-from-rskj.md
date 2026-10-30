# rustock's miner lacks six behaviours rskj's `MinerServerImpl` has

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-30 by mapping rskj's tests
(e507f45) to rustock's (branch `fix/miner-gas-packing-cap-and-gasprice-gate` on 1909b1c); the
full table is `docs/rskj-test-parity.md` in rustock.

Operational, none consensus. Listed together because each is small; the parity table names
the rskj test for each.

- **Submission rate limit.** rskj's `SubmissionRateLimitHandler`
  (`miner.server.workSubmissionRateLimitInMills`) refuses a second submission inside the
  window. rustock's submit path accepts every one (`crates/execution/src/mining/server.rs`).
  Seven rskj tests.
- **Duplicate submission.** rskj answers a resubmitted solution with `OK`; rustock answers
  `ParentNoLongerHead`, and its own test asserts that.
- **Template rebuild triggers.** rskj rebuilds on a new best block and on new pending
  transactions whose fees cross `minFeesNotifyInDollars` (`NewBlockTxListener`); rustock
  rebuilds on a timer and after its own submission. Four tests.
- **extraData format.** rskj writes RLP `[1, "<version>-<commit>", clientExtraData]`
  truncated to 32 bytes; rustock writes the configured bytes raw and refuses more than 32 at
  startup. Three tests.
- **Minimum gas price target.** `next_minimum_gas_price` implements RSKIP-09's 1% step, but
  `MiningConfig.min_gas_price_target` is never set, so the miner only inherits the parent's
  minimum and never walks it toward `miner.minGasPrice`. Seven `MinimumGasPriceCalculatorTest`
  tests have no counterpart.
- **Eviction of underpriced transactions.** The template skips a transaction under the
  block's minimum but does not remove it from the pool as rskj's `txsToRemove` does.

## Fix

Each is a port of the named rskj class with its tests; the minimum gas price target is a
one-line wiring in `crates/cli/src/main.rs` plus the tests.
