# Phase 3: Implementation Plan

## Reference

- Spec: `design/specs/2026-03-11-phase3-pipeline-engine.md`
- Risk: RED (pipeline gates, orchestrator restrictions)

## Dependency Graph

```
Chunk 1 (Pipeline Definitions)
    │
    ├──→ Chunk 2 (Error Handling Procedures)
    │
    ├──→ Chunk 3 (Gate Presentation System)
    │
    └──→ Chunk 4 (Agent Dispatch Module)
              │
              └──→ Chunk 5 (Orchestrator Skill)
                        │
                        ├──→ Chunk 6 (task.md + bypass.md)
                        │
                        └──→ Chunk 7 (Telemetry + Install + Tests)
```

Chunks 2, 3, 4 are independent of each other but all depend on Chunk 1.
Chunk 5 depends on 2, 3, 4. Chunk 6 and 7 depend on 5.

---

## Chunk 1: Pipeline Definitions

**Goal:** Define the exact step sequences, gates, and agent mappings for all 4 pipeline types as structured YAML.

### Task 1.1: Create pipeline directory structure + update scaffold

- **Files:** `src/global/core/pipelines/` (new directory), `src/global/lib/scaffold.sh` (edit)
- **Source:** `design/architecture/pipelines.md`, `design/architecture/overview.md`
- **Key points:**
  - Create directory `src/global/core/pipelines/`
  - This becomes `$MOIRA_HOME/core/pipelines/` after install
  - Update `moira_scaffold_global()` in `scaffold.sh`: add `mkdir -p "$target_dir"/core/pipelines` (per updated `overview.md` file tree)
  - Update `moira_state_transition()` in `state.sh`: extend valid steps per D-036
  - Pipeline definitions use Greek agent names (per D-034, matching actual role files)

### Task 1.2: Quick Pipeline definition

- **File:** `src/global/core/pipelines/quick.yaml`
- **Source:** `design/architecture/pipelines.md` → Quick Pipeline section
- **Key points:**
  - `_meta` with name, description, trigger conditions (`size: small, confidence: high`)
  - `steps[]`: 5 pipeline steps — classify, explore, implement, review, plus final-gate and post (budget report)
  - Each step: `id`, `agent` (Greek name), `role` (functional name), `mode` (foreground), `writes_to` (artifact path), `reads_from` (input dependencies)
  - `gates[]`: 2 gates — classification (after classify), final (after review)
  - Each gate: `id`, `after_step`, `options[]`, `required: true`
  - Classification gate options: proceed, modify (re-classify), abort
  - Final gate options: done, tweak, redo, diff
  - `error_handlers`: E1→pause+ask, E5→retry(max:1)+escalate, E6→retry(1)+escalate
  - Post-pipeline: `post.reflection: lightweight` (noted but not executed in Phase 3)
  - Post-pipeline: `post.budget_report: true`

### Task 1.3: Standard Pipeline definition

- **File:** `src/global/core/pipelines/standard.yaml`
- **Source:** `design/architecture/pipelines.md` → Standard Pipeline section
- **Key points:**
  - Steps: classify → explore+analyze (parallel) → architect → plan → implement → review → test → final
  - Parallel step representation: step with `mode: parallel`, `agents: [hermes, athena]`
  - Gates: classification, architecture (after architect), plan (after plan), final
  - Architecture gate options: proceed, details, modify, abort
  - Plan gate options: proceed, details, modify, abort
  - Final gate options: done, tweak, redo, diff, test
  - Implementation may have multiple batches (sequential in Phase 3)
  - Error handlers: full E1-E6 set
  - E5 quality failure: max 2 attempts (retry implementer with feedback, then escalate)
  - E2 scope change: stop, present scope analysis, options: upgrade/split/reduce/continue
  - Post: reflector (background, non-blocking — noted, not executed Phase 3)

### Task 1.4: Full Pipeline definition

