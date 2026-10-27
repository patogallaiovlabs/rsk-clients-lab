# Correctness before speed

A run counts only if every block of the scenario was imported, in order, with exactly the
hashes in `samples/<scenario>/reference_hashes.txt` (`consensus.json` says `consensus_ok`).
A run that fails stops the campaign. It is reported as a consensus finding: first diverging
block, which check failed, and the cause if known. Never time, and never report a speed for, a
client that computed something different.
