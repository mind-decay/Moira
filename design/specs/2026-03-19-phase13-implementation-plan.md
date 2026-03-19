# Phase 13 Implementation Plan: Ariadne Integration

**Date:** 2026-03-19
**Spec:** `design/specs/2026-03-19-phase13-ariadne-integration.md`
**Design source:** `design/subsystems/project-graph.md`

## Chunks Overview

| Chunk | Goal | Deliverables | Depends on |
|-------|------|-------------|------------|
| 1 | Foundation | D1, D2, D13, D14 | — |
| 2 | Agent definitions | D3, D4 | Chunk 1 |
| 3 | Commands | D5, D6, D7, D8, D9 | Chunk 1 |
| 4 | Pipeline integration | D10, D11 | Chunks 1, 2 |
| 5 | Installation & tests | D12, D15, D16 | All above |

---

## Chunk 1: Foundation

**Goal:** Shell library, access matrix, schemas, guard hook — all base infrastructure with no cross-dependencies.

### Task 1.1: Create `src/global/lib/graph.sh` (D1)

**Files:** CREATE `src/global/lib/graph.sh`
**Source:** Spec D1, `design/subsystems/project-graph.md` § CLI Interface
**Key points:**
- 12 functions, all prefixed `moira_graph_`
- Every function handles missing `ariadne` binary gracefully (return empty/error code, never crash)
- `moira_graph_check_binary` — run `ariadne info`, return version string or empty
- `moira_graph_build <project_root> [output_dir]` — run `ariadne build` with args, pass through exit code
- `moira_graph_update <project_root> [output_dir]` — run `ariadne update` with args, pass through exit code
- `moira_graph_query <subcommand> [args...]` — run `ariadne query` with all args, return stdout
- `moira_graph_views_generate [output_dir] [graph_dir]` — run `ariadne views generate` with optional output/graph-dir args
- `moira_graph_serve_start <project_root>` — start `ariadne serve` in background, persist PID for later stop
- `moira_graph_serve_stop` — stop MCP server process if running
- `moira_graph_is_fresh <graph_dir>` — return 0 if graph.json exists and is newer than project source files, 1 otherwise
- `moira_graph_summary <graph_dir>` — extract node_count, edge_count, cluster_count, cycle_count, smell_count, monolith_score from stats.json/clusters.json. Return key=value pairs for display
- `moira_graph_read_view <level> [cluster_name] [graph_dir]` — return contents of L0 index.md or L1 cluster view
- `moira_graph_output_dir` — return `.ariadne/graph/`
- `moira_graph_views_dir` — return `.ariadne/views/`
- Bash 3.2+ compatible, same style as other `src/global/lib/*.sh` files
- Header comment references D-105, D-102

**Commit:** `moira(pipeline): add graph.sh shell library for Ariadne CLI integration`

### Task 1.2: Update Knowledge Access Matrix (D2)

**Files:** MODIFY `src/global/core/knowledge-access-matrix.yaml`
**Source:** Spec D2, `design/subsystems/project-graph.md` § Agent Integration
**Key points:**
- Add `graph` column to each agent's `read_access` row (lines 12-21)
- Format: append `, graph: L0` / `L1` / `L2` to each agent line
- Exact values per spec D2: apollo=L0, hermes=L0, athena=L1, metis=L1, daedalus=L1, hephaestus=L2, themis=L1, aletheia=L1, mnemosyne=L2, argus=L2
- Add inline comments with `# graph extras: blast_radius, smells` etc. per agent
- Add `graph_extras` comment block after end of file (after line 32) — use YAML comments (`#`) to document query commands, not a data block, to avoid breaking knowledge.sh grep/sed parsing
- NO write_access entry for graph — all agents are read-only
- Update header comment (lines 8-9) to mention graph

**Commit:** `moira(pipeline): add graph column to knowledge access matrix`

### Task 1.3: Schema Updates (D13)

**Files:** MODIFY `src/schemas/current.schema.yaml`, MODIFY `src/schemas/config.schema.yaml`
**Source:** Spec D13
**Key points:**

