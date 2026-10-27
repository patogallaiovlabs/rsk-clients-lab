# Fairness

Both clients get the same blocks, the same machine, the same CPU and memory limits and an
empty database for every run. Warm-up is handled the same way for both (the analyzer keeps
only blocks at least 90% full, by gas). No setting is tuned for one client only: if a client
needs a non-default setting to run at all, the report says which and why. Every report names
both commits and every non-default setting.
