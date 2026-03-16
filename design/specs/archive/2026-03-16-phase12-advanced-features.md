# Phase 12: Advanced Features — Checkpoint/Resume, Epic Decomposition, Tweak/Redo, Version Migration

## Goal

Implement checkpoint/resume for interrupted tasks, epic decomposition execution, tweak/redo post-completion flows, version migration (`/moira upgrade`), passive audit checks, mechanical xref enforcement, and Tier 3 full bench testing. After Phase 12: long tasks survive session interruptions via checkpoint/resume with validated state restoration; epics execute as DAG-scheduled sub-tasks with parallel independent execution; completed tasks support targeted tweak and full redo with re-entry points; global layer upgrades use three-way conflict classification for safe migration; passive audit checks produce inline warnings during pipeline execution; agents consult the xref manifest before committing; Tier 3 bench runs full test suite across all fixtures.

**Why now:** This is the final phase. Phases 1-11 deliver a complete single-session pipeline with quality gates, reflection, metrics, and audit. Phase 12 adds resilience (resume), scale (epics), flexibility (tweak/redo), and maintenance (upgrade). These features require all prior infrastructure — state management, pipeline engine, quality gates, reflection, metrics, and audit.

## Risk Classification

**ORANGE (overall)** — Orchestrator skill modifications for checkpoint/resume and tweak/redo. New command implementations. New shell libraries. Pipeline flow changes for epic sub-task execution.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: Checkpoint Library | YELLOW | New shell library, additive |
| D2: Resume Command | ORANGE | Replaces placeholder, modifies orchestrator state handling |
| D3: Orchestrator Checkpoint Integration | ORANGE | Modifies orchestrator.md Section 2 and Section 7 |
| D4: Epic Execution Library | YELLOW | New shell library for DAG scheduling |
| D5: Epic Orchestrator Integration | ORANGE | Modifies orchestrator.md Section 2 (repeatable group handling for sub-pipelines) |
| D6: Tweak Flow | ORANGE | Adds tweak dispatch logic to orchestrator.md Section 7 |
| D7: Redo Flow | ORANGE | Adds redo dispatch logic to orchestrator.md Section 7 |
| D8: Upgrade Command + Library | YELLOW | New command and library, does not modify existing core |
| D9: Passive Audit Checks | ORANGE | Modifies orchestrator.md pipeline steps (pipeline flow changes) |
| D10: Xref Mechanical Enforcement | ORANGE | Modifies orchestrator.md Section 7 completion flow (pipeline flow changes) |
| D11: Tier 3 Bench | GREEN | New test cases and configuration, additive |
| D12: Tier 1 Tests | GREEN | New test files, additive |

## Design Sources

| Deliverable | Primary Source | Supporting Sources |
|-------------|---------------|-------------------|
| D1-D3: Checkpoint/Resume | `subsystems/checkpoint-resume.md` | `architecture/commands.md` (/moira resume), `schemas/manifest.schema.yaml` |
| D4-D5: Epic Decomposition | `architecture/pipelines.md` (Decomposition Pipeline) | `subsystems/checkpoint-resume.md` (Epic Checkpointing), `schemas/queue.schema.yaml` |
| D6-D7: Tweak/Redo | `architecture/tweak-redo.md` | `subsystems/fault-tolerance.md` (Tweak & Redo), `architecture/commands.md` (At Completion) |
| D8: Upgrade | `architecture/distribution.md` (/moira upgrade) | `architecture/commands.md` (/moira upgrade) |
| D9: Passive Audit | `subsystems/audit.md` (Passive Checks) | Phase 11 spec (deferred items) |
| D10: Xref Enforcement | D-077, D-093(g) | Phase 11 spec (deferred items) |
| D11: Tier 3 Bench | `subsystems/testing.md` (Tiered Testing) | `IMPLEMENTATION-ROADMAP.md` (Phase 12 Testing) |

## Deliverables

### D1: Checkpoint Library (`src/global/lib/checkpoint.sh`)

**What:** Shell library for checkpoint creation, validation, and manifest management.

**Functions:**

- `moira_checkpoint_create <task_id> <step> <reason> [state_dir]` — Create a checkpoint at the current pipeline position. Writes/updates `manifest.yaml` in the task directory with: current step, reason (context_limit/user_pause/error/session_end), resume_context, decisions made (from status.yaml gates), files modified (from git diff), git branch, git HEAD SHA. Called by orchestrator when checkpoint is triggered.

