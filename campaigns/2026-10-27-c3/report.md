# Campaign 2026-10-27-c3: RSKj vs rustock

Mainnet DB on Boton, sequential design (docs/mainnet-db-plan.md): RSKj's cycles first on hard-link clones of the seed staged by perf-lab (/var/lib/rsk/mainnet-seed, tip #9,003,579), run as regtest with node.props, 2 CPUs and 7 GB RAM per box, JVM -Xms2G -Xmx4G, maxOpenFiles 1000. rustock's cycles come after the boxes' seed is swapped for rustock's compacted seed.

Status **done**, queued 2026-10-28T01:33:14Z, finished 2026-10-28T02:26:39Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `ecbacadcf1ed` |

Each run replays the scenario's blocks into one client from a hard-link clone of the mainnet seed (`docs/mainnet-db-plan.md`) and counts only if every block hash matches RSKj's reference replay. Per run: the 10% trimmed mean of per-block `totalMs` over the blocks at least 90% full. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` and each phase cover in each client.

Docker: both containers limited to 4 CPUs and 10g memory; RSKj with `-Xms2G -Xmx4G`. Boton: fwd slot runs RSKj on box A and rustock on box B, rev swaps them, and the cycle's figure is the mean of the two boxes.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| mainnet-sim@mainnet | boton | n/a | n/a | n/a | no data |
| ecdsa@mainnet | boton | n/a | n/a | n/a | no data |

## mainnet-sim@mainnet, boton

**no data**: no complete cycles.

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|

## ecdsa@mainnet, boton

**no data**: no complete cycles.

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
