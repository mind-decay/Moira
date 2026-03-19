---
name: moira:refresh
description: Update project model and knowledge base
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---

# Moira — Refresh

This command updates the project's MCP registry by re-scanning available MCP servers.

> Full project re-scan (all scanners, knowledge, rules) is NOT yet implemented. This command currently handles MCP re-scan only.

---

## Step 1: Verify Initialization

Read `.claude/moira/config.yaml`.

- If not found: display error and stop:
  ```
  Moira is not initialized for this project.
  Run /moira:init first.
  ```

## Step 2: MCP Re-scan

Read the MCP scanner template and dispatch a single Explorer agent:
- `~/.claude/moira/templates/scanners/mcp-scan.md`
- `~/.claude/moira/core/rules/roles/hermes.yaml`
- `~/.claude/moira/core/rules/base.yaml`

**Agent — MCP Scanner:**
- description: "Hermes — MCP re-scan"
- subagent_type: general-purpose
- prompt: Combine Hermes identity + base rules + mcp-scan.md instructions

Wait for completion.

## Step 2b: Graph Update

If the Ariadne binary is installed and a graph already exists, run an incremental update.

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh
version=$(moira_graph_check_binary)
if [[ -z "$version" ]]; then
  exit 0
fi
if [[ ! -f ".ariadne/graph/graph.json" ]]; then
  exit 0
fi
moira_graph_update "{project_root}" && moira_graph_views_generate'
```

- If binary not found: skip silently (exit 0, no message).
- If no existing graph (`.ariadne/graph/graph.json` missing): skip silently.
- If update succeeds: store result for display in Step 4.
- If update fails: log warning but continue (graph is non-blocking).

After update, extract summary for display:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_summary'
```

## Step 3: Merge Registry

After scanner returns, merge new results with existing registry per D-084:

1. Read existing registry from `.claude/moira/config/mcp-registry.yaml` (if exists)
2. Read new scan results from `.claude/moira/state/init/mcp-scan.md`
3. Merge strategy:
   - **New servers** (in scan but not in registry): add them
   - **Existing servers** (in both): preserve user customizations to existing tool entries (when_to_use, when_NOT_to_use, token_estimate edits). Only update fields that were NOT user-edited.
   - **Removed servers** (in registry but not in scan): mark with `removed: true` — do NOT delete
4. Write merged registry back to `.claude/moira/config/mcp-registry.yaml`
5. If no MCP servers found at all: set `mcp.enabled: false` in config.yaml

## Step 4: Display Summary

```
═══════════════════════════════════════════
  MOIRA — Refresh Complete
═══════════════════════════════════════════
  MCP Registry: updated
  ├─ Servers: {N} ({+added}, {-removed})
  └─ Tools: {M} total

  {If graph update ran:}
  Project Graph: updated
  ├─ Files: {node_count} | Edges: {edge_count}
  └─ Clusters: {cluster_count}

  {If graph skipped (no binary or no existing graph):}
  {omit graph section entirely}
═══════════════════════════════════════════
```
