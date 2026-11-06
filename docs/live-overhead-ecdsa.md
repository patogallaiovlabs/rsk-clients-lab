# Where RSKj's live-mining overhead goes (ecdsa)

One instrumented live arm, read against the code at `clients/rskj` fa5733f8e. The question:
RSKj replays ecdsa blocks in about 95 ms (campaign 2026-11-02-c1, Docker) but mines them live
in about 121 ms (2026-11-02-c2, ecdsa@mainnet, Docker), while rustock's live and replay
numbers are the same. What is the 25 ms made of, and what could perf-lab change.

## The arm

`state/runs/live-diag-rskj-ecdsa`: `bin/live-arm.sh rskj <fa5733f8e jar> ecdsa@mainnet`,
2026-11-05 16:13Z, 30 minutes, Docker on this Mac, 2 CPUs, 10 GB, `-Xms2G -Xmx4G`, the
mainnet seed from #9003567. 103 blocks mined and exported (#9003568 to #9003670), k6 option 7
success rate 100%. Not a campaign arm: no cross replay, nothing compared with rustock.

Instrumentation, all outside `rsk.conf`:

- `conf/rskj/logback-diag.xml`: the lab's logback plus a `DIAG` appender that takes the
  `minerserver`, `blocktominebuilder`, `blockvalidator` and `blocksyncservice` loggers at
  DEBUG into `diag.log`, isolated from `rsk.log` for the reason `BLOCK-BREAKDOWN` is. With
  root at DEBUG but `FILE-AUDIT` thresholded at `-Dlogging=INFO`, those lines never reach
  `rsk.log`; raising the threshold floods it (`trie` is at TRACE), so the appender route.
- A JFR recording for the whole arm (`settings=profile`, `arm.jfr`), and a host-side
  sampler (`sampler.sh` in the run directory): `docker stats` and per-thread CPU ticks
  from `/proc/1/task/*/stat` every 5 s, a `jattach threaddump` every 30 s.
- `bin/live-arm.sh` gained two optional environment hooks, `CLIENTSLAB_RSKJ_LOGBACK`
  (the logback path, default unchanged) and `CLIENTSLAB_RSKJ_JVM_EXTRA` (appended to the
  JVM options of the mining run only, not the export), and now copies `rsk.log`, `diag.log`
  and any `.jfr` out of the data mount with the breakdown log. Campaign arms are unaffected.

`analyze_live_diag.py` (in the run directory) produces `analysis.json` and every number
below. Unless said otherwise, numbers are the 10% trimmed mean over the 53 qualifying
blocks: at least 50 blocks into the arm and at least 20 transactions, the lab's warm-up rule.

## The numbers

Per block, qualifying blocks, milliseconds:

| component | this arm | 2026-11-02-c2 | replay (2026-11-02-c1) | what it is, from the code |
|---|---|---|---|---|
| totalMs | 123.6 | 120.8 | 95.8 | `internalTryToConnect`, `docs/timing-scope.md` |
| executeMs | 110.0 | 105.0 | 93.7 | `blockExecutor.execute`: transactions plus the trie save (`statePersistMs`, 3.2 here) |
| initialValidationMs | 5.1 | 4.3 | 0.0 | `BlockValidatorImpl.isValid`: `prefetchSenders` and the rules |
| preambleMs | 1.8 | 3.1 | 0.0 | duplicate check and parent lookup in the block store |
| saveReceiptsMs | 2.7 | 2.8 | 0.0 | receipts to RocksDB |
| switchChainMs | 1.0 | 0.9 | 0.0 | block saved, made best |
| other phases | 0.5 | 0.4 | 0.6 | state root register, processBest, listeners |

The replay column is a different set of blocks (the ecdsa sample has 23 transactions per block
at the same gas; the live blocks here have 138), so its executeMs is not the same work. Its
zeros are real: on the replay path the block store already holds the block's parent as the
tip and nothing else is cold, and the rounding is to whole milliseconds.

The clean comparison for executeMs is inside the arm. Every mined block was executed twice on
the same machine against the same parent state: once by the miner, as the last candidate
built before the solution arrived (`miner-build-block-listener` thread, `executeAndFill`),
and once on import (`TimedMinerClient`, `execute`). Same transactions in the same order,
same gas, moments apart (median 6 s).

| | last candidate build | import of that block | difference |
|---|---|---|---|
| execute totalMs | 97.5 | 110.0 | +12.5 |
| txExecutionMs | 96 | 107 | +11 |
| statePersistMs | 0 (commit only) | 3.2 (trie save) | +3.2 |

The import is slower by 12.5 ms in every block (median 13), and 11 of those are in the
transaction loop itself, for the same transactions. all 926 executions in the arm (823 builds, 103 imports) logged
`invalidTxCount=0`; the build's loop also tries every transaction left in the pool after the
block is full (up to 1126 per build, 726 on average at the end, against 138 that fit), so the
build column is if anything an overestimate of the work the included transactions need.

Candidate rebuilds per block:

| | value |
|---|---|
| builds per qualifying block | 9.1 (7.8 over all 103 blocks) |
| build duration | 94.8 ms mean |
| build CPU per block | 0.85 s |
| build thread busy, share of wall time | 5.8% |
| triggers over the arm | 792 from the pending-tx listener, 30 from the 1-minute refresh timer, 1 at start |
| when in the block interval the builds start | 15% within 0.5 s of the new best block, 41% at 0.5 to 2 s, 39% at 2 to 5 s, 5% later |
| builds whose execution overlapped an import | 1 of 53 blocks (1.9%) |
| transactions tried per build (pool backlog) | 726 on average in the last phase, block holds 138 |

Per k6 phase (5 minutes each; phase sizes are k6's target transactions per block), all
blocks, plain means:

| phase | blocks | txCount | gas M | block interval s | tx/s mined | builds/block | build ms | executeMs | initialValidationMs |
|---|---|---|---|---|---|---|---|---|---|
| 20 | 15 | 19 | 22.1 | 18.2 | 1.0 | 5.4 | 210 | 197 | 4.3 |
| 35 | 18 | 29 | 24.8 | 16.4 | 1.8 | 6.6 | 194 | 168 | 8.1 |
| 60 | 18 | 55 | 24.8 | 18.4 | 3.0 | 8.6 | 108 | 117 | 2.3 |
| 100 | 19 | 87 | 24.8 | 15.8 | 5.5 | 8.8 | 96 | 112 | 4.6 |
| 160 | 16 | 144 | 24.9 | 18.8 | 7.6 | 9.3 | 95 | 113 | 5.6 |
| 250 | 13 | 209 | 25.0 | 22.9 | 9.1 | 9.2 | 92 | 105 | 6.5 |

The first two phases are the JVM's warm-up (the reason the lab drops the first 50 blocks);
builds and imports are both twice as slow there. Blocks come every 16 to 23 s, not the 10 s
median, because the timed miner restarts its timer on every new best block. k6 delivers 1 to
9 transactions per second mined; block gas is at the limit from phase 35 on.

CPU, from the sampler over the qualifying window (960 s), and JFR:

| thread (or group) | CPU s | share of node CPU | share of 2 CPUs |
|---|---|---|---|
| miner-build-block-listener | 43.5 | 57% | 2.3% |
| nioEventLoopGroup (4 RPC threads) | 20.7 | 27% | 1.1% |
| TimedMinerClient (import) | 6.0 | 8% | 0.3% |
| C2 and C1 compiler | 2.6 | 3% | 0.1% |
| G1 (GC threads and service) | 1.1 | 1.4% | 0.06% |
| everything else | about 2 | 3% | 0.1% |

`docker stats` agrees: 9.7% of one CPU on average, so the container is idle about 95% of the
time. GC: 74 collections in the arm, 1.84 s of pauses, 11 ms mean after warm-up (max 46 ms,
one 687 ms pause at start); none of them began inside an import window (0 of 53 blocks).
Lock waits: the four RPC threads spent 11.8 s blocked on `EthModuleTransactionBase`'s
monitor (every `eth_sendTransaction` is serialized there) and their CPU is BouncyCastle
signing (`ECKey.doSign`, pure Java) plus `TransactionPoolImpl.removeObsoleteTransactions`
on every add. The import thread blocked on no monitor. JFR's execution samples on the import
thread (151 samples) have the same shape as the build thread's (952): `VM.executeOpcode`,
`BigInteger` construction in `DataWord`, `RLP.decode2`, `AccountState.<init>`,
`callToPrecompiledAddress`. Nothing extra shows up in the import, it runs the same code
slower.

Validation rules, from the `Validation rule <name>` lines (millisecond timestamps, so each
rule is a whole number of milliseconds and the sum of the logged rules is an upper bound):

| | ms |
|---|---|
| all 17 logged rules together, first `Validating block` line to the last rule's start | under 1 |
| `initialValidationMs` minus that span | 5.1 |

So the rules are not where `initialValidationMs` goes; the time is before the first rule
line. `BlockValidatorImpl.isValid` runs `prefetchSenders` first, and that is where it is.

## Mechanisms and what to test

**Import executes the same transactions 11 ms slower than the miner did (the largest
component, 9% of executeMs).** The data rules out the obvious causes: the build thread is
busy 5.8% of the time and overlapped 1 import in 53; GC never landed in an import; the
container is 95% idle; the import thread waits on no lock; its profile is the build's. What
differs is the thread and the object graph. The import runs on `TimedMinerClient`, which
sleeps between blocks and wakes once every 16 s to do 110 ms of work, while the build thread
runs the same code nine times per block. And the block it imports is not the candidate: in
`processSolution`, `blockFactory.cloneBlockForModification` re-decodes the candidate from its
RLP, so every `Transaction` is a fresh object whose fields parse lazily and whose sender
memo is empty (see the next item). Two tests for perf-lab, separable: (a) replay with a pause,
`ConnectBlocks` sleeping 10 s between blocks, on this Mac and on a Boton box; if executeMs
rises toward the live value, the cost is the cold thread (frequency, cache, core placement
in the Docker VM, and Boton's slower cores would explain its larger gap of +46 ms); (b) a
build of RSKj where `processSolution` imports the candidate's own `Block` object (clone only
the header for the merged-mining fields, keep the transaction objects), which also removes
the next item.

**`initialValidationMs` 5.1 ms is `prefetchSenders`, re-recovering senders the miner already
had.** `BlockValidatorImpl.prefetchSenders` calls `tx.getHash()` and `tx.getSender()`, the
cache-less path, on a parallel stream (2 CPUs here), for every transaction of the re-decoded
block. The rules that follow then hit `BlockTxSignatureCache` by hash and cost nothing
measurable. On a self-mined block every sender is in the signature cache already (the pool
recovered them at admission). Tests: `prefetchSenders` with `tx.getSender(signatureCache)`
instead of `tx.getSender()`; or skip it when the block's hash is in `blocksWaitingForPoW`;
or the candidate-object import above, which keeps the memoized senders and hashes. rustock
spends 0.2 ms here. Expected gain: 4 to 5 ms per block on Docker, 12 on Boton.

**`executeMs` includes a 3.2 ms trie save the build does not do (`statePersistMs`).** The
import calls `execute` with `saveState=true`, so `saveOrCommitTrackState` writes the new trie
nodes to the store inside the execute phase; the build commits to the cache only. rustock's
`trieSaveMs` is 0.6 ms. This is real work the replay path pays too, so it is part of the
replay gap, not the live gap; listed because it sits inside executeMs and would otherwise be
mistaken for transaction time. Test: move the save after the post-execute validation, or
batch it with the receipts write.

**`preambleMs` 1.8 (3.1 in the campaign), `saveReceiptsMs` 2.7, `switchChainMs` 1.0: block
store round trips on the mainnet seed.** The preamble is `blockStore.getBlockByHash` and
`getTotalDifficultyForHash` for a hash the store does not have (a bloom-filter miss in
RocksDB on the 186 GB seed) and the best-block read under `accessLock`. Receipts and the
block save are RocksDB writes of a 138-transaction block with its receipts. All three are
zero on the empty-database replay and small but present on the seed, so they are seed costs
rather than live costs; they are in the live gap only because the campaign compares live on
the seed with replay from empty. Tests: a replay campaign on the seed for the same
scenario (the lab has `ecdsa@mainnet` as a replay scenario), which prices these three
without mining; and for the preamble, checking `blocksWaitingForPoW` or the in-memory best
block before the store.

**Candidate rebuilds: 9 per block, 0.85 s of CPU per block, not in the import's way.** The
fee gate in `NewBlockTxListener.isWorthRebuilding` (`rebuildFeeFraction` 0.1) already holds
rebuilds to about 9 per block from the 130 the comment describes; 95% of them start within
5 s of the new best block, while the pool refills, and they finished before the next
solution in 52 of 53 blocks. Each build still iterates the whole pool backlog (726
transactions tried for 138 that fit, `TransactionExecutor` created and rejected on block
gas for each). On 2 CPUs this is 2.3% of the machine. It becomes contention only when the
build thread and the import coincide, which the timed miner's exponential interval makes
rare here; on Boton, where a build takes about 190 ms, the overlap probability roughly
doubles and is worth measuring from its own breakdown log (the `block execute breakdown`
lines on the `miner-build-block-listener` thread are already in every campaign's raw
directory, so the count needs no new run). Tests, in order of expected effect on the live
gap: none large on Docker; a minimum interval between rebuilds (1 s) or a gas-delta
threshold instead of the fee fraction would cut the 9 to about 3 and the backlog iteration
with it, which mostly buys CPU headroom for the import on 2-CPU boxes; stopping the loop at
the first transaction that does not fit (the pool is price-ordered) would cut each build's
tail.

**RPC threads: 27% of the node's CPU, on signing.** k6 sends unsigned transactions and the
node signs them with BouncyCastle (`ECKey.doSign`), serialized on one monitor; the pool also
runs `removeObsoleteTransactions` on each add. This is the load generator's cost on the node,
the same on both clients by design, and it never showed up in an import window here. On a
2-CPU box it is the second consumer after the builds, so a GC or JIT thread cap would not
help (GC and JIT together are 5% of node CPU, 0.2% of the machine); the signing path (native
secp256k1 for `eth_sendTransaction`, as the ecrecover path already has) would.

**GC and JIT are not in the gap on Docker.** No GC pause intersected an import; after
warm-up the pauses are 11 ms and about one per 2.5 blocks. The 687 ms pause and the slow
first two phases are warm-up, outside the qualifying window. On a 2-CPU Boton box the same
check is worth repeating from a JFR recording before capping threads.

## What this does not settle

The arm ran on this Mac's Docker only; the Boton numbers (246 vs 184, +46 ms executeMs) are
larger than a cold-thread effect of the Docker size would predict, so test (a) above should
run on a box. The 11 ms import excess has no direct measurement of its cause, only
exclusions; (a) and (b) are the two candidates left. `initialValidationMs` is attributed
by subtraction (whole-millisecond rule timestamps against the breakdown's own timer),
not by a timer around `prefetchSenders`.
