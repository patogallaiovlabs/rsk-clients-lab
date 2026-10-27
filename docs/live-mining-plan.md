# Plan: live mining under k6 load, RSKj vs rustock

Status: proposed 2026-10-27, nothing built. Everything below was read in the code at rustock
`clients-lab/comparison` (8eb2285, on Lerner's 43dc5e5), RSKj `perf-lab/integration`, the k6
suite in `rsk-perf-lab/repos/rskj-k6-tests` and perf-lab's live scripts. Where a claim is an
inference rather than something read, the text says so.

The replay campaigns feed both clients the same blocks. A live campaign has each client mine
its own blocks under the same k6 load, as perf-lab's `5-live` and `6-boton` do for RSKj
(`bin/bench.sh live`, `scripts/local-ab.sh`, `bin/live-arm-mainnet.sh`,
`scripts/boton/run-counterbalanced.sh`). The statistic stays perf-lab's: per arm, the 10%
trimmed mean of `totalMs` over blocks at least 90% full, paired cycles, exact sign test.

## 1. Can k6 drive rustock today?

Mostly, through the node's own wallet. Neither scenario signs locally:
`utils/transaction-signer.js` says so at `createRawTransaction` (a placeholder) and every
send is `eth_sendTransaction` with an unlocked account. Both scenarios read the account list
from `eth_accounts` in `setup()` and take one account per VU (10 VUs each).

What options 14 and 7 call, and what the fork answers (`crates/rpc/src/server.rs`):

| Method | Used for | rustock |
|---|---|---|
| `eth_accounts` | the sender list | `sign::eth_accounts`, the wallet's addresses; empty without `--wallet-file` |
| `eth_sendTransaction` | every transaction, with `from`, `nonce`, `gas`, `gasPrice`, `data` set by k6 | `sign::eth_send_transaction`: signs with the wallet key, chain id from the chain config, then the pool |
| `eth_getTransactionCount` `pending` and `latest` | the in-flight gate, every iteration | `state::eth_get_transaction_count`; `pending` reads the pool's pending nonce |
| `eth_gasPrice` | the price of every transaction | `eth::eth_gas_price`, from the gas price tracker |
| `eth_estimateGas` | contract deployments in `setup()` (capped) | `call::eth_estimate_gas` |
| `eth_getBlockByNumber` `latest` | block gas limit for pacing and phase sizing | present; block 0 was invisible until #332 fixed it |
| `eth_blockNumber`, `eth_getTransactionReceipt` | block tracking, deployment and calibration receipts | present |

Option 7 also recognises RSKj's error strings for nonce too low or high, a known
transaction, an insufficient gas bump and `same hash already exists` (`ecdsa-stress-test.js`
84 to 88, `ERR_*` in `transaction-signer.js`). rustock's pool errors are its own wording
(`txpool.rs` 79 onwards), so a rejection rustock words differently is counted as a failure
and the VU re-syncs its nonce on the next iteration rather than skipping. That costs
throughput, not correctness; the amount is unknown until a run.

Accounts and keys. `conf/genesis_25M.json` funds the ten regtest accounts (`cd2a3d9f…`,
`7986b3df…`, and so on) plus four more and the bridge. Their keys are `keccak256("cow")`,
`keccak256("cow1")` to `keccak256("cow9")`: RSKj's regtest wallet derives them from those
seeds, and the fork ships the same ten in `regtest-wallet.example.keys`, loaded with
`--wallet-file`. On the mainnet seed the credited list in
`rsk-perf-lab/database-seed/seeds/mainnet/meta.json` is the same thirteen genesis addresses
plus two more; the ten cow accounts are among them, so the same key file serves both chains.

Someone has run the battery against the fork: commit d73ce31 "Four RPC defects the
rskj-k6-tests battery found (#332)" fixes genesis visibility, `net_version`,
`eth_newPendingTransactionFilter` and `rpc_modules`, and mentions 155 locally mined blocks.
`regtest-loadtest.example.toml` is the configuration they used. Its own comment says there
was no continuous mining then; the `AutoMiner` (`crates/rpc/src/evm.rs` 262 onwards) exists
now, see section 2.

Gaps, all harness-only:

- The node must be started with `--wallet-file`, `--mine --mining-coinbase`, `--dev-rpc`
  (the `evm_*` namespace, which `evm_startMining` lives in) and the account rate limiter off.
  Configuration, no code.
- Something must call `evm_startMining` once after the node is up, or the adapter below adds
  a flag that starts the miner at boot. Options 14 and 7 never call it.
- The error wording mismatch above. Not an adapter item: aligning error strings changes what
  the client answers, and the k6 side is perf-lab's. Measure the failure rate first.

## 2. Mining parity

RSKj, as perf-lab runs it (`rsk/Dockerfile` entrypoint, `rsk/rsk.conf`): `TimedMinerClient`
schedules each block after a delay drawn from an exponential distribution with median
`miner.client.medianBlockTime` (10 s in the image; the 5 s in `rsk.conf` is overridden by
the `-D` flag), floor 100 ms, the median scaled by the ratio of the current difficulty to the
first block's (`TimedMinerClient.scheduleNextMining`). With `skipPowValidation` the nonce is
0 and there is no search. The block is built by `MinerServerImpl` from the pool, gas limit
`targetgaslimit` 25M, and enters the chain through `EthereumImpl.addNewMinedBlock`, which
is `blockchain.tryToConnect`: the same `internalTryToConnect` that logs the breakdown line.

rustock has two ways to mine. `--mine` alone serves `mnr_getWork` and the three submit
methods for external mining software, rebuilding the template every
`--mining-refresh-secs` (60). The `AutoMiner`, started by `evm_startMining`, is a thread
that polls the pool every 250 ms and, whenever anything is pending, calls `mine_one_now`:
build a template, search a Bitcoin nonce, submit it to the same `complete_and_import` path
an external solution takes. There is no block time: blocks come as fast as a template can
be built and imported while the pool is non-empty, and no block is mined while it is empty.

What a template is (`crates/execution/src/mining/template.rs`, `build`): gas limit
inherited from the parent unchanged unless a target is set (`next_gas_limit`; the CLI
sets none, `MiningConfig::default`), so it stays 25M from the genesis on both chains;
minimum gas price likewise; timestamp wall clock, never at or before the parent; transactions
chosen as RSKj's `sortByPriceTakingIntoAccountSenderAndNonce` does (cluster by sender,
nonce order, merge by price) until the gas limit, then REMASC; the block executed once to fill
the roots. With RSKIP-144 active it is executed twice (once to learn the partition, once in
sublist order). Our chain has no RSKIP-144 height (`harness/regtest-config` reads the genesis
and leaves `rskip144` unset on RSKj's regtest), so `partition` returns early and the block is
executed once at build, then again at import, which is also RSKj's shape (build in
`BlockToMineBuilder`, execute again in `tryToConnect`).

What must match, and how:

| Setting | RSKj | rustock | Match |
|---|---|---|---|
| Block gas limit 25M | `-Dtargetgaslimit=25000000` | inherited from the parent | yes, both chains start at 25M |
| Block time, exponential, 10 s median | `TimedMinerClient` | none; the `AutoMiner` mines whenever the pool is non-empty | adapter `harness/timed-mining`: a scheduled miner with the same draw, floor and difficulty scaling, started by a flag |
| Proof of work skipped | nonce 0 | `mine_one` searches up to 16 × 2^18 nonces against `MAX / difficulty`; the genesis difficulty is 2^28, so on this chain the search would usually fail (`NoSolution`) | the same adapter: when `--skip-pow-validation` is on, submit with nonce 0 as RSKj does |
| RSKIP-144 off | `rskip144 = -1` | no height on RSKj's regtest; `execution_threads` default 1 | yes |
| Genesis, activations | `genesis_25M.json`, `rskip97 = 0` | `--genesis`, `--consensus-rule rskip97=0` | yes, as in replay |
| Pool: outdated after 10 blocks or 650 s | `reference.conf` | `PoolConfig` defaults 10 and 650 | yes |
| Pool: per-account slots | `accountSlots = 500` in `rsk.conf` | no per-account cap; `MAX_POOL_TRANSACTIONS` 8192 | not identical; see below |
| Account rate limiter off | `-Dtransaction.accountTxRateLimit.enabled=false` | `--account-tx-rate-limit false` (the TOML shows the section) | yes |
| Template refresh on new transaction | `updateWorkOnNewTransaction = true` | the `AutoMiner` builds a fresh template per block; the 60 s refresh is for `mnr_getWork` | equivalent for a timed miner that builds at mining time |
| Flush cadence | every 10 blocks, inside the connect (`onBestBlockMs`) | `commit_mined_block` flushes the trie store on every mined block | adapter `harness/timed-mining` (or a flag of its own): flush every N blocks on the mined path, N = `--import-flush-every` |
| Difficulty rule | RSKj's calculator, `rskip97` from 0 | the port of the same rule | yes, assumed from the replay hashes matching |

Pool limits cannot be made identical without changing the pool, which the adapter boundary
forbids. Under options 14 and 7 the load keeps at most 100 (option 14) or a few blocks' worth
(option 7, `BACKLOG_BLOCKS = 5`) of transactions in flight per account, 10 accounts, so
both pools stay under 1,000 entries and neither limit is reached. The report should say so
and check `txpool_status` during an arm.

What cannot be matched: the two nodes keep their own wall clocks and random draws, so the
block sequences differ (that is the nature of live arms, and the paired-cycle design
absorbs it); RSKj's template build runs in its own threads while mining candidates are
rebuilt on every new transaction (`updateWorkOnNewTransaction`), which is CPU the node
spends outside the measured connect; rustock's timed miner would build once per block. The
difference is in the unmeasured part of the node and in how much CPU each leaves for the
connect. On a 2 CPU container this can matter; the report has to name it.

## 3. Timing

rustock logs no per-block line on the mining path. `--breakdown-log` is read only by
`run_import_blocks` (`main.rs` 2573 and 3355 onwards), and `complete_and_import` calls
`process_and_commit`, the untimed sibling of `process_block_timed`. The mined block is
reported with one `info!` line, `Mined block #n … imported: IMPORTED_BEST`
(`mining/server.rs` 248), with no duration.

What is needed (adapter `harness/mined-block-timing`): `complete_and_import` times its stages
with the same `ImportTimings` and writes `breakdown_line` to the `--breakdown-log` file when
the result is `ImportedBest`. The mapping onto the import phases of `docs/timing-scope.md`:

| Phase | On the mined path |
|---|---|
| preambleMs | `take_template`, the executed-head check |
| initialValidationMs | `MergedMiningRule.validate` and `process_block`'s first stage (header, body rules, roots) |
| executeMs, trieSaveMs | `execute_block` inside `process_block` |
| postExecuteValidationMs | `process_block`'s check of the header against the result |
| switchChainMs | `commit_mined_block`: header, body, total difficulty, canonical update, exec head |
| saveReceiptsMs | `commit_receipts` (receipts, transaction index, bridge index), which `process_and_commit` runs before `commit_mined_block`, so the two phases swap order; the line reports them by name, so the analyzer does not care |
| onBestBlockMs | the `on_committed` hook (pool `remove_mined`, `evict_outdated`) and the trie flush |

`totalMs` would run from the start of `complete_and_import` to the log call, which is the
same scope as RSKj's `internalTryToConnect` on a mined block: validation, execution, state
root check, store, receipts, pool update, flush. Outside it on both sides: template build,
nonce handling, RPC. Two differences stay. The flush is on every block in rustock today
(the row above), and `process_block` re-executes a block the template already executed,
as RSKj does; the template's execution is outside `totalMs` in both.

The analyzer (`bin/analyze_block_breakdown.py`) parses `key=value` pairs and needs no change.
perf-lab's live arm check (`bench.sh`) reads a timestamp from the first 19 characters of each
line, which rustock's line does not carry; the lab's own check should use block numbers
above the seed tip instead, which both lines carry.

## 4. Validity without a hash gate

The arms mine different blocks, so the reference-hash gate of the replay campaigns does not
apply. Three checks replace it, all required for an arm to count:

1. **Cross replay.** After each arm, export its blocks (`ExportBlocks` from RSKj; the
   rustock side needs an export, see the adapter list) and replay them into the other client
   through the existing `bin/replay-docker.sh` path, from the same starting database. Every
   block must connect with the hash the miner gave it. A mismatch is a consensus finding
   against whichever client is wrong and stops the campaign, as today. The replay is the
   expensive part: at 30 to 60 ms per full block on the mainnet state, 200 blocks take
   seconds; the cost is starting the node on a clone, a few minutes each on the mainnet seed.
2. **Mined blocks are the node's own.** Every breakdown line has a block number above the
   seed tip (1159 or 9,003,579) and the log starts empty; exactly one k6 driver ran
   (perf-lab's checks in `bench.sh`, kept).
3. **k6 client-side checks.** Option 14's threshold `tx_success_rate > 0.98` and option 7's
   revert sampling (`pollSample`) must hold; the k6 summary of each arm is kept with the arm.
   An arm with a success rate below the threshold measured a node that rejected the load and
   is discarded.

A fourth, cheap, comparison: per arm, transactions per block and gas used per block from the
breakdown lines. Two clients under the same load should fill blocks alike; a large gap in
`txCount` at equal `gasUsed` points at a pool or selection difference before any timing is
read.

## 5. Design

Arms and cycles as in the replay campaigns: a cycle is one RSKj arm and one rustock arm, the
order alternating; 6 cycles per scenario, up to 12 when the direction is consistent but not
significant. Each arm: fresh database (a new volume, or a hard-link clone of the seed), the
node started, k6 started against it, 30 minutes, k6 stopped, the breakdown log and the k6
summary collected, the node stopped, the blocks exported, the database dropped. Scenarios
`mainnet-sim` (option 14) and `ecdsa` (option 7), the same thresholds.

Machines:

- **Docker on this Mac**: the two clients in containers with the same limits. The replay
  campaigns use 4 CPUs and 6 GB; perf-lab's live arms use 2 CPUs. Take 2 CPUs and 6 GB for
  the small chain and 10 GB on the mainnet seed, as perf-lab does, so the numbers can be read
  beside perf-lab's. k6 runs on the host against `localhost:4444`, as in `local-ab.sh`.
- **Boton**: native binaries, counterbalanced as `bin/boton-campaign.sh` does: one slot RSKj
  on A and rustock on B, the next swapped. k6 runs on the box (`run-load.sh`), so the boxes
  need the k6 binary and Node, which perf-lab's deploy already installs. Small chain only
  until the rustock seed is on the boxes (`docs/mainnet-db-plan.md` decided sequential there).

Chains, in order:

1. **Small chain** from `genesis_25M.json`, empty database. Cheapest, and the k6 setup
   deploys its contracts in the first blocks. The first 20 blocks are dropped
   (`--min-block 20`, as perf-lab does), which also removes the deployment blocks.
2. **Mainnet seed**: RSKj on a clone of `perflab-mainnet:/seed` with `node.props`;
   rustock on a clone of the converted seed (`docs/mainnet-db-plan.md` steps 4 and 5, plus
   `harness/mainnet-overrides`). The ten cow accounts are credited there, so the same wallet
   file works. Docker only.

Time per campaign: an arm is 30 minutes plus about 5 minutes of start, collection and cross
replay on the small chain, and about 10 on the mainnet seed (opening a 186 GiB database takes
minutes). Six cycles of two arms and two scenarios: 24 arms, about 14 hours on the small
chain and 16 on the seed; up to twice that at 12 cycles. Boton: 6 cycles of 2 slots of
about 40 minutes per scenario, 16 hours, the same as perf-lab's `6-boton`.

Scripts the lab needs:

- `bin/live-arm.sh <client> <artifact> <scenario> <db> <out-dir>`: one arm, both clients,
  both databases, Docker. The RSKj branch is `live-arm-mainnet.sh` with the lab's conf and
  image; the rustock branch runs `rustock-cli` with the replay flags of `clients/rustock.json`
  minus `--import-blocks`, plus `--wallet-file`, `--mine`, `--mining-coinbase`, `--dev-rpc`,
  `--rpc-host 0.0.0.0`, the timed-mining flag and `--breakdown-log`. Starts k6, waits, collects.
- `bin/check-live-arm.sh`: the checks of section 4, writing `consensus.json` and
  `summary.json` in the shape `bin/check-run.sh` writes, so `bin/stats.py` reads live and
  replay runs alike.
- `bin/lab.py`: a `--kind live` on `queue`, a `run_live` beside `run_docker` with the same
  cycle loop and lock handling (an arm holds the Docker slot as a long holder for 35 to 45
  minutes), and the cross replay called between arms.
- `bin/boton-campaign.sh`: a live slot beside the replay slot, deploying the k6 suite as
  `run-load.sh` does.
- `clients/rustock.json`: `live_args` beside `import_args`; a `conf/rustock-wallet.keys`
  copied from the fork's example file.
- `bin/report.py`: the live sections, with the k6 success rate and the cross-replay result
  per arm.

Adapter pull requests in rustock, each on `harness/<topic>` and merged into
`clients-lab/harness`:

- `harness/timed-mining`: a miner thread with RSKj's schedule (exponential, configurable
  median, 100 ms floor, median scaled by difficulty), nonce 0 when `--skip-pow-validation`,
  started by a flag (`--mine-timed <median>`), flush every N blocks on the mined path.
  Harness-only: it changes when blocks are mined and when the trie is flushed, not what a
  block contains or how it is executed.
- `harness/mined-block-timing`: the breakdown line on the mining path (section 3).
- `harness/export-blocks`: write the chain from height N as RSKj's `ExportBlocks` format, so
  the cross replay reads rustock's blocks with the existing `import-blocks` and `ConnectBlocks`.
  The decoder for that format exists (`parse_export_line`); the encoder is its inverse.
- `harness/mainnet-overrides`: already planned in `docs/mainnet-db-plan.md`.

## 6. Risks and unknowns, ranked

1. **Proof of work on this chain.** Read in the code, not run: `mine_one` gives up after
   about 4 million nonces and the genesis difficulty is 2^28, so until `harness/timed-mining`
   lands, `evm_startMining` would likely mine nothing on `genesis_25M.json`. The first smoke
   test should be one `evm_mine` on the small chain.
2. **The sync service's view of the state root.** Issue #323 (named in commit d73ce31): a
   locally mined block advances the committed head without telling the sync service, which
   repairs it on its tick (`resync_state_root_with_exec_head`). Two warnings in 155 blocks
   then. With no peers nothing else moves the head, but a repair that re-reads the root is
   work the node does between blocks, and a repair that goes wrong would reject the next
   template's parent. Watch the log for the warning during the smoke test.
3. **Load shape differs between the arms.** Option 14 paces itself from the observed block
   time and option 7 from the observed gas limit and backlog; both react to the node. A node
   that rejects more sends (the error wording of section 1) or answers RPC more slowly gets
   less load, so fewer blocks qualify as full and the trimmed mean is over a different
   population. Report qualifying blocks, `txCount` and the k6 success rate per arm, and
   discard arms under 20 qualifying blocks as perf-lab does.
4. **Unmeasured CPU.** The template build, the RPC server and the pool run beside the
   connect and compete for the 2 CPUs. RSKj rebuilds a candidate on every new transaction,
   rustock once per block. `totalMs` would then include contention that the replay does not
   have, and the two clients would carry different amounts of it. Mitigation: 4 CPUs in
   Docker, and a sensitivity check at 2.
5. **Cross replay on the mainnet seed.** Each cross replay opens a second clone of a
   186 GiB database; disk and minutes per arm. The clone budget in `docs/mainnet-db-plan.md`
   step 1 was written for one clone at a time.
6. **No k6 on the Boton boxes for rustock yet.** perf-lab's deploy installs the suite for its
   own runs; the lab's Boton slot has never started k6. Inferred to be a copy of `run-load.sh`.
7. **`eth_mining` answers false** in rustock whatever the miner does (`eth::eth_mining`).
   Neither option 14 nor 7 reads it; the basic suite does. Not a blocker; noted so nobody
   reads it as "not mining".
8. **Error strings.** Section 1: unquantified until a run.
