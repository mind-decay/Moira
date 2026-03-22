# Implementation Roadmap

## Phase Order

Based on dependency analysis. Each phase builds on previous.

---

## Phase 1: Foundation — File Structure & State Management

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

## Phase 2: Core Agent Definitions

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

## Phase 3: Pipeline Engine (Orchestrator Skill)

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

## Phase 4: Rules Assembly & Knowledge System

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

## Phase 5: Bootstrap Engine (/moira init)

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

## Phase 6: Quality Gates & Review System

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

## Phase 7: Context Budget Tracking

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

## Phase 8: Hooks & Self-Monitoring

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

## Phase 9: MCP Integration

**Goal:** MCP tools are registered, allocated per step, tracked, and cached.

**Deliverables:**
- MCP registry generator
- MCP allocation in plans
- MCP usage instructions in agent prompts
- MCP usage review checklist
- MCP knowledge caching

**Why ninth:** MCP adds capability to existing agents. System works without it.

---

## Phase 10: Reflection Engine

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

## Phase 11: Metrics & Audit

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

## Phase 12: Advanced Features

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

## Phase 13: Ariadne Integration — Project Graph in Moira Pipelines

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

## Phase 14: Analytical Pipeline

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
- [ ] Analytical tasks execute through Analytical Pipeline with correct subtype routing
- [ ] Progressive depth produces convergence metrics that inform user decisions
- [ ] Calliope writes/updates documents without touching source code
- [ ] QA1-QA4 gates catch substantive analytical weaknesses (not just cosmetic issues)
