# Campaign 2026-11-02-c2: RSKj vs rustock, live mining

ecdsa live on the mainnet seed against the new RSKj baseline: perf-lab/integration fa5733f8eb9a9b733fa55c6b6326c1bf01e50a93 with s010 landed (co.rsk:native 1.5.0-SNAPSHOT on upstream libsecp256k1 0.8.0, ecdsa replay executeMs -58.8%). Rerun of 2026-10-29-c1 (RSKj e507f45, rustock 1909b1c, 2.58x) with the current rustock (2f185c8: gated by 2026-11-02-c1), live.min_block 50, k6 at head minimumGasPrice x1.1.

Status **done**, queued 2026-11-02T21:42:29Z, finished 2026-11-03T04:12:58Z.

| client | ref | commit |
|---|---|---|
| RSKj | `fa5733f8eb9a9b733fa55c6b6326c1bf01e50a93` | `fa5733f8eb9a` |
| rustock | `2f185c8` | `2f185c8fe781` |

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 50 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host, pricing every transaction at the head block's minimumGasPrice times 1.1 on both arms (`live.k6_gas_price`).

## Summary

Per-block `totalMs`, 10% trimmed mean over the blocks at least 90% full.

| scenario | where | RSKj ms/block | rustock ms/block | rustock vs RSKj | verdict |
|---|---|---|---|---|---|
| ecdsa@mainnet | docker | 120.8 | 87.8 | 1.38x faster | rustock faster |

## ecdsa@mainnet, docker

**rustock faster**: rustock faster in 6/6 cycles, median -27.34%, sign-test p=0.03125.

| cycle | client | blocks mined | qualifying | txs | gas used | k6 success | cross replay | counts |
|---|---|---|---|---|---|---|---|---|
| 1 | rskj | 124 | 76 | 10011 | 3,007,036,525 | 100.00% | ok | yes |
| 1 | rustock | 112 | 63 | 11055 | 2,684,707,170 | 100.00% | ok | yes |
| 2 | rskj | 116 | 68 | 10771 | 2,832,633,559 | 100.00% | ok | yes |
| 2 | rustock | 109 | 60 | 11573 | 2,636,121,023 | 100.00% | ok | yes |
| 3 | rskj | 124 | 76 | 10566 | 3,007,485,661 | 100.00% | ok | yes |
| 3 | rustock | 116 | 67 | 11413 | 2,808,823,436 | 100.00% | ok | yes |
| 4 | rskj | 111 | 63 | 9526 | 2,709,851,144 | 100.00% | ok | yes |
| 4 | rustock | 106 | 56 | 9785 | 2,572,018,977 | 100.00% | ok | yes |
| 5 | rskj | 130 | 82 | 12567 | 3,157,864,790 | 100.00% | ok | yes |
| 5 | rustock | 120 | 71 | 11242 | 2,909,230,234 | 100.00% | ok | yes |
| 6 | rskj | 130 | 82 | 10627 | 3,156,349,518 | 100.00% | ok | yes |
| 6 | rustock | 114 | 64 | 10919 | 2,777,746,088 | 100.00% | ok | yes |

| statistic | rustock vs RSKj | rustock faster | p | per cycle |
|---|---|---|---|---|
| trimmed mean | 1.38x faster | 6/6 | 0.0312 | 1.41x faster, 1.48x faster, 1.39x faster, 1.31x faster, 1.36x faster, 1.32x faster |
| mean | 1.23x faster | 6/6 | 0.0312 | 1.33x faster, 1.46x faster, 1.23x faster, 1.20x faster, 1.24x faster, 1.15x faster |
| median | 1.35x faster | 6/6 | 0.0312 | 1.36x faster, 1.47x faster, 1.36x faster, 1.31x faster, 1.35x faster, 1.33x faster |

Per-block milliseconds, trimmed mean, mean over runs (a phase one client does not log shows n/a; same-named phases are compared in the last column):

| phase | RSKj | rustock | rustock vs RSKj (paired median) |
|---|---|---|---|
| totalMs | 120.8 | 87.8 | 1.38x faster |
| executeMs | 105.0 | 85.2 | 1.22x faster (6/6) |
| initialValidationMs | 4.3 | 0.2 | 22.22x faster (6/6) |
| onBestBlockMs | 0.1 | 0.2 | 1.32x slower (0/6) |
| onBlockMs | 0.0 | n/a |  |
| postExecuteValidationMs | 0.0 | 0.0 |  |
| preambleMs | 3.1 | 0.2 | 13.21x faster (6/6) |
| processBestMs | 0.0 | n/a |  |
| saveReceiptsMs | 2.8 | 0.9 | 2.90x faster (6/6) |
| statePersistMs | 0.0 | n/a |  |
| stateRootRegisterMs | 0.0 | n/a |  |
| switchChainMs | 0.9 | 0.3 | 3.30x faster (6/6) |
| trieSaveMs | n/a | 0.6 |  |
| txExecutionMs | 103.6 | n/a |  |