- **File:** `src/global/core/pipelines/full.yaml`
- **Source:** `design/architecture/pipelines.md` → Full Pipeline section
- **Key points:**
  - Steps: classify → explore+analyze (parallel) → architect → plan → [phase loop: implement → review → test → phase-gate] → integration-test → final
  - Phase loop represented as `repeatable_group` with `gate_per_iteration: true`
  - Architecture gate: user CHOOSES from alternatives (not just approve/reject)
  - Phase gates after each iteration of the loop
  - Integration test step after all phases
  - Checkpoint noted at each phase gate (manifest.yaml write, Phase 12 functionality)
  - Error handlers: E1-E6 full, E7-E8 stub (per spec D5)

### Task 1.5: Decomposition Pipeline definition

- **File:** `src/global/core/pipelines/decomposition.yaml`
- **Source:** `design/architecture/pipelines.md` → Decomposition Pipeline section
- **Key points:**
  - Steps: classify → analyze (deep) → architect (system-level) → decompose (planner creates task list) → [per-task: execute via appropriate sub-pipeline] → integration → final
  - Decomposition gate: user approves task breakdown + dependency order
  - Per-task gates after each sub-task
  - Sub-tasks reference other pipeline types (standard/full)
  - Queue integration (writes to `queue.yaml` — schema already exists from Phase 1)
  - Each sub-task creates checkpoint

**Commit:** `moira(pipeline): add pipeline definitions for all 4 pipeline types`

---

## Chunk 2: Error Handling Procedures

**Goal:** Complete error handling flows as a skill file the orchestrator references.

### Task 2.1: Error handling skill

- **File:** `src/global/skills/errors.md`
- **Source:** `design/subsystems/fault-tolerance.md`
- **Key points:**
  - Structure: one section per error type
  - E1-E6: full implementation. Each section has: Detection (how to recognize), Recovery (step-by-step), Display (user-facing template), State Updates (what to write), Escalation (when to give up)
  - E7 (drift): stub — log if detected, no automated detection (Phase 8)
  - E8 (stale knowledge): stub — log and escalate to user, no freshness checking (Phase 4)
  - E1 (missing data): agent returns `STATUS: blocked` → orchestrator shows BLOCKED display with answer/point/skip/abort options → on answer, re-dispatch agent with new info
  - E2 (scope change): explorer/architect signals scope larger → stop pipeline → present upgrade/split/reduce/continue options → preserve existing work
  - E3 (conflict): agent documents both sides → orchestrator presents options → user chooses
  - E4 (budget): pre-exec handled by planner (future), mid-exec agent returns `STATUS: budget_exceeded` → spawn new agent for remaining
  - E5 (quality): reviewer finds CRITICAL → retry implementer with feedback (attempt 1) → re-review → if still failing, different approach or escalate (attempt 2) → after 2 failures, escalate with root cause
  - E6 (agent failure): retry 1x → if repeat, diagnostic analysis (input valid? instructions clear? context budget?) → escalate with report + recommendation
  - E7 (drift): detected by guard hook (Phase 8) or reflector (Phase 10) — for Phase 3, just log violations
  - E8 (stale knowledge): detected during exploration — for Phase 3, just report, no auto-update
  - Retry counter: tracked in `status.yaml` retries block
  - Display templates: use the exact formats from fault-tolerance.md (blocked display, quality failure display, agent failure display)

**Commit:** `moira(pipeline): add error handling procedures skill`

---

## Chunk 3: Gate Presentation System

**Goal:** Templates and logic for presenting approval gates to the user.

### Task 3.1: Gate presentation skill

