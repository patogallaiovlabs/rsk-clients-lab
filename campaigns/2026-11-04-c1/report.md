# Campaign 2026-11-04-c1: RSKj vs rustock, live mining

First live campaign on the Boton boxes (bin/boton-live-slot.sh, new): ecdsa under k6 option 7 on the empty database, both boxes mining at once, one client each, swapped every slot; cross replays in Docker on this Mac. RSKj fa5733f8e (perf-lab/integration with s010, co.rsk:native on libsecp256k1 0.8.0) vs rustock 2f185c8 (gated by 2026-11-02-c1). The Docker counterpart on the new baseline is 2026-11-02-c2 (ecdsa@mainnet, 1.38x); the empty-database Docker live row before s010 was 2026-10-28-c4 (2.94x). The boxes hold no rustock seed, so the @mainnet scenarios cannot run live there yet.

Status **done**, queued 2026-11-04T15:33:59Z, finished 2026-11-04T22:21:03Z.

| client | ref | commit |
|---|---|---|
| RSKj | `fa5733f8eb9a9b733fa55c6b6326c1bf01e50a93` | `fa5733f8eb9a` |
| rustock | `2f185c8` | `2f185c8fe781` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 50 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).

Boton: the two boxes mine at the same time, one client each, natively from an empty database (`bin/boton-live-slot.sh`): the fwd slot runs RSKj on box A and rustock on box B, the rev slot swaps them, and a cycle is one of each. k6 runs on the box against its own node, with the same options and pricing rule as in Docker; the cross replays run in Docker on this Mac. A cycle's figure is the mean of the two boxes' within-box comparisons.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa | boton | 246.3 | 183.8 | 1.35x faster | rustock faster |

## ecdsa, boton

**rustock faster**: rustock faster in 6/6 cycles, median -25.83%, sign-test p=0.03125.

| cycle | client | started (UTC) | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|---|
| 1 | rskj (fwd, box A) | 2026-11-04 15:55 | 121 | 73 | 11013 | 2,920,507,687 | 100.00% | ok | yes |
| 1 | rustock (fwd, box B) | 2026-11-04 15:55 | 123 | 72 | 11984 | 2,963,869,795 | 100.00% | ok | yes |
| 1 | rustock (rev, box A) | 2026-11-04 16:28 | 133 | 84 | 14500 | 3,258,116,128 | 100.00% | ok | yes |
| 1 | rskj (rev, box B) | 2026-11-04 16:27 | 131 | 82 | 12841 | 3,198,281,336 | 99.99% | ok | yes |
| 2 | rskj (fwd, box A) | 2026-11-04 17:00 | 132 | 84 | 11613 | 3,193,524,262 | 100.00% | ok | yes |
| 2 | rustock (fwd, box B) | 2026-11-04 16:59 | 121 | 72 | 12255 | 2,918,733,676 | 100.00% | ok | yes |
| 2 | rustock (rev, box A) | 2026-11-04 17:32 | 115 | 66 | 10633 | 2,808,176,858 | 100.00% | ok | yes |
| 2 | rskj (rev, box B) | 2026-11-04 17:32 | 135 | 87 | 13506 | 3,306,838,108 | 100.00% | ok | yes |
| 3 | rskj (fwd, box A) | 2026-11-04 18:04 | 118 | 69 | 12029 | 2,854,713,973 | 100.00% | ok | yes |
| 3 | rustock (fwd, box B) | 2026-11-04 18:04 | 132 | 83 | 11664 | 3,231,596,181 | 100.00% | ok | yes |
| 3 | rustock (rev, box A) | 2026-11-04 18:37 | 100 | 51 | 9195 | 2,411,094,764 | 100.00% | ok | yes |
| 3 | rskj (rev, box B) | 2026-11-04 18:36 | 122 | 74 | 10144 | 2,949,477,755 | 100.00% | ok | yes |
| 4 | rskj (fwd, box A) | 2026-11-04 19:09 | 111 | 63 | 11231 | 2,685,623,058 | 100.00% | ok | yes |
| 4 | rustock (fwd, box B) | 2026-11-04 19:08 | 129 | 79 | 12422 | 3,123,098,487 | 100.00% | ok | yes |
| 4 | rustock (rev, box A) | 2026-11-04 19:41 | 118 | 69 | 12315 | 2,858,220,971 | 100.00% | ok | yes |
| 4 | rskj (rev, box B) | 2026-11-04 19:41 | 134 | 86 | 14213 | 3,258,239,993 | 99.99% | ok | yes |
| 5 | rskj (fwd, box A) | 2026-11-04 20:13 | 117 | 69 | 9584 | 2,859,229,407 | 100.00% | ok | yes |
| 5 | rustock (fwd, box B) | 2026-11-04 20:13 | 124 | 75 | 12602 | 3,008,304,997 | 100.00% | ok | yes |
| 5 | rustock (rev, box A) | 2026-11-04 20:45 | 122 | 73 | 12212 | 2,959,901,206 | 100.00% | ok | yes |
| 5 | rskj (rev, box B) | 2026-11-04 20:45 | 125 | 76 | 12545 | 3,032,023,849 | 100.00% | ok | yes |
| 6 | rskj (fwd, box A) | 2026-11-04 21:17 | 116 | 68 | 10740 | 2,809,484,987 | 100.00% | ok | yes |
| 6 | rustock (fwd, box B) | 2026-11-04 21:17 | 106 | 57 | 10302 | 2,585,627,837 | 100.00% | ok | yes |
| 6 | rustock (rev, box A) | 2026-11-04 21:50 | 137 | 88 | 12348 | 3,279,380,647 | 100.00% | ok | yes |
| 6 | rskj (rev, box B) | 2026-11-04 21:49 | 115 | 67 | 11486 | 2,798,355,490 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.35x faster | 6/6 | 0.0312 | 1.36x faster, 1.38x faster, 1.36x faster, 1.33x faster, 1.34x faster, 1.29x faster |
| mean | 1.43x faster | 6/6 | 0.0312 | 1.44x faster, 1.48x faster, 1.47x faster, 1.42x faster, 1.42x faster, 1.33x faster |
| median | 1.32x faster | 6/6 | 0.0312 | 1.33x faster, 1.33x faster, 1.33x faster, 1.27x faster, 1.31x faster, 1.30x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 246.3 | 183.8 | 1.35x faster |
| executeMs | 228.1 | 181.8 | 1.26x faster (6/6) |
| extendAlternativeChainMs | 0.0 | n/a |  |
| initialValidationMs | 12.1 | 0.4 | 33.90x faster (6/6) |
| onBestBlockMs | 0.6 | 0.3 | 1.71x faster (5/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 0.0 | 0.1 |  |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 0.1 | 1.1 | 19.29x slower (0/2) |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.0 | 0.2 |  |
| trieSaveMs | n/a | 0.3 |  |
| txExecutionMs | 225.2 | n/a |  |
