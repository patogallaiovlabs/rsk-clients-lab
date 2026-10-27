# What totalMs covers in each client

Both clients write one line per block connected as best:

```
block connect breakdown best: block=<n> hash=<hex> totalMs=<ms> <phase>Ms=... txCount=<n> gasUsed=<n>
```

RSKj prints whole milliseconds (`TimeUnit.NANOSECONDS.toMillis`); rustock prints milliseconds
with three decimals. A phase with the same name does the same work in both. References are to
RSKj `e507f4503` (`clients/rskj`) and rustock `clients-lab/comparison` (`clients/rustock`).

## RSKj

`rskj-core/src/main/java/co/rsk/core/bc/BlockChainImpl.java`, `internalTryToConnect` (205).
The clock starts at 213 and the line is logged at 393.

| Phase | Lines | Work |
|---|---|---|
| preambleMs | 213 to 274 | duplicate check, best block and parent lookup |
| initialValidationMs | 274 to 284 | `isValid(block)`: header and body rules, proof of work (skipped by `skipPowValidation`), transactions root, uncles |
| executeMs | 293 to 297 | `blockExecutor.execute`: transactions, REMASC, state root |
| postExecuteValidationMs | 302 to 306 | `blockExecutor.validate`: state root, receipts root, logs bloom, gas used, paid fees against the header |
| stateRootRegisterMs | 330 to 334 | `stateRootHandler.register` |
| switchChainMs | 353 to 357 | `switchToBlockChain`: block saved, made best |
| saveReceiptsMs | 359 to 363 | `saveReceipts` |
| processBestMs | 365 to 369 | `transactionPool.processBest` |
| onBestBlockMs | 371 to 375 | listeners, among them `BlockChainFlusher` (`BlockChainFlusher.java` 107 to 114, 144), which flushes the stores every `flushNumberOfBlocks` blocks. Its counter starts at 1, so replaying from block 1 with 10 it flushes at blocks 10, 20, and so on |
| onBlockMs | 377 to 381 | `onBlock` listeners |

totalMs runs from 213 to the log call, so it includes every phase above, the flush on every
tenth block among them. Outside it: decoding the line and the block in `ConnectBlocks`
(`co/rsk/cli/tools/ConnectBlocks.java` 78 to 90), `tryToConnect`'s lock (137), and the final
`flushAll` at shutdown.

## rustock

`crates/sync/src/import.rs`, `BlockImporter::import` (252), called once per line by
`run_import_blocks` (`crates/cli/src/main.rs` 3352, call at 3388). The phase clock is `Laps`,
which reads `Instant::now` only when `--breakdown-log` is given.

| Phase | Lines | Work |
|---|---|---|
| preambleMs | 252 to 266 | the block extends the best block |
| initialValidationMs | 268 to 274, plus `process_block`'s first stage (`crates/execution/src/processor.rs` 766 to 803) | `HeaderVerifier::verify` against the parent (proof of work skipped by `--skip-pow-validation`), `validate_block` (body rules, uncles, fork detection data), transactions root, ommers hash |
| executeMs | `processor.rs` 826 to 832 | `execute_block`: sender recovery, transactions, REMASC, trie update, state root, trie nodes saved, receipts root. `trieSaveMs`, logged beside it, is the part spent in `TrieNode::save` (one batch write of the dirty nodes into the trie store). Lookups during execution stay in `executeMs` |
| postExecuteValidationMs | `processor.rs` 805 to 902 | gas used, paid fees, state root, receipts root, logs bloom against the header |
| switchChainMs | 297 to 302 | `store_headers_batch` (header, total difficulty, canonical index, head) and `put_body` |
| saveReceiptsMs | 303 to 304 | `commit_receipts`: receipts, transaction index, Bridge event index |
| onBestBlockMs | 309 to 319 | `ExecutionCommitter::after_block`: every `--import-flush-every` blocks, the trie store flushed and the executed head recorded; zero otherwise. Same cadence as RSKj: blocks 10, 20, and so on |

totalMs (320) covers the whole call, the flush included. Outside it: reading and decoding the
line (`parse_export_line`, `main.rs` 3382) and the final flush in `BlockImporter::finish`.

**Mined blocks.** `crates/execution/src/mining/server.rs`, `MinerServer::complete_and_import`,
writes the same line for a block the node mines and connects (`--mine`, with
`--breakdown-log`). The clock starts when the solution is matched to its template and the
line is written after the commit. preambleMs: the template looked up by its merged-mining
hash and the executed-head check. initialValidationMs: `MergedMiningRule::validate` (proof of
work skipped by `--skip-pow-validation`) plus `process_block`'s first stage, transactions root
and ommers hash. executeMs and postExecuteValidationMs: as on the import path, the same
`process_block_timed`. saveReceiptsMs: `commit_receipts`, which runs before the
block is stored on this path (the import stores first), so the two phases swap order; the
line names them, so the analyzer does not care. switchChainMs: header, body and total
difficulty written, then the canonical index and the executed head. onBestBlockMs: the
committed hook (the pool told what was mined, `remove_mined` and `evict_outdated`) and the
trie flush every `--flush-every` blocks (default 10), zero otherwise. totalMs covers all of
them, rskj's `internalTryToConnect` scope for a mined block (`addNewMinedBlock` is
`tryToConnect`). Outside it on both sides: the template build, which executes the block
once more before the connect, the nonce handling and the RPC.

## Differences that remain

- rustock has nothing like `stateRootRegisterMs`, `processBestMs` or `onBlockMs`: there is no
  separate state-root table, no transaction pool and no listener in the import. The work is
  not done, so it is not timed.
- RSKj's execute covers less than rustock's: RSKj saves trie nodes to its store at flush time,
  while rustock's `execute_block` writes them to the trie store's memory every block. Both
  totals include the work; the split between executeMs and onBestBlockMs differs.
- What a flush writes differs. RSKj flushes five stores in parallel (unitrie, blocks,
  receipts, blooms, state roots). rustock flushes its trie store; headers, bodies and receipts
  go to its block database as they are stored, inside switchChainMs and saveReceiptsMs.
- RSKj rounds every phase down to a whole millisecond; sums of RSKj phases fall short of its
  totalMs by up to one millisecond per phase.

`trieSaveMs` (both rustock lines): the part of `executeMs` spent writing dirty trie nodes to the trie store, a comparison-only probe on `clients-lab/comparison`; RSKj has no such phase.
