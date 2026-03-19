---
name: moira:status
description: Show current Moira system state
allowed-tools:
  - Read
  - Bash
  - Glob
  - Grep
---

# /moira:status — System State

Show the current state of the Moira system for this project.

## Setup

- **MOIRA_HOME:** `~/.claude/moira/`
- **Project state:** `.claude/moira/state/`
- **Config:** `.claude/moira/config.yaml`

## Step 1: Verify Initialization

Read `.claude/moira/config.yaml`.

If not found, display and stop:
```
Moira is not initialized for this project.
Run /moira:init first.
```

## Step 2: Read System State

Read the following files (skip any that don't exist):

1. **Version:** `~/.claude/moira/.version`
2. **Config:** `.claude/moira/config.yaml` — project name, stack, quality mode
3. **Current task:** `.claude/moira/state/current.yaml` — active pipeline state
4. **Locks:** `.claude/moira/config/locks.yaml` — active locks (if exists)
5. **Graph:** `.ariadne/graph/graph.json` — graph existence check

## Step 3: Recent Tasks

Scan `.claude/moira/state/tasks/` for task directories. For each (up to last 5, sorted by directory name descending):
- Read `status.yaml` to get: task_id, description, status, pipeline, size, created_at, completed_at

## Step 4: Knowledge Freshness

Source the knowledge library and check freshness:
```bash
source ~/.claude/moira/lib/knowledge.sh
source ~/.claude/moira/lib/yaml-utils.sh
```

For each knowledge type (project-model, conventions, decisions, patterns, failures, quality-map):
- Check if directory exists in `.claude/moira/knowledge/{type}/`
- If exists, count files and check for freshness markers

## Step 5: Display

Format output as follows:

```
═══════════════════════════════════════════
  MOIRA — System Status
═══════════════════════════════════════════

  Version:     {version}
  Project:     {project.name}
  Stack:       {project.stack}
  Quality:     {quality.mode} mode
  Bootstrap:   quick={yes/no}  deep={yes/no}

─── Active Task ──────────────────────────

  {If current.yaml exists and task_id is set:}
  Task:        {task_id}
  Pipeline:    {pipeline}
  Step:        {step} ({step_status})
  Context:     {orchestrator_percent}% used
  {If gate_pending:}
  Gate:        {gate_pending} — awaiting decision

  {If no active task:}
  No active task.

─── Recent Tasks ─────────────────────────

  {For each recent task, newest first:}
  {task_id}  {status_icon} {status}  {pipeline}  {size}
  {description (truncated to 60 chars)}

  Status icons: completed=done, failed=FAIL, aborted=STOP, in_progress=..., pending=wait

─── Knowledge ────────────────────────────

  {For each knowledge type that exists:}
  {type}: {file_count} entries  ({freshness_category})

  {For types that don't exist:}
  {type}: not initialized

─── Project Graph ────────────────────────

  {If .ariadne/graph/graph.json exists, run via Bash:}
  {source ~/.claude/moira/lib/graph.sh && moira_graph_summary}
  {source ~/.claude/moira/lib/graph.sh && moira_graph_is_fresh && echo "fresh" || echo "stale"}
  {Check .ariadne/graph/.serve.pid for MCP server status}

  Files: {node_count}  Edges: {edge_count}  Clusters: {cluster_count}
  Cycles: {cycle_count}  Smells: {smell_count}
  Monolith: {monolith_score}  Freshness: {fresh/stale}
  MCP server: {running (PID {pid}) / stopped}

  {If .ariadne/graph/graph.json does not exist:}
  Project Graph: not available (ariadne not installed)

─── Locks ────────────────────────────────

  {If locks exist:}
  {lock_id}: {developer} on {branch} (expires {ttl})

  {If no locks:}
  No active locks.

═══════════════════════════════════════════
```

## Notes

- This command is read-only. It never modifies state.
- If knowledge freshness scoring fails (e.g., no task count), show "unknown" instead of crashing.
- Truncate long descriptions to keep output clean.
- Use the `moira_yaml_get` function from yaml-utils.sh where possible for reading YAML values.
