# Plan: comparing the clients on the mainnet database

Status: done. Approved 2026-10-27, the seeds converted and the campaigns run that week, both
seeds rebuilt on 2026-10-28 (last section). The steps and decisions below are kept as the
record of how it was done; the state of the seeds today is in the last section.

Today both clients replay from an empty database, so every block touches a state of a few
MB. On a real state (the mainnet seed, a 125 GB unitrie) the trie reads and writes
dominate, which is where the two clients differ most (`campaigns/2026-10-26-c1/analysis.md`).
This plan brings rustock onto that seed.

## What exists

- **The seed.** The seed volume (`config.json` `mainnet_seed.volume`), `/seed`: an RSKj
  mainnet database, 185 GB: unitrie 125 GB, blocks 36 GB, receipts 25 GB. The tip was
  #9,003,579 (hash `0x471f0ffc…`) in the first build and is #9,003,567 since the rebuild of
  2026-10-28. `database-seed/seeds/mainnet/{meta.json,node.props}` describe it. Runs use a
  hard-link clone made in seconds (`bin/seed.sh clone`).
- **Its activations are not mainnet's.** `node.props` schedules `reed810`, `tbd1000`,
  `rskip351` and `rskip535` at #9,002,504 (the funding block) and `rskip536` at #8,804,200,
  so every block mined on the seed runs under rules mainnet has not activated. RSKj reads
  them from `-D` overrides.
- **rustock can convert an RSKj database** (`clients/rustock/docs/rskj-import.md`):
  `--import-rskj <dir>` copies `unitrie/` verbatim (same node bytes, same roots) and splits
  `blocks/` into headers and bodies; `--metadata-in-memory` then rebuilds the canonical index
  in minutes. Receipts and blooms are not copied. About an hour on 9.2M blocks.

## Steps (as planned on 2026-10-27; all done)

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
   the runtime image's entrypoint for the node) until enough are full, then
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
  90 GB free, not enough for both. Decided: convert on this Mac (`/rustock-seed` in the seed volume,
  about 160 GB; Docker campaigns stay paired), and on Boton run **sequentially**: all RSKj
  cycles on the existing database, then remove it, upload the rustock seed, run the rustock
  cycles. The report must say the Boton design was sequential, not counterbalanced. Afterwards
  the boxes hold rustock's seed; any later RSKj work on the mainnet DB there needs the RSKj seed
  uploaded again (hours per box) before it can resume.
- **rustock's trie engine:** the default, `rocksdb` (`--trie-backend single`). `flatdb` is
  experimental in the fork and can be a later arm of its own.
- **Two kinds of runs.** Deterministic replay (this plan) and live mining under k6 on the same
  seed, for both clients; the live design is in `docs/live-mining-plan.md`.

## Decision (2026-10-27, evening): compaction on this Mac, in sequence

The converted seed's trie compaction rewrites the whole trie (about 125 GB) before deleting
any input, which this Mac cannot hold beside both seeds. Decided: mine the samples and run the
RSKj replay cycles here first, then delete this Mac's copy of the RSKj seed (the boxes keep
theirs), compact rustock's seed and rebuild its index, run the rustock
cycles, and copy the compacted seed (about 160 GB) to the boxes. The Docker comparison on the
mainnet DB is therefore sequential too, and the report says so.

## Finding (2026-10-27, night): the seed runs as regtest

The first rustock replay on the compacted seed diverged at block #9,003,580. The cause was
the lab's configuration, not the conversion: the sample's transactions carry chain id 33
(`v = 101`), because RSKj runs on the mainnet seed with `--regtest` and
`node.props` (regtest consensus on a mainnet state). rustock replayed under `--network-id 30`
and the activation ladder of `harness/mainnet-overrides`, so it recovered different senders.
With the regtest configuration of the small chain (`--network-id 33`, `conf/genesis_25M.json`,
`rskip97=0`, everything else at genesis) and the single trie backend, rustock imports the 204
blocks of `mainnet-sim@mainnet` with the reference hashes in 12 s. `clients/rustock.json`'s
`mainnet_*_args` are now that configuration; `harness/mainnet-overrides` stays in the harness
but this comparison does not use it.

## Boton (2026-10-28)

