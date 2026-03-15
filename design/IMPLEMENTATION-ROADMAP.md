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
- Cross-reference manifest (`src/global/core/xref-manifest.yaml`) — dependency map between files for consistency enforcement (D-077). Design doc for manifest schema TBD in phase spec
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

**Why last:** Advanced workflows. Core system must be solid first.

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
