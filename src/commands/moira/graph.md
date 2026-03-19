---
name: moira:graph
description: Query project structure graph
argument-hint: "[blast-radius|cluster|file|cycles|layers|metrics|smells|importance|spectral|diff|compressed|stats] [args...]"
allowed-tools:
  - Read
  - Bash
---

# /moira:graph — Project Structure Graph

Query the project's structural dependency graph via the Ariadne CLI.

## Setup

- **Graph library:** `~/.claude/moira/lib/graph.sh`
- **Graph data:** `.ariadne/graph/`
- **Graph views:** `.ariadne/views/`

## Step 1: Verify Prerequisites

### 1a: Check Binary

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_check_binary'
```

If output is empty (binary not found), display and stop:
```
ariadne binary not found.
Install: cargo install ariadne-graph
Or: curl -sSL https://raw.githubusercontent.com/anthropics/ariadne/main/install.sh | bash
```

### 1b: Check Graph Exists

Read `.ariadne/graph/graph.json`.

If not found, display and stop:
```
No graph found. Run /moira:init or ariadne build .
```

## Step 2: Parse Subcommand

Parse `$ARGUMENTS` to extract the subcommand (first word) and remaining arguments.

If no subcommand provided: default to `stats`.

## Step 3: Execute Query

Map subcommands to `ariadne query` calls. All queries use `--format md` for human/agent-readable output.

Run via Bash (always use `bash -c`):

### `stats` (default — no subcommand)
```bash
bash -c 'ariadne query stats --format md'
```

### `blast-radius`
Requires a file path argument.
```bash
bash -c 'ariadne query blast-radius <file> --format md'
```
If no file argument provided: display "Usage: /moira:graph blast-radius <file>"

### `cluster`
Requires a cluster name argument.
```bash
bash -c 'ariadne query cluster <name> --format md'
```
If no name argument provided: display "Usage: /moira:graph cluster <name>"

### `file`
Requires a file path argument.
```bash
bash -c 'ariadne query file <path> --format md'
```
If no path argument provided: display "Usage: /moira:graph file <path>"

### `cycles`
```bash
bash -c 'ariadne query cycles --format md'
```

### `layers`
```bash
bash -c 'ariadne query layers --format md'
```

### `metrics`
```bash
bash -c 'ariadne query metrics --format md'
```

### `smells`
```bash
bash -c 'ariadne query smells --format md'
```

### `importance`
```bash
bash -c 'ariadne query importance --format md'
```

### `spectral`
```bash
bash -c 'ariadne query spectral --format md'
```

### `diff`
This subcommand requires the MCP server (`ariadne serve`) to be running.

Check if server is running:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && cat .ariadne/graph/.serve.pid 2>/dev/null'
```

If PID file does not exist or process is not running, display and stop:
```
This subcommand requires ariadne serve.
Start with: ariadne serve --project .
```

If server is running, the structural diff is available via the `ariadne_diff` MCP tool. Invoke it directly.

### `compressed`
Requires a level argument (0, 1, or 2).
```bash
bash -c 'ariadne query compressed --level <level> --format md'
```
If no level argument provided: display "Usage: /moira:graph compressed <level>"

### Unknown subcommand
Display:
```
Unknown subcommand: {subcommand}

Available: blast-radius, cluster, file, cycles, layers, metrics, smells, importance, spectral, diff, compressed, stats
```

## Step 4: Display Results

Display the output from the ariadne query directly. The `--format md` flag produces markdown output suitable for display.

## Notes

- This command is read-only. It never modifies graph data.
- All queries go through the `ariadne` CLI binary, not through graph.sh library functions (graph.sh is for programmatic use by other commands).
- The `diff` subcommand is the only one that requires the MCP server; all others use the CLI.
- If a query returns empty output, display "No results." instead of blank output.