`current.schema.yaml`:
- Add `graph_available` field after the existing fields (insert after line ~69, before bench_mode section)
- Type: boolean, optional, default: false
- Description: "Whether Ariadne graph data is available for this pipeline run"
- Comment: "Set by orchestrator during bootstrap checks"

`config.schema.yaml`:
- Add `graph` section after `bootstrap` section (after line 189)
- `graph.enabled` (boolean, optional, default: conditional — true if ariadne binary is found during init, per spec D13)
- `graph.timeout` (number, optional, default: 60, "ariadne build timeout in seconds")

**Commit:** `moira(pipeline): add graph fields to current and config schemas`

### Task 1.4: Guard Hook Update (D14)

**Files:** MODIFY `src/global/hooks/guard.sh`
**Source:** Spec D14
**Key points:**
- Current violation check (line 68): condition checks if file path is outside `.claude/moira`
- Add `.ariadne/` to allowed paths for Read operations only — Write/Edit to `.ariadne/` remains a violation
- Split the check by tool_name so Read of `.ariadne/` is allowed while Write/Edit is not
- Add comment: "# .ariadne/ is Ariadne graph output — orchestrator may check existence (D-105)"

**Commit:** `moira(pipeline): allow orchestrator Read access to .ariadne/ in guard hook`

---

## Chunk 2: Agent Definitions

**Goal:** Update Daedalus for graph instruction assembly, add graph guidance hints to all 9 other agents.

**Depends on:** Chunk 1 (access matrix must exist with graph column)

### Task 2.1: Update Daedalus Role (D3)

**Files:** MODIFY `src/global/core/rules/roles/daedalus.yaml`
**Source:** Spec D3, `design/subsystems/project-graph.md` § Planner Integration
**Key points:**
- Add capabilities (insert after line 41 in capabilities block):
  - "Load graph views from .ariadne/views/ and assemble Project Graph section in instruction files per graph access matrix levels"
  - "Query ariadne blast-radius and importance for affected files when graph is available"
  - "Include graph token estimates in context budget calculations"
- Add to `knowledge_access` block (after line 56): `graph: L1  # + extras: blast_radius, importance`
- Add to `output_structure` section (after line 67): instruction files include `## Project Graph` section when graph is available
- Add NEVER constraint (in `never` block, after line 47): "NEVER write to .ariadne/ — graph data is read-only, produced by ariadne CLI"
- Format follows existing daedalus.yaml style (multiline strings in identity, bullet lists in capabilities)

**Commit:** `moira(agents): add graph integration to Daedalus planner role`

### Task 2.2: Update 9 Agent Roles (D4)

**Files:** MODIFY 9 files in `src/global/core/rules/roles/`: `apollo.yaml`, `hermes.yaml`, `athena.yaml`, `metis.yaml`, `hephaestus.yaml`, `themis.yaml`, `aletheia.yaml`, `mnemosyne.yaml`, `argus.yaml`
**Source:** Spec D4, `design/subsystems/project-graph.md` § How Each Agent Benefits
**Key points:**
- For each agent: append graph guidance to existing `capabilities` block (not a new field — keep structure consistent with existing role files)
- Each hint starts with "If Project Graph / graph data / graph index / graph metrics / graph subgraph / structural diff / graph test mappings is available..."
- Exact wording per spec D4 for each agent
- Add `knowledge_access` entry: `graph: L0/L1/L2` matching access matrix
- All hints are conditional ("If ... is available") — agent must work without graph
- Changes are small per file — one bullet in capabilities + one line in knowledge_access

**Commit:** `moira(agents): add graph guidance hints to all agent roles`

---

## Chunk 3: Commands

**Goal:** Create `/moira:graph` command, update `init`, `refresh`, `status`, `health` with graph integration. Update help.

**Depends on:** Chunk 1 (graph.sh must exist)

### Task 3.1: Create `/moira:graph` Command (D9)

**Files:** CREATE `src/commands/moira/graph.md`
**Source:** Spec D9, `design/subsystems/project-graph.md` § `/moira:graph`
**Key points:**
- Frontmatter: `allowed-tools: [Read, Bash]`
- Parse first argument as subcommand (blast-radius, cluster, file, cycles, layers, metrics, smells, importance, spectral, diff, compressed)
- Default (no subcommand): `ariadne query stats --format md`
- Each subcommand maps to `ariadne query <subcommand> <args> --format md`
- Exception: `diff` maps to MCP tool `ariadne_diff` (requires serve mode)
- Error handling: 3 cases per spec D9 (binary missing, graph missing, server not running)
- Follow existing command file patterns (e.g., `src/commands/moira/status.md`)

