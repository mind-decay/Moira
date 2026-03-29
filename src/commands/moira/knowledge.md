---
name: moira:knowledge
description: View and manage the Moira knowledge base
argument-hint: "[patterns|decisions|quality-map|conventions|project-model|failures|edit]"
allowed-tools:
  - Bash
---

# /moira:knowledge — Knowledge Base

Run the Moira CLI to display knowledge base information. This is a read-only, LLM-free operation.

Execute via Bash, passing through any arguments:
```bash
bash ~/.claude/moira/bin/moira knowledge $ARGUMENTS
```

Where `$ARGUMENTS` is the user's argument (e.g., `patterns`, `decisions`, `edit`, or empty for overview).

Display the output directly to the user. Do not add commentary — the CLI output is self-explanatory.