- **File:** `src/global/skills/gates.md`
- **Source:** `design/architecture/pipelines.md` → Approval Gate UX, `design/architecture/commands.md` → In-Pipeline Actions
- **Key points:**
  - Standard gate template (from pipelines.md): header, summary, key points, impact, details path, health report, options
  - Classification gate specifics: show size, confidence, pipeline type, reasoning. Options: proceed, modify (provide different size), abort
  - Architecture gate specifics: show decision summary, alternatives rejected, impact. Options: proceed, details, modify, abort. For Full pipeline: show alternatives to choose from
  - Plan gate specifics: show step count, batch count, estimated budget, file list. Options: proceed, details, modify, abort
  - Phase gate specifics: show phase progress, what was done, what's next. Options: proceed, checkpoint (save + pause), abort
  - Decomposition gate specifics: show task list with sizes, dependencies, order. Options: proceed, modify, abort
  - Final gate specifics: show completion summary, changes made, files affected. Options: done, tweak, redo, diff, test
  - **Blocked/error gate templates** (distinct from approval gates, per `commands.md` At Error/Block section):
    - Blocked gate (E1-INPUT): options answer/point/skip/abort
    - Scope change gate (E2): options upgrade/split/reduce/continue
    - Conflict gate (E3): present options A/B + recommendation
    - Quality failure gate (E5, after max retries): options redesign/manual/simplify
    - Agent failure gate (E6): options retry-split/retry-as-is/manual/rollback
  - Health report section (per self-monitoring.md): context %, violations count, agents dispatched, gates passed, retries, progress step N/M
  - Budget report section (per context-budget.md): per-agent budget table + orchestrator context line
  - All gates use `Name (role)` format for agent references (D-034)
  - **Gate state management:** set `gate_pending` in current.yaml, record decision in status.yaml via `moira_state_gate()`
  - **Final gate special handling:** `moira_state_gate()` accepts only proceed/modify/abort. When user chooses `done` at final gate, record as `moira_state_gate(gate_name, "proceed")`. Completion actions (tweak/redo/diff/test) are NOT gate decisions — they trigger separate orchestrator flows after the gate is recorded as `proceed`.

**Commit:** `moira(pipeline): add gate presentation system skill`

---

## Chunk 4: Agent Dispatch Module

**Goal:** Instructions for how the orchestrator constructs and sends agent prompts.

### Task 4.1: Agent dispatch skill

- **File:** `src/global/skills/dispatch.md`
- **Source:** `design/architecture/agents.md` → Agent Response Contract + Agent Spawning Strategy, `design/architecture/rules.md` → Rule Assembly
- **Key points:**
  - **Prompt construction (Phase 3 simplified):** Read role YAML → extract identity, capabilities, never constraints → combine with response contract → add task context (from state files) → add output path → format as structured prompt
  - The prompt template: Identity section (from role yaml) → Rules section (base inviolable rules + role NEVER constraints) → Task section (what to do, input files to read) → Output section (where to write artifacts, response format)
  - **Foreground dispatch:** Use Agent tool, wait for result. Parse STATUS line from response. If success → read SUMMARY and ARTIFACTS → update state. If failure/blocked → trigger error handler.
  - **Background dispatch:** Use Agent tool with `run_in_background: true`. Used for post-task reflection (Phase 10) and parallel batches (Phase 4+).
  - **Parallel dispatch:** Two agents in single message (e.g., Explorer + Analyst). Use Agent tool twice in one message. Both foreground, orchestrator waits for both.
  - **Response parsing:** Agent returns text. Parse first line for STATUS. Parse SUMMARY, ARTIFACTS, NEXT. If format doesn't match → E6 (agent failure, nonsensical output).
  - **State updates after dispatch:** Call `moira_state_transition()` before dispatch (step → in_progress). Call `moira_state_agent_done()` after completion. On gate → set `gate_pending` in current.yaml.
  - **Agent naming:** Always refer to agents as `Name (role)` in orchestrator output. E.g., "Dispatching Hermes (explorer)..."
  - **Worktree consideration:** For Implementer agents that write code, consider using `isolation: "worktree"` (available in Agent tool). Decision: NOT used in Phase 3 — Implementers write directly. Worktree isolation is a Phase 12 concern for parallel safety.

**Commit:** `moira(pipeline): add agent dispatch module skill`

---

## Chunk 5: Orchestrator Skill

**Goal:** The central orchestrator skill that ties everything together — the brain of Moira.

**Depends on:** Chunks 1-4 (pipeline definitions, error handling, gates, dispatch)

### Task 5.1: Orchestrator skill file