**Commit:** `moira(pipeline): add /moira:graph command with 12 subcommands`

### Task 3.2: Update `/moira:init` (D5)

**Files:** MODIFY `src/commands/moira/init.md`
**Source:** Spec D5
**Key points:**
- Insert Step 4b between current Step 4 (scanner dispatch, lines 54-96) and Step 5 (config generation, lines 98-103)
- Step 4b runs in parallel with Step 4's scanner agents (same Agent tool dispatch block)
- Structure: check binary → if found, run build + views in Bash → report summary; if not, report degradation message
- Report format: "Project Graph: {N} files, {M} edges, {K} clusters"
- Install suggestion includes both cargo and curl options
- Update Step 11 (user review gate, lines 157-203): add graph summary line to the review output template (after knowledge freshness section)
- Note in Step 4b: source `graph.sh` via Bash (same pattern as bootstrap.sh sourcing)

**Commit:** `moira(pipeline): integrate Ariadne graph build into /moira:init`

### Task 3.3: Update `/moira:refresh` (D6)

**Files:** MODIFY `src/commands/moira/refresh.md`
**Source:** Spec D6
**Key points:**
- Insert new step between current Step 2 (MCP re-scan, lines 29-41) and Step 3 (merge registry, lines 43-54)
- New Step 2b: Graph Update
- Check binary, check graph exists, run `moira_graph_update`, run `moira_graph_views_generate`
- Report format: "Graph updated: {N} files changed, {M} added, {K} removed"
- If binary not found or no existing graph: skip silently (no error, no message)
- Update Step 4 (display summary, lines 56-66): add graph update result if it ran

**Commit:** `moira(pipeline): integrate Ariadne graph update into /moira:refresh`

### Task 3.4: Update `/moira:status` (D7)

**Files:** MODIFY `src/commands/moira/status.md`
**Source:** Spec D7
**Key points:**
- Add graph summary section to Step 5 display output (lines 59-110)
- Insert after Knowledge section (line ~99), before Locks section (line ~101)
- Use `moira_graph_summary` via Bash to get counts
- If summary returns empty: display "Project Graph: not available (ariadne not installed)"
- If summary returns data: display formatted section with Files, Edges, Clusters, Cycles, Bottlenecks, Smells, Monolith score, Freshness, Last updated, MCP server status
- Add `.ariadne/graph/graph.json` to Step 2 file reads (lines 31-38) for existence check

**Commit:** `moira(pipeline): add graph summary to /moira:status`

### Task 3.5: Update `/moira:health` (D8)