- `moira_checkpoint_validate <task_id> [state_dir]` — Validate checkpoint preconditions before resume. Three checks:
  1. **Artifact check:** `∀ step ∈ completed_steps: artifact_file(step) exists on disk`
  2. **Git consistency:** current branch matches `validation.git_branch`, HEAD is descendant of `validation.git_head_at_checkpoint` (allows new commits on top, rejects branch switches)
  3. **File integrity:** files listed in `files_modified` exist and match expected state (git diff against checkpoint HEAD)

  Returns structured result: `valid` (all checks pass), `inconsistent` (artifact or file mismatch — lists specifics), `branch_changed` (different branch), `external_changes` (files modified since checkpoint — lists which files).

- `moira_checkpoint_build_resume_context <task_id> [state_dir]` — Generate the `resume_context` block from task artifacts. Reads key decisions from gate records in status.yaml, key findings from completed step summaries in current.yaml history, and files modified from git diff. Produces a compressed human-readable summary optimized for orchestrator context (~200-500 tokens).

- `moira_checkpoint_cleanup <task_id> [state_dir]` — Remove checkpoint data after successful task completion. Deletes `manifest.yaml` from task directory. Called in Section 7 `done` flow.

**Validation model:** The three checks form a precondition set. Resume proceeds only when all three pass. Any failure produces a deterministic recovery path (re-explore, re-plan, explain) — never silent degradation.

### D2: Resume Command (`src/commands/moira/resume.md`)

**What:** Replace the placeholder with full implementation per `checkpoint-resume.md`.

**Flow:**
1. Read `state/current.yaml` — find last active task (or scan `state/tasks/*/manifest.yaml` if current.yaml is idle)
2. If no checkpoint found → display "No checkpointed tasks found"
3. Call `moira_checkpoint_validate <task_id>`
4. Route by validation result:
   - `valid` → display checkpoint summary, ask user to confirm resume
   - `inconsistent` → display inconsistency details, offer re-explore / re-plan / explain (per `checkpoint-resume.md` Resume Flow §5)
   - `branch_changed` → display branch mismatch, ask user to switch branch or abort
   - `external_changes` → display changed files, offer accept / revert / re-plan (per `checkpoint-resume.md` Resume Flow §6)
5. On confirmed resume: load `resume_context` + `plan.md` + `manifest.yaml` into orchestrator context, re-enter pipeline at checkpoint step

**Post-resume quality check:** After the first post-resume step completes, dispatch Themis (reviewer) for a quick integration check: does new work integrate with pre-resume work? Are contracts maintained? Style consistent? If issues found → flag before continuing.

**Allowed tools:** `Agent`, `Read`, `Write` (dispatch agents, read state, write updated state).

### D3: Orchestrator Checkpoint Integration

**What:** Modify `orchestrator.md` to support checkpoint creation and context-driven checkpointing.

**Changes to orchestrator.md:**

1. **Section 2 — Repeatable Group Handling:** When user chooses `checkpoint` at a phase/per-task gate:
   - Call `moira_checkpoint_create <task_id> <current_step> user_pause`
   - Set `current.yaml` step_status to `checkpointed`
   - Display: "Checkpoint saved. Resume with `/moira resume`."
   - Stop pipeline execution

2. **Section 6 — Budget Monitoring:** When context reaches `critical` (>60%):
   - Change from "recommendation" to "mandatory checkpoint" (per `checkpoint-resume.md` Checkpoint Triggers)
   - Call `moira_checkpoint_create <task_id> <current_step> context_limit`
   - Display warning with explicit instruction to resume in new session
   - Stop pipeline execution

3. **Section 7 — Completion Flow:** After `done` action, call `moira_checkpoint_cleanup <task_id>` to remove manifest if it exists.

4. **Section 2 — Pre-Pipeline Setup:** Add resume detection:
   - Check if `current.yaml` has `step_status: checkpointed`
   - If yes → display: "Task {task_id} was checkpointed at step {step}. Run `/moira resume` to continue."
   - Do NOT auto-resume — user must explicitly invoke `/moira resume` (Art 4.2)

### D4: Epic Execution Library (`src/global/lib/epic.sh`)

**What:** Shell library for epic task queue management and DAG-based sub-task scheduling.

**Functions:**

- `moira_epic_parse_queue <task_id> [state_dir]` — Read `queue.yaml` from decomposition output. Validate structure against `queue.schema.yaml`. Return parsed task list with dependency graph.

