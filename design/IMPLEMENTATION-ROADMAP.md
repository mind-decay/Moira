# Implementation Roadmap

## Phase Order

Based on dependency analysis. Each phase builds on previous.

---

## Phase 1: Foundation — File Structure & State Management

**Goal:** Forge directory structure exists, state can be read/written/resumed.

**Deliverables:**
- Directory scaffold generator (creates .claude/forge/ tree)
- State management (manifest.yaml read/write/validate)
- Task ID generation
- Lock file management
- Config file schemas (YAML structures)

**Why first:** Everything depends on file structure. Without it, nothing else can store or read data.

---

## Phase 2: Core Agent Definitions

**Goal:** All 9 agents (Explorer, Analyst, Architect, Planner, Implementer, Reviewer, Tester, Reflector, Auditor) have working prompt definitions.

**Deliverables:**
- Base rules (core/rules/base.yaml)
- Role rules for each agent (core/rules/roles/*.yaml)
- Quality criteria files (core/rules/quality/*.yaml)
- Agent response contract enforcement
- Knowledge access matrix implementation

**Why second:** Agents are the execution units. Pipelines are just sequences of agent calls.

---

## Phase 3: Pipeline Engine (Orchestrator Skill)

**Goal:** Orchestrator can execute all 4 pipeline types (Quick/Standard/Full/Decomposition).

**Deliverables:**
- Orchestrator skill definition
- Pipeline state machine (classify → analyze → plan → implement → review → test)
- Gate presentation system
- Agent dispatch logic (foreground/background)
- Pipeline selection based on classification
- Error handling (retry, escalate, abort)

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

## Phase 5: Bootstrap Engine (/forge init)

**Goal:** `/forge init` fully works — scans project, generates config, creates knowledge base.

**Deliverables:**
- Tech scanner agent
- Structure scanner agent
- Convention scanner agent
- Pattern scanner agent (quick scan)
- Config generator (stack.yaml, conventions.yaml, patterns.yaml)
- Project-specific agent adaptation
- Deep scan (background) trigger
- Onboarding flow

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
- Quality map generation
- CONFORM/EVOLVE mode switching
- Code quality criteria enforcement

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

**Goal:** Guard hook prevents orchestrator violations. Budget hook tracks usage.

**Deliverables:**
- guard.sh implementation
- budget-track.sh implementation
- Hook configuration in settings.json
- Orchestrator context monitoring
- Violation logging
- Health report in gates

**Why eighth:** Monitoring layer on top of working system.

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
- Evidence tracking (3-confirmation rule)
- Rule change proposal system
- Knowledge updates from reflection

**Why tenth:** Reflection improves the system. System must exist first.

---

## Phase 11: Metrics & Audit

**Goal:** Full metrics dashboard, audit system, trend analysis.

**Deliverables:**
- Metrics collection per task
- Monthly aggregation
- Dashboard display (/forge metrics)
- Drill-down views
- 5-domain audit system
- Batch recommendation approval
- Tiered audit depth (light/standard/deep)

**Why eleventh:** Metrics and audit analyze system performance. Needs history of tasks.

---

## Phase 12: Advanced Features

**Goal:** Checkpoint/resume, multi-developer, epic decomposition, tweak/redo.

**Deliverables:**
- Checkpoint system (manifest, resume_context)
- Resume validation
- Lock system for multi-developer
- Epic decomposition pipeline
- Tweak flow
- Redo flow with re-entry points
- Version migration (/forge upgrade)

**Why last:** Advanced workflows. Core system must be solid first.

---

## Testing Strategy

Each phase includes:
1. Manual testing on target project (ЛК ЮЛ)
2. Edge case verification
3. Integration with previous phases
4. User feedback incorporation

## Success Criteria

System is complete when:
- [ ] `/forge init` bootstraps correctly on ЛК ЮЛ project
- [ ] Small/medium/large tasks execute through correct pipelines
- [ ] Orchestrator context stays < 25% on average
- [ ] First-pass acceptance rate > 80%
- [ ] No orchestrator violations (reads/writes project files)
- [ ] Knowledge base grows organically with each task
- [ ] Audit identifies real issues
- [ ] Metrics show improvement trends over time
- [ ] Resume works without quality degradation
- [ ] Multiple developers can work concurrently
