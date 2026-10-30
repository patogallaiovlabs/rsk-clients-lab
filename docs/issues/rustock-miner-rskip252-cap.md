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

rskj has this test already: `MinerUtilsTest.filterTransactions_whenRskip252EnabledThenTxWithMoreGasPriceThanCapExcluded`
(with its `...Disabled...` twin). rustock ported the import rule and its test
(`block_txs_max_gas_price_enforces_the_100x_cap_from_rskip252`) but not the miner's; porting
that test is the natural start.

## Status

Fixed on 2026-10-30, rustock branch `fix/miner-gas-packing-cap-and-gasprice-gate` (on top of
1909b1c), uncommitted until the user says so. Selection (`filter_candidates`, rskj
`MinerUtils.filterTransactions`) drops a transaction priced over 100 times the template's
minimum from the RSKIP252 height on, with the same zero-minimum short-circuit as
`TxGasPriceCap`, and the assembled block is run through the body rules every peer applies
(`BlockProcessor::validate_block_body_rules`: gas price floor and cap, REMASC last, extra data,
minimum gas price step) before it is handed out. Tests ported: rskj's `filterTransactions_...`
pair as `filter_transactions_when_rskip252_enabled_then_tx_with_more_gas_price_than_cap_excluded`
and `..._disabled_then_tx_included_regardless_gas_price`, plus the template-level
`a_transaction_over_the_rskip252_cap_is_left_out_of_the_template`.
