---
name: moira:metrics
description: View Moira performance metrics dashboard
argument-hint: "[details <section>|compare|export]"
allowed-tools:
  - Bash
---

# /moira:metrics — Performance Metrics

Run the Moira CLI to display metrics. This is a read-only, LLM-free operation.

Execute via Bash, passing through any arguments:
```bash
bash ~/.claude/moira/bin/moira metrics $ARGUMENTS
```

Where `$ARGUMENTS` is the user's subcommand (e.g., `details quality`, `compare`, `export`, or empty for dashboard).

Display the output directly to the user. Do not add commentary — the CLI output is self-explanatory.
