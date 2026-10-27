# Plan: comparing the clients on the mainnet database

Status: approved 2026-10-27; conversion on this Mac started the same day.

Today both clients replay from an empty database, so every block touches a state of a few
MB. On a real state (perf-lab's mainnet seed, a 125 GB unitrie) the trie reads and writes
dominate, which is where the two clients differ most (`campaigns/2026-10-26-c1/analysis.md`).
This plan brings rustock onto that seed.

## What exists

- **The seed.** Docker volume `perflab-mainnet`, `/seed`: an RSKj mainnet database at tip
  #9,003,579 (hash `0x471f0ffc…`), 186 GiB: unitrie 125 GB, blocks 36 GB, receipts 25 GB.
  `rsk-perf-lab/database-seed/seeds/mainnet/{meta.json,node.props}` describe it. Runs use a
  hard-link clone made in seconds (`database-seed/clone.sh`).
- **Its activations are not mainnet's.** `node.props` schedules `reed810`, `tbd1000`,
  `rskip351` and `rskip535` at #9,002,504 (the funding block) and `rskip536` at #8,804,200,
  so every block mined on the seed runs under rules mainnet has not activated. RSKj reads
  them from `-D` overrides.
- **rustock can convert an RSKj database** (`clients/rustock/docs/rskj-import.md`):
  `--import-rskj <dir>` copies `unitrie/` verbatim (same node bytes, same roots) and splits
  `blocks/` into headers and bodies; `--metadata-in-memory` then rebuilds the canonical index
  in minutes. Receipts and blooms are not copied. About an hour on 9.2M blocks.

## Steps

1. **Disk.** A converted rustock seed is about 160 GB (trie 125 + blocks 36), beside the
   186 GiB RSKj seed. This Mac has 171 GB free; too tight with clones and run output.
   Options: free 17 GB more in Docker (build cache, unused images) and run with a thin
   margin; put the rustock seed on the external disk `Backup 1`; or convert only the trie and
   the last N thousand blocks (the sample needs the state and the parent headers, not the full
   history; `--probe-unitrie` can confirm the state is complete). The Boton boxes have 75 GB
   disks, so the mainnet DB stays Docker-only unless a box is resized.
2. **Adapter, one more PR** (`harness/mainnet-overrides`): the harness branch refuses
   `--hardfork`, `--consensus-rule` and `--genesis` on chain id 30. Allow activation
   overrides on a mainnet-derived chain behind an explicit flag, mapping `node.props`'s
   names (`reed810`, `tbd1000`, `rskip351/535/536`) onto the fork's ladder. Checked
   2026-10-27: the fork knows `reed810`, `rskip351`, `rskip535` and `rskip536`; it has no
   `tbd1000`, but in RSKj that upgrade only switches on RSKIP559 (deterministic pegout
   sorting in the bridge), which no block of our samples exercises, so the override can map
   `tbd1000` to nothing and the report must say so.
3. **Sample.** Mine blocks on a clone of the seed with RSKj under k6 (mainnet-sim and
   ecdsa, as `bin/build-sample.sh` does on the small chain, using
   `rsk-perf-lab/bin/live-arm-mainnet.sh` for the node) until enough are full, then
   `ExportBlocks` from #9,003,580 up and record the reference hashes. Target about 200
   blocks per scenario; full 25M blocks on this state take 30-60 ms each in RSKj.
4. **Conversion.** `rustock-cli --import-rskj /seed/test/local-regtest/database`
   plus `--metadata-in-memory` into a new rustock seed directory in the same volume, under
   the Docker lock. Check: rustock reports tip #9,003,579 with hash `0x471f0ffc…` and the
   same state root RSKj logs for that block. That is the feasibility gate; stop here if it
   fails.
5. **Per-run clones.** Hard-link clones of the rustock seed, as `clone.sh` does for RSKj
   (RocksDB tables are immutable, so links are safe). `bin/replay-docker.sh` gets a `db`
   option: `empty` (today) or `mainnet`, which mounts a clone and passes `node.props` to
   RSKj and the override flags to rustock; `maxOpenFiles 1000` and 10 GB memory for both.
6. **Campaign.** A scenario variant per sample (`mainnet-sim@mainnet`, `ecdsa@mainnet`),
   same cycles, same hash gate, same report. Docker only.

## Decisions (2026-10-27)

- **Where the seeds live.** The Boton volumes (`/var/lib/rsk`, 295 GB) hold the RSKj seed with
  90 GB free, not enough for both. Decided: convert on this Mac (`perflab-mainnet:/rustock-seed`,
  about 160 GB; Docker campaigns stay paired), and on Boton run **sequentially**: all RSKj
  cycles on the existing database, then remove it, upload the rustock seed, run the rustock
  cycles. The report must say the Boton design was sequential, not counterbalanced. Afterwards
  the boxes hold rustock's seed; perf-lab's `6-boton` mainnet-DB stage needs the RSKj seed
  uploaded again (hours per box) before it can resume.
- **rustock's trie engine:** the default, `rocksdb` (`--trie-backend single`). `flatdb` is
  experimental in the fork and can be a later arm of its own.
- **Two kinds of runs.** Deterministic replay (this plan) and live mining under k6 on the same
  seed, for both clients; the live design is in `docs/live-mining-plan.md`.

## Decision (2026-10-27, evening): compaction on this Mac, in sequence

The converted seed's trie compaction rewrites the whole trie (about 125 GB) before deleting
any input, which this Mac cannot hold beside both seeds. Decided: mine the samples and run the
RSKj replay cycles here first, then delete this Mac's copy of the RSKj seed (the boxes keep
theirs; perf-lab is paused), compact rustock's seed and rebuild its index, run the rustock
cycles, and copy the compacted seed (about 160 GB) to the boxes. The Docker comparison on the
mainnet DB is therefore sequential too, and the report says so.

## Finding (2026-10-27, night): the seed runs as regtest

The first rustock replay on the compacted seed diverged at block #9,003,580. The cause was
the lab's configuration, not the conversion: the sample's transactions carry chain id 33
(`v = 101`), because perf-lab's RSKj runs on the mainnet seed with `--regtest` and
`node.props` (regtest consensus on a mainnet state). rustock replayed under `--network-id 30`
and the activation ladder of `harness/mainnet-overrides`, so it recovered different senders.
With the regtest configuration of the small chain (`--network-id 33`, `conf/genesis_25M.json`,
`rskip97=0`, everything else at genesis) and the single trie backend, rustock imports the 204
blocks of `mainnet-sim@mainnet` with the reference hashes in 12 s. `clients/rustock.json`'s
`mainnet_*_args` are now that configuration; `harness/mainnet-overrides` stays in the harness
but this comparison does not use it.
