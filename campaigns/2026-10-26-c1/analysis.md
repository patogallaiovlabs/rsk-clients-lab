# Where the mainnet-sim time goes

The Docker campaign measured this. On mainnet-sim, rustock's `executeMs` is 52.2 ms/block and RSKj's is 12.1, rustock slower in 0/6 cycles. That phase is almost the whole gap: `totalMs` is 56.1 against 17.8. Validation is faster in rustock (1.3 ms against 2.8). Receipts and chain switch add about 2.6 ms in rustock and about nothing in RSKj.

`docs/timing-scope.md` says what that phase covers. RSKj's `executeMs` runs the transactions, REMASC and the state root, and `statePersistMs` inside it is 2.4 ms. rustock's `executeMs` does the same work and also writes the trie nodes into its trie store on every block. RSKj flushes its stores every tenth block, under `onBestBlockMs`.

## Profiles

One replay of each client, recorded after the campaign. These runs do not count. RSKj was a JFR recording of the Docker replay (1,159 blocks, hashes matched, 42 s). rustock was `perf record` on box A (1,159 blocks imported in 107 s). The rustock recording includes perf's own overhead and a slower machine, so the two profiles are read for mix, and the campaign stays the source of the times.

Of the RSKj samples that are the replay itself, keccak is 48% and the in-memory trie is 43%. The EVM is 4%. Another 20% of all samples is `HexEncoder.decode` of the export file, which `timing-scope.md` places outside `totalMs`.

On the rustock recording, symbols at or above 0.4% of samples add up as follows. RocksDB is 23%, and the hottest single function is `InlineSkipList::FindGreaterOrEqual` at 10.8%. Keccak is 16.7%. secp256k1 field arithmetic is 11.2%. Trie path encode and decode is 8.3%.

## What that supports

The campaign's missing 40 ms sits where the two clients store trie nodes differently, and the rustock profile shows that store on the CPU: a RocksDB memtable lookup on the hot path. RSKj's profile of the same blocks is keccak and an in-memory trie.

Signature recovery is visible in rustock and is a place it is ahead. On the ecdsa sample the same build's `executeMs` is 2.54x faster than RSKj (90.3 ms against 229.0).

## The trie-store write

`trieSaveMs` is the `TrieNode::save` batch, included in `executeMs` and logged beside it. One diagnostic replay of that build (`clientslab-rustock:trie-save-linux-arm64`, hashes matched, 60 s, 1,027 full blocks) measures it at 8.6 ms (10% trimmed mean). `executeMs` on the same run is 50.9. The batch write is about a sixth of execute. The other 42 ms is the rest of the phase, which is where the profile put the RocksDB memtable lookups.
