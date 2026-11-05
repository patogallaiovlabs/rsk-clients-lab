# Campaign 2026-11-04-c2: RSKj vs rustock, live mining

ecdsa live on the Boton boxes on the mainnet seed, sequential (docs/live-mining-plan.md, last section): every RSKj cycle on both boxes at once from hard-link clones of perf-lab's seed, then bin/boton-seed.sh swaps both boxes to rustock's seed (149 GB each), then every rustock cycle; the arms land in the fwd/rev layout and are paired per box as in 2026-11-04-c1 (empty database, 1.35x). Same builds as 2026-11-04-c1: RSKj fa5733f8e, rustock 2f185c8. The Docker counterpart is 2026-11-02-c2 (ecdsa@mainnet, 1.38x). Never extended. The swap evicts perf-lab's RSKj seed from the boxes (rsk-perf-lab/TO-DO.md).

Status **done**, queued 2026-11-04T22:35:34Z, finished 2026-11-05T13:20:34Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `fa5733f8eb9a` |
| rustock | `clients-lab/comparison` | `2f185c8fe781` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 50 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).

Boton: the boxes hold one client's seed at a time (295 GB volumes), so the campaign ran sequentially (`docs/mainnet-db-plan.md`): every RSKj arm first, both boxes mining at the same time, each from a hard-link clone of the RSKj seed; then the seed swap (`bin/boton-seed.sh`, most of a day); then every rustock arm the same way. The arms keep the fwd/rev layout, so a cycle's figure is still the mean of the two boxes' within-box comparisons, but the two halves of a cycle ran hours apart (the arm table has the times). k6 runs on the box against its own node, with the same options and pricing rule as in Docker; the cross replays run in Docker on this Mac on a clone of the seed here. The boxes have 7 GB of memory where the Docker arms get 10 GB.

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa@mainnet | boton | 260.4 | 192.2 | 1.34x faster | rustock faster |

## ecdsa@mainnet, boton

**rustock faster**: rustock faster in 6/6 cycles, median -25.10%, sign-test p=0.03125.

| cycle | client | started (UTC) | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|---|
| 1 | rskj (fwd, box A) | 2026-11-04 22:37 | 112 | 64 | 9434 | 2,734,679,401 | 100.00% | ok | yes |
| 1 | rustock (fwd, box B) | 2026-11-05 10:03 | 122 | 73 | 11816 | 2,983,603,350 | 100.00% | ok | yes |
| 1 | rustock (rev, box A) | 2026-11-05 10:04 | 105 | 55 | 9624 | 2,548,967,889 | 100.00% | ok | yes |
| 1 | rskj (rev, box B) | 2026-11-04 22:36 | 128 | 80 | 9967 | 3,107,936,647 | 100.00% | ok | yes |
| 2 | rskj (fwd, box A) | 2026-11-04 23:09 | 117 | 69 | 11026 | 2,858,792,915 | 100.00% | ok | yes |
| 2 | rustock (fwd, box B) | 2026-11-05 10:38 | 103 | 54 | 10303 | 2,511,014,378 | 100.00% | ok | yes |
| 2 | rustock (rev, box A) | 2026-11-05 10:39 | 101 | 52 | 10117 | 2,460,863,474 | 100.00% | ok | yes |
| 2 | rskj (rev, box B) | 2026-11-04 23:08 | 111 | 63 | 10017 | 2,685,051,963 | 100.00% | ok | yes |
| 3 | rskj (fwd, box A) | 2026-11-04 23:41 | 112 | 64 | 8603 | 2,735,644,234 | 100.00% | ok | yes |
| 3 | rustock (fwd, box B) | 2026-11-05 11:11 | 125 | 76 | 13259 | 3,058,794,915 | 97.70% | ok | yes |
| 3 | rustock (rev, box A) | 2026-11-05 11:11 | 116 | 66 | 12590 | 2,821,903,156 | 100.00% | ok | yes |
| 3 | rskj (rev, box B) | 2026-11-04 23:40 | 87 | 39 | 7140 | 2,113,196,608 | 100.00% | ok | yes |
| 4 | rskj (fwd, box A) | 2026-11-05 00:13 | 116 | 68 | 9387 | 2,835,853,160 | 100.00% | ok | yes |
| 4 | rustock (fwd, box B) | 2026-11-05 11:43 | 116 | 67 | 11958 | 2,810,776,040 | 100.00% | ok | yes |
| 4 | rustock (rev, box A) | 2026-11-05 11:44 | 118 | 68 | 10823 | 2,847,057,827 | 100.00% | ok | yes |
| 4 | rskj (rev, box B) | 2026-11-05 00:12 | 110 | 62 | 8866 | 2,683,831,539 | 100.00% | ok | yes |
| 5 | rskj (fwd, box A) | 2026-11-05 00:45 | 123 | 75 | 11206 | 2,983,587,610 | 100.00% | ok | yes |
| 5 | rustock (fwd, box B) | 2026-11-05 12:16 | 124 | 74 | 9666 | 2,982,406,578 | 100.00% | ok | yes |
| 5 | rustock (rev, box A) | 2026-11-05 12:16 | 138 | 89 | 13348 | 3,358,523,745 | 100.00% | ok | yes |
| 5 | rskj (rev, box B) | 2026-11-05 00:45 | 111 | 63 | 9322 | 2,711,001,670 | 100.00% | ok | yes |
| 6 | rskj (fwd, box A) | 2026-11-05 01:18 | 115 | 67 | 9924 | 2,809,946,181 | 100.00% | ok | yes |
| 6 | rustock (fwd, box B) | 2026-11-05 12:48 | 108 | 59 | 11259 | 2,636,750,067 | 100.00% | ok | yes |
| 6 | rustock (rev, box A) | 2026-11-05 12:49 | 105 | 56 | 9549 | 2,558,100,590 | 100.00% | ok | yes |
| 6 | rskj (rev, box B) | 2026-11-05 01:18 | 112 | 64 | 10378 | 2,686,496,372 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.34x faster | 6/6 | 0.0312 | 1.43x faster, 1.40x faster, 1.30x faster, 1.33x faster, 1.32x faster, 1.34x faster |
| mean | 1.42x faster | 6/6 | 0.0312 | 1.48x faster, 1.49x faster, 1.35x faster, 1.41x faster, 1.43x faster, 1.41x faster |
| median | 1.27x faster | 6/6 | 0.0312 | 1.33x faster, 1.33x faster, 1.25x faster, 1.25x faster, 1.23x faster, 1.28x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 260.4 | 192.2 | 1.34x faster |
| executeMs | 228.6 | 188.7 | 1.21x faster (6/6) |
| extendAlternativeChainMs | 0.8 | n/a |  |
| initialValidationMs | 8.7 | 0.4 | 21.93x faster (6/6) |
| onBestBlockMs | 1.0 | 0.3 | 2.09x faster (5/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 1.5 | 1.1 | 1.47x faster (5/6) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 5.2 | 1.1 | 4.53x faster (6/6) |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 1.7 | 0.2 | 9.17x faster (6/6) |
| trieSaveMs | n/a | 1.3 |  |
| txExecutionMs | 224.4 | n/a |  |
