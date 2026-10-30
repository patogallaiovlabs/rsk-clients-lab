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

## Status

Fixed on 2026-10-30, rustock branch `fix/miner-gas-packing-cap-and-gasprice-gate`, all six:

- `SubmissionRateLimiter` on the miner server, `--mining-submission-rate-limit-ms` (zero, rskj's
  default, disables it); a refused submission answers `RateLimited`, and the submission counts
  whether or not the work is found, as `processSolution` has it.
- A resubmitted solution is recognised by its completed block hash before the parent check and
  answered `EXIST`, as `addNewMinedBlock` does; rustock's own test asserting the old error is
  replaced by the port of `submitTwoBitcoinBlocksAtSameTimeWithoutRateLimit`.
- The sync service carries `BestBlockListeners`; the miner registers `on_best_block`, which
  resets the fee accumulator and rebuilds. The pool carries an `on_added` listener; behind
  `--mining-update-work-on-new-transaction` (off by default, as rskj's
  `updateWorkOnNewTransaction`) the miner's `RebuildPolicy` rebuilds once arrivals pay a tenth
  of the candidate's fees, rskj's `isWorthRebuilding`.
- `extraData` is rskj's RLP `[1, "<version>-<commit>", client]`, the client string cut to keep
  the field within 32 bytes (`mining/extra_data.rs`); the commit comes from `RUSTOCK_GIT_COMMIT`
  at build time, "unknown" otherwise.
- `--mining-min-gas-price` sets `MiningConfig.min_gas_price_target`, so the RSKIP-09 step already
  implemented is reached.
- `filter_candidates` reports the underpriced and over-cap candidates as rskj's `txsToRemove`, and
  the builder removes them from the pool through `remove_transactions` (the hook that already
  carried the EVM-refused ones).

Tests ported: the six `SubmissionRateLimitHandlerTest` cases, `MinerServerTest`'s two
rate-limit submissions, three `extraData` cases, `onBestBlockBuildBlockToMine`,
`onNewTxBuildBlockToMine`, the two `rebuilds*` cases and `secondBuildBlockToMineTurnsNotifyFlagOff`,
the seven `MinimumGasPriceCalculatorTest` cases, and `MinerUtilsTest.invalidGasPriceTransactionTest`.
