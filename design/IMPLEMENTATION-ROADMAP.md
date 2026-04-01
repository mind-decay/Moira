# Implementation Roadmap

## Phase Order

Based on dependency analysis. Each phase builds on previous.

---

## Phase 1: Foundation — File Structure & State Management — COMPLETED

**Goal:** Moira directory structure exists, state can be read/written/resumed.

**Deliverables:**
- Directory scaffold generator (creates `~/.claude/moira/` global tree + `.claude/moira/` project tree)
- Command files in `~/.claude/commands/moira/` (native custom commands, D-030)
- YAML state schemas — full schemas per D-029:
  - `budgets.schema.yaml` — context budget allocations (committed)
  - `config.yaml` — project configuration (committed)
  - `current.yaml` — active pipeline state (gitignored)
  - `status.yaml` — per-task status (gitignored)
  - `manifest.yaml` — checkpoint for resume (gitignored)
  - `queue.yaml` — epic task queue (gitignored)
  - `locks.yaml` — multi-developer locks (committed, in config/, D-033)
- State management (read/write/validate for all schemas above)
- Task ID generation
- `install.sh` — copies files to `~/.claude/moira/` + `~/.claude/commands/moira/`

**Testing (Tier 1 — Structural Verifier):**
- Directory structure validation scripts (bash + grep, 0 tokens)
- YAML schema validation checks

**Why first:** Everything depends on file structure. Without it, nothing else can store or read data.

---

## Phase 2: Core Agent Definitions — COMPLETED

**Goal:** All 10 agents have working prompt definitions.

**Agents (D-028):** Classifier, Explorer, Analyst, Architect, Planner, Implementer, Reviewer, Tester, Reflector, Auditor.

**Deliverables:**
- Base rules (`core/rules/base.yaml`)
- Role rules for each agent (`core/rules/roles/*.yaml`) — including Classifier (D-028)
- Quality criteria files (`core/rules/quality/*.yaml`)
- Agent response contract enforcement
- Knowledge access matrix implementation
- NEVER constraints per agent (Art 1.2)

**Testing (Tier 1 — Structural Verifier):**
- Each role file has explicit NEVER constraints (Art 1.2 check)
- Response contract format validation
- Knowledge access matrix consistency check

**Why second:** Agents are the execution units. Pipelines are just sequences of agent calls.

---

## Phase 3: Pipeline Engine (Orchestrator Skill) — COMPLETED

**Goal:** Orchestrator can execute all 4 pipeline types (Quick/Standard/Full/Decomposition).

**Deliverables:**
- Orchestrator command file (`commands/moira/task.md`) with `allowed-tools` restriction (D-031)
- Pipeline state machine (classify → analyze → plan → implement → review → test)
- Gate presentation system
- Agent dispatch via native Agent tool (foreground/background, parallel)
- Pipeline selection based on Classifier output (Art 2.1)
- Error handling (retry, escalate, abort) per fault-tolerance.md
- State file writes (`current.yaml`, `status.yaml`) at each pipeline step (Art 3.1)

**Testing (Tier 1 + Live Telemetry bootstrap):**
- Pipeline selection is pure function of classification (Art 2.1 check)
- All required gates present per pipeline (Art 2.2 check)
- No auto-proceed logic in gates (Art 4.2 check)
- Live telemetry collection begins (passive, per-task metrics)

**Why third:** With file structure + agents defined, we can wire them into pipelines.

---

## Phase 4: Rules Assembly & Knowledge System — COMPLETED

**Goal:** Planner can assemble multi-layer rules. Knowledge base can be read/written at correct levels.

**Deliverables:**
- Rule layer assembly (L1-L4 merge logic)
- Conflict detection between layers
- Knowledge level system (L0/L1/L2 for each knowledge type)
- Knowledge read/write utilities
- Freshness markers
- Archival rotation

**Why fourth:** Agents need assembled rules to work correctly. Knowledge feeds into agent decisions.

---

## Phase 5: Bootstrap Engine (/moira init) — COMPLETED

**Goal:** `/moira init` fully works — scans project, generates config, creates knowledge base.

**Deliverables:**
- 4x Explorer invocations with Layer 4 instructions (D-032):
  - Tech scan (languages, frameworks, tools)
  - Structure scan (directory layout, entry points)
  - Convention scan (naming, imports, patterns)
  - Pattern scan (component structure, API patterns)
- All 4 scanners dispatched in parallel via Agent tool
- Config generator (`config.yaml` from scan frontmatter)
- `.claude/CLAUDE.md` integration (moira:start/moira:end markers, idempotent)
- Existing `.claude/` compatibility (no conflicts with GSD/other tools)
- Deep scan (background) trigger on first task
- Onboarding flow
- `/moira:init --force` (full reinit, preserves knowledge)

**Why fifth:** Bootstrap uses agents + rules + knowledge system. Needs all of them working.

---

## Phase 6: Quality Gates & Review System — COMPLETED

**Goal:** Full quality gate system with checklists, severity classification, retry logic.

