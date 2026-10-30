# rustock's miner is stopped by one invalid pending transaction and mines while syncing

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-30 by mapping rskj's tests
(e507f45) to rustock's (branch `fix/miner-gas-packing-cap-and-gasprice-gate` on 1909b1c); the
full table is `docs/rskj-test-parity.md` in rustock.

Not consensus; it is whether the miner produces blocks at all.

## What happens

A pending transaction the EVM refuses before running it, for a nonce the state no longer
expects, a balance that no longer covers it or too little intrinsic gas, makes `execute_block`
fail (`crates/execution/src/executor.rs`, the `EVMError` is propagated with `?`), and with it
the template. The pool admitted the transaction when it was valid; the state moved. rskj's
`BlockToMineBuilder` collects the executor's invalid transactions and removes them from the
pool (`BlockToMineBuilderInvalidTxEvictionTest`, `BlockToMineBuilderEvictionEndToEndTest`).
rustock's mining mode of the executor drops only what does not fit the block's gas, and
`PendingTransactionSource` has no eviction hook; the transaction stays until
`evict_outdated` reaches it, and no template builds meanwhile.

rskj's `MinerClientImpl.mineBlock` refuses to mine while `hasBetterBlockToSync()`
(`MinerManagerTest.mineBlockWhileSyncingBlocks`). rustock's `MinerServer`, `TimedMiner` and
`AutoMiner` never consult sync state, so a node catching up mines on a stale head.

## Fix

In the executor's mining mode, treat a pre-execution `EVMError::Transaction` as rskj treats an
invalid transaction: drop it, drop the sender's later ones, report the indices; give the
template builder a way to tell the pool, and remove them. Gate `build_work` on the sync
service reporting no better block to fetch. Port the three rskj tests.
