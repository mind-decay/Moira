# Phase 13 Spec: Ariadne Integration — Project Graph in Moira Pipelines

**Date:** 2026-03-19
**Status:** Draft
**Risk classification:** ORANGE (new data flow into existing pipelines, Knowledge Access Matrix changes, command modifications). D10 (orchestrator modification) is individually RED — change is minimal (boolean flag only), no orchestrator restriction changes.

## Goal

Integrate Ariadne (external project graph engine, Phases 1-3 complete) into Moira pipelines so that agents receive structural topology data — file dependencies, architectural layers, blast radius, Martin metrics, architectural smells, spectral analysis — through the existing instruction file mechanism. Add graph-related commands (`/moira:graph`) and extend existing commands (`init`, `refresh`, `status`, `health`).

## Dependencies

- **Moira Phases 1-12:** Complete (core infrastructure)
- **Ariadne Phases 1-3:** Complete (CLI + algorithms + MCP server + architectural intelligence)
- **Design source:** `design/subsystems/project-graph.md` (updated 2026-03-19 with full Ariadne capabilities)

## Key Decisions Referenced

- **D-102:** Graceful degradation without binary
- **D-103:** Anamnesis integration boundary
- **D-104:** Ariadne as separate project
- **D-105:** Moira reads `.ariadne/` directly (no copy/symlink) — NEW, added with this spec
- **D-106:** Graph health as subsection of Structural score — NEW, added with this spec
- **D-107:** Pre-planning agents receive L0 graph via dispatch — NEW, added with this spec

## Deliverables

### D1: Shell Library — `src/global/lib/graph.sh`

**Source:** `design/subsystems/project-graph.md` § CLI Interface

Shell function wrappers for the `ariadne` CLI. All graph operations go through this library.

Functions:
- `moira_graph_check_binary` — check if `ariadne` is installed, return version or empty (uses `ariadne info`)
- `moira_graph_build <project_root> [output_dir]` — run `ariadne build`, return exit code
- `moira_graph_update <project_root> [output_dir]` — run `ariadne update` (delta), return exit code
- `moira_graph_query <subcommand> [args...]` — run `ariadne query <subcommand>`, return output
- `moira_graph_views_generate [output_dir] [graph_dir]` — run `ariadne views generate`
- `moira_graph_serve_start <project_root>` — start MCP server in background, write PID
- `moira_graph_serve_stop` — stop MCP server by PID
- `moira_graph_is_fresh <graph_dir>` — check if graph.json exists and is newer than most recent source file change
- `moira_graph_summary <graph_dir>` — extract node_count, edge_count, cluster_count, cycle_count, smell_count, monolith_score from stats.json for status display
- `moira_graph_read_view <level> [cluster_name] [graph_dir]` — read L0 index.md or L1 cluster view, return content
- `moira_graph_output_dir` — resolve output directory (default: `.ariadne/graph/`)
- `moira_graph_views_dir` — resolve views directory (default: `.ariadne/views/`)

All functions handle missing binary gracefully (return empty/error code, never crash).

**Graph directory convention:** Ariadne writes to `.ariadne/graph/` and `.ariadne/views/` by default. Moira reads from these locations directly — no copying or symlinking (D-105). The `.ariadne/` directory is committed to git (deterministic, reproducible output).

### D2: Knowledge Access Matrix Update — `src/global/core/knowledge-access-matrix.yaml`

**Source:** `design/subsystems/project-graph.md` § Agent Integration

Add `graph` as a new knowledge type column in the existing `read_access` structure. Graph is read-only — no `write_access` entry (no agent writes to the graph). An `extras` comment documents which on-demand graph queries Daedalus may include per agent.

