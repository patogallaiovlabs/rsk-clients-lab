# rsk-clients-lab

Compares the block processing time of two RSK clients on the same workloads:

- **RSKj** at the head of the ref in `clients/rskj.json`, the integration branch of the lab's RSKj fork;
- **rustock**, the same client written in Rust, from [SergioDemianLerner/rustock](https://github.com/SergioDemianLerner/rustock), a fork well ahead of [rustock-rs/rustock](https://github.com/rustock-rs/rustock).

The lab measures. It does not optimize either client.

## In one picture

```mermaid
flowchart LR
    A["<b>1. Queue</b><br/>a campaign: scenarios,<br/>where, replay or live<br/><i>≈ 1 min</i>"]:::script
    B["<b>2. Build</b><br/>both clients at<br/>their pinned commits<br/><i>≈ 5 to 20 min</i>"]:::script
    C["<b>3. Run</b><br/>6 paired cycles, one<br/>client at a time on<br/>the same machine<br/><i>minutes to 7 h</i>"]:::script
    D["<b>4. Check</b><br/>every block hash equals<br/>RSKj's; live: four checks<br/><i>seconds</i>"]:::check
    E["<b>5. Judge</b><br/>trimmed mean per run,<br/>paired diff, sign test<br/><i>seconds</i>"]:::check
    F(["<b>6. Report</b><br/>report.md, both commits,<br/>every non-default setting<br/>docs updated by an AI"]):::done
    X(["<b>consensus finding</b><br/>first diverging block,<br/>written up for upstream"]):::dead
    A --> B --> C --> D --> E --> F
    D -. "a hash differs" .-> X
    E -. "direction consistent,<br/>not yet significant" .-> C

    classDef script fill:#fff5dc,stroke:#c99a2e,color:#4a3a10
    classDef check  fill:#f3e8fd,stroke:#8a4fd1,color:#3b1a5e
    classDef done   fill:#dff5e3,stroke:#3a9a55,color:#123d1f
    classDef dead   fill:#fde3e3,stroke:#c94b4b,color:#5a1515
```

Scripts run the campaign and decide; an AI reads the result, explains it and writes it up.
A replay campaign on the Mac takes minutes (the mainnet seed) to three hours (both
scenarios from an empty database); a live campaign about seven hours. A campaign is kept only
when both clients computed the same blocks: a different hash stops it, and the finding goes
upstream before any speed is reported.

```bash
bin/lab.py queue --where docker --scenarios ecdsa,mainnet-sim     # a replay campaign
bin/lab.py queue --kind live --scenarios ecdsa@mainnet --cycles 6  # a live one on the mainnet seed
bin/start.sh                                                       # run the queue, detached
bin/lab.py status [id]                                             # where it is
```

## Method

Each campaign replays the same blocks into both clients, one client at a time, from an empty
database. The blocks were mined by RSKj under k6 load, so the workload is inside them and both
clients execute identical transactions:

| Scenario | Blocks | Workload |
|---|---|---|
| `mainnet-sim` | 1..1159 | k6 option 14: storage writes, ERC-20, native transfers and calldata-heavy rollup txs, about 164 txs per block |
| `ecdsa` | 1..207 | k6 option 7: signature-recovery-heavy contract calls |

RSKj replays with `ConnectBlocks`; rustock with `import-blocks`, which the harness adapter adds
(see "The rustock adapter"). Both log one line per block in RSKj's format,
`block connect breakdown best: block=… hash=… totalMs=… executeMs=… …`, so one analyzer reads
both. `docs/timing-scope.md` maps each client's phases and states what `totalMs` covers in each.

A run counts only if every block was imported with exactly RSKj's reference hashes. A mismatch
stops the campaign and is reported as a consensus finding about rustock.

A cycle is one run of each client, the order alternating between cycles. A campaign runs 6
cycles per scenario (up to 12 when the direction is consistent but not yet significant), and
judges with the statistics RSKj's own A/B benchmarks use: per run, the 10% trimmed mean of per-block `totalMs` over
the blocks at least 90% full, with the plain mean and median beside it; per cycle, the paired
difference; across cycles, the exact sign test. The verdict is "rustock faster", "rustock slower"
or "no difference", with the minimum difference set per scenario in `config.json`.

| Where | How |
|---|---|
| Docker, this Mac | each client in its own container with the same CPU and memory limits and a fresh data volume |
| Boton, boxes A and B | native binaries (RSKj jar, rustock built for linux/amd64 in Ubuntu 22.04), counterbalanced: one slot runs RSKj on A and rustock on B, the next swaps them |

One node per machine at a time. This Mac's Docker VM and the Boton boxes may be shared with
other labs through the locks in `~/.research-lab/locks`; the protocol is in `bin/lib.sh`.

## Live mining

A live campaign (`bin/lab.py queue --kind live`) has each client mine its own blocks instead
of replaying a sample: one 30-minute arm per client per cycle, in Docker on this Mac, the node
under the scenario's k6 load (option 14 for `mainnet-sim`, 7 for `ecdsa`) from an empty
database or a clone of the mainnet seed (`mainnet-sim@mainnet`, `ecdsa@mainnet`). RSKj runs
through the runtime image's entrypoint (timed mining at a 10 s median, 2 CPUs); rustock runs
`live_args` from `clients/rustock.json`, which need the adapter's timed miner, mined-block
timing line and block export (`docs/live-mining-plan.md`). The hash gate becomes four checks
(`bin/check-live-arm.sh`): the arm's blocks replay into the other client with the same hashes
(the cross replay, through `bin/replay-docker.sh --blocks`), the log holds exactly the arm's
own blocks, the k6 success rate held, and at least 20 blocks were at least 90% full after the
first 20. The statistic and the verdict are the ones above; `report.md` adds a per-arm table
with blocks mined, qualifying blocks, transactions, k6 success rate and the cross-replay
result, since the two arms of a cycle mine different blocks. Boton live slots are a later step.

Out of scope, because rustock cannot do it yet: the mainnet database (it cannot read RSKj's;
`docs/mainnet-db-plan.md` converts a copy).

## How a campaign moves

```mermaid
flowchart TD
    Q["<b>queue</b><br/>lab.py queue · campaign.json<br/>refs from clients/*.json"]:::script
    B["<b>build</b><br/>build-client.sh · RSKj jar, rustock image<br/>(linux/amd64 binary for Boton)<br/><i>≈ 5 to 20 min</i>"]:::script
    Q --> B

    subgraph REPLAY ["replay cycle · the same blocks into each client, order alternating"]
        direction TB
        R1["<b>run RSKj</b><br/>ConnectBlocks · empty DB<br/>or a hard-link clone of the seed<br/><i>≈ 10 s to 15 min</i>"]:::script --> R2["<b>run rustock</b><br/>import-blocks (the adapter)<br/><i>≈ 10 s to 15 min</i>"]:::script
        R2 --> R3["<b>hash gate</b><br/>check-run.sh · every hash equals<br/>samples/&lt;scenario&gt;/reference_hashes.txt"]:::check
    end

    subgraph LIVE ["live cycle · each client mines its own blocks under k6"]
        direction TB
        L1["<b>arm A</b><br/>live-arm.sh · 30 min · k6 option 7 or 14<br/>gas price: head minimum x 1.1 on both"]:::script --> L2["<b>arm B</b><br/>the other client, same load<br/><i>30 min</i>"]:::script
        L2 --> L3["<b>cross replay</b><br/>replay-docker.sh --blocks · A's blocks<br/>into B and B's into A<br/><i>≈ 1 min</i>"]:::check
        L3 --> L4["<b>four checks</b><br/>check-live-arm.sh · hashes equal, log holds<br/>its own blocks, k6 rate held, 20+ full blocks"]:::check
    end

    B -- "--kind replay" --> REPLAY
    B -- "--kind live" --> LIVE
    R3 -. "hash differs" .-> V
    L4 -. "cross replay differs" .-> V
    L4 -. "arm measured nothing" .-> DROP(["arm discarded,<br/>cycle repeated"]):::idle
    R3 --> J
    L4 --> J
    J{"<b>judge</b><br/>stats.py · after 6 cycles<br/>sign test on paired cycles"}:::check
    J -- "consistent, p > 0.05" --> MORE(["up to 12 cycles"]):::idle --> REPLAY
    J -- "decided" --> REP["<b>report</b><br/>report.py · report.md<br/>summary, per-cycle and per-phase tables"]:::script
    REP --> AN["<b>agent-analyst</b> · Opus<br/>where the time goes, phase by phase,<br/>profiling when the numbers are not enough"]:::agent
    AN --> WR(["<b>agent-writer</b> · Sonnet<br/>the summary the user reads<br/>docs and HANDOFF updated"]):::done

    V["<b>agent-validator</b> · Sonnet<br/>first diverging block and phase,<br/>a consensus finding"]:::agent
    V --> ISS(["written up for upstream<br/>docs/issues/ · never timed"]):::dead
    DROP -. "harness fault" .-> AD
    V -. "harness fault<br/>(config, import, timing, packaging)" .-> AD["<b>agent-adapter</b> · Opus<br/>harness/&lt;topic&gt; branch, PR text in docs/prs/,<br/>merged into clients-lab/harness,<br/>rebuilt as clients-lab/comparison"]:::agent
    AD --> B
    DG["<b>agent-diagnose</b> · Haiku<br/>client, harness or machine fault?<br/><i>≈ 20 s</i>"]:::agent
    DG -. "machine" .-> B
    REPLAY -. "a run fails" .-> DG
    LIVE -. "an arm fails" .-> DG

    classDef agent  fill:#e8f0fe,stroke:#4a6fd1,color:#1a2b5e
    classDef script fill:#fff5dc,stroke:#c99a2e,color:#4a3a10
    classDef check  fill:#f3e8fd,stroke:#8a4fd1,color:#3b1a5e
    classDef done   fill:#dff5e3,stroke:#3a9a55,color:#123d1f
    classDef dead   fill:#fde3e3,stroke:#c94b4b,color:#5a1515
    classDef idle   fill:#eeeeee,stroke:#999999,color:#333333
```

Yellow: a script runs it. Purple: a script decides. Blue: a Claude agent
(`.claude/agents/`), with its model. Green: the result the user reads. Red: a consensus
finding, which is never timed. Dotted: a way back or out. `bin/lab.py` drives every step;
one cycle holds the machine's lock from its first run to its last check, so another lab's
short jobs may run between cycles but never inside one. On Boton the replay cycle is a slot:
RSKj on box A and rustock on box B, the next slot swapped (`bin/boton-campaign.sh`); live
cycles run on this Mac only.

## The rustock adapter

rustock needs small harness-only changes to be measured, each proposed upstream as a pull
request to the SergioDemianLerner fork from a branch in `clients/rustock`:

1. a regtest chain from a genesis file with RSKj's activation heights and REMASC constants;
2. `import-blocks --file`, through the same validation and execution path as sync;
3. the per-block timing line;
4. a multi-arch Dockerfile and the linux/amd64 build for Boton.

Until they merge, `clients-lab/harness` holds the merge of all four. The lab builds
`clients-lab/comparison`, which tracks that merge and holds comparison-only instrumentation.
Every report names the commit. No adapter change may touch what the client computes or how fast.

## Layout

| Path | What |
|---|---|
| `clients/rskj`, `clients/rustock` | submodules; `clients/<name>.json` describes how each is built and run |
| `conf/` | genesis and RSKj node config; `rustock-wallet.keys`, the ten regtest keys k6 sends from in live arms |
| `database-seed/`, `k6-tests/` | submodules: the mainnet seed tooling (rsk-database-seed, driven through `bin/seed.sh`) and the k6 suite (rskj-k6-tests) |
| `docker/` | the rustock build image and the RSKj runtime image (`docker/runtime/Dockerfile`) |
| `samples/<scenario>/` | block file (gitignored), reference hashes, `meta.json` with its sha256 |
| `bin/` | `build-client.sh`, `replay-docker.sh`, `live-arm.sh`, `import-sample.sh`, `with-lock.sh`, stats and analyzer |
| `docs/` | timing scope, adapter pull request descriptions |
| `campaigns/<date>-<id>/` | a campaign's report (raw data under `raw/`, not committed) |
| `state/` | builds, runs, logs (gitignored) |

## Commands

```bash
bin/build-client.sh rskj "$(jq -r .ref clients/rskj.json)"   # -> state/builds/rskj-<sha>.jar
bin/build-client.sh rustock clients-lab/comparison linux-arm64
bin/replay-docker.sh rskj state/builds/rskj-<sha>.jar ecdsa state/runs/try-rskj
bin/live-arm.sh rskj state/builds/rskj-<sha>.jar ecdsa state/runs/live-rskj   # one 30-minute live arm
bin/with-lock.sh <command>                                # run anything heavy in the shared Docker slot
```