- **File:** `src/global/skills/orchestrator.md`
- **Source:** All design documents, primarily `design/architecture/overview.md` → Orchestrator Boundaries
- **Key points:**
  - **Structure:** Sections correspond to orchestrator's decision flow, not to individual features
  - **Section 1 — Identity and Boundaries:** You are Moira, the orchestrator. You dispatch agents, present gates, track state. You NEVER read/write project files. Anti-rationalization rules (per self-monitoring.md). If you catch yourself thinking "just quickly..." → STOP.
  - **Section 2 — Pipeline Execution Loop:** Read pipeline definition YAML for current pipeline type → for each step: dispatch agent (per dispatch.md) → on result: check STATUS → if success and gate follows: present gate (per gates.md) → on gate approval: advance to next step → on gate modify: re-dispatch agent with feedback → on gate abort: stop pipeline
  - **Section 3 — Pipeline Selection:** After classification result, determine pipeline type. This is a PURE FUNCTION: small+high→quick, small+low→standard, medium→standard, large→full, epic→decomposition. NO exceptions. NO judgment calls.
  - **Section 4 — State Management:** Before each step: write current step to current.yaml. After each step: update status.yaml with artifacts. At each gate: record decision. At completion: final status update. All state writes go through moira state file operations.
  - **Section 5 — Error Handling:** Reference errors.md skill. On agent STATUS: blocked → E1 flow. On scope change signal → E2 flow. On reviewer CRITICAL → E5 flow. On agent garbage output → E6 flow. On orchestrator context > threshold → warning/checkpoint recommendation.
  - **Section 6 — Budget Monitoring:** Track orchestrator context usage (approximate). Four thresholds per `context-budget.md`: Healthy (<25%) → normal, Monitor (25-40%) → include in gate health report, Warning (40-60%) → display alert, Critical (>60%) → recommend checkpoint. At completion → display full budget report.
  - **Section 7 — Completion Flow:** Final gate is recorded as `proceed` via `moira_state_gate()`. Then completion action: `done` → display summary, budget report, telemetry write. `tweak` → dispatch Explorer (scope check) → Implementer (targeted fix) → Reviewer → final gate again. `redo` → git revert, archive previous artifacts, re-enter at chosen point. `diff` → show git diff. `test` → dispatch Aletheia (tester).
  - **Section 8 — Display Conventions:** All output uses `Name (role)` format. Pipeline progress shown as tree (per naming.md CLI examples). Minimal output by default, details on request.
  - Size: Target ~3000-4000 words. Must be comprehensive but not context-heavy. The orchestrator needs to fit within its own budget.

### Task 5.2: Orchestrator skill review

After writing, verify against Constitution checklist:
- Grep orchestrator.md for Read/Write/Edit targeting non-moira paths → count must be 0
- Verify all 4 pipeline types referenced
- Verify all gate types defined
- Verify error handling references errors.md
- Verify anti-rationalization rules present
- Verify `Name (role)` format used consistently

**Commit:** `moira(pipeline): add orchestrator skill — the brain of Moira`

---

## Chunk 6: Command Files (task.md + bypass.md)

**Goal:** Replace placeholder commands with functional implementations.

**Depends on:** Chunk 5 (orchestrator skill)

### Task 6.1: Update task.md command

- **File:** `src/commands/moira/task.md`
- **Source:** `design/architecture/commands.md`, spec D6
- **Key points:**
  - Keep existing frontmatter (`allowed-tools` unchanged)
  - Add `argument-hint`: keep existing
  - Body: instructions for the orchestrator when `/moira:task` is invoked
  - Step 1: Parse user argument (task description + optional `small:`/`medium:`/`large:` prefix)
  - Step 2: Generate task ID (use `task-id.sh` pattern — read .version for prefix, generate timestamp-based ID)
  - Step 3: Create task directory `state/tasks/{id}/` using scaffold (or mkdir)
  - Step 4: Write `input.md` with original task description
  - Step 5: Write `input.md` with original task description
  - Step 6: Initialize `status.yaml` with task_id, description, developer, created_at
  - Step 7: Initialize `current.yaml` with task_id, pipeline=null (determined after classification), step=classification
  - Step 8: Create stub `manifest.yaml` with task_id, pipeline=null, developer (per spec AD-4 — foundation for Phase 12 resume)
  - Step 9: Read orchestrator skill from `~/.claude/moira/skills/orchestrator.md`
  - Step 10: Begin pipeline execution per orchestrator skill instructions
  - Note: task.md is the ENTRY POINT. It sets up state then hands control to orchestrator skill logic. The orchestrator skill contains the full pipeline logic.
  - task.md should be focused: setup + load orchestrator. Not duplicating orchestrator logic.

