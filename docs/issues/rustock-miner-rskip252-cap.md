# rustock's miner includes transactions over the RSKIP252 gas price cap

For SergioDemianLerner/rustock. Found by rsk-clients-lab on 2026-10-29, campaign
`2026-10-28-c6`, rustock 1909b1c (`clients-lab/comparison`, upstream base 43dc5e5).

## What happens

RSKIP252 (rskj `BlockTxsMaxGasPriceRule`, `TxGasPriceCap.FOR_BLOCK`, active since
fingerroot500) makes a block invalid if any transaction in it pays more than 100 times the
block's `minimumGasPrice`. rustock enforces it on import
(`crates/core/src/validation/block_rules.rs`, `BlockTxsMaxGasPriceRule`, wired in
`BlockProcessor::validate_block_rules`) but not when it mines: `select_transactions` in
`crates/execution/src/mining/template.rs` drops transactions priced under the minimum and
nothing else, and the sealed block is not run through the block rules. rskj's miner drops
them (`MinerUtils.isHighGasPriced`), so an rskj node never seals such a block.

A rustock miner that receives a transaction priced over the cap therefore seals a block that
every rskj node, and rustock itself on import, rejects. Its own chain keeps growing on top
of it.

## How it showed

A regtest-configured mainnet copy at tip #9003567 whose `minimumGasPrice` had been walked
down to 587 wei, with a k6 load that prices by `eth_gasPrice`. rustock's `eth_gasPrice`
answered 26,065,600 wei (see the companion issue on the fee-market gate), the miner put
those transactions in block #9003569, and rskj rejected it:

```
WARN [blockvalidator] Tx gas price=26065600 is above the cap. Block=448584413f..., Tx=4c9b9c80...
WARN [blockchain] Invalid block with number: 9003569
```

Every one of the 138 blocks rustock mined in that arm had the same transactions and would
have been rejected the same way. On mainnet the minimum tracks the market and the cap is
100 times away, so it takes a chain whose minimum is far under what senders pay.

## Fix

Drop, in `select_transactions`, every transaction whose gas price exceeds the minimum times
100 from the RSKIP252 height on (the same `TxGasPriceCap` the import rule uses), and run
`validate_block_rules` on the sealed block before announcing it, so the miner cannot produce
what the importer refuses. A test: a pending transaction at 101 times the template's
minimum is left out, one at 100 times is included.
