# --breakdown-log on the mined path: the connect timing line for blocks this node mines

Branch `harness/mined-block-timing` in `clients/rustock`, on `harness/timed-mining`. One commit.

## What and why

`--breakdown-log` wrote rskj's `block connect breakdown best:` line only from `--import-blocks`.
A block the node mined itself was reported with one info line and no duration, so a live arm,
where each client mines its own blocks under k6, had nothing the analyzer could read.
`MinerServer::complete_and_import` now times its phases with the same clock and the same keys,
and writes the line to the `--breakdown-log` file for every block it connects as best:

```
block connect breakdown best: block=<n> hash=<hex> totalMs=<ms> preambleMs=... initialValidationMs=...
  executeMs=... postExecuteValidationMs=... switchChainMs=... saveReceiptsMs=... onBestBlockMs=...
  txCount=<n> gasUsed=<n>
```

The timing types move from `rustock_sync::import` to a new `rustock_execution::breakdown`
(`ConnectTimings`, `Laps`, the line format); the sync crate re-exports `ConnectTimings` as
`ImportTimings`, so the import path is unchanged. `process_and_commit` is called as its two
halves, `process_block` (timed when measuring) and `commit_receipts`, so receipts can be timed
apart from execution; the block is validated, executed and stored exactly as before. Without the
flag no clock is read and no sink is set. The CLI opens the file once, writes each line and
flushes it, so the file is complete whenever the node is stopped.

Paragraph for the lab's `docs/timing-scope.md`, under rustock:

> **Mined blocks.** `crates/execution/src/mining/server.rs`, `MinerServer::complete_and_import`,
> writes the same line for a block the node mines and connects (`--mine`, with
> `--breakdown-log`). The clock starts when the solution is matched to its template and the
> line is written after the commit. preambleMs: the template looked up by its merged-mining
> hash and the executed-head check. initialValidationMs: `MergedMiningRule::validate` (proof of
> work skipped by `--skip-pow-validation`) plus `process_block`'s first stage, transactions root
> and ommers hash. executeMs and postExecuteValidationMs: as on the import path, the same
> `process_block_timed`. saveReceiptsMs: `commit_receipts`, which runs before the
> block is stored on this path (the import stores first), so the two phases swap order; the
> line names them, so the analyzer does not care. switchChainMs: header, body and total
> difficulty written, then the canonical index and the executed head. onBestBlockMs: the
> committed hook (the pool told what was mined, `remove_mined` and `evict_outdated`) and the
> trie flush every `--flush-every` blocks (default 10), zero otherwise. totalMs covers all of
> them, rskj's `internalTryToConnect` scope for a mined block (`addNewMinedBlock` is
> `tryToConnect`). Outside it on both sides: the template build, which executes the block
> once more before the connect, the nonce handling and the RPC.

## How to test

```bash
cargo test -p rustock-execution breakdown
cargo test -p rustock-execution mining::tests::a_mined_block_writes_the_breakdown_line
cargo test -p rustock-sync import
cargo test -p rustock-cli --test import_blocks
```

`a_mined_block_writes_the_breakdown_line` mines three blocks through a server with a sink and
checks one line per block, in order, with exactly the twelve keys of the import path's line in
its order, a total that bounds the sum of the phases, and the block's hash and transaction
count. `without_a_breakdown_sink_nothing_is_written_and_mining_is_unchanged` is the off case.
`breakdown::tests` cover the line format (moved from the sync crate) and that disabled laps
read no clock. The import tests still pass, line for line.

By hand, on the lab's genesis with `--mine --mine-timed 1s --breakdown-log <file>`: one line
per mined block, `txCount=1 gasUsed=0` for an empty block (REMASC only), `txCount=3
gasUsed=42000` for one with two transfers; totals of 2 to 4 ms in a debug build.