```yaml
# In read_access block — add graph column to each agent:
read_access:
  apollo:      { ..., graph: L0 }
  hermes:      { ..., graph: L0 }
  athena:      { ..., graph: L1 }    # extras: blast_radius, smells
  metis:       { ..., graph: L1 }    # extras: metrics, spectral
  daedalus:    { ..., graph: L1 }    # extras: blast_radius, importance
  hephaestus:  { ..., graph: L2 }    # extras: subgraph, compressed
  themis:      { ..., graph: L1 }    # extras: diff, smells, cycles
  aletheia:    { ..., graph: L1 }    # extras: (test mappings via L1 views)
  mnemosyne:   { ..., graph: L2 }    # extras: metrics
  argus:       { ..., graph: L2 }    # extras: stats, smells, spectral

# Graph extras reference (for Daedalus instruction assembly):
# On-demand graph queries that may be included in instruction files
# based on task relevance. Not always loaded — Daedalus decides per step.
graph_extras:
  blast_radius: "ariadne query blast-radius <file> --format md"
  subgraph: "ariadne query subgraph <files> --format md"
  smells: "ariadne query smells --format md"
  metrics: "ariadne query metrics --format md"
  importance: "ariadne query importance --format md"
  spectral: "ariadne query spectral --format md"
  compressed: "ariadne query compressed --level <N> --format md"
  diff: "ariadne_diff MCP tool (requires serve mode)"
  stats: "ariadne query stats --format md"
  cycles: "ariadne query cycles --format md"
```

Level semantics for graph:
- **L0:** `views/index.md` (~200-500 tokens)
- **L1:** L0 + relevant `views/clusters/*.md` (~500-2000 tokens per cluster)
- **L2:** L1 + on-demand subgraph/blast-radius queries (~1000-5000 tokens)

### D3: Daedalus (Planner) Integration — `src/global/core/rules/roles/daedalus.yaml`

**Source:** `design/subsystems/project-graph.md` § Planner Integration

Update Daedalus role rules to include graph data loading in instruction file assembly:

1. **Read graph access matrix** — determine which graph level and extras each downstream agent receives
2. **Load graph views** — read L0 index, L1 cluster views for affected clusters
3. **Query blast radius** — for files being modified, run `ariadne query blast-radius` to find affected dependents
4. **Query importance** — check if any modified files have high importance scores
5. **Include graph section in instruction files** — add `## Project Graph` section with appropriate data per agent access level
6. **Budget estimation** — include graph view token estimates in context budget calculations

Instruction file graph section format:

```markdown
## Project Graph

### Graph Overview (L0)
[contents of views/index.md]

### Relevant Clusters (L1)
[contents of views/clusters/{name}.md for affected clusters]

### Subgraph
[output of ariadne query subgraph for working area — only if agent has subgraph extra]

### Blast Radius
[output of ariadne query blast-radius for modified files — only if agent has blast_radius extra]

### Architectural Smells
[output of ariadne query smells — only if agent has smells extra]

### Martin Metrics
[output of ariadne query metrics — only if agent has metrics extra]

### Importance Ranking
[output of ariadne query importance — only if agent has importance extra]

### Spectral Analysis
[output of ariadne query spectral — only if agent has spectral extra]

### Structural Diff
[output of ariadne query diff — only if agent has diff extra, requires MCP server mode]
```

**Graceful degradation:** If `ariadne` binary is not installed or graph data doesn't exist, Daedalus omits the `## Project Graph` section entirely. No errors, no warnings in instruction files.

### D4: Agent Role Updates — `src/global/core/rules/roles/*.yaml`

**Source:** `design/subsystems/project-graph.md` § How Each Agent Benefits

Minimal updates to agent role files to reference graph data when available:

- **Apollo (classifier):** Add guidance: "If Project Graph section is present in context, use centrality and dependent count to assess true complexity."
- **Hermes (explorer):** Add guidance: "If graph index is available, use cluster information to target search instead of broad grep."
- **Athena (analyst):** Add guidance: "If graph data is available, include blast radius and architectural smells in impact analysis."
- **Metis (architect):** Add guidance: "If graph metrics are available, use Martin metrics and spectral analysis to inform design decisions. Avoid increasing coupling of files in Zone of Pain."
- **Hephaestus (implementer):** Add guidance: "If graph subgraph is available, use it for exact import paths and available exports. Verify new imports against graph edges."
- **Themis (reviewer):** Add guidance: "If structural diff is available, check for new cycles, layer violations, and newly introduced architectural smells."
- **Aletheia (tester):** Add guidance: "If graph test mappings are available, use them to identify untested files and missing test coverage."
- **Mnemosyne (reflector):** Add guidance: "If graph metrics are available, include structural context in reflection: clusters touched, layers crossed, Martin metric changes."
- **Argus (auditor):** Add guidance: "If graph data is available, include architectural health in audit: cycle trends, smell count, monolith score, bottleneck evolution."

**Key constraint:** These are additive hints. All agents must function correctly without graph data (graph is an enhancement, not a dependency).

### D5: `/moira:init` Update — `src/commands/moira/init.md`

**Source:** `design/subsystems/project-graph.md` § Integration with Existing Commands

Add graph build step to initialization sequence. Insert between existing steps 4 (scanner dispatch) and 5 (config generation):

**Step 4b (NEW): Build Project Graph**
1. Check for `ariadne` binary via `moira_graph_check_binary`
2. If found:
   - Run `ariadne build <project_root>` in parallel with the 4 scanner agents (step 4)
   - Run `ariadne views generate` after build completes
   - Report: "Project Graph: {N} files, {M} edges, {K} clusters"
3. If not found:
   - Report: "ariadne not found — Project Graph features unavailable. Install: cargo install ariadne-graph or curl -sSL .../install.sh | bash"
   - Continue without graph (graceful degradation per D-102)

**Update step 11 (user review gate):** Include graph summary in the review output if graph was built.

**Note:** `init.md` uses Bash to call shell functions. `graph.sh` must be sourced in the init command's Bash calls (same pattern as other libs sourced via bootstrap.sh).

### D6: `/moira:refresh` Update — `src/commands/moira/refresh.md`

**Source:** `design/subsystems/project-graph.md` § Integration with Existing Commands

Add graph update step to refresh sequence:

1. Check for `ariadne` binary
2. If found and graph exists (`.ariadne/graph/graph.json`):
   - Run `ariadne update <project_root>` (incremental delta)
   - Run `ariadne views generate` (regenerate views)
   - Report structural changes: "Graph updated: {N} files changed, {M} added, {K} removed"
   - If MCP server running: report "MCP server auto-updated"
3. If binary not found or no existing graph: skip silently

### D7: `/moira:status` Update — `src/commands/moira/status.md`

**Source:** `design/subsystems/project-graph.md` § Integration with Existing Commands

Add graph summary section to status output:

```
Project Graph:
  Files: 847 | Edges: 2,341 | Clusters: 12
  Cycles: 2 | Bottlenecks: 3 | Smells: 4
  Monolith score: 0.23 | Freshness: current
  Last updated: 4 tasks ago | MCP server: running
```

Or if graph not available:

```
Project Graph: not available (ariadne not installed)
```

Uses `moira_graph_summary` from `graph.sh`.

### D8: `/moira:health` Update — `src/commands/moira/health.md`

**Source:** `design/subsystems/project-graph.md` § Integration with Existing Commands

Add graph health checks to health scoring:

```
Graph Health:
  ✓ Graph exists and is current
  ⚠ 2 circular dependencies (auth ↔ billing)
  ⚠ 3 files with centrality > 0.9 (bottlenecks)
  ⚠ 1 god file detected (src/utils/format.ts)
  ✓ All clusters < 50 files
  ✓ No unstable foundations
  ✓ Monolith score: 0.23 (healthy)
```

