# Shared machines

rsk-perf-lab and this lab share this Mac's Docker VM and both Boton boxes through
`~/.research-lab/locks`. Priorities, lower first: perf-lab's `6-boton` 0, its replays and
profiling 1, its candidate uploads and this lab's campaigns 2. On Docker a campaign cycle is a
`long` holder with its queue time as priority, so perf-lab's short replays and gates go first.
Never remove a lock whose `lab` file names another lab.
