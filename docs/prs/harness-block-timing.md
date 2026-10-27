# --breakdown-log: one timing line per imported block, in rskj's shape

Branch `harness/block-timing` in `clients/rustock`, on `harness/import-blocks`. One commit.

## What and why

rskj logs, per block it connects as best, `block connect breakdown best:` with `totalMs` and the
time of each phase of `BlockChainImpl.internalTryToConnect`. The lab compares the clients on
that line. `--breakdown-log <file>` makes `--import-blocks` write the same line for rustock:

```
block connect breakdown best: block=<n> hash=<hex> totalMs=<ms> preambleMs=... initialValidationMs=...
  executeMs=... postExecuteValidationMs=... switchChainMs=... saveReceiptsMs=... onBestBlockMs=...
  txCount=<n> gasUsed=<n>
```

on one line, milliseconds with three decimals. Each phase is named after the rskj phase that
does the same work, and `totalMs` has rskj's scope: the whole connect, including the flush that
runs every tenth block (in rskj inside `onBestBlock`, here `onBestBlockMs`).
`docs/timing-scope.md` in the lab lists both clients' phases with file and line.

`BlockProcessor::process_block_timed` reports the three stages of `process_block`; the untimed
`process_block` reads no clock, and the importer reads one only when the flag is given.

## How to test

```bash
cargo test -p rustock-cli --test import_blocks
cargo test -p rustock-sync import
```

`the_breakdown_log_has_a_line_per_block` imports 15 blocks and checks one line per block with
every key; `the_breakdown_line_reads_like_rskjs` checks the format.