Health check items:
- Graph exists and freshness
- Cycle count (⚠ if > 0)
- Bottleneck count (centrality > 0.9, ⚠ if > 0)
- God files (⚠ if smells include god_file)
- Cluster sizes (⚠ if any cluster > 50 files)
- Unstable foundations (⚠ if smells include unstable_foundation)
- Monolith score (⚠ if > 0.5)

**Scoring contribution:** Graph health is a subsection of Structural health (part of the 30% structural weight, D-106). If graph is unavailable, this subsection is skipped (not penalized).

### D9: `/moira:graph` Skill — `src/commands/moira/graph.md`

**Source:** `design/subsystems/project-graph.md` § `/moira:graph` — Moira Skill

New command wrapping `ariadne` CLI for interactive use within Claude Code sessions.

**Subcommands:**

```
/moira:graph                     → ariadne query stats --format md
/moira:graph blast-radius <file> → ariadne query blast-radius <file> --format md
/moira:graph cluster <name>      → ariadne query cluster <name> --format md
/moira:graph file <path>         → ariadne query file <path> --format md
/moira:graph cycles              → ariadne query cycles --format md
/moira:graph layers              → ariadne query layers --format md
/moira:graph metrics             → ariadne query metrics --format md
/moira:graph smells              → ariadne query smells --format md
/moira:graph importance          → ariadne query importance --format md
/moira:graph spectral            → ariadne query spectral --format md
/moira:graph diff                → MCP tool ariadne_diff (requires serve mode)
/moira:graph compressed <level>  → ariadne query compressed --level <level> --format md
```

**Error handling:**
- If `ariadne` not installed: "ariadne binary not found. Install: cargo install ariadne-graph"
- If graph not built: "No graph found. Run /moira:init or ariadne build ."
- If subcommand requires MCP server and server not running: "This subcommand requires ariadne serve. Start with: ariadne serve --project ."

**Tool access:** Read, Bash (for running ariadne CLI)

### D10: Orchestrator Skill Update — `src/global/skills/orchestrator.md`

**Source:** `design/subsystems/project-graph.md` § Agent Integration
**Risk:** RED (orchestrator modification) — change is minimal: boolean flag only, no restriction changes.

Minimal update to the orchestrator:

1. In Section 1 (Bootstrap Checks), add after deep-scan check:
   - Check if `.ariadne/graph/graph.json` exists via Read tool (this is a Moira infrastructure file, not project source — same as checking `.moira/config.yaml`)
   - Set `graph_available` flag for use in dispatch context
   - If graph exists and is stale (source files newer than graph.json): note in telemetry, don't block

2. In Section 2 (Pipeline Execution), no changes — graph data flows through Daedalus instruction files, not through orchestrator context.

3. In Section 2, post-agent guard check protected paths: add `.ariadne/**` to the protected list. Only `ariadne` CLI should write to this directory — agents must not modify graph data.

**Key:** The orchestrator does NOT read graph data itself (Art 1.1). Checking file existence is the same pattern as checking `config.yaml` exists — metadata, not content.

### D11: Dispatch Skill Update — `src/global/skills/dispatch.md`

**Source:** `design/subsystems/project-graph.md` § Planner Integration

Update dispatch logic to pass `graph_available` flag to agents (D-107):

1. For pre-planning agents (Apollo, Hermes, Athena, Metis): if `graph_available`, include L0 graph index in dispatch context via `moira_graph_read_view L0`
2. For Daedalus: if `graph_available`, pass graph directory path so Daedalus can query and include graph data in instruction files
3. For post-planning agents (Hephaestus, Themis, Aletheia): graph data comes via instruction files (no dispatch change needed)

**Budget adjustment:** When including graph views, add estimated token count to context budget tracking (~200-500 tokens for L0).

### D12: Install Script Update — `src/install.sh`

Update the `verify()` function to include new files:

- Add `graph.sh` to the lib file verification list
- Add `graph` to the command file verification list

### D13: Schema Updates

