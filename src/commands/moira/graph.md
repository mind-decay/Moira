---
name: moira:graph
description: Query project structure graph
argument-hint: "[blast-radius|cluster|file|cycles|layers|metrics|smells|importance|spectral|diff|compressed|stats|churn|coupling|hotspots|ownership|hidden-deps|annotate|annotations|bookmark|bookmarks] [args...]"
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

### `churn`
Requires `temporal_available = true` (check `.claude/moira/state/current.yaml`).
```bash
bash -c 'ariadne query churn --period <period> --format md'
```
Period argument: `30d` (default), `90d`, or `1y`.
If temporal not available: display "Temporal data not available (no git history or ariadne temporal not enabled)."

### `coupling`
Requires `temporal_available = true`.
```bash
bash -c 'ariadne query coupling --min-confidence <threshold> --format md'
```
Default threshold: `0.7`.
If temporal not available: display "Temporal data not available."

### `hotspots`
Requires `temporal_available = true`.
```bash
bash -c 'ariadne query hotspots --top <n> --format md'
```
Default top: `10`.
If temporal not available: display "Temporal data not available."

### `ownership`
Requires `temporal_available = true`.
```bash
bash -c 'ariadne query ownership <path> --format md'
```
If no path argument provided: show project-wide ownership.
If temporal not available: display "Temporal data not available."

### `hidden-deps`
Requires `temporal_available = true`.
```bash
bash -c 'ariadne query hidden-deps --format md'
```
If temporal not available: display "Temporal data not available."

### `annotate`
Requires graph available.
```bash
bash -c 'ariadne annotate <target> --tag <tag> --text "<text>"'
```
If no target/tag/text argument provided: display "Usage: /moira:graph annotate <target> <tag> <text>"

### `annotations`
Requires graph available.
```bash
bash -c 'ariadne query annotations --tag <tag> --format md'
```
If no tag argument: list all annotations.

### `bookmark`
Requires graph available.
```bash
bash -c 'ariadne bookmark <name> <paths...>'
```
If no name/paths argument provided: display "Usage: /moira:graph bookmark <name> <paths...>"

### `bookmarks`
Requires graph available.
```bash
bash -c 'ariadne query bookmarks --format md'
```

### Unknown subcommand
Display:
```
Unknown subcommand: {subcommand}

Available: blast-radius, cluster, file, cycles, layers, metrics, smells, importance, spectral, diff, compressed, stats, churn, coupling, hotspots, ownership, hidden-deps, annotate, annotations, bookmark, bookmarks
```

## Step 4: Display Results

Display the output from the ariadne query directly. The `--format md` flag produces markdown output suitable for display.

## Notes

- This command is read-only. It never modifies graph data.
- All queries go through the `ariadne` CLI binary, not through graph.sh library functions (graph.sh is for programmatic use by other commands).
- The `diff` subcommand is the only one that requires the MCP server; all others use the CLI.
- If a query returns empty output, display "No results." instead of blank output.
