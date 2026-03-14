# Phase 3: Pipeline Engine (Orchestrator Skill)

## Goal

The Moira orchestrator can execute all 4 pipeline types (Quick/Standard/Full/Decomposition) through a deterministic state machine, dispatching agents, presenting gates, handling errors, and tracking state at every step.

## Risk Classification

**RED** — Pipeline gate changes, orchestrator restriction changes. Requires constitutional verification + user approval.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | All articles — primary constraint |
| `design/architecture/pipelines.md` | Pipeline flows, gate UX, error handling, smart batching |
| `design/architecture/agents.md` | Agent contracts, spawning strategy |
| `design/architecture/overview.md` | Orchestrator boundaries, data flow, file structure |
| `design/architecture/commands.md` | `/moira:task` UX, gate actions, completion actions |
| `design/architecture/naming.md` | Greek mythology names, display format `Name (role)` |
| `design/architecture/rules.md` | 4-layer rule system, assembly process |
| `design/architecture/escape-hatch.md` | Bypass flow, anti-manipulation |
| `design/subsystems/fault-tolerance.md` | E1-E8 error taxonomy, recovery strategies |
| `design/subsystems/self-monitoring.md` | 3-layer guard, context monitoring, health report |
| `design/subsystems/context-budget.md` | Budget allocations, thresholds, overflow handling |
| `design/subsystems/testing.md` | Tier 1 structural verifier additions, live telemetry bootstrap |
| `design/decisions/log.md` | D-001, D-003, D-004, D-015, D-028, D-030, D-031 |

## Prerequisites (from Phase 1-2)

Phase 3 depends on:

- **Phase 1:** Directory scaffold, state schemas (`current.yaml`, `status.yaml`, `manifest.yaml`), state management (`state.sh`), YAML utilities (`yaml-utils.sh`), task ID generation (`task-id.sh`), command stubs with `allowed-tools` frontmatter
- **Phase 2:** All 10 agent role definitions (`roles/*.yaml`), base rules (`base.yaml`), quality criteria files, response contract (`response-contract.yaml`), knowledge access matrix

## Deliverables

### D1: Orchestrator Skill (`src/global/skills/orchestrator.md`)

The brain of the system. A markdown file loaded as the orchestrator's system context when `/moira:task` is invoked.

**Contains:**
- Pipeline state machine definition (steps per pipeline type)
- Gate definitions with required gates per pipeline
- Agent dispatch logic (which agent, foreground/background, parallel grouping)
- Pipeline selection function (pure mapping from classification to pipeline type, Art 2.1)
- Error handling procedures (E1-E8 recovery flows)
- Orchestrator boundary rules (anti-rationalization, Art 1.1)
- Budget monitoring thresholds and actions (canonical source: `context-budget.md`):
  - Healthy: < 25% — normal operation
  - Monitor: 25-40% — include in status display
  - Warning: 40-60% — display alert to user
  - Critical: > 60% — recommend checkpoint
- Response parsing logic (how to read agent STATUS/SUMMARY/ARTIFACTS/NEXT)
- State file update instructions (when and what to write to current.yaml, status.yaml)

**Constitutional constraints:**
- `allowed-tools` in `task.md` frontmatter prevents orchestrator from calling Edit/Grep/Glob/Bash (D-031, Layer 1)
- Orchestrator MUST use Agent tool for all project work (Art 1.1)
- Orchestrator reads ONLY `.claude/moira/` paths (never project files)

### D2: Pipeline Definitions (`src/global/core/pipelines/`)

Four YAML files defining the exact step sequences, gates, and agent mappings for each pipeline type.

**Files:**
- `quick.yaml` — 6 steps: classify → explore → implement → review → final-gate → post (budget report)
- `standard.yaml` — 9 steps: classify → explore+analyze (parallel) → architect → plan → implement → review → test → final-gate → post (reflection stub + budget report)
- `full.yaml` — classify → explore+analyze (parallel) → architect → plan → [per-phase: implement → review → test → phase-gate] → integration-test → final-gate → post (reflection stub + budget report)
- `decomposition.yaml` — classify → analyze → architect → decompose → [per-task: execute via appropriate pipeline] → integration → final-gate → post (reflection stub + budget report)