- `moira_epic_validate_dag <task_id> [state_dir]` — Validate the dependency graph is a DAG:
  1. Cycle detection via topological sort (Kahn's algorithm). If cycle found → return error with cycle path.
  2. All `depends_on` references point to existing task IDs.
  3. No self-dependencies.
  Returns: `valid` or `cycle_detected: [task_a → task_b → task_a]`.

- `moira_epic_next_tasks <task_id> [state_dir]` — Given current queue state, return tasks eligible for execution. A task is eligible when: `status == pending` AND `∀ dep ∈ depends_on: status(dep) == completed`. Returns list of eligible task IDs, sorted by dependency depth (tasks with fewer transitive dependencies first). Multiple eligible tasks can execute in parallel.

- `moira_epic_update_progress <task_id> <subtask_id> <new_status> [state_dir]` — Update sub-task status in `queue.yaml`. Recalculate `progress.*` counters.

- `moira_epic_check_dependencies <task_id> <subtask_id> [state_dir]` — Pre-start dependency check for a specific sub-task. Verifies `∀ dep ∈ task.depends_on: status(dep) == completed`. Returns `ready` or `blocked: [list of incomplete dependencies]`.

**DAG scheduling model:** Topological sort determines execution order. Independent tasks (no pending dependencies) are identified by `moira_epic_next_tasks` and can be dispatched in parallel. This reuses the same parallel dispatch mechanism as batch implementation (send multiple Agent calls in one message). The orchestrator calls `moira_epic_next_tasks` after each sub-task completion to find the next batch.

### D5: Epic Orchestrator Integration

**What:** Modify `orchestrator.md` to handle decomposition pipeline sub-task execution.

**Changes to orchestrator.md:**

1. **Section 2 — Repeatable Group Handling for Decomposition Pipeline:** When the `repeatable_group` in the decomposition pipeline has `role: sub-pipeline`:
   - After decomposition gate approval, call `moira_epic_validate_dag` → if cycle detected, display error and abort
   - Call `moira_epic_next_tasks` to get initial batch of independent sub-tasks
   - For each eligible sub-task:
     - Create sub-task state: `state/tasks/{subtask_id}/input.md` from decomposition artifact
     - Classify sub-task (dispatch Apollo) to determine pipeline type (standard/full)
     - Execute sub-task through its own pipeline (recursive: the orchestrator runs a nested pipeline)
   - Independent sub-tasks MAY execute in parallel if orchestrator context budget allows (display estimated parallel cost, ask user)
   - After each sub-task completion: call `moira_epic_update_progress`, present per-task gate, call `moira_epic_next_tasks` for next batch
   - On `checkpoint` at per-task gate: checkpoint the epic (includes queue.yaml state with per-subtask progress)

**Sub-pipeline execution model:** Each sub-task runs as a nested invocation of the orchestrator's main loop (Section 2) with the sub-task's classified pipeline type. The orchestrator re-enters its own pipeline execution loop with the sub-task's pipeline definition. Budget tracking is cumulative — sub-task agent dispatches count toward the epic's total orchestrator context. The orchestrator monitors its own context level across all sub-task executions and triggers mandatory checkpoint if >60% is reached at any point during epic execution.

2. **Queue file location:** Decomposition pipeline writes per-epic queue data to `state/tasks/{epic_task_id}/queue.yaml` (per-task scope, consistent with other task artifacts). The global `state/queue.yaml` (as defined in `queue.schema.yaml` `_meta.location`) serves as a pointer to the active epic task ID for `/moira resume` discovery. Schema `_meta.location` documents the global pointer; per-task queue is a working copy within the task directory. Both use the same field structure — the schema validates either.

### D6: Tweak Flow

**What:** Implement the tweak completion action in `orchestrator.md` Section 7, per `tweak-redo.md`.

**Tweak pipeline:**
1. User chooses `tweak` at final gate
2. User describes what needs changing
3. Dispatch Hermes (explorer) — quick exploration to identify affected files
4. **Scope check:** Compare tweak-affected files against original task's file set.
   - `tweak_files ⊆ task_files ∪ directly_connected(task_files)` → proceed
   - Otherwise → display: "This changes scope beyond original task. Recommend separate task." Offer `force-tweak` / `new-task`
5. Dispatch Hephaestus (implementer) with: original plan context + current file state + tweak description + scope limits
6. Dispatch Themis (reviewer) — reviews ONLY changed lines + integration points
7. Dispatch Aletheia (tester) — updates affected tests
8. Present final gate again (user can tweak again, done, or redo)
9. Increment `completion.tweak_count` in status.yaml

**Scope check implementation:** Explorer returns list of files the tweak would touch. Orchestrator compares against the task's modified files (determined via `git diff` against the pre-task HEAD stored in status.yaml `git.pre_task_head`). If tweak touches files NOT in the original set AND those files are not direct imports/dependents of original files → out of scope. Note: file list is computed from git diff, not a stored field — avoids adding a new field to status.schema.yaml.

### D7: Redo Flow

**What:** Implement the redo completion action in `orchestrator.md` Section 7, per `tweak-redo.md`.

**Redo pipeline:**
1. User chooses `redo` at final gate
2. User provides reason for redo
3. User chooses re-entry point: `architecture` / `plan` / `implement`
4. **Git revert:** Dispatch Hephaestus (implementer) to run `git revert` on task commits (D-001 compliance — orchestrator never runs commands). The implementer receives: list of commits to revert, instruction to revert in correct order.
5. **Archive previous attempt:** Rename artifacts to versioned names:
   - `architecture.md` → `architecture-v{N}.md` (marked "rejected: {reason}")
   - `plan.md` → `plan-v{N}.md`
   - Implementation artifacts → discarded (code reverted)
6. **Re-enter pipeline at chosen point:**
   - `architecture`: re-dispatch Metis with original exploration + analysis + REJECTED approach with reason + user constraints → continue through architecture gate
   - `plan`: re-dispatch Daedalus with original architecture + REJECTED plan + user constraints → continue through plan gate
   - `implement`: re-dispatch implementation with original plan → continue through implementation
7. Pipeline continues normally from re-entry point
8. Increment `completion.redo_count` in status.yaml

**Re-entry point preservation (from `tweak-redo.md`):**

| Re-entry | Preserved | Re-done |
|----------|-----------|---------|
| architecture | exploration + analysis | architecture + plan + implementation |
| plan | exploration + analysis + architecture | plan + implementation |
| implement | exploration + analysis + architecture + plan | implementation only |

**Knowledge capture:** Every redo writes a failure entry to `knowledge/failures/`:
```markdown
## [{task_id}-v{N}] {approach} rejected
CONTEXT: {task description}
APPROACH: {architecture summary}
REJECTED BECAUSE: {user reason}
LESSON: {extracted from reason}
APPLIES TO: {scope}
```

### D8: Upgrade Command + Library

**What:** Implement `/moira upgrade` command and supporting library per `distribution.md`.

#### D8a: Upgrade Library (`src/global/lib/upgrade.sh`)

**Functions:**

- `moira_upgrade_check_version` — Compare installed version (`~/.claude/moira/.version`) against source version (`$MOIRA_SOURCE/.version`). Returns: `current`, `available`, `is_newer` (boolean).

- `moira_upgrade_diff_files <old_dir> <new_dir>` — List files that changed between versions. For each changed file, classify using three-way comparison:
  - `auto_apply`: file unchanged in project (project == old_global) AND changed in new version → safe to update
  - `keep_project`: file customized in project (project != old_global) AND unchanged in new version → keep project version
  - `conflict`: file customized in project AND changed in new version → needs manual resolution
  - `new_file`: file exists only in new version → safe to add
  - `removed`: file exists in old but not new → flag for review

  Three-way logic: `base` = old global version (stored at `~/.claude/moira/.version-snapshot/` during install), `project` = current project layer files, `new` = new global version files.

- `moira_upgrade_apply <change_list>` — Apply safe changes (auto_apply + new_file). Skip conflicts (keep_project files). Returns list of applied vs skipped.

- `moira_upgrade_snapshot <dir>` — Save current global layer as version snapshot for future three-way comparisons. Copies `~/.claude/moira/core/` and `~/.claude/moira/skills/` to `~/.claude/moira/.version-snapshot/`.

#### D8b: Upgrade Command (`src/commands/moira/upgrade.md`)

**What:** New command file for `/moira upgrade`.

**Flow:**
1. Check current version vs available version
2. If already latest → "Moira is up to date (v{version})"
3. Display changelog summary (from new version's CHANGELOG.md if present, or git log between versions)
4. Call `moira_upgrade_diff_files` → categorize all changes
5. Display upgrade gate:
   ```
   ═══════════════════════════════════════════
    MOIRA UPGRADE — v{old} → v{new}
   ═══════════════════════════════════════════
    Changes:
    ├─ {N} files auto-apply (safe)
    ├─ {N} files keep project version (customized)
    ├─ {N} conflicts (both changed)
    └─ {N} new files

    ▸ apply  — upgrade (safe changes only)
    ▸ diff   — show detailed file changes
    ▸ skip   — stay on current version
   ═══════════════════════════════════════════
   ```
6. On `apply`: call `moira_upgrade_apply`, call `moira_upgrade_snapshot`, update `.version`
7. Post-upgrade: recommend `/moira audit` to verify consistency

**Allowed tools:** `Agent`, `Read`, `Write`, `Bash` (needs Bash for file comparison and copy operations during upgrade).

**Version pinning:** If `config.yaml` has `moira.auto_upgrade: false` and `moira.version` is pinned → display warning and require explicit confirmation to upgrade past pinned version.

### D9: Passive Audit Checks

**What:** Inline audit warnings during pipeline execution (deferred from Phase 11 spec).

**Changes to orchestrator.md:**

Three passive check points inserted into the pipeline:

1. **On task start (Section 2, after pre-pipeline setup):**
   - Check `config/locks.yaml` for stale locks (expired TTL) → display warning if found (informational only — lock system is post-v1 per D-068, but the check costs nothing)
   - Check `state/current.yaml` for orphaned in-progress state → display warning, offer cleanup

2. **After Explorer completes (Section 2, after exploration step):**
   - Compare Explorer findings against `knowledge/project-model/summary.md` for contradictions
   - If Explorer reports different structure/stack than knowledge says → display: "⚠ Knowledge drift detected: Explorer found {X}, knowledge says {Y}. Consider `/moira refresh`."
   - Non-blocking — continue pipeline. Warning is recorded in status.yaml `warnings[]`

3. **After Reviewer completes (Section 2, after review step):**
   - If Reviewer findings mention convention violations that contradict `knowledge/conventions/summary.md` → display: "⚠ Convention drift: Reviewer found patterns inconsistent with documented conventions."
   - Non-blocking. Recorded in status.yaml `warnings[]`

**Cost:** Near-zero. These are Read operations on small files (~200 tokens each) with string comparison. No agent dispatch.

### D10: Xref Mechanical Enforcement

**What:** Agents consult xref manifest before committing (deferred from Phase 11).

**Changes to orchestrator.md Section 7:**

After implementation completes and before presenting the final gate:

1. Read `~/.claude/moira/core/xref-manifest.yaml`
2. For each `value_must_match` and `enum_must_match` entry: check if any files in the entry's `dependents` list were modified in this task (determined via git diff against pre-task HEAD)
3. If a dependent file was modified: verify the modified values still match the canonical source
4. If mismatch found → display warning at final gate:
   ```
   ⚠ XREF CONSISTENCY WARNING
   Modified: src/global/lib/budget.sh
   Canonical: src/schemas/budgets.schema.yaml
   Field: _MOIRA_BUDGET_DEFAULTS_*
   Issue: budget values in budget.sh don't match schema defaults

   ▸ fix — dispatch implementer to synchronize
   ▸ ignore — proceed (inconsistency remains)
   ```
5. On `fix`: dispatch Hephaestus with xref context to synchronize the files

**Scope:** Only applies to Moira system files (files listed in xref-manifest.yaml). Does not affect project source code. This is a post-implementation check, not a pre-commit hook — it runs within the orchestrator's final gate presentation.

### D11: Tier 3 Full Bench

**What:** Complete the Tier 3 bench test suite for full-matrix testing.

**Files:**
- Additional test cases in `src/tests/bench/cases/` covering:
  - All cells in the test matrix (testing.md §Test Matrix) not covered by Tier 2
  - Failure path overlays: gate_rejection, agent_blocked, reviewer_critical→retry, budget_exceeded
  - Epic decomposition test case (with sub-task dependencies)
  - Checkpoint/resume test case (simulate session interruption)
  - Tweak test case (post-completion modification)
  - Redo test case (rollback and re-entry)

- `src/tests/bench/tier3-config.yaml` — Tier 3 specific configuration:
  ```yaml
  tier: 3
  budget:
    max_tokens: 300000
    max_tests: 30
    warn_at: 200000
  trigger_matrix:
    - pipeline_flow_change
    - gate_logic_change
    - agent_role_boundary
    - orchestrator_skill
    - rules_assembly_logic
    - new_agent_type
    - constitution_amendment
    - major_version_release
  ```

**Test case additions for Phase 12 features:**

- `tier3-checkpoint-resume.yaml`: Task that triggers checkpoint at 60% context, validates resume in fresh session, verifies post-resume quality check
- `tier3-epic-decomposition.yaml`: Epic with 3 sub-tasks (1 independent, 2 dependent), verifies DAG scheduling and parallel execution
- `tier3-tweak.yaml`: Standard task completion followed by tweak (within scope) and tweak (out of scope — verify recommendation)
- `tier3-redo.yaml`: Standard task completion followed by redo at each re-entry point (architecture, plan, implement)

### D12: Tier 1 Tests

**What:** Structural verification tests for Phase 12 artifacts.

**Files:**

- `src/tests/tier1/test-checkpoint-resume.sh` — Tests:
  - checkpoint.sh library exists and defines expected functions
  - manifest.schema.yaml is valid and matches checkpoint.sh field expectations
  - resume.md command is not a placeholder
  - resume.md has correct allowed-tools (Agent, Read, Write)

- `src/tests/tier1/test-epic.sh` — Tests:
  - epic.sh library exists and defines expected functions
  - queue.schema.yaml is valid and matches epic.sh field expectations
  - Decomposition pipeline definition references repeatable_group with role: sub-pipeline

- `src/tests/tier1/test-tweak-redo.sh` — Tests:
  - orchestrator.md contains tweak flow logic (not placeholder text)
  - orchestrator.md contains redo flow logic (not placeholder text)
  - orchestrator.md contains knowledge/failures/ write for redo

- `src/tests/tier1/test-upgrade.sh` — Tests:
  - upgrade.sh library exists and defines expected functions
  - upgrade.md command exists and is not a placeholder
  - upgrade.md has correct allowed-tools

- `src/tests/tier1/test-passive-audit.sh` — Tests:
  - orchestrator.md contains passive audit check points (stale locks, knowledge drift, convention drift)

## Dependencies on Previous Phases

| Dependency | Phase | Status | What's Used |
|-----------|-------|--------|-------------|
| State management | 1 | Done | state.sh, yaml-utils.sh, manifest.schema.yaml, queue.schema.yaml |
| Pipeline engine | 3 | Done | orchestrator.md, pipeline definitions, gate system |
| Agent dispatch | 3 | Done | dispatch.md, agent tool calls |
| Knowledge system | 4 | Done | knowledge read/write, freshness markers |
| Quality gates | 6 | Done | Reviewer dispatch, quality checklists |
| Budget tracking | 7 | Done | budget.sh, context monitoring |
| Hooks | 8 | Done | guard.sh, violation detection |
| Reflection | 10 | Done | Reflector dispatch, pattern tracking |
| Metrics | 11 | Done | metrics.sh, collect_task |
| Audit | 11 | Done | audit.sh, audit templates, Argus |
| Xref manifest | 11 | Done | xref-manifest.yaml, Tier 1 xref tests |

## Files Created

| File | Type | Description |
|------|------|-------------|
| `src/global/lib/checkpoint.sh` | Shell library | Checkpoint create, validate, resume context |
| `src/global/lib/epic.sh` | Shell library | Epic DAG scheduling, queue management |
| `src/global/lib/upgrade.sh` | Shell library | Version comparison, three-way diff, migration |
| `src/commands/moira/upgrade.md` | Command | /moira upgrade implementation |
| `src/tests/tier1/test-checkpoint-resume.sh` | Test | Tier 1 tests for checkpoint/resume |
| `src/tests/tier1/test-epic.sh` | Test | Tier 1 tests for epic execution |
| `src/tests/tier1/test-tweak-redo.sh` | Test | Tier 1 tests for tweak/redo |
| `src/tests/tier1/test-upgrade.sh` | Test | Tier 1 tests for upgrade |
| `src/tests/tier1/test-passive-audit.sh` | Test | Tier 1 tests for passive audit checks |
| `src/tests/bench/cases/tier3-checkpoint-resume.yaml` | Bench test | Tier 3 checkpoint/resume test case |
| `src/tests/bench/cases/tier3-epic-decomposition.yaml` | Bench test | Tier 3 epic decomposition test case |
| `src/tests/bench/cases/tier3-tweak.yaml` | Bench test | Tier 3 tweak test case |
| `src/tests/bench/cases/tier3-redo.yaml` | Bench test | Tier 3 redo test case |
| `src/tests/bench/tier3-config.yaml` | Config | Tier 3 bench configuration |

## Files Modified

| File | Change | Reason |
|------|--------|--------|
| `src/commands/moira/resume.md` | Replace placeholder with full implementation | D2 |
| `src/global/skills/orchestrator.md` | Section 2: add checkpoint detection, resume redirect, passive audit checks, epic sub-pipeline handling. Section 6: mandatory checkpoint at >60%. Section 7: add tweak flow, redo flow, checkpoint cleanup, xref enforcement | D3, D5, D6, D7, D9, D10 |
| `src/global/skills/gates.md` | Add 4 gate templates: (1) tweak scope gate (in-scope/force-tweak/new-task options), (2) redo re-entry gate (architecture/plan/implement selection + reason prompt), (3) xref warning gate (fix/ignore per inconsistency), (4) passive audit inline warning format (non-blocking, no options, recorded in status.yaml). Update completion gate documentation to reference tweak/redo flows | D6, D7, D9, D10 |
| `src/global/skills/errors.md` | Add E4-BUDGET critical level routing: when orchestrator context >60%, route to mandatory checkpoint flow instead of spawn-continuation flow. Add DAG cycle handling: when `moira_epic_validate_dag` returns `cycle_detected`, display cycle path to user and abort epic (no retry — Planner must fix decomposition). Note: resume validation failures are handled by the resume command itself, not by errors.md (command-level, not pipeline-level errors) | D3, D5 |
| `src/schemas/current.schema.yaml` | Add `checkpointed` to `step_status` enum (currently: pending, in_progress, awaiting_gate, completed, failed) | D3 |
| `src/global/lib/state.sh` | Add `checkpointed` to `valid_statuses` in `moira_state_transition()` (line 75: currently missing from validated set) | D3 |
| `src/global/lib/scaffold.sh` | Add `mkdir -p ".version-snapshot"` to `moira_scaffold_global()` for upgrade version snapshot storage | D8 |
| `src/install.sh` | Add checkpoint.sh, epic.sh, upgrade.sh to install, add upgrade.md command, add Tier 3 bench config, call `moira_upgrade_snapshot` after global layer install to create initial version snapshot, verify new files | D1, D4, D8 |
| `src/tests/tier1/run-all.sh` | Add Phase 12 test files to test runner | D12 |
| `src/tests/tier1/test-file-structure.sh` | Add Phase 12 artifact checks (checkpoint.sh, epic.sh, upgrade.sh, upgrade.md) | D12 |
| `src/tests/tier1/test-install.sh` | Add Phase 12 installation verification | D12 |
| `design/architecture/overview.md` | Add `lib/checkpoint.sh`, `lib/epic.sh`, `lib/upgrade.sh`, `.version-snapshot/` to file tree | New files in canonical structure |

## Success Criteria

1. Checkpoint created at phase gate (user chooses `checkpoint`) contains valid manifest with resume_context
2. Checkpoint created automatically at >60% context contains valid manifest
3. `/moira resume` validates state and continues from exact checkpoint position
4. `/moira resume` detects and reports inconsistencies (missing artifacts, branch change, external modifications)
5. Post-resume quality check (Reviewer integration check) runs after first resumed step
6. Epic decomposition creates valid DAG of sub-tasks
7. Epic sub-tasks execute in dependency order, with independent tasks eligible for parallel execution
8. Cycle detection catches invalid dependency graphs before execution
9. Tweak flow: scope check identifies in-scope vs out-of-scope tweaks correctly
10. Tweak flow: implementer modifies only described changes, reviewer checks integration
11. Redo flow: git revert via implementer agent (not orchestrator direct command)
12. Redo flow: re-entry at each point (architecture/plan/implement) preserves correct artifacts
13. Redo flow: failure entry written to knowledge/failures/
14. `/moira upgrade` performs three-way conflict classification correctly
15. `/moira upgrade` auto-applies safe changes, flags conflicts
16. Passive audit checks produce inline warnings without blocking pipeline
17. Xref enforcement detects cross-file inconsistencies at final gate
18. Tier 3 bench test cases exist and cover Phase 12 features
19. All existing Tier 1 tests continue to pass (regression check)

## Deferred / Out of Scope

1. **Multi-developer lock system** — Deferred to post-v1 per D-068. Branch isolation is the interim solution. The design in `multi-developer.md` is preserved for future implementation. Passive stale lock check (D9) is included as zero-cost preparatory infrastructure.

2. **Parallel epic sub-task execution** — The DAG scheduling identifies independent tasks, but parallel execution of sub-pipelines is offered as an option, not default. Each sub-pipeline is a full pipeline run that consumes significant orchestrator context. Default is sequential with parallel as user-approved option when context budget allows.

3. **Automatic conflict resolution in upgrade** — Three-way diff classifies conflicts but does not attempt automatic merge. Conflicts are flagged for manual resolution. Automatic merge would require content-level diff understanding that's better handled by the user or a dedicated agent in a future version.

## New Decision Log Entries Required

- **D-094: Phase 12 Architectural Choices** — covers:
  - (a) Mandatory checkpoint at >60% context (upgrade from "recommendation" to "mandatory" per checkpoint-resume.md Checkpoint Triggers table). This is a behavioral change in the orchestrator — current Section 6 says "offer checkpoint", new behavior forces it.
  - (b) Version snapshot for three-way upgrade comparison stored at `~/.claude/moira/.version-snapshot/`. Created during install and updated during upgrade.
  - (c) Epic sub-task parallel execution is user-approved option, not default. Rationale: each sub-pipeline consumes significant orchestrator context; sequential is safer.
  - (d) Tweak scope check uses file set containment (`tweak_files ⊆ task_files ∪ directly_connected`). "Directly connected" means files that import from or are imported by task files.
  - (e) Redo git revert dispatches a dedicated Hephaestus agent (not re-using the implementation agent) to maintain clear separation — this is a "revert operation" not an "implementation operation". Hephaestus receives explicit revert instructions.
  - (f) Passive audit checks are non-blocking warnings recorded in status.yaml `warnings[]`. They never stop the pipeline.
  - (g) Xref mechanical enforcement runs at final gate (post-implementation, pre-user-review), not as a pre-commit hook. Rationale: pre-commit hooks fire per tool call (performance concern per D-072); final gate check fires once per pipeline.
  - (h) Post-resume quality check dispatches Themis (reviewer) for integration review after first post-resume step. This is a single extra agent dispatch per resume, bounded cost.
  - (i) Epic sub-pipeline execution is a recursive invocation of the orchestrator's main loop (Section 2) with the sub-task's pipeline definition. Budget tracking is cumulative across all sub-task executions within the epic. No separate orchestrator context per sub-task — the same orchestrator session manages all sub-tasks sequentially (or parallel if user approves).

## Constitutional Compliance

```
ARTICLE 1: Separation of Concerns
Art 1.1 OK  Orchestrator never runs git commands directly. Git revert in redo
            is dispatched via Hephaestus (implementer) agent. Resume command
            uses Agent tool for validation explorer. Upgrade command uses Bash
            only for file copy operations within ~/.claude/moira/ (not project).
Art 1.2 OK  No agent NEVER constraints weakened. Hephaestus receives explicit
            revert instructions — does not make decisions about WHAT to revert.
            Hermes (explorer) in tweak scope check — reports facts only.
Art 1.3 OK  Checkpoint, epic, upgrade are separate libraries. No god components.

ARTICLE 2: Determinism
Art 2.1 OK  No pipeline selection changes. Epic sub-tasks classified individually.
Art 2.2 OK  No gates removed. Tweak and redo add gates (scope check, re-entry).
            Checkpoint is a gate option already defined in pipeline YAML.
Art 2.3 OK  Resume validation is deterministic (3 checks, explicit outcomes).
            DAG scheduling is deterministic (topological sort).
            Three-way upgrade classification is deterministic.

ARTICLE 3: Transparency
Art 3.1 OK  Checkpoint creates manifest.yaml. Resume logs validation result.
            Epic progress tracked in queue.yaml. Tweak/redo updates status.yaml.
Art 3.2 OK  Budget report unchanged. Checkpoint includes context level.
Art 3.3 OK  Resume inconsistencies displayed to user with options.
            Passive audit warnings displayed inline. Xref warnings at gate.
            Upgrade conflicts displayed before applying.

ARTICLE 4: Safety
Art 4.1 OK  No fabrication. Resume context built from actual artifacts.
Art 4.2 OK  User must explicitly invoke /moira resume (no auto-resume).
            User approves upgrade changes. User confirms redo.
            Mandatory checkpoint at >60% stops pipeline but user decides when
            to resume — this is safety, not overriding user authority.
Art 4.3 OK  Redo uses git revert (reversible). Checkpoint is non-destructive.
            Upgrade creates version snapshot before applying (rollback possible).
Art 4.4 OK  No escape hatch interaction.

ARTICLE 5: Knowledge Integrity
Art 5.1 OK  Redo failure entries include evidence (task ID, rejected approach, reason).
Art 5.2 OK  No rule change proposals from Phase 12 features.
Art 5.3 OK  Redo failure entries are new knowledge — consistency check applies.

ARTICLE 6: Self-Protection
Art 6.1 OK  No code path modifies CONSTITUTION.md.
Art 6.2 OK  This spec written before implementation.
Art 6.3 OK  Tier 1 tests added. Xref enforcement strengthens invariant verification.
```