**Deliverables:**
- Requirements completeness checklist (Q1)
- Architecture soundness checklist (Q2)
- Plan feasibility checklist (Q3)
- Code review checklist (Q4)
- Test coverage checklist (Q5)
- Quality map generation (resolve knowledge.md ↔ quality.md schema)
- CONFORM/EVOLVE mode switching
- Code quality criteria enforcement

**Testing (Tier 2 — Behavioral Bench bootstrap):**
- Bench fixture projects created (greenfield-webapp, mature-webapp, legacy-webapp)
- First behavioral test cases for agent output quality
- Rubric definitions for behavioral tests (D-024; LLM-judge invocation deferred to Phase 10 per D-046)

**Why sixth:** Quality gates refine what agents already produce. Agents must work first.

---

## Phase 7: Context Budget Tracking — COMPLETED

**Goal:** Budget estimation, tracking, reporting, and overflow handling.

**Deliverables:**
- Budget configuration (budgets.yaml)
- Pre-execution estimation (Planner integration)
- Post-execution tracking
- Budget report generation
- Overflow detection and handling
- MCP budget integration

**Why seventh:** Budget system enhances existing pipeline. Not blocking for basic operation.

---

## Phase 8: Hooks & Self-Monitoring — COMPLETED

**Goal:** PostToolUse hooks detect violations and track budget. `allowed-tools` provides primary prevention (D-031).

**Deliverables:**
- `guard.sh` — PostToolUse hook for violation detection and audit logging (NOT prevention — `allowed-tools` handles that)
- `budget-track.sh` — PostToolUse hook for token usage logging
- Hook configuration merge into `settings.json`
- Violation logging (`violations.log`, `tool-usage.log`)
- Health report in gates (context usage, violation count)
- CLAUDE.md prompt enforcement rules (third layer of D-031)

**Why eighth:** Monitoring layer on top of working system. Note: primary enforcement (`allowed-tools`) is already in place from Phase 3.

---

## Phase 9: MCP Integration — COMPLETED

**Goal:** MCP tools are registered, allocated per step, tracked, and cached.

**Deliverables:**
- MCP registry generator
- MCP allocation in plans
- MCP usage instructions in agent prompts
- MCP usage review checklist
- MCP knowledge caching

**Why ninth:** MCP adds capability to existing agents. System works without it.

---

## Phase 10: Reflection Engine — COMPLETED

**Goal:** Post-task reflection, pattern detection, rule change proposals.

**Deliverables:**
- Lightweight reflection (per task)
- Pattern analysis (per 5 tasks)
- Deep reflection (per epic)
- Evidence tracking (3-confirmation rule, Art 5.2)
- Rule change proposal system
- Knowledge updates from reflection

**Testing (Tier 2 — Behavioral Bench + LLM-Judge):**
- LLM-judge fully operational (D-024)
- Calibration set for judge stability validation
- Statistical confidence bands for metrics (D-025)

**Why tenth:** Reflection improves the system. System must exist first.

---

## Phase 11: Metrics & Audit — COMPLETED

**Goal:** Full metrics dashboard, audit system, trend analysis.

**Deliverables:**
- Metrics collection per task
- Monthly aggregation
- Dashboard display (/moira metrics)
- Drill-down views
- 5-domain audit system
- Batch recommendation approval
- Tiered audit depth (light/standard/deep)
- Cross-reference manifest (`src/global/core/xref-manifest.yaml`) — dependency map between files for consistency enforcement (D-077)
- Tier 1 xref validation tests — verify manifest entries match actual file content
- Agent pre-commit xref check — agents consult manifest before committing to find affected files

**Why eleventh:** Metrics and audit analyze system performance. Needs history of tasks.

---

## Phase 12: Advanced Features — COMPLETED

**Goal:** Checkpoint/resume, multi-developer, epic decomposition, tweak/redo.

**Deliverables:**
- Checkpoint system (`manifest.yaml`, `resume_context`)
- Resume validation (Explorer check on changed files)
- Lock system for multi-developer (`config/locks.yaml` — committed, with TTL, D-033) (deferred to post-v1, branch isolation is interim — D-068)
- Epic decomposition pipeline (`queue.yaml`)
- Tweak flow
- Redo flow with re-entry points (git revert delegated to Implementer agent, not orchestrator)
- Version migration (`/moira:upgrade`)

**Testing (Tier 3 — Full Bench):**
- Full behavioral bench across all fixture projects
- Tiered test execution by change risk (D-026)
- Live telemetry privacy validation (D-027)

**Key decisions:** D-095 (max_attempts semantics clarification), D-096 (orchestrator state management via YAML writes).

**Why last:** Advanced workflows. Core system must be solid first.

---

## Phase 13: Ariadne Integration — Project Graph in Moira Pipelines — COMPLETED

**Goal:** Ariadne (external project graph engine) fully integrated into Moira pipelines — agents use graph data (including architectural intelligence), commands available, MCP server optionally configured.

**Depends on:** Core Moira (Phases 1-12), Ariadne Phases 1-3 (external project, developed independently).