Each definition includes:
- `steps[]` — ordered step list with step ID, agent(s), mode (foreground/background/parallel)
- `gates[]` — gate checkpoints with ID, position (after which step), options, required (always true)
- `error_handlers` — per-error-type recovery actions

### D3: Gate Presentation System (`src/global/skills/gates.md`)

Templates and logic for presenting approval gates to the user.

**Gate types (approval gates):**
- Classification gate (after Apollo classifies) — options: proceed, modify, abort
- Architecture gate (after Metis decides) — options: proceed, details, modify, abort
- Plan gate (after Daedalus plans) — options: proceed, details, modify, abort
- Phase gate (after each phase in Full pipeline) — options: proceed, checkpoint, abort
- Decomposition gate (after Daedalus decomposes epic) — options: proceed, modify, abort
- Final gate (completion review) — options: done, tweak, redo, diff, test

**Error/blocked gates (per fault-tolerance.md):**
- Blocked gate (E1-INPUT) — options: answer, point, skip, abort
- Scope change gate (E2-SCOPE) — options: upgrade, split, reduce, continue
- Conflict gate (E3-CONFLICT) — presents options A/B + agent recommendation, user chooses
- Quality failure gate (E5-QUALITY, after max retries) — options: redesign, manual, simplify
- Agent failure gate (E6-AGENT) — options: retry-split, retry-as-is, manual, rollback

**Each gate template includes:**
- Header: `═══ GATE: <Name> ═══`
- Summary (1-3 sentences from agent artifact)
- Key points (bullets)
- Impact (files affected, budget)
- Details path (link to full artifact)
- Health report (context usage, violations, agents dispatched, gates passed, retries)
- Options with descriptions

**Final gate completion actions are NOT gate decisions (D-037).** Gate is recorded as `proceed` via `moira_state_gate()`. Completion action (done/tweak/redo/diff/test) triggers a separate orchestrator flow.

### D4: Agent Dispatch Module (`src/global/skills/dispatch.md`)

Instructions for how the orchestrator spawns agents via the native Agent tool.

**Covers:**
- Prompt assembly: how to construct the agent prompt from L1-L4 rules + task context + response contract
- Foreground dispatch (sequential steps — orchestrator waits)
- Background dispatch (parallel batches — concurrent)
- Parallel dispatch pattern (Explorer + Analyst in single message)
- Response parsing: extracting STATUS, SUMMARY, ARTIFACTS, NEXT from agent return
- Failure detection: agent returned error, timeout, nonsensical output
- State updates after each dispatch (call `state.sh` functions)

### D5: Error Handling Procedures (`src/global/skills/errors.md`)

Error handling flows matching fault-tolerance.md.

**Full implementation (E1-E6):**

For each error type E1-E6:
- Detection criteria (how orchestrator recognizes the error)
- Recovery flow (exact steps)
- User-facing display template
- State file updates
- Escalation path

**Stub implementation (E7-E8):**
- E7 (drift/rule violation): stub per D-038. Log if detected, no automated detection (Phase 8).
- E8 (stale knowledge): stub per D-038. Log and escalate to user, no freshness checking (Phase 4).

**Retry limits:**
- E5 (quality failure): max 2 attempts, then escalate
- E6 (agent failure): retry 1x, then diagnose + escalate
- All retries logged in status.yaml

### D6: Updated `task.md` Command (`src/commands/moira/task.md`)

Replace the placeholder with the actual orchestrator entry point.

**Flow:**
1. Parse user input (task description + optional size hint)
2. Generate task ID
3. Create task directory under `state/tasks/{id}/`
4. Write `input.md` with original task description
5. Initialize `status.yaml` with task_id, description, developer, created_at
6. Initialize `current.yaml` with task_id, pipeline=null, step=classification
7. Create stub `manifest.yaml` with task_id, pipeline=null, developer (per AD-4)
8. Read orchestrator skill from `~/.claude/moira/skills/orchestrator.md`
9. Begin pipeline: dispatch Apollo (classifier)
10. On classification result: present classification gate
11. On gate approval: determine pipeline type and execute

**Frontmatter (unchanged from Phase 1):**
```yaml
allowed-tools:
  - Agent
  - Read
  - Write
  - TaskCreate
  - TaskUpdate
  - TaskList
```

### D7: Updated `bypass.md` Command (`src/commands/moira/bypass.md`)

