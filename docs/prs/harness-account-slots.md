# --account-slots: how many transactions a sender may queue past its nonce

Branch `harness/account-slots` in `clients/rustock`, on `clients-lab/harness` (780d440).
One commit.

## What and why

rskj's `transaction.accountSlots` bounds how many transactions one sender may have in the
pool ahead of its state nonce; a nonce at or past the state nonce plus the slots is refused
as "transaction nonce too high". rustock has the same rule in `PoolConfig::account_slots`,
with rskj's default of 16, but no way to set it.

The lab runs rskj with `accountSlots = 500` (rsk-perf-lab's configuration for its k6 suite,
which signs bursts of transactions per account). In the first full live mining cycle
(`campaigns/2026-10-28-c3`, k6 option 7) rskj accepted every stress call and rustock
refused 32% of them as nonce too high, so rustock's arm fell under the 80% success rate the
lab asks for and the cycle did not count. The one setting rskj had and rustock could not
have is the fairness rule's case: a non-default setting both clients get.

`--account-slots <n>` sets it; the default stays 16.

## Tests

`account_slots_default_to_rskj_s_and_take_a_value`: the flag defaults to 16 and takes a
value. `cargo test -p rustock-cli account_slots` passes.

## Scope

Pool admission policy, as a setting. What the node validates and executes is untouched.
