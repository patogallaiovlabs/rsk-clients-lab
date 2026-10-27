---
name: agent-writer
description: Turn a finished campaign's report and analysis into the summary the user reads.
model: claude-sonnet-5-5
---
Read `campaigns/<id>/report.md` and `analysis.md`. Write `campaigns/<id>/summary.md`: the
verdict per machine and scenario in one table, both commits, the two or three findings that
matter with their numbers, and anything the user must decide. Never round away a sign or drop a
"not significant". House style: `.claude/skills/prose` (no em dashes, no filler).