**`src/schemas/current.schema.yaml`** — add `graph_available` boolean field (optional, default false) to pipeline state. Set by orchestrator at bootstrap.

**`src/schemas/config.schema.yaml`** — add optional `graph` section:
```yaml
graph:
  enabled: boolean  # whether graph integration is active (default: true if ariadne found)
  timeout: number   # ariadne build timeout in seconds (default: 60)
```

### D14: Guard Hook Update — `src/global/hooks/guard.sh`

Add `.ariadne/graph/graph.json` existence check to the allowed paths for the orchestrator (Read-only, existence check only). The orchestrator uses Read to check if graph.json exists — this must not trigger a violation.

### D15: Tier 1 Tests — `src/tests/tier1/test-graph-integration.sh`

**Source:** Testing requirements from roadmap

New test script validating graph integration:

1. `moira_graph_check_binary` returns version string or empty (not crash)
2. `moira_graph_summary` returns valid counts when graph.json exists
3. `moira_graph_summary` returns empty/defaults when graph.json doesn't exist
4. Knowledge access matrix has `graph` column with valid levels for all 10 agents
5. No agent has write access to graph (all read-only)
6. `moira_graph_read_view L0` returns non-empty when views exist
7. `moira_graph_read_view L0` returns empty when views don't exist
8. Graph section format in instruction file template matches expected structure
9. `/moira:graph` command file exists and has correct tool access (Read, Bash)
10. Graph health check items are present in health command
11. `install.sh` verify list includes `graph.sh` and `graph` command

### D16: Cross-Reference Manifest Update — `src/global/core/xref-manifest.yaml`

Update the cross-reference manifest to include graph-related files and their dependencies:

- `lib/graph.sh` ← `knowledge-access-matrix.yaml`, `design/subsystems/project-graph.md`
- `commands/moira/graph.md` ← `lib/graph.sh`
- `commands/moira/init.md` ← `lib/graph.sh`
- `commands/moira/refresh.md` ← `lib/graph.sh`
- `commands/moira/status.md` ← `lib/graph.sh`
- `commands/moira/health.md` ← `lib/graph.sh`
- `rules/roles/daedalus.yaml` ← `knowledge-access-matrix.yaml` (graph column)
- `skills/dispatch.md` ← `lib/graph.sh`, `knowledge-access-matrix.yaml`
- `install.sh` ← `lib/graph.sh`, `commands/moira/graph.md`
- `schemas/current.schema.yaml` ← `skills/orchestrator.md` (graph_available field)

## File List

| File | Action | Deliverable |
|------|--------|-------------|
| `src/global/lib/graph.sh` | CREATE | D1 |
| `src/global/core/knowledge-access-matrix.yaml` | MODIFY | D2 |
| `src/global/core/rules/roles/daedalus.yaml` | MODIFY | D3 |
| `src/global/core/rules/roles/apollo.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/hermes.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/athena.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/metis.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/hephaestus.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/themis.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/aletheia.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/mnemosyne.yaml` | MODIFY | D4 |
| `src/global/core/rules/roles/argus.yaml` | MODIFY | D4 |
| `src/commands/moira/init.md` | MODIFY | D5 |
| `src/commands/moira/refresh.md` | MODIFY | D6 |
| `src/commands/moira/status.md` | MODIFY | D7 |
| `src/commands/moira/health.md` | MODIFY | D8 |
| `src/commands/moira/graph.md` | CREATE | D9 |
| `src/commands/moira/help.md` | MODIFY | D9 |
| `src/global/skills/orchestrator.md` | MODIFY | D10 |
| `src/global/skills/dispatch.md` | MODIFY | D11 |
| `src/install.sh` | MODIFY | D12 |
| `src/schemas/current.schema.yaml` | MODIFY | D13 |
| `src/schemas/config.schema.yaml` | MODIFY | D13 |
| `src/global/hooks/guard.sh` | MODIFY | D14 |
| `src/tests/tier1/test-graph-integration.sh` | CREATE | D15 |
| `src/tests/tier1/test-agent-definitions.sh` | MODIFY | D15 |
| `src/global/core/xref-manifest.yaml` | MODIFY | D16 |