**Note:** The project graph engine is a separate project called **Ariadne** (D-104). Ariadne is a standalone Rust CLI + MCP server with its own repository and release cycle. Ariadne Phases 1-3 are complete, providing: core graph engine (build/update/query), algorithms (blast radius, centrality, PageRank, clustering, layers, cycles), view generation, MCP server (17 tools, file watcher, freshness tracking), and architectural intelligence (Martin metrics, 7 smell detectors, spectral analysis, hierarchical compression, structural diff).

**Deliverables:**
- `/moira:init` integration:
  - Step 4b: `ariadne build` runs in parallel with scanner agents
  - Step 7: views generated alongside knowledge base
  - Binary check with graceful degradation message (D-102)
  - Optional: start `ariadne serve` as background MCP server
- `/moira:refresh` integration: `ariadne update` (delta) with structural diff report
- `/moira:graph` skill: 12 subcommands — overview, blast-radius, cluster, file, cycles, layers, metrics, smells, importance, spectral, diff, compressed
- `/moira:status` extension: graph summary section (files, edges, clusters, cycles, smells, monolith score, freshness)
- `/moira:health` extension: graph health checks (cycles, bottlenecks, smells, cluster sizes, monolith score)
- Knowledge Access Matrix extension: `graph` column (L0/L1/L2 per agent, read-only) with architectural intelligence data per agent role
- Planner integration: load graph views + smells + metrics into agent instruction files per access matrix
- Shell function wrappers for `ariadne` CLI calls
- MCP server configuration: optional `ariadne serve` integration for real-time queries
- Agent instruction templates: graph context injection points (including architectural intelligence)
- Installation documentation: what Ariadne is, why it's needed, how to install

**Testing:**
- Init with/without `ariadne` binary → verify graceful degradation
- Full pipeline run with graph → verify agents receive correct graph views
- `/moira:graph` subcommands (all 12) → verify output format and accuracy
- Status/health commands → verify graph + architectural intelligence sections appear
- MCP server integration → verify tool responses match CLI output
- Architectural intelligence → verify smells, metrics, spectral data flows to correct agents

**Key decisions:** D-102 (graceful degradation), D-103 (Anamnesis integration boundary), D-104 (Ariadne as separate project).

**Why Phase 13:** Integration requires both the graph engine (Ariadne) and core Moira infrastructure (Phases 1-12). This connects them. Ariadne is developed independently — this phase can begin once both Ariadne and core Moira are ready.

---

## Phase 14: Analytical Pipeline — COMPLETED

**Goal:** Analytical tasks (architecture review, audits, weakness analysis, documentation, research, decision analysis) execute through a dedicated pipeline with progressive depth, CS-based rigor methods, and Ariadne as primary analytical tool.

**Depends on:** Phase 3 (pipeline engine), Phase 13 (Ariadne integration), Phase 2 (agent definitions — Calliope extends agent set).

**Deliverables:**
- Apollo classification extension: two-dimensional (mode + size/subtype) (D-117)
- Calliope (scribe) agent definition: role rules, NEVER constraints, response contract (D-118)
- Analytical Pipeline YAML definition (`core/pipelines/analytical.yaml`) (D-119)
- Progressive depth mechanism: depth checkpoint gates, convergence tracking
- Ariadne Level C integration: baseline queries (Tier 1) + agent MCP access (Tier 2) (D-120)
- CS methods implementation in agent instructions (D-121):
  - CS-1: Fixpoint convergence (delta tracking between passes)
  - CS-2: Graph-based coverage (Ariadne as coverage space)
  - CS-3: Hypothesis-driven analysis (finding format enforcement)
  - CS-4: Abductive reasoning (competing explanations template)
  - CS-5: Information gain (Ariadne-based prioritization)
  - CS-6: Lattice-based finding organization (hierarchical structure)
- Analytical quality gates QA1-QA4 in Themis instructions (D-122)
- Depth checkpoint gate UX template
- Analytical-specific state files (analysis-pass-N.md, finding-lattice.md, etc.)
- Knowledge access matrix update for Calliope
- Calliope role rules (`calliope.yaml`)

**Testing:**
- Classification correctly identifies analytical vs implementation tasks
- Pipeline executes all subtypes (research, design, audit, weakness, decision, documentation)
- Progressive depth: single-pass and multi-pass scenarios
- Convergence metrics computed correctly
- Coverage metrics use Ariadne data
- QA1-QA4 gates catch real analytical weaknesses
- Calliope writes/updates documents without modifying code
- Graceful degradation without Ariadne (reduced coverage metrics, no structural queries)

**Key decisions:** D-117 (two-dimensional classification), D-118 (Calliope agent), D-119 (progressive depth), D-120 (Ariadne Level C), D-121 (CS methods), D-122 (analytical quality gates).

**Why Phase 14:** Requires working pipeline engine (Phase 3) and Ariadne integration (Phase 13). Analytical pipeline is an extension of core Moira, not a prerequisite for code-producing workflows.

---