Implement the escape hatch per `escape-hatch.md`.

**Frontmatter `allowed-tools` (unchanged from Phase 1):**
```yaml
allowed-tools:
  - Agent    # dispatch Implementer directly
  - Read     # read moira state/config
  - Write    # write bypass-log.yaml
```

Note: `TaskCreate`/`TaskUpdate`/`TaskList` are intentionally excluded — bypass does not create tracked tasks. Bypass logging goes to `state/bypass-log.yaml`, not the task system.

**Flow (per updated `escape-hatch.md`):**
1. Display bypass warning with trade-offs
2. Recommend Quick Pipeline
3. Wait for user choice: "1" (Quick) or "2" (Bypass)
4. If "2": dispatch Hephaestus (implementer) directly
5. Log to `state/bypass-log.yaml`
6. Display completion without quality indicators

### D8: Live Telemetry Writer

Integrated into pipeline completion. After every pipeline completes (or fails), write `telemetry.yaml` to the task directory.

**Contents (per testing.md):**
- pipeline type, classification confidence/correctness
- agents called (role, status, context_pct, duration_sec)
- gates (name, result, retry_count)
- retries total, budget total tokens
- reviewer findings summary
- first_pass_accepted, final_result
- constitutional_pass, violations

**Schema:** `src/schemas/telemetry.schema.yaml` — must be created per D-029 (full schemas upfront). Follows same `_meta` + `fields` pattern as other schemas.

**Failure behavior (Art 3.3):** If telemetry write fails, append non-blocking warning to budget report. Pipeline not affected.

### D9: Tier 1 Test Additions (`src/tests/tier1/`)

Structural verification tests specific to Phase 3.

**New test file: `test-pipeline-engine.sh`**

Tests:
- Pipeline selection is pure function of classification (Art 2.1): `quick.yaml` → only for small+high_confidence, etc.
- All required gates present per pipeline (Art 2.2): quick=2, standard=4, full=5+, decomposition=4+ (classification + decomposition + at least 1 per-task + final)
- No auto-proceed logic in gates (Art 4.2): grep for auto-proceed/skip-gate patterns, count must be 0
- No conditional skip logic for gates: pipeline definitions have no `if`/`when`/`skip` around gates
- Orchestrator skill contains no direct project file operations (Art 1.1): grep for Read/Write/Edit targeting non-moira paths
- Every pipeline step writes to state files (Art 3.1): each step in pipeline definitions has a `writes_to` field
- Error recovery paths include user notification (Art 3.3): error handler definitions have `display` field
- Budget report exists in pipeline completion flow (Art 3.2)

**Extended existing tests:**
- `test-file-structure.sh`: add checks for new files (pipelines/, skills/)
- `test-install.sh`: add verification for new artifacts

### D10: Updated `install.sh`

Add new Phase 3 artifacts to the install script.

**Scaffold update:** `scaffold.sh` → add `mkdir -p "$target_dir"/core/pipelines` to `moira_scaffold_global()`.

**New copy operations:**
- `global/skills/*.md` → `$MOIRA_HOME/skills/`
- `global/core/pipelines/*.yaml` → `$MOIRA_HOME/core/pipelines/`

**New verification checks:**
- Orchestrator skill exists and has content
- All 4 pipeline definition files exist
- Pipeline definitions contain required `gates:` section
- Telemetry schema exists

## Non-Deliverables (explicitly deferred)

- **Rule assembly** (Phase 4): Planner assembles L1-L4 rules. For Phase 3, agents receive a simplified prompt that includes their role rules + task context inline.
- **Knowledge loading** (Phase 4): Agents don't receive knowledge base content yet. Knowledge access matrix exists but is not enforced at runtime.
- **MCP integration** (Phase 9): No MCP tool allocation or tracking.
- **Reflection** (Phase 10): Post-task reflection is noted in pipeline definition but not executed.
- **Checkpoint/resume** (Phase 12): Manifest writing is noted but `/moira:resume` not functional.
- **Smart batching** (Phase 4+): For Phase 3, the Planner describes batches but the orchestrator dispatches implementers sequentially. Parallel implementation batches are a Phase 4+ concern.
- **Budget estimation** (Phase 7): Budget monitoring tracks orchestrator context but does not do pre-execution estimation.

