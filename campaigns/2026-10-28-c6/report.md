# Campaign 2026-10-28-c6: RSKj vs rustock, live mining

Live mining on the mainnet seed (rebuilt 2026-10-29, senders funded from the bridge; rustock seed re-converted from it): ecdsa under k6 option 7, 30-minute arms, 10g memory, rustock 1909b1c.

Status **consensus-failure**, queued 2026-10-28T23:58:39Z, finished 2026-10-29T01:03:53Z.

| client | ref | commit |
|---|---|---|
| RSKj | `perf-lab/integration` | `e507f45031cf` |
| rustock | `clients-lab/comparison` | `1909b1c7ea16` |

## Stopped

```
rustock ecdsa@mainnet c1-rustock cross replay: {'consensus_ok': False, 'records': 1, 'expected': 138, 'first_difference': '< 9003569 448584413fd3508ca83a6c3410d8a54a60be4b84fcc0419d054cd7381fb51a5f', 'wall_s': 6, 'client': 'rskj', 'artifact': '/Users/patricio/workspace/rsk/research-lab/rsk-clients-lab/state/builds/rskj-e507f45031cf0e8a71bf571fcdbfbe9aa529a21b.jar'}
```

Each arm has one client mine its own blocks under the scenario's k6 load for 30 minutes (`bin/live-arm.sh`). An arm counts only if its blocks replayed into the other client with the same hashes (the cross replay), its log holds exactly its own blocks, the k6 success rate held and at least 20 blocks were at least 90% full after the first 20 (`bin/check-live-arm.sh`). The two arms of a cycle mine different blocks: the paired design absorbs that, the per-arm table below shows how alike the load was. Per arm: the 10% trimmed mean of per-block `totalMs` over the qualifying blocks. Per cycle: rustock vs RSKj in percent (negative means rustock is faster). Across cycles: the exact sign test. `docs/timing-scope.md` says what `totalMs` covers in each client; on the mined path rustock's line comes from the adapter (`docs/live-mining-plan.md`, section 3).

Docker: both containers limited to 2 CPUs and 6g memory (10g on the mainnet seed); RSKj with `-Xms2G -Xmx4G`, timed mining at a 10 s median in both; k6 on the host.
