# Adapter boundary

Changes inside `clients/rustock` (or any client) are harness-only: chain configuration,
block import, timing lines, packaging. Never a change to what the client computes or how fast
it computes it. Each change lives on its own `harness/<topic>` branch, written as an upstream
pull request (tests, description in `docs/prs/`); `clients-lab/harness` merges them. The lab
builds `clients-lab/comparison`, which tracks that merge and holds comparison-only
instrumentation, until upstream merges the adapter branches.
