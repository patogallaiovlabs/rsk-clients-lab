# --export-blocks: write the chain in rskj's ExportBlocks format

Branch `harness/export-blocks` in `clients/rustock`, on `harness/mined-block-timing`. One commit.

## What and why

A live arm mines its own blocks, so the only check that they are right is to replay them into
the other client. rskj's `ExportBlocks` writes a chain as one line per block,
`number,hashHex,totalDifficultyHex,blockRlpHex`, which rskj's `ConnectBlocks` and this node's
`--import-blocks` read. `--export-blocks <file>` writes the canonical chain in that format,
from `--export-from` (default 1) to `--export-to` (default the best block), plain or gzip when
the name ends in `.gz`, and exits. It opens the block store only.

Each field is written as `co.rsk.cli.tools.ExportBlocks.exportBlocks` writes it. The hash is
the one the block is stored under. The total difficulty is `BigInteger.toByteArray()`: shortest
big-endian form, a leading zero byte when the top bit is set, `00` for zero. The RLP is
`Block.getEncoded()`: the header in its full wire form (version fields, edges and base event
included, which `Header::encode` already produces), then the transactions, then the uncles.
Transactions are written in the bytes they were received or built with (`rlp_for_trie`, what
their hashes and the transactions root are computed over), because rskj keeps a zero gas price
as a literal `00` byte there and re-encoding would canonicalise it to `80`. The decoder is the
existing `parse_export_line`; `encode_block` is the inverse of its `decode_block`.

Testing the round trip on rskj's own exports found the stored total difficulty short from the
first block with an uncle: the import path and the mined path added the header's difficulty
alone, where rskj's `Block.getCumulativeDifficulty` adds the uncles' too (the sync path and the
`--repair total-difficulty` tool already did). Both now add them, through
`mining::cumulative_difficulty`. The total difficulty is not consensus, and neither decoder
reads the field, so no hash depended on it; the exported file did.

## How to test

```bash
cargo test -p rustock-sync import
cargo test -p rustock-cli --test import_blocks
cargo test -p rustock-execution cumulative_difficulty
```

`an_export_after_an_import_reproduces_rskjs_file` imports rskj's regtest fixture (blocks 1 to
15, version-2 headers) and checks that `--export-blocks` writes the gunzipped fixture byte for
byte, both the whole chain and a range (5 to 9, as `.gz`).
`an_exported_line_parses_back_to_the_same_block` and
`total_difficulty_is_written_as_java_writes_a_big_integer` cover the encoder alone.

By hand, on the lab's ecdsa sample (207 blocks, an uncle at block 47): a fresh import of
blocks 1 to 50 followed by an export is byte for byte the first 50 lines of
`gzcat samples/ecdsa/blocks.txt.gz`; the full 207-block database, imported before the
total-difficulty fix, exported identically once `--repair total-difficulty` had rewritten the
161 totals from block 47 on. A chain mined with `--mine-timed` exports, re-imports from an empty
data directory with every hash equal, and re-exports to the identical file.
