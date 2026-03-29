---
name: moira:graph
description: Query project structure graph
argument-hint: "[blast-radius|cluster|file|cycles|layers|metrics|smells|importance|spectral|diff|compressed|stats|churn|coupling|hotspots|ownership|hidden-deps|annotate|annotations|bookmark|bookmarks] [args...]"
allowed-tools:
  - Bash
---

# /moira:graph — Project Structure Graph

Run the Moira CLI to query the project graph. This is a read-only, LLM-free operation.

Execute via Bash, passing through all arguments:
```bash
bash ~/.claude/moira/bin/moira graph $ARGUMENTS
```

Where `$ARGUMENTS` is the subcommand and its arguments (e.g., `blast-radius src/main.ts`, `cycles`, `smells`, or empty for `stats`).

Display the output directly to the user. Do not add commentary — the CLI output is self-explanatory.
