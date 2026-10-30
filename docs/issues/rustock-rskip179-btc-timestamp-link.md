# rustock does not enforce RSKIP179, the Bitcoin-to-RSK timestamp link

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-30 by mapping rskj's tests
(e507f45) to rustock's (branch `fix/miner-gas-packing-cap-and-gasprice-gate` on 1909b1c); the
full table is `docs/rskj-test-parity.md` in rustock.

A consensus rule, active on mainnet since iris300.

## What happens

rskj `BlockTimeStampValidationRule.isBitcoinTimestampValid`: from RSKIP179 on, a header
must carry a decodable Bitcoin merged-mining header, and the Bitcoin block's time and the RSK
header's timestamp must differ by less than `maxTimestampsDiffInSecs`: 300 s, or 7200 s on
testnet once RSKIP297 is active (`Constants.getMaxTimestampsDiffInSecs`). A header that fails
is invalid.

rustock has no such check. `TimestampRule` (`crates/core/src/validation/header_rules.rs`)
compares the RSK timestamp with the clock and the parent; `MergedMiningRule`
(`crates/core/src/validation/merged_mining.rs`) verifies the proof and never reads the Bitcoin
header's time. Nothing under `crates/` mentions RSKIP179.

## How it shows

A block whose Bitcoin header time is 300 s or more away from its RSK timestamp is rejected by
every rskj node and accepted by rustock, which then follows a chain the network refuses. The
mainnet replay cannot show it: no such block exists on the canonical chain, because rskj
miners never produced one.

## Fix

Add the check to the header rules from the RSKIP179 height (iris300 on mainnet, with the
testnet widening under RSKIP297): decode the merged-mining header, take its time, compare
with the RSK timestamp, strict inequality as rskj has it. Port
`BlockTimeStampValidationRuleTest.timestampsAreCloseEnough` and its missing-header case.