## Architectural Decisions

### AD-1: Orchestrator Skill as Markdown

The orchestrator skill is a single markdown file containing all pipeline logic as structured natural language instructions. It is NOT a script or code module. The orchestrator (main Claude) reads this skill and follows its instructions.

**Rationale:** Claude Code custom commands execute as Claude prompts. The orchestrator IS Claude following instructions. All logic is expressed as structured, unambiguous instructions that Claude can follow deterministically.

### AD-2: Pipeline Definitions as YAML (D-035)

Per D-035. Pipeline step sequences and gate definitions are separate YAML files in `core/pipelines/`, not embedded in the orchestrator skill.

### AD-3: Simplified Agent Dispatch for Phase 3

Without the full rule assembly system (Phase 4), agent prompts are constructed inline by the orchestrator. The prompt includes:
1. Agent role rules (read from `core/rules/roles/{agent}.yaml`)
2. Response contract (read from `core/response-contract.yaml`)
3. Task-specific context (read from task state files)
4. Output path (where to write artifacts)

This is a temporary pattern that Phase 4 replaces with full L1-L4 assembly.

### AD-4: State Files as Source of Truth

The orchestrator tracks all progress through state files (`current.yaml`, `status.yaml`). If the orchestrator session ends unexpectedly, the state files reflect the last completed step.

Phase 3 also creates a stub `manifest.yaml` for each task (task_id, pipeline, developer, checkpoint fields set to initial values). This provides the foundation for Phase 12 checkpoint/resume without requiring structural changes later. The stub is minimal — Phase 12 will populate the full checkpoint data.

### AD-5: Sequential Implementation by Default

In Phase 3, all implementation batches run sequentially (one Implementer at a time). Parallel background dispatch for independent batches is deferred to Phase 4+ when the Planner can properly define dependency graphs and contracts.

**Rationale:** Sequential execution is correct by default. Parallel execution requires guarantees about file independence that only the full rule assembly system can provide.

## Success Criteria

1. **Pipeline selection works:** Task description → classification → correct pipeline type (verified by test)
2. **Gates are presented:** User sees all required gates with correct format and options
3. **Gates cannot be skipped:** No code path allows proceeding without gate approval
4. **Agents are dispatched correctly:** Each pipeline step dispatches the right agent with right context
5. **State is tracked:** `current.yaml` and `status.yaml` reflect pipeline progress at every step
6. **Errors are handled:** E1-E6 errors detected and recovered per fault-tolerance.md
7. **Budget is monitored:** Orchestrator context thresholds trigger appropriate warnings
8. **Bypass works:** `/moira:bypass` dispatches Implementer directly with full logging
9. **Telemetry writes:** Pipeline completion writes `telemetry.yaml`
10. **Tier 1 tests pass:** All structural verification tests pass (existing + new)
11. **Constitutional compliance:** All constitutional invariant checks satisfied (19 articles in Constitution; testing.md references "23 checks" which includes sub-checks — exact enumeration defined during Tier 1 test implementation)

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — allowed-tools prevents orchestrator from touching project files
[✓] 1.2 — Agent dispatch uses role definitions with NEVER constraints
[✓] 1.3 — Orchestrator, pipeline definitions, gate system are separate components

ARTICLE 2: Determinism
[✓] 2.1 — Pipeline selection is pure mapping from classification
[✓] 2.2 — Gate definitions are fixed per pipeline, no skip logic
[✓] 2.3 — Error handling asks user, never assumes

ARTICLE 3: Transparency
[✓] 3.1 — Every step writes to state files
[✓] 3.2 — Budget report at pipeline completion
[✓] 3.3 — All errors displayed to user, telemetry failure warned

ARTICLE 4: Safety
[✓] 4.1 — Agents use base rules with fabrication prohibition
[✓] 4.2 — All gates require user action, no auto-proceed
[✓] 4.3 — Git-backed changes (Implementer commits)
[✓] 4.4 — Bypass requires `/moira:bypass` command + exact "2" confirmation (per updated escape-hatch.md)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — N/A (knowledge not written in Phase 3)
[✓] 5.2 — N/A (reflection not active in Phase 3)
[✓] 5.3 — N/A (knowledge not written in Phase 3)

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation
[✓] 6.3 — Tier 1 tests validate constitutional invariants
```