## Phase 15: Ariadne-Driven Bootstrap & Quality-Map Fix

**Goal:** Ariadne structural data flows mechanically into knowledge base at init/refresh. Quality-map populated with real evidence instead of keyword heuristics. Scanner budgets cut ~46% via hybrid bash pre-collect + lighter agents.

**Depends on:** Phase 5 (bootstrap engine), Phase 13 (Ariadne integration), Phase 6 (quality gates — quality-map schema).

**Context (D-188):** Three bugs discovered in init/refresh → quality-map connectivity: (1) keyword matching trap — scanner prohibited from subjective words that quality-map classifier expects, (2) append-only quality-map — existing entries never updated, (3) no category migration — patterns stuck in initial classification forever. Additionally, Ariadne graph built during init but data never flows into knowledge base.

### Chunk 1: Ariadne → Knowledge Pipeline (bash/jq)

New function `moira_graph_populate_knowledge()` in `graph.sh`. Runs after `moira_graph_build()` during init. All queries use `ariadne query <cmd> --json | jq` — zero LLM tokens.

**Tasks:**
- [ ] 1.1: `ariadne query smells --json` → parse smell array → write each as `### {smell_type}: {file}` entry in `quality-map/full.md` under `## 🔴 Problematic Patterns`, with fields: Category (smell type), Evidence (ariadne structural analysis), File(s), Confidence (high — structural), Observation count (1), Lifecycle (🆕 NEW)
- [ ] 1.2: `ariadne query cycles --json` → parse cycle array → write each as `### Circular dependency: {members}` in quality-map Problematic, with cycle member files as evidence
- [ ] 1.3: `ariadne query refactor-opportunities --json` → parse Pareto-ranked list → write top N as quality-map Problematic entries with effort/impact/rank metadata
- [ ] 1.4: `ariadne query hotspots --json` → if temporal available, parse hotspot array → write as quality-map Problematic entries (files with high churn × complexity × blast_radius)
- [ ] 1.5: `ariadne query coupling --json` → if temporal available, parse coupling pairs above threshold → write as quality-map Adequate entries (structural coupling with co-change evidence)
- [ ] 1.6: `ariadne query centrality --json` → parse top-N bottleneck files → append `## Structural Bottlenecks` section to `project-model/full.md` with file paths, betweenness centrality scores
- [ ] 1.7: `ariadne query layers --json` → parse layer assignments → append `## Architectural Layers` section to `project-model/full.md` with layer name → file list mapping
- [ ] 1.8: `ariadne query metrics --json` → parse Martin metrics per cluster → append `## Cluster Metrics` section to `project-model/full.md` with instability, abstractness, distance-from-main-sequence per cluster
- [ ] 1.9: `ariadne query boundaries --json` → parse boundary list → merge with `boundaries.yaml` (ariadne-detected boundaries supplement scanner-detected, don't overwrite)
- [ ] 1.10: `ariadne query overview --json` → parse summary → append `## Graph Summary` section to `project-model/full.md` (node/edge/cluster/cycle/smell counts, monolith score, temporal availability)
- [ ] 1.11: Regenerate L0/L1 condensed files for project-model and quality-map after all writes
- [ ] 1.12: Graceful degradation — if ariadne binary absent or any query fails, skip silently (quality-map stays empty, project-model gets scanner data only)
- [ ] 1.13: Remove `_moira_bootstrap_gen_quality_map()` keyword matching function from `bootstrap.sh` — replaced by this pipeline

**Files:** `src/global/lib/graph.sh` (new function), `src/global/lib/bootstrap.sh` (remove keyword function), `src/global/lib/knowledge.sh` (L0/L1 regeneration)

### Chunk 2: Quality-Map Observation Count & Category Migration

Fix `moira_knowledge_update_quality_map()` in `knowledge.sh` to properly accumulate evidence and migrate categories.

**Tasks:**
- [ ] 2.1: On IF FOUND (existing entry matches): increment `Observation count` field, append new evidence line (`task-{id} {date}` or `refresh {date}` or `ariadne-init {date}`), update freshness marker
- [ ] 2.2: Category migration logic — after updating observation count, check:
  - Strong pattern with 3+ failed findings → move to `## ⚠️ Adequate Patterns` section, update Lifecycle to `⬇️ DEMOTED`
  - Adequate pattern with 3+ failed findings → move to `## 🔴 Problematic Patterns`, Lifecycle `⬇️ DEMOTED`
  - Problematic pattern resolved in ariadne diff (smell gone) → move to `## ✅ Strong Patterns`, Lifecycle `⬆️ PROMOTED`
  - Adequate pattern with 3+ consecutive passes (no failures) → move to `## ✅ Strong Patterns`, Lifecycle `⬆️ PROMOTED`
- [ ] 2.3: Migration mechanics — parse full.md, find entry by `### {name}` header, remove from old section, insert into new section with updated metadata
- [ ] 2.4: After migration, regenerate `summary.md` via `_moira_knowledge_regen_quality_summary()`
- [ ] 2.5: Unit tests in `src/tests/tier1/` — test observation increment, test demotion at 3 observations, test promotion on resolution, test migration preserves evidence history

**Files:** `src/global/lib/knowledge.sh` (fix existing function), `src/tests/tier1/test-quality-map-lifecycle.sh` (new)

### Chunk 3: Ariadne Diff at Refresh

New function `moira_graph_diff_to_knowledge()` in `graph.sh`. Runs after `moira_graph_update()` during refresh.

**Tasks:**
- [ ] 3.1: `ariadne query diff --json` → parse new/removed/changed smells, new/broken cycles
- [ ] 3.2: New smells → append to quality-map as Problematic (same format as Chunk 1.1)
- [ ] 3.3: Resolved smells → find matching entry in quality-map, trigger promotion via Chunk 2 migration logic
- [ ] 3.4: New cycles → append to quality-map as Problematic (same format as Chunk 1.2)
- [ ] 3.5: Broken cycles → find matching entry, trigger promotion
- [ ] 3.6: Re-query changed metrics (centrality, hotspots) → update project-model sections (overwrite, not append)
- [ ] 3.7: Update refresh.md Step 2b to call `moira_graph_diff_to_knowledge()` after graph update
- [ ] 3.8: Graceful degradation — if no prior graph exists (first refresh without init graph), skip diff, run full populate instead

**Files:** `src/global/lib/graph.sh` (new function), `src/commands/moira/refresh.md` (update Step 2b)

### Chunk 4: Hybrid Scanner Pre-Collection

Bash pre-collects raw data into files, agents receive pre-collected data instead of scanning from scratch.

**Tasks:**
- [ ] 4.1: New bash function `moira_scan_precollect_tech()` in `bootstrap.sh` — reads package.json, tsconfig.json, .eslintrc*, .prettierrc*, Dockerfile, docker-compose*, .github/workflows/*.yml, .env.example, go.mod, pyproject.toml, Cargo.toml, Gemfile (whichever exist). Writes concatenated contents with file headers to `.claude/moira/state/init/raw-configs.md`. Checks lock file existence (package-lock.json, yarn.lock, pnpm-lock.yaml, etc.) and appends existence flags
- [ ] 4.2: New bash function `moira_scan_precollect_structure()` in `bootstrap.sh` — runs `ls` depth 1-2 for top-level + source dirs, runs `ariadne query overview --json`, `ariadne query clusters --json`, `ariadne query layers --json` (if available). Writes combined output to `.claude/moira/state/init/raw-structure.md`
- [ ] 4.3: Update tech-scan.md template — add `## Pre-Collected Data` section at top: "Raw config files have been pre-collected at `.claude/moira/state/init/raw-configs.md`. Read that file FIRST. Only use Read/Glob for files NOT included in pre-collection." Reduce budget from 140k to 50k
- [ ] 4.4: Update structure-scan.md template — add `## Pre-Collected Data` section: "Project structure and Ariadne graph data pre-collected at `.claude/moira/state/init/raw-structure.md`. Read that file FIRST. Focus on interpreting the structure — directory roles, entry points, test organization — not on discovery." Reduce budget from 140k to 50k
- [ ] 4.5: Update init.md Step 4 — before dispatching scanner agents, run `moira_scan_precollect_tech` and `moira_scan_precollect_structure` via Bash. Then dispatch 4 agents (2 lightweight + 2 full)
- [ ] 4.6: Convention-scan.md and pattern-scan.md — reduce budget from 140k to 100k (no pre-collection, but tighter limit)
- [ ] 4.7: Update refresh.md Step 2 — same pre-collection before re-scan agents

**Files:** `src/global/lib/bootstrap.sh` (new functions), `src/global/templates/scanners/tech-scan.md`, `src/global/templates/scanners/structure-scan.md`, `src/commands/moira/init.md`, `src/commands/moira/refresh.md`

### Chunk 5: Deep Scanner Ariadne Pre-Context

Deep scanners receive Ariadne structural data as pre-context file, freeing budget for semantic analysis.

**Tasks:**
- [ ] 5.1: New bash function `moira_deepscan_prepare_context()` in `graph.sh` — queries `ariadne query overview`, `clusters`, `cycles`, `boundaries`, `layers`, `centrality` (top 20), writes combined markdown to `.claude/moira/state/init/ariadne-context.md`
- [ ] 5.2: Update deep-architecture-scan.md — add `## Pre-Context (Ariadne Data)` section: "Structural map at `.claude/moira/state/init/ariadne-context.md` contains clusters, layers, cycles, boundaries from static analysis. Read it first. Focus your file reading on SEMANTIC understanding: business logic, data flow between services, API contracts, middleware chains. Do NOT spend budget rediscovering structure that Ariadne already mapped."
- [ ] 5.3: Update deep-dependency-scan.md — add pre-context section: "Ariadne pre-context contains cycles and structural dependencies. Focus on: package versions/freshness, unused packages (declared but never imported), duplicate functionality, version constraint analysis."
- [ ] 5.4: Update deep-test-coverage-scan.md — add pre-context section with note: "Use `ariadne_tests_for` data in pre-context for source→test mapping. Focus on: test quality, assertion density, mock patterns, missing coverage for critical paths."
- [ ] 5.5: Update deep-security-scan.md — add pre-context section: "Ariadne boundaries and centrality data show system entry points and high-impact files. Focus security analysis on these boundaries first."
- [ ] 5.6: Graceful fallback — each template includes: "If pre-context file does not exist, proceed with full manual scanning as before."
- [ ] 5.7: Wire into init: call `moira_deepscan_prepare_context()` after graph build (step 4b), before deep scans trigger on first task

**Files:** `src/global/lib/graph.sh` (new function), `src/global/templates/scanners/deep/deep-architecture-scan.md`, `deep-dependency-scan.md`, `deep-test-coverage-scan.md`, `deep-security-scan.md`, `src/commands/moira/init.md`

### Chunk 6: Integration Testing

**Tasks:**
- [ ] 6.1: Test init WITH ariadne binary → verify quality-map has Problematic entries from smells/cycles, project-model has layers/centrality/metrics sections
- [ ] 6.2: Test init WITHOUT ariadne binary → verify graceful degradation (quality-map empty, scanners work at full budget as fallback)
- [ ] 6.3: Test refresh with ariadne diff → verify new smells appear in quality-map, resolved smells trigger promotion
- [ ] 6.4: Test quality-map lifecycle: create entry → 3 failed findings → verify demotion → resolve smell → verify promotion
- [ ] 6.5: Test pre-collected scanner budgets → verify tech/structure agents stay under 50k
- [ ] 6.6: Test deep scanner pre-context → verify agents read ariadne-context.md and focus on semantics
- [ ] 6.7: Verify total init token usage < 340k (target: 46% reduction from ~560k baseline)
- [ ] 6.8: Run `/moira:bench` on existing fixture project to verify no regressions

**Files:** `src/tests/tier1/test-ariadne-knowledge-pipeline.sh`, `src/tests/tier1/test-quality-map-lifecycle.sh`, `src/tests/tier1/test-hybrid-scanners.sh`

**Token Budget Impact:**
| Component | Before | After | Savings |
|-----------|--------|-------|---------|
| Tech scanner | 140k (agent) | ~50k (bash pre-collect + light agent) | -90k |
| Structure scanner | 140k (agent) | ~50k (ariadne + bash pre-collect + light agent) | -90k |
| Convention scanner | 140k (agent) | 100k (tighter budget) | -40k |
| Pattern scanner | 140k (agent) | 100k (tighter budget) | -40k |
| Ariadne → knowledge | — | ~0 (bash/jq) | free |
| Quality-map fixes | — | ~0 (bash) | free |
| **Total init** | **~560k** | **~300k** | **-46%** |

**Risk classification:** ORANGE (knowledge structure changes, bootstrap flow changes). Requires regression check + design doc update.

**Key decisions:** D-188 (Ariadne-driven bootstrap).

**Why Phase 15:** Requires working bootstrap (Phase 5), Ariadne integration (Phase 13), and quality gates (Phase 6). This phase fixes known bugs and maximizes the value already built in those phases.


## Phase 16: Pipeline Token Optimization

**Goal:** Reduce Full pipeline token consumption by ~50% (from ~1.1M to ~530-570k) without losing quality signals. Inspired by GSD's architecture: front-load quality in planning, embed verification in execution, minimize dispatch count.

**Depends on:** Phase 3 (pipeline engine), Phase 6 (quality gates), Phase 15 (execution data that motivated this optimization).

**Context (D-189 through D-193):** Phase 15 execution report revealed ~1.1M tokens / ~115 min for ~1,780 lines of output. Root causes: duplicate file reading across agents (~50-80k wasted), per-batch review/test overhead (8 dispatches = ~384k for 1 real bug caught), 17 total dispatches generating ~174k orchestrator overhead. Benchmarking against GSD showed that comparable quality is achievable with ~5-7 dispatches through front-loaded plan validation and embedded task verification.

### Chunk 1: Merged Research Step (D-189)

Hermes's exploration instructions expanded to include Q1 gap analysis. Athena becomes on-demand.

**Tasks:**
- [ ] 1.1: Update Hermes role rules (`roles/hermes.yaml`) — add `## Gap Analysis` instruction block with Q1 completeness checklist items. Frame as fact-reporting: "report which edge cases have no handler, which error paths are missing."
- [ ] 1.2: Update exploration Layer 4 templates — add gap analysis section to exploration output contract
- [ ] 1.3: Update orchestrator dispatch logic — Standard and Full pipelines dispatch Hermes only (not parallel Hermes+Athena)
- [ ] 1.4: Add `analyze` option to plan gate in orchestrator — dispatches Athena on-demand with exploration.md as input
- [ ] 1.5: Update knowledge-access-matrix.yaml — Hermes gets L1 project-model (was L0) to support gap analysis context
- [ ] 1.6: Verify Decomposition pipeline still dispatches Athena by default (unchanged for epics)

**Files:** `src/global/core/rules/roles/hermes.yaml`, `src/global/skills/orchestrator.md`, `src/global/skills/dispatch.md`, `src/global/core/knowledge-access-matrix.yaml`

### Chunk 2: Plan Validation Step (D-190)

Themis gains plan-check mode. Dispatched after Daedalus in Full pipeline.

**Tasks:**
- [ ] 2.1: Add `plan_check` variant to Themis role rules (`roles/themis.yaml`) — scope/file/dependency/contract/verify/budget validation checklist
- [ ] 2.2: Update Full pipeline orchestrator flow — dispatch Themis in plan-check mode after Daedalus, before plan gate
- [ ] 2.3: Update plan gate presentation — include plan-check findings alongside plan summary
- [ ] 2.4: Add plan-check re-dispatch logic — if critical findings, re-dispatch Daedalus with feedback before presenting gate
- [ ] 2.5: Create plan-check quality criteria file (`core/rules/quality/q3b-plan-check.yaml`)

**Files:** `src/global/core/rules/roles/themis.yaml`, `src/global/skills/orchestrator.md`, `src/global/core/rules/quality/q3b-plan-check.yaml`

### Chunk 3: Embedded Task Verification (D-191)

Daedalus produces `Verify:` and `Done:` fields per task. Hephaestus runs verification. Test hook replaces Aletheia.

**Tasks:**
- [ ] 3.1: Update Daedalus role rules — add verify/done field requirement to plan output contract
- [ ] 3.2: Update Daedalus Layer 4 templates — verify field examples and guidance
- [ ] 3.3: Update Hephaestus role rules — add embedded verification protocol (run verify, 2 fix attempts, record results)
- [ ] 3.4: Update Hephaestus Layer 4 templates — verification execution instructions
- [ ] 3.5: Implement bash build/test step in orchestrator — after all implementation batches, BEFORE final review: run `config.yaml → tooling.post_implementation[]`. If empty, skip. Write results to `test-results.md`. If fail → Hephaestus retry (max 2)
- [ ] 3.6: Remove Aletheia dispatch from Standard/Full pipelines entirely (D-194)
- [ ] 3.7: Update final gate `test` option — dispatch Hephaestus (not Aletheia) for ad-hoc testing
- [ ] 3.8: Update onboarding — `/moira:init` prompts user to configure `tooling.post_implementation` with their build/test commands
- [ ] 3.9: Ensure Daedalus includes test-writing tasks in plan when tests are a deliverable (Hephaestus writes tests)

**Files:** `src/global/core/rules/roles/daedalus.yaml`, `src/global/core/rules/roles/hephaestus.yaml`, `src/global/skills/orchestrator.md`, `src/global/skills/dispatch.md`

### Chunk 4: Analysis Paralysis Guard (D-192)

Prompt-level guard added to Hephaestus, Daedalus, and Themis.

**Tasks:**
- [ ] 4.1: Add paralysis guard to base rules or per-agent role rules — 5+ consecutive reads without write → STOP
- [ ] 4.2: Hermes threshold: 10+ consecutive reads (exploration role)
- [ ] 4.3: Verify guard text is included in assembled instructions (dispatch.md check)

**Files:** `src/global/core/rules/roles/hephaestus.yaml`, `src/global/core/rules/roles/daedalus.yaml`, `src/global/core/rules/roles/themis.yaml`, `src/global/core/rules/roles/hermes.yaml`

### Chunk 5: Optimized Full Pipeline Flow (D-193)

Pipeline YAML and orchestrator updated for new flow: fewer batches, no per-phase review/test, mid-point gate conditional.

**Tasks:**
- [ ] 5.1: Update full.yaml — already done in design docs, implement runtime support
- [ ] 5.2: Update standard.yaml — already done in design docs, implement runtime support
- [ ] 5.3: Update orchestrator batch logic — default 2 batches, split threshold at ~120 tool uses
- [ ] 5.4: Implement conditional mid-point gate — fires only when >2 batches, after ~50% complete
- [ ] 5.5: Update final review dispatch — Themis reads all implementation phases, not just last
- [ ] 5.6: Remove per-phase Aletheia dispatch from orchestrator loop
- [ ] 5.7: Update artifact-validate.sh — new plan-check artifact validation
- [ ] 5.8: Update xref-manifest.yaml — new cross-references for plan-check, test-hook, verify fields

**Files:** `src/global/skills/orchestrator.md`, `src/global/skills/dispatch.md`, `src/hooks/artifact-validate.sh`, `src/global/core/xref-manifest.yaml`

### Chunk 6: Testing & Verification

**Tasks:**
- [ ] 6.1: Update existing Tier 1 tests — pipeline YAML validation (new steps, removed steps, gate changes)
- [ ] 6.2: New test: verify Hermes role rules include gap analysis instructions
- [ ] 6.3: New test: verify Daedalus role rules require verify/done fields
- [ ] 6.4: New test: verify Hephaestus role rules include embedded verification protocol
- [ ] 6.5: New test: verify Themis role rules include plan-check variant
- [ ] 6.6: New test: verify paralysis guard in relevant agent rules
- [ ] 6.7: New test: verify full.yaml has plan_check step and test_hook step
- [ ] 6.8: New test: verify standard.yaml has test_hook step (no aletheia in pipeline)
- [ ] 6.9: New test: verify plan gate has 'analyze' option
- [ ] 6.10: Regression: run existing Tier 1 suite, verify no breakage
- [ ] 6.11: Manual: run a task through optimized pipeline, measure token usage

**Files:** `src/tests/tier1/` (new and updated test files)

**Token Budget Impact:**
| Component | Before (Phase 15) | After (Optimized) | Savings |
|-----------|-------------------|-------------------|---------|
| Exploration (Hermes) | 88k | ~100k (expanded with Q1) | -12k (larger, but replaces Athena) |
| Analysis (Athena) | 56k | 0k (on-demand only) | +56k |
| Architecture (Metis) | 88k | ~100k | -12k (reads exploration only) |
| Planning (Daedalus) | 66k | ~60k | +6k |
| Plan-check (Themis) | — | ~40k | -40k (new step) |
| Implementation (Hephaestus × 4) | 314k | ~200k (× 2 batches) | +114k |
| Review (Themis × 4) | 264k | ~80k (× 1 final) | +184k |
| Testing (Aletheia × 4) | 120k | ~0k (bash build/test step, D-194) | +120k |
| Integration (Aletheia) | — | — | — |
| Orchestrator | 174k | ~60k (~8 dispatches) | +114k |
| **Total** | **~1.1M** | **~530-570k** | **~50%** |

**Risk classification:** RED (pipeline gate changes, agent role boundary changes per D-193). Requires constitutional amendment to Art 2.2.

**Constitutional amendment required:** Art 2.2 — Full pipeline gate list changes from "classification + architecture + plan + per-phase + final" to "classification + architecture + plan + mid-point (conditional) + final". User must edit CONSTITUTION.md directly.

**Key decisions:** D-189 (merged research step), D-190 (plan validation), D-191 (embedded verification), D-192 (paralysis guard), D-193 (optimized pipeline structure), D-194 (Aletheia removed from pipelines).

**Why Phase 16:** Motivated by Phase 15 execution data showing ~730 tokens/line of output. Requires working pipeline engine (Phase 3) and quality gates (Phase 6) as foundation. Builds on GSD benchmarking insights to achieve comparable quality at ~50% token cost.

---

## Testing Strategy

Three-layer architecture woven across phases (D-023):

**Tier 1 — Structural Verifier (bash + grep, 0 tokens, deterministic):**
- Built during Phase 1-3
- Runs on every change (always)
- Validates: file structure, YAML schemas, NEVER constraints, gate presence, Art 1.1 compliance

**Tier 2 — Behavioral Bench (full Moira runs on fixtures, LLM-judge):**
- Fixtures created during Phase 6
- LLM-judge operational by Phase 10 (D-024)
- Runs on prompt/rule changes (targeted, 3-5 tests)

**Tier 3 — Full Bench (all tests, statistical analysis):**
- Full suite by Phase 12
- Runs on pipeline/gate/role boundary changes (D-026)
- Confidence bands for regression detection (D-025)

**Live Telemetry (passive, per-task metrics):**
- Begins Phase 3 (passive collection, privacy-first, D-027)
- Numbers and enums only, never content

**Per-phase testing:**
1. Manual testing on target project
2. Edge case verification
3. Integration with previous phases
4. User feedback incorporation

## Success Criteria

System is complete when:
- [ ] `/moira init` bootstraps correctly on a real-world project
- [ ] Small/medium/large tasks execute through correct pipelines
- [ ] Orchestrator context stays < 25% on average
- [ ] First-pass acceptance rate > 80%
- [ ] No orchestrator violations (reads/writes project files)
- [ ] Knowledge base grows organically with each task
- [ ] Audit identifies real issues
- [ ] Metrics show improvement trends over time
- [ ] Resume works without quality degradation
- [ ] Multiple developers can work concurrently
- [ ] Ariadne (project graph) integration works with/without binary (graceful degradation)
- [ ] Agents use graph data for navigation and impact analysis
- [ ] Explorer token usage reduced by 50%+ with graph
- [ ] Quality-map populated with real structural evidence (smells, cycles, refactoring needs) at init — not empty templates
- [ ] Quality-map entries accumulate observations and migrate between categories (Strong/Adequate/Problematic)
- [ ] Init token budget < 340k (46% reduction from 560k baseline) via hybrid bash pre-collect + lighter agents
- [ ] Init/refresh work identically with and without Ariadne binary (graceful degradation)
- [x] Analytical tasks execute through Analytical Pipeline with correct subtype routing
- [x] Progressive depth produces convergence metrics that inform user decisions
- [x] Calliope writes/updates documents without touching source code
- [x] QA1-QA4 gates catch substantive analytical weaknesses (not just cosmetic issues)
