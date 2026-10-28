# Campaign 2026-10-28-c5: RSKj vs rustock, live mining

Live mining on the mainnet seed: ecdsa under k6 option 7, 30-minute arms, 10g memory, rustock 1909b1c; follows 2026-10-28-c4 on the small chain.

Status **failed**, queued 2026-10-28T21:17:44Z, finished 2026-10-28T21:17:51Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `1909b1c7ea16` |

## Stopped

```
docker cycle 1 of ecdsa@mainnet failed (exit 1)
```

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host.
