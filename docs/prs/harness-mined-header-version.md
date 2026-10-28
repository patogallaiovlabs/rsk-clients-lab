# Mined headers carry the version the chain activates

Branch `harness/mined-header-version` in `clients/rustock`, on `clients-lab/harness` (d9d2d2e).
One commit.

## What and why

The block template set a header version only when RSKIP-144 had split the block into
sublists; otherwise it built a version-0 header whatever the chain had activated. On rskj's
regtest (`rskip351 = 1`, `rskip535 = 1`, `rskip144 = -1`) every rskj block is version 2, and
rskj's `BlockFactory.decodeHeader` reads the version byte after `ummRoot` unconditionally
once RSKIP-351 is active: given rustock's version-0 header it read the merged-mining header
as the version and failed with a `NullPointerException` in `ConnectBlocks`. The lab found it
in the first live mining cycle (`campaigns/2026-10-27-c4`): RSKj's 48 mined blocks replayed
into rustock, rustock's 42 did not replay into RSKj.

The template now picks the version as rskj's `BlockHeaderBuilder` does: 2 from RSKIP-535 on,
1 from RSKIP-351 on, 0 before. The edges are present and empty from RSKIP-144 on when the
block has no sublists (rskj emits them on every header from reed810), the partition's edges
when it has, and absent before RSKIP-144. A version-2 header's base event is empty rather
than absent when the block carries none.

The decoder had one assumption the change exposes: four or more items after
`minimumGasPrice` meant an `ummRoot` was first. A versioned header on a chain without
papyrus200 (only the test fixture; every real network activates it long before RSKIP-351)
starts those items with the bare version byte instead, which an `ummRoot` (empty or 32 bytes)
never is, so the decoder now checks for it before taking an `ummRoot`.

## Tests

`a_template_carries_the_header_version_the_chain_activates`: on a chain with everything but
reed810 active, the template's header is version 2 with no edges and an empty base event, and
its sealed wire form decodes back to the same fields and the same hash (the versioned header
is hashed in its compressed form). `a_chain_without_reed810_declares_no_partition` now checks
the edges rather than the whole version record. `cargo test -p rustock-execution --lib
mining::` (105) and `cargo test -p rustock-core` (176) pass.

## Scope

Mining path only: what the node validates and executes is untouched. A node that mined on
regtest or on a chain past RSKIP-351 produced blocks other rskj nodes could not decode; this
is the fix.
