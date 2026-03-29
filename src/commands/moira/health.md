---
name: moira:health
description: Check Moira system health
argument-hint: "[report|details|history]"
allowed-tools:
  - Bash
---

# /moira:health — System Health Check

Run the Moira CLI for structural health checks (tier 1 tests + graph health). This is a read-only, LLM-free operation.

Execute via Bash:
```bash
bash ~/.claude/moira/bin/moira health $ARGUMENTS
```

Display the output directly to the user.

**Note:** The CLI provides structural conformance scoring only. Quality and Efficiency scores require LLM-based evaluation (judge). If the user needs the full composite score with quality evaluation, inform them that a full `/moira:bench` run is needed for quality data.