### Task 6.2: Update bypass.md command

- **File:** `src/commands/moira/bypass.md`
- **Source:** `design/architecture/escape-hatch.md`, spec D7
- **Key points:**
  - Frontmatter `allowed-tools` stays as-is: Agent, Read, Write (no TaskCreate/TaskUpdate/TaskList — bypass doesn't create tracked tasks, per spec D7)
  - **Invocation form:** actual command is `/moira:bypass` (not `/moira bypass:` as shown in escape-hatch.md design doc). Anti-manipulation checks must use the real invocation form.
  - Body: bypass flow per escape-hatch.md
  - Step 1: Display bypass warning exactly as in escape-hatch.md (trade-offs, recommendation)
  - Step 2: Wait for user choice: "1" (Quick Pipeline) or "2" (Confirm bypass)
  - Step 3: If "1" → redirect to Quick Pipeline (same as `/moira:task small:`)
  - Step 4: If "2" → dispatch Hephaestus (implementer) directly with task description
  - Step 5: Log bypass to `state/bypass-log.yaml` (timestamp, description, files_changed, developer)
  - Step 6: Display completion without quality indicators
  - Anti-manipulation: ONLY accept "2" as confirmation. Not "yes", "y", "sure", "proceed", "confirm"
  - Inviolable rules still apply even in bypass: never fabricate, never commit secrets, never modify outside scope

**Commit:** `moira(pipeline): implement task.md and bypass.md commands`

---

## Chunk 7: Telemetry, Install, Tests

**Goal:** Telemetry writing, install script updates, and Tier 1 structural tests.

**Depends on:** Chunk 5 (orchestrator skill references telemetry)

### Task 7.1: Telemetry schema

- **File:** `src/schemas/telemetry.schema.yaml`
- **Source:** `design/subsystems/testing.md` → Per-Task Telemetry Format
- **Key points:**
  - Define schema following same pattern as other schemas (`_meta`, `fields`)
  - Fields: task_id, timestamp, moira_version, pipeline.type, pipeline.classification_confidence, pipeline.classification_correct
  - execution.agents_called (block), execution.gates (block), execution.retries_total, execution.budget_total_tokens
  - quality.reviewer_findings (block), quality.first_pass_accepted, quality.final_result
  - structural.constitutional_pass, structural.violations (block)
  - All fields use privacy-safe types: numbers, booleans, enums — no content strings

### Task 7.2: Update install.sh

- **File:** `src/install.sh`
- **Source:** Spec D10
- **Key points:**
  - Note: `scaffold.sh` already updated in Task 1.1 to create `core/pipelines/` directory
  - Add copy for `global/skills/*.md` → `$MOIRA_HOME/skills/`
  - Add copy for `global/core/pipelines/*.yaml` → `$MOIRA_HOME/core/pipelines/`
  - Add verification: orchestrator skill exists + is non-empty
  - Add verification: 4 pipeline definition files exist
  - Add verification: each pipeline definition contains `gates:` section
  - Add verification: telemetry schema exists (`schemas/telemetry.schema.yaml`)
  - Update checks_total count accordingly

### Task 7.3: Pipeline engine structural tests

- **File:** `src/tests/tier1/test-pipeline-engine.sh`
- **Source:** Spec D9
- **Key points:**
  - Test: Pipeline selection mapping — parse each pipeline YAML, verify trigger conditions match Art 2.1
  - Test: Gate completeness — quick has 2 gates, standard has 4, full has 5+, decomposition has 4+ (classification + decomposition + at least 1 per-task + final)
  - Test: No auto-proceed — grep all pipeline YAMLs + skill files for patterns like `auto_proceed`, `skip_gate`, `auto_approve` → count must be 0
  - Test: No conditional gate skip — grep for patterns that conditionally bypass gates
  - Test: Orchestrator purity — grep orchestrator.md for file operations on non-moira paths (patterns: `Read.*src/`, `Write.*src/`, `Edit.*src/`, `Grep.*src/`, `Glob.*src/`) → count must be 0
  - Test: State write per step — each step in pipeline definitions has `writes_to` or `artifacts` field
  - Test: Error recovery has display — each error handler in pipeline/error definitions has user-facing display
  - Test: Budget report at completion — orchestrator skill mentions budget report in completion flow
  - Use test helpers from `test-helpers.sh` (already exists from Phase 1)
  - No registration needed — `run-all.sh` auto-discovers `test-*.sh` files via glob

### Task 7.4: Update existing tests

- **File:** `src/tests/tier1/test-file-structure.sh` (edit), `src/tests/tier1/test-install.sh` (edit)
- **Key points:**
  - `test-file-structure.sh`: add checks for `skills/` directory, `core/pipelines/` directory, expected files in each
  - `test-install.sh`: add verification that install copies pipeline and skill files correctly
  - Update expected file counts if applicable

### Task 7.5: Run all Tier 1 tests

- Execute `src/tests/tier1/run-all.sh`
- All tests must pass
- Fix any failures

**Commit:** `moira(pipeline): add telemetry schema, install updates, and Tier 1 tests`

---

## Implementation Order Summary

```
1. Chunk 1 — Pipeline Definitions (4 YAML files)
   ↓
2. Chunks 2, 3, 4 — Error Handling, Gates, Dispatch (3 skill files, can be parallel)
   ↓
3. Chunk 5 — Orchestrator Skill (the brain)
   ↓
4. Chunk 6 — Command Files (task.md + bypass.md)
   ↓
5. Chunk 7 — Telemetry + Install + Tests
   ↓
6. Final verification: run all Tier 1 tests + constitutional checklist
```

## Design Consistency Notes

During Phase 1-2, some naming decisions were made that Phase 3 must align with:

1. **Agent names in YAML:** Role files use Greek names (apollo.yaml, hermes.yaml, etc.). Pipeline definitions must reference agents by these names.
2. **State functions:** `moira_state_transition()`, `moira_state_gate()`, `moira_state_agent_done()` exist in `state.sh`. Pipeline engine uses these for state tracking.
3. **Valid pipeline steps in state.sh:** classification, exploration, analysis, architecture, plan, implementation, review, testing, reflection, decomposition, integration, completion (D-036). Pipeline step IDs in YAML definitions must use only valid step names.
4. **Status enums:** pending, in_progress, awaiting_gate, completed, failed (in current.yaml). Pipeline state machine uses these transitions.
5. **Gate decisions:** proceed, modify, abort (validated by `moira_state_gate()`). Final gate completion actions (done/tweak/redo/diff/test) are separate from gate decisions per D-037.

## Flagged Inconsistencies

All design-level inconsistencies have been resolved in design docs prior to this plan:
- Final gate semantics → D-037
- State step names → D-036
- Pipeline definitions location → D-035, `overview.md` updated
- Bypass invocation form → `escape-hatch.md` updated
- E7/E8 scope → D-038

**Remaining implementation notes (not design decisions):**
1. **Budget allocations:** `agents.md` defines Classifier budget as 20k, `context-budget.md` doesn't list Classifier separately. `agents.md` is authoritative for agent budgets.
2. **Parallel dispatch in Standard Pipeline:** pipelines.md shows Explorer + Analyst as parallel. Phase 3 supports this (two Agent calls in one message, both foreground). Implementation batches are sequential per AD-5.
3. **Telemetry schema install:** `install.sh` wildcard `cp schemas/*.yaml` auto-picks up `telemetry.schema.yaml`. Verification in install.sh should explicitly check for it.
