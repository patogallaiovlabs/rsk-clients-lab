# --import-blocks: import an rskj ExportBlocks file through follow mode's checks

Branch `harness/import-blocks` in `clients/rustock`, on `harness/regtest-config`. One commit.

## What and why

To compare the clients on the same chain, rustock has to take the blocks rskj mined into an
empty node and stop at the first block whose result differs. rskj's `ExportBlocks` writes
`number,hash,totalDifficultyHex,blockRlpHex` per line; `--import-blocks <file>` reads that,
plain or gzipped, and imports each block through `BlockImporter` (`rustock-sync`):

1. the block must extend the best block;
2. the header is checked against its parent with `HeaderVerifier` and the body with
   `BlockProcessor::validate_block`, as follow mode does;
3. `process_block` executes it and checks transactions root, ommers hash, gas used, paid fees,
   state root, receipts root and logs bloom against the header;
4. header, body and receipts are stored, in rskj's order (validate, execute, check, store);
5. every `--import-flush-every` blocks (10, rskj's `flushNumberOfBlocks`) the trie is flushed
   and the executed head recorded, through the `ExecutionCommitter` follow mode uses.

The first failure ends the process with a non-zero status and
`import failed at block <n> hash <hex> check <name>: <error>`, with the failed block's trie
nodes flushed so its state can be diffed against rskj's (`diff_roots`).

`ExportBlocks` writes headers in rskj's full encoding, and a versioned header is hashed in its
compressed encoding, so the importer recomputes the hash of versioned headers.
`process_and_commit` is split into `process_block` and `commit_receipts`; what it does is
unchanged.

## How to test

```bash
cargo test -p rustock-cli --test import_blocks
cargo test -p rustock-sync import
```

The integration test imports blocks 1 to 15 of an rskj regtest chain (version-2 headers, twenty
contract calls a block, a flush at 10, REMASC's first payout at 15) and checks the best block is
rskj's block 15; a second test checks that a block that does not connect stops the import. By
hand, from an empty directory:

```bash
rustock-cli --network-id 33 --no-rpc --data-dir db --trie-backend external --trie-dir db-trie \
  --genesis genesis_25M.json --skip-pow-validation --consensus-rule rskip97=0 \
  --min-gas-limit 3000000 --max-gas-limit 18446744073709551615 \
  --import-blocks blocks.txt.gz --import-flush-every 10
```

`--trie-backend external` is needed because the fork refuses a fresh data directory with the
default `single` backend ("This database has no trie in it").