**Files:** MODIFY `src/commands/moira/health.md`
**Source:** Spec D8, D-106
**Key points:**
- Add Graph Health subsection to Structural Conformance section (lines 25-31)
- Run ariadne query commands (smells, cycles, stats, spectral) via Bash to collect data
- Parse results for: cycle count, bottleneck count (centrality > 0.9), god file smells, cluster sizes, unstable foundations, monolith score
- Each check outputs pass or warning with details
- If graph unavailable: skip subsection entirely (don't penalize score, per D-106)
- Add graph checks to structural pass/fail ratio calculation

**Commit:** `moira(pipeline): add graph health checks to /moira:health`

### Task 3.6: Update `/moira:help` Command

**Files:** MODIFY `src/commands/moira/help.md`
**Source:** Spec D9 (new command must be discoverable)
**Key points:**
- Add `/moira:graph` entry to the command table
- Description: "Query project structure graph (blast-radius, clusters, metrics, smells)"
- Insert in alphabetical order among existing commands

**Commit:** `moira(pipeline): add /moira:graph to help command table`

---

## Chunk 4: Pipeline Integration

**Goal:** Wire graph availability into orchestrator bootstrap and dispatch context.

**Depends on:** Chunks 1 (graph.sh, schemas) and 2 (agent roles with graph access)

### Task 4.1: Update Orchestrator Skill (D10)

**Files:** MODIFY `src/global/skills/orchestrator.md`
**Source:** Spec D10
**Key points:**

Section 1 (Bootstrap Deep Scan Check, lines 55-71):
- After deep-scan check, add graph availability check
- Use Read tool to check if `.ariadne/graph/graph.json` exists
- Set `graph_available = true/false` as pipeline context variable
- If exists but stale: note in telemetry log, don't block pipeline
- Check `config.yaml` `graph.enabled` — if explicitly false, set `graph_available = false`
- Write `graph_available` to `current.yaml` state (per D13 schema)

Section 2 (post-agent guard check, lines 111-122):
- Add `.ariadne/**` to the protected paths list in post-agent guard check
- Format: same as existing protected paths (absolute prohibition pattern)
- Comment: "# Graph data — only ariadne CLI writes here (Art 1.2)"

**Commit:** `moira(pipeline): add graph availability check to orchestrator bootstrap`

### Task 4.2: Update Dispatch Skill (D11)

**Files:** MODIFY `src/global/skills/dispatch.md`
**Source:** Spec D11, D-107
**Key points:**

Simplified Assembly Steps subsection (lines 47-59):
- After step 4 (knowledge loading), add step 4b: Graph context loading
- If `graph_available` is true:
  - For pre-planning agents (Apollo, Hermes, Athena, Metis): read L0 graph index via Bash `moira_graph_read_view L0`, append to prompt
  - For Daedalus: pass graph directory path (`.ariadne/graph/`, `.ariadne/views/`) in task context so Daedalus can query and assemble instruction files
- For post-planning agents: no change (graph data comes via instruction files)
- Budget adjustment: add ~200-500 tokens (L0 range from design doc) to context estimate when including L0 graph index

Pre-assembled Instructions section:
- Add note that instruction files may contain `## Project Graph` section (assembled by Daedalus)
- No code change — just documentation that dispatch reads and uses these files as-is

**Commit:** `moira(pipeline): add graph context injection to dispatch skill`

---

## Chunk 5: Installation & Tests

**Goal:** Update install script, write tests, update cross-reference manifest, update existing consistency test.

**Depends on:** All previous chunks (validates everything)

### Task 5.1: Update Install Script (D12)

**Files:** MODIFY `src/install.sh`
**Source:** Spec D12
**Key points:**
- Line 214: Add `graph.sh` to the lib file verification list (after `upgrade.sh`)
- Line 229: Add `graph` to the command array (after `upgrade`)
- No other changes needed — file copy uses glob (`*.sh`, `*.md`) so new files are copied automatically

**Commit:** `moira(pipeline): add graph.sh and graph command to install verification`

### Task 5.2: Update Existing Agent Definitions Test

**Files:** MODIFY `src/tests/tier1/test-agent-definitions.sh`
**Source:** Ripple effect — existing test must validate new `graph` dimension
**Key points:**
- Line 111: `KNOWLEDGE_DIMS` array currently lists 4 dimensions (project_model, conventions, decisions, patterns). Does NOT include quality_map, failures, libraries, or graph
- Add `graph` to `KNOWLEDGE_DIMS` so the existing consistency check between role files and matrix covers the graph column
- Note: the array may need other dimensions too (quality_map, failures, libraries) if they're missing — check and add all that are relevant

**Commit:** `moira(pipeline): add graph dimension to agent definitions test`

### Task 5.3: Create Tier 1 Tests (D15)

**Files:** CREATE `src/tests/tier1/test-graph-integration.sh`
**Source:** Spec D15
**Key points:**
- Follow existing test script pattern (e.g., `test-knowledge-system.sh`)
- Source test helpers, set up temp directories
- 13 test cases (11 from spec + 2 added for coverage):
  1. `moira_graph_check_binary` — source graph.sh, call function, verify no crash
  2. `moira_graph_summary` — create mock graph.json/stats.json, verify parsed counts
  3. `moira_graph_summary` — test with no graph.json, verify empty/defaults
  4. Access matrix graph column — grep `knowledge-access-matrix.yaml` for `graph:` in each agent row, verify L0/L1/L2
  5. No write access — grep `write_access` section, verify no `graph` entry
  6. `moira_graph_read_view L0` — create mock `views/index.md`, verify content returned
  7. `moira_graph_read_view L0` — no views dir, verify empty return
  8. Instruction file template — grep `daedalus.yaml` for "Project Graph" reference
  9. Graph command file — check `commands/moira/graph.md` exists, grep for `allowed-tools`
  10. Health command — grep `health.md` for graph health check items
  11. Install verify — grep `install.sh` for `graph.sh` in lib list and `graph` in command list
  12. **NEW:** Refresh command — grep `refresh.md` for `moira_graph_update` reference (covers SC6)
  13. **NEW:** Graph subcommands — grep `graph.md` for all 12 subcommand patterns (blast-radius, cluster, file, cycles, layers, metrics, smells, importance, spectral, diff, compressed, stats) (strengthens SC3)
- Script is executable, uses `set -euo pipefail`
- Auto-discovered by `run-all.sh` via `test-*.sh` glob

**Commit:** `moira(pipeline): add Tier 1 tests for graph integration`

### Task 5.4: Update Cross-Reference Manifest (D16)

**Files:** MODIFY `src/global/core/xref-manifest.yaml`
**Source:** Spec D16
**Key points:**
- Add new xref entries after existing xref-007 (after line 93)
- xref-008: graph access levels — canonical: `knowledge-access-matrix.yaml` (graph column), referenced by: `rules/roles/*.yaml` (knowledge_access.graph), `skills/dispatch.md` (graph context loading)
- xref-009: graph shell functions — canonical: `lib/graph.sh`, referenced by: `commands/moira/init.md`, `commands/moira/refresh.md`, `commands/moira/status.md`, `commands/moira/health.md`, `commands/moira/graph.md`, `skills/dispatch.md`
- xref-010: graph_available field — canonical: `schemas/current.schema.yaml`, referenced by: `skills/orchestrator.md` (bootstrap check), `skills/dispatch.md` (context loading)
- xref-011: graph config — canonical: `schemas/config.schema.yaml` (graph section), referenced by: `skills/orchestrator.md` (graph.enabled check)
- Follow existing entry format (id, description, canonical, referenced_by, validation)

**Commit:** `moira(pipeline): add graph cross-references to xref manifest`

---

## Dependency Graph

```
Chunk 1 (Foundation)
├── Task 1.1: graph.sh          ─┐
├── Task 1.2: access matrix     ─┤ no internal deps
├── Task 1.3: schemas           ─┤
└── Task 1.4: guard.sh          ─┘
         │
    ┌────┴────┐
    ▼         ▼
Chunk 2      Chunk 3
(Agents)     (Commands)
├─ 2.1 daedalus (needs 1.1, 1.2)
├─ 2.2 agents  (needs 1.2)
│    │         ├─ 3.1 graph.md  (needs 1.1)
│    │         ├─ 3.2 init.md   (needs 1.1)
│    │         ├─ 3.3 refresh   (needs 1.1)
│    │         ├─ 3.4 status    (needs 1.1)
│    │         ├─ 3.5 health    (needs 1.1)
│    │         └─ 3.6 help      (needs 3.1)
│    │
    ┌┴────────┐
    ▼         │
Chunk 4       │
(Pipeline)    │
├─ 4.1 orchestrator (needs 1.3, 1.4)
└─ 4.2 dispatch    (needs 1.1, 1.2, 2.1)
         │         │
         └────┬────┘
              ▼
         Chunk 5
         (Install & Tests)
         ├─ 5.1 install.sh       (needs 1.1, 3.1)
         ├─ 5.2 agent-def test   (needs 1.2, 2.2)
         ├─ 5.3 graph tests      (needs all)
         └─ 5.4 xref             (needs all)
```

**Parallelizable:**
- Chunk 1 tasks (1.1-1.4) are all independent
- Chunks 2 and 3 can run in parallel after Chunk 1
- Chunk 4 can start after Chunk 1 completes (tasks 4.1, 4.2 are sequential)
- Chunk 5 must be last

**Total:** 5 chunks, 16 tasks, 3 new files, 24 modified files