The boxes have 2 CPUs and 7 GB of RAM; their data volume (`/var/lib/rsk`, 295 GB) held
the RSKj seed (`mainnet-seed/seed`, 186 GB) and a clone of it (`database`).
`bin/boton-campaign.sh` now runs the listed clients only and, on the mainnet DB, starts each
run from a hard-link clone of the seed made on that volume (`/var/lib/rsk/clientslab-db`;
links do not cross file systems, and the run directory is on the root disk). Campaign
`2026-10-27-c3` ran RSKj's 24 runs first, all with the reference hashes: mainnet-sim about
75 ms/block on box A and 110 on box B, ecdsa 386 and 541 (box B is the slower box, as earlier
runs measured). Then `bin/boton-rustock-seed.sh` removed the RSKj seed and its clones from both
boxes and copied rustock's compacted seed (148 GB) to `/var/lib/rsk/rustock-seed`, at about
5 MB/s per box over the shared uplink; rustock's half of the campaign runs when both copies
are done. RSKj on the mainnet DB there needs the RSKj seed uploaded again (most of a day
per box).

### Boton, rustock half (2026-10-28)

The first rustock run on a box failed before its first block: `Failed to open RocksDB ...
Too many open files`. The box's soft descriptor limit is 1024 and the single-backend seed has
2138 table files (rustock's own `max_open_files` is 512 per column family, which the opener
exceeds anyway). `bin/boton-campaign.sh` now runs every box command under `ulimit -n 65536`
(the hard limit is 1048576), for both clients; RSKj already capped itself at
`database.rocksdb.maxOpenFiles=1000`. The failed attempt is kept in
`state/logs/c3-rustock-ulimit-failure.txt`; the campaign was rerun with `lab.py run
2026-10-27-c3 --clients rustock`.

Result (`campaigns/2026-10-27-c3/report.md`, 6 cycles, both halves consensus-clean):
mainnet-sim 94.2 vs 98.0 ms/block (rustock 1.05x slower on the trimmed mean, 1/6 cycles;
the mean says 1.10x faster 6/6 and the median 1.12x slower 0/6, so the verdict is
"extend"); ecdsa 463.9 vs 182.5 ms/block (rustock 2.55x faster, 6/6). As on the Mac:
rustock's executeMs is about twice RSKj's on mainnet-sim (86 vs 43 ms) and its
initialValidationMs a sixth (3.6 vs 24 ms); the two nearly cancel on the boxes. The halves
ran hours apart (RSKj 2026-10-28 01:40Z, rustock 10:45Z) on the same boxes.

## Decision (2026-10-28, night): rebuild the seeds once, then keep both

The live mainnet campaign (`docs/live-mining-plan.md`) found the RSKj seed gone from this
Mac. Decided, with the user:

1. Rebuild it from the tarball on Backup 1 with `bin/seed.sh` (senders funded
   from the bridge, so the tip moves) and re-convert rustock's seed from it. The Docker VM
   cannot hold the RSKj seed, the converted seed and the conversion's compaction peak at
   once, so the bootstrapped RSKj seed is parked on Backup 1 during the conversion and
   restored after it (`state/rebuild-mainnet-seed.sh`, resumable).
2. Make rustock's import compact before it returns, so the peak falls inside the import,
   while the RSKj seed is still an input: one harness PR in the fork. After that both
   seeds stay in the volume for good and nothing is parked or deleted again.
3. No rustock-to-RSKj converter: its only benefit was regenerating a seed we no longer
   delete. Hard-linking the trie tables between the two seeds stays an idea for when disk
   gets tight.
4. The mainnet samples (`ecdsa@mainnet`, `mainnet-sim@mainnet`) belong to the old seed
   and must be mined again on the new one before any further replay campaign on the
   mainnet DB; live mining does not need them. The Boton boxes still hold the old rustock
   seed.

Status 2026-10-29: step 1 done. The RSKj seed was rebuilt (tip #9003567, `database-seed/seeds/mainnet/meta.json`),
parked on Backup 1 while rustock imported it (3062 s, then 54 s of in-memory metadata), and
restored; both seeds are in the volume `clientslab-mainnet` (renamed from `perflab-mainnet`;
`/seed` 185 GB, `/rustock-seed` 149 GB) and the parked copy is gone. The live campaign that
followed is `2026-10-28-c6` (`docs/live-mining-plan.md`). Step 2 (compaction inside the
import) is still open.
