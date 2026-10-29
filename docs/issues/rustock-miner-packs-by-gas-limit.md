# rustock's miner fills a block by declared gas limits, rskj by gas used

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-29, campaign
`2026-10-29-c3`, rustock 1909b1c (`clients-lab/comparison`, upstream base 43dc5e5). Not a
consensus rule: the blocks are valid. It halves what a rustock miner puts in a block when
senders over-provision gas.

## What happens

`select_transactions` in `crates/execution/src/mining/template.rs` adds each candidate's
`gas_limit` to `gas_committed` and stops at the block gas limit, before anything is executed.
rskj's `BlockToMineBuilder` executes the candidates as it goes (`BlockExecutor.executeAndFill`):
a transaction must fit in the block limit minus the gas **used** so far
(`TransactionExecutor`, "Too much gas used in this block"), and once it has run only its
gas used counts. A sender that declares more gas than it uses costs rskj nothing and costs
rustock the difference.

## How it showed

Both clients mined 30 minutes under the same k6 load (option 14: native transfers at 21,000,
ERC-20 calls at 100,000, storage writes at 300,000, calldata-heavy calls at 1,500,000
declared gas), on the same mainnet state, same 25 M block gas limit:

| client | txs per block | gas used per block | sum of declared limits per block |
|---|---|---|---|
| rskj | 101 to 156 | 24.8 to 25.0 M | 40 to 43 M |
| rustock | 52 to 94 | 14.5 to 15.7 M | 25.0 M, exactly |

rustock's template stops when the declared limits reach 25 M, with the block 60% full, while
1,000 transactions wait in its pool. Under k6 option 7 (ECDSA calls, limits close to usage)
both clients fill their blocks alike, which is why the earlier live campaigns did not show it.

On mainnet, wallets routinely declare more gas than they use, so a rustock miner would
produce emptier blocks than an rskj miner from the same pool and earn less in fees.

## Fix

Select while executing, as rskj does: run each candidate against the template's state, keep
it if its gas limit fits in `block_gas_limit - gas_used_so_far`, and advance `gas_used` by
its receipt's gas used, not its limit. The template is executed once already to fill the
roots (`build`), so the cost is the ordering, not an extra execution. A test: ten candidates
declaring 5 M each and using 1 M each on a 25 M block; rskj's rule includes all ten, the
current rule five.