**Total:** 3 new files, 24 modified files

## What Is NOT In Scope

- **Ariadne development** — Ariadne is a separate project, already complete (Phases 1-3)
- **MCP server auto-start** — `ariadne serve` integration is documented as optional capability; full MCP server configuration (settings.json, mcp-registry.yaml) is deferred to post-Phase 13
- **Graph-aware classification logic** — Apollo receives graph data but classification algorithm changes are not in this phase (Apollo uses graph as additional context, not as a decision rule change)
- **Structural diff in review** — Themis receives diff data in instruction files, but the review checklist (Q4) is not modified in this phase
- **Benchmarks** — Tier 2-3 tests for graph-enhanced agent quality are future work
- **Anamnesis cross-referencing** — D-103 defines the boundary; actual integration is post-Anamnesis
- **Error codes for Ariadne failures** — graph failures are non-blocking (log and continue per D-102); no new error type needed

## Success Criteria

1. `/moira:init` with `ariadne` installed builds the graph in parallel with scanners
2. `/moira:init` without `ariadne` completes normally with degradation message
3. `/moira:graph` (all 12 subcommands) produces correct output
4. `/moira:status` shows graph summary section (including monolith score and freshness)
5. `/moira:health` shows graph health checks
6. `/moira:refresh` runs `ariadne update` and reports changes
7. Daedalus instruction files include `## Project Graph` section with correct access levels per agent
8. Instruction files omit graph section when graph is unavailable (no errors)
9. All 11 Tier 1 graph tests pass
10. Cross-reference manifest is valid (xref test passes)
11. No constitutional violations (Art 1.1: orchestrator doesn't read graph data; Art 1.2: no agent writes to graph)
12. `install.sh verify` validates `graph.sh` and `graph.md` presence

## Constitutional Compliance

- **Art 1.1:** Orchestrator checks graph existence only (boolean flag via Read on `.ariadne/graph/graph.json`). This is metadata, not project source — same pattern as checking `.moira/config.yaml`. Graph content is read by Daedalus (an agent) and passed to downstream agents via instruction files. Orchestrator never reads graph.json content, clusters.json, or stats.json.
- **Art 1.2:** Graph column in access matrix is read-only for all agents. No agent has write access. Graph is updated only by `ariadne` CLI (external tool). `.ariadne/**` added to protected paths to prevent agent writes.
- **Art 2.1:** Graph data does not change pipeline selection logic. Classification remains a pure function of Apollo's output. Graph enriches Apollo's context but doesn't add conditional branches.
- **Art 3.1:** Graph build/update are logged in telemetry. Graph availability is recorded in pipeline state (`current.yaml` `graph_available` field).
- **Art 4.2:** No graph operation bypasses user gates. Graph is passive data.
- **Art 5.1:** Graph is NOT knowledge (per `project-graph.md`). Knowledge integrity rules don't apply.
- **Art 6.2:** Implementation conforms to `design/subsystems/project-graph.md` (updated 2026-03-19).

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| `ariadne build` slow on large projects | Init takes longer | Parallel with scanners; timeout configurable (default 60s, in config.yaml) |
| Graph data too large for instruction files | Agent context overflow | L0/L1/L2 tiering + token estimates; Daedalus budget-checks graph sections |
| Ariadne CLI output format changes | Integration breaks | Pin to Ariadne version; `graph.sh` wraps all calls |
| MCP server lock conflicts | CLI can't update | `graph.sh` checks lock; graceful skip with warning |
| Agent confusion from graph data | Lower quality output | Graph data is additive hints; agents must work without it |
| Guard.sh false positive on graph read | Orchestrator blocked | `.ariadne/graph/graph.json` added to guard.sh allowed paths |
