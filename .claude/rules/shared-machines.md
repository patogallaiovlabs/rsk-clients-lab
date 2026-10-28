# Shared machines

This Mac's Docker VM and both Boton boxes may be shared with other labs through
`~/.research-lab/locks`, with the protocol in `bin/lib.sh`. Priorities, lower first: 0 and 1
are for more urgent work of other labs, this lab's campaigns hold at 2. On Docker a campaign
cycle is a `long` holder with its queue time as priority, so another lab's short jobs go
first. Never remove a lock whose `lab` file names another lab.
