# Phase 12: Implementation Plan

**Spec:** `design/specs/2026-03-16-phase12-advanced-features.md`
**Date:** 2026-03-16

## Chunk Overview

```
Chunk 1: Schema + State Updates (no dependencies)
Chunk 2: Checkpoint Library (depends on Chunk 1 schema)
Chunk 3: Epic Execution Library (depends on Chunk 1 schema)
Chunk 4: Upgrade Library (no dependency on Chunks 2-3)
Chunk 5: Gates + Errors Skill Updates (no dependency on Chunks 2-4)
Chunk 6: Orchestrator — Checkpoint + Passive Audit (depends on Chunks 2, 5)
Chunk 7: Orchestrator — Epic Integration (depends on Chunks 3, 5, 6)
Chunk 8: Orchestrator — Tweak + Redo + Xref (depends on Chunks 5, 6)
Chunk 9: Commands — Resume + Upgrade (depends on Chunks 2, 4, 6)
Chunk 10: Install + Scaffold + Overview (depends on Chunks 2, 3, 4)
Chunk 11: Tier 3 Bench Tests (depends on Chunks 6, 7, 8)
Chunk 12: Tier 1 Tests + Regression (depends on all previous chunks)
```

---

## Chunk 1: Schema + State Updates

**Goal:** Update existing schemas and state library for Phase 12 new enum values.

### Task 1.1: Add `checkpointed` to current.schema.yaml
- **File:** `src/schemas/current.schema.yaml`
- **Source:** Spec D3 §1, line 92
- **Key points:**
  - Add `checkpointed` to `step_status` enum (line 34): `[pending, in_progress, awaiting_gate, completed, failed, checkpointed]`
  - No other fields change
- **Commit:** `moira(checkpoint): add checkpointed status to current.yaml schema`

### Task 1.2: Add `checkpointed` to state.sh valid_statuses
- **File:** `src/global/lib/state.sh`
- **Source:** Spec D3, Files Modified table
- **Key points:**
  - In `moira_state_transition()` (line 75), add `checkpointed` to `valid_statuses` string
  - Currently: `"pending in_progress awaiting_gate completed failed"`
  - New: `"pending in_progress awaiting_gate completed failed checkpointed"`
- **Commit:** `moira(checkpoint): add checkpointed to state.sh valid statuses`

### Task 1.3: Add `.version-snapshot` to scaffold.sh
- **File:** `src/global/lib/scaffold.sh`
- **Source:** Spec D8, Files Modified table
- **Key points:**
  - Add `mkdir -p "$target_dir"/.version-snapshot` to `moira_scaffold_global()` after line 32 (last `mkdir`), before the closing `}`
- **Commit:** `moira(pipeline): add version-snapshot directory to global scaffold`

---

## Chunk 2: Checkpoint Library

**Goal:** Create checkpoint.sh with create, validate, build_resume_context, cleanup functions.

### Task 2.1: Create checkpoint.sh
- **File:** `src/global/lib/checkpoint.sh`
- **Source:** Spec D1, `subsystems/checkpoint-resume.md`
- **Key points:**
  - Source yaml-utils.sh from same directory (same pattern as state.sh)
  - `moira_checkpoint_create <task_id> <step> <reason> [state_dir]`:
    - Read `status.yaml` gates block for decisions_made
    - Run `git rev-parse --abbrev-ref HEAD` for git_branch
    - Run `git rev-parse HEAD` for git_head_at_checkpoint
    - Run `git diff --name-only HEAD~N` (where N = commits since task start) for files_modified
    - Call `moira_checkpoint_build_resume_context` for resume_context
    - Write all to `state/tasks/{task_id}/manifest.yaml` using `moira_yaml_set`
    - Fields match `manifest.schema.yaml`: task_id, pipeline (from current.yaml), developer, checkpoint.step, checkpoint.batch (null unless batch info available), checkpoint.created_at (ISO 8601), checkpoint.reason, resume_context, decisions_made, files_modified, files_expected (null), dependencies (null), validation.git_branch, validation.git_head_at_checkpoint, validation.external_changes_expected (false)
  - `moira_checkpoint_validate <task_id> [state_dir]`:
    - Read manifest.yaml
    - Check 1 (artifacts): For each step in `current.yaml` history with status=success, verify artifact file exists in `state/tasks/{task_id}/`
    - Check 2 (git): Compare `git rev-parse --abbrev-ref HEAD` against validation.git_branch. Use `git merge-base --is-ancestor` to check HEAD is descendant
    - Check 3 (files): `git diff --name-only {checkpoint_head}` — if non-empty AND validation.external_changes_expected is false → external_changes
    - Return: echo one of `valid`, `inconsistent:{details}`, `branch_changed:{expected}:{actual}`, `external_changes:{file_list}`
  - `moira_checkpoint_build_resume_context <task_id> [state_dir]`:
    - Read status.yaml gates for key decisions
    - Read current.yaml history for step summaries
    - Build multi-line string: "Task: {description}. Pipeline: {type}. Completed: {steps}. Key decisions: {decisions}. Continue from: {step}."
    - Target ~200-500 tokens
  - `moira_checkpoint_cleanup <task_id> [state_dir]`:
    - `rm -f state/tasks/{task_id}/manifest.yaml`
- **Commit:** `moira(checkpoint): implement checkpoint library`

---

## Chunk 3: Epic Execution Library

**Goal:** Create epic.sh with DAG validation, next-task scheduling, progress tracking.

### Task 3.1: Create epic.sh
- **File:** `src/global/lib/epic.sh`
- **Source:** Spec D4, `architecture/pipelines.md` (Decomposition Pipeline), `schemas/queue.schema.yaml`
- **Key points:**
  - Source yaml-utils.sh from same directory
  - `moira_epic_parse_queue <task_id> [state_dir]`:
    - Read `state/tasks/{task_id}/queue.yaml`
    - Validate required fields: epic_id, tasks block
    - Output parsed task list (id, description, size, status, depends_on per task)
  - `moira_epic_validate_dag <task_id> [state_dir]`:
    - Parse queue, extract task IDs and depends_on edges
    - Kahn's algorithm in bash:
      - Build in-degree count per node
      - Initialize queue with zero-in-degree nodes
      - Process: dequeue, decrement dependents' in-degrees, enqueue new zeros
      - If processed count < total nodes → cycle exists
    - Check all depends_on references are valid task IDs
    - Check no self-references
    - Return: echo `valid` or `cycle_detected:{path}`
  - `moira_epic_next_tasks <task_id> [state_dir]`:
    - Parse queue, find tasks where status=pending AND all depends_on tasks have status=completed
    - Sort by transitive dependency depth (fewest deps first)
    - Output eligible task IDs, one per line
  - `moira_epic_update_progress <task_id> <subtask_id> <new_status> [state_dir]`:
    - Update subtask status in queue.yaml using moira_yaml_set
    - Recalculate progress.completed, progress.in_progress, progress.pending, progress.failed
  - `moira_epic_check_dependencies <task_id> <subtask_id> [state_dir]`:
    - Find subtask's depends_on list
    - Check each dependency status
    - Return: echo `ready` or `blocked:{incomplete_deps}`
- **Commit:** `moira(pipeline): implement epic DAG scheduling library`

---

## Chunk 4: Upgrade Library

**Goal:** Create upgrade.sh with version comparison, three-way diff, snapshot functions.

### Task 4.1: Create upgrade.sh
- **File:** `src/global/lib/upgrade.sh`
- **Source:** Spec D8a, `architecture/distribution.md` (/moira upgrade)
- **Key points:**
  - `moira_upgrade_check_version`:
    - Read `~/.claude/moira/.version` (installed)
    - Read `$MOIRA_SOURCE/.version` (new source, env var or arg)
    - Compare semver: split on `.`, compare major/minor/patch numerically
    - Output: `current={X} available={Y} is_newer={true|false}`
  - `moira_upgrade_diff_files <old_dir> <new_dir>`:
    - `old_dir` = `~/.claude/moira/.version-snapshot/` (base)
    - `new_dir` = new source directory
    - For project-layer comparison: `project_dir` = `~/.claude/moira/` (current installed)
    - Walk all files in old_dir, new_dir, project_dir
    - Per-file three-way classification:
      - `auto_apply`: `diff -q project old` succeeds (identical) AND `diff -q old new` fails (changed) → safe update
      - `keep_project`: `diff -q project old` fails (customized) AND `diff -q old new` succeeds (unchanged) → keep
      - `conflict`: `diff -q project old` fails AND `diff -q old new` fails → both changed
      - `new_file`: file in new_dir but not old_dir
      - `removed`: file in old_dir but not new_dir
    - Output: classification per file, one per line: `{classification}\t{filepath}`
  - `moira_upgrade_apply <change_list_file>`:
    - Read file with classification+path pairs
    - For `auto_apply`: `cp -f "$new_dir/$path" "$project_dir/$path"`
    - For `new_file`: `cp -f "$new_dir/$path" "$project_dir/$path"` (mkdir -p parent if needed)
    - Skip `keep_project`, `conflict`, `removed`
    - Output: count applied, count skipped, list of conflicts
  - `moira_upgrade_snapshot <dir>`:
    - `rm -rf "$dir/.version-snapshot"`
    - `mkdir -p "$dir/.version-snapshot"`
    - `cp -r "$dir/core" "$dir/.version-snapshot/core"`
    - `cp -r "$dir/skills" "$dir/.version-snapshot/skills"`
    - Copy other tracked dirs (templates, schemas, lib, hooks) for future three-way
- **Commit:** `moira(pipeline): implement upgrade library with three-way diff`

---

## Chunk 5: Gates + Errors Skill Updates

**Goal:** Add new gate templates and error handling for Phase 12 flows.

### Task 5.1: Add new gate templates to gates.md
- **File:** `src/global/skills/gates.md`
- **Source:** Spec D6, D7, D9, D10, Files Modified table
- **Key points:**
  - Add after Per-Task Gate section (before Final Gate):
  - **Tweak Scope Gate** — presented when tweak scope check detects out-of-scope files:
    ```
    ═══════════════════════════════════════════
     TWEAK: Scope Check
    ═══════════════════════════════════════════
     Tweak would modify files outside original task scope:
     {list of out-of-scope files}

     Original task modified: {list of in-scope files}

     1) force-tweak — apply tweak anyway (may cause inconsistencies)
     2) new-task    — create separate task for out-of-scope changes
     3) cancel      — keep current result
    ═══════════════════════════════════════════
    ```
  - **Redo Re-entry Gate** — presented when user chooses redo at final gate:
    ```
    ═══════════════════════════════════════════
     REDO — Choose Re-entry Point
    ═══════════════════════════════════════════
     What prompted the redo?
     > {user reason}

     Re-enter pipeline at:
     1) architecture — change approach entirely (preserves exploration + analysis)
     2) plan         — keep architecture, change execution plan
     3) implement    — keep plan, re-implement from scratch
     4) cancel       — keep current result
    ═══════════════════════════════════════════
    ```
  - **Xref Warning Gate** — presented when xref inconsistency found at final gate:
    ```
    ═══════════════════════════════════════════
     ⚠ XREF CONSISTENCY WARNING
    ═══════════════════════════════════════════
     {per-inconsistency block:}
     Modified: {dependent_file}
     Canonical: {canonical_source}
     Field: {field}
     Issue: {description of mismatch}

     1) fix    — dispatch Hephaestus (implementer) to synchronize
     2) ignore — proceed (inconsistency remains)
    ═══════════════════════════════════════════
    ```
  - **Passive Audit Warning** — inline, non-blocking, no gate ID:
    ```
    ⚠ {warning_type}: {description}
    {details if any}
    (Non-blocking — recorded in status.yaml warnings)
    ```
    Warning types: `STALE LOCKS`, `ORPHANED STATE`, `KNOWLEDGE DRIFT`, `CONVENTION DRIFT`
  - Update Final Gate section documentation to note that `tweak` triggers tweak pipeline (spec D6) and `redo` triggers redo pipeline (spec D7) — cross-reference to orchestrator.md Section 7
  - **Gate decision mapping:** New gates record decisions using existing `proceed/modify/abort` enum per gates.md Gate State Management (lines 420-422) pattern. Mapping: `force-tweak` → `proceed` (note: "force-tweak"), `new-task` → `modify` (note: "new-task recommended"), `cancel` → `abort`. Redo: `architecture/plan/implement` → `proceed` (note: "re-entry: {point}"). Xref: `fix` → `modify`, `ignore` → `proceed`. Passive audit: non-blocking, no gate state recorded.
- **Commit:** `moira(pipeline): add tweak, redo, xref, passive audit gate templates`

### Task 5.2: Update errors.md for Phase 12
- **File:** `src/global/skills/errors.md`
- **Source:** Spec D3, D5, Files Modified table
- **Key points:**
  - In E4-BUDGET section, add **Critical Level Override** subsection:
    - When `context_budget.warning_level` is `critical` (>60%), E4-BUDGET recovery changes:
    - Instead of "spawn continuation agent" → route to mandatory checkpoint flow
    - Call `moira_checkpoint_create <task_id> <current_step> context_limit`
    - Display context warning with mandatory checkpoint message
    - Stop pipeline — user must resume in new session via `/moira resume`
    - This overrides the default E4-BUDGET mid-exec recovery (save partial + spawn new) only at critical level
  - Add **DAG Cycle Detection** section (new, after E11-TRUNCATION):
    - Not a new error code — handled inline during epic decomposition
    - When `moira_epic_validate_dag` returns `cycle_detected`:
      - Display: "Epic decomposition contains circular dependencies: {cycle_path}"
      - Options: `modify` (send back to Daedalus with cycle feedback) or `abort`
      - No automatic retry — cycles are a planning error, not transient
  - Add note under E6-AGENT: resume validation failures (inconsistent, branch_changed, external_changes) are command-level errors handled by `/moira resume` command, not pipeline-level error handlers
- **Commit:** `moira(pipeline): update error handling for checkpoint and epic cycle detection`

---

## Chunk 6: Orchestrator — Checkpoint + Passive Audit

**Goal:** Modify orchestrator.md for checkpoint integration, mandatory checkpoint at >60%, and passive audit checks.

### Task 6.1: Add checkpoint detection to Pre-Pipeline Setup
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D3 §4
- **Key points:**
  - In Section 2, Pre-Pipeline Setup, after audit-pending flag check (item 3):
  - Add item 4: **Check for checkpointed task**
    - Read `current.yaml` → `step_status`
    - If `checkpointed`:
      - Read `task_id` and `step` from `current.yaml`
      - Display: "Task {task_id} was checkpointed at step {step}. Run `/moira resume` to continue."
      - Do NOT start a new pipeline — return to user prompt
      - User must explicitly run `/moira resume` or start a new task (which resets current.yaml)
- **Commit:** `moira(checkpoint): add checkpoint detection to orchestrator pre-pipeline`

### Task 6.2: Add passive audit checks
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D9
- **Key points:**
  - In Section 2, Pre-Pipeline Setup, after checkpoint detection (item 4):
  - Add item 5: **Passive audit — task start checks**
    - Check `config/locks.yaml` for stale locks (TTL expired) — if found, display passive audit warning (per gates.md passive audit template). Informational only (D-068)
    - Check `current.yaml` for orphaned in_progress state (task_id set but step_status not `checkpointed` and no active session) — if found, display warning, offer cleanup (reset current.yaml to idle)
  - In Section 2, Main Loop, after agent return parsing for exploration step:
  - Add: **Passive audit — post-exploration check**
    - Read `knowledge/project-model/summary.md`
    - Compare key facts (stack, structure) against Explorer's SUMMARY
    - If contradictions detected → display passive audit warning
    - Record in status.yaml `warnings[]` via `moira_yaml_append` equivalent
    - Non-blocking: continue pipeline
  - In Section 2, Main Loop, after agent return parsing for review step:
  - Add: **Passive audit — post-review check**
    - Read `knowledge/conventions/summary.md`
    - Check if Reviewer findings mention convention drift
    - If detected → display passive audit warning
    - Record in status.yaml `warnings[]`
    - Non-blocking: continue pipeline
  - **Warnings storage format:** Passive audit warnings use the existing `warnings[]` block in status.schema.yaml. Field mapping: `type` = warning type string (e.g., "stale_locks", "knowledge_drift", "convention_drift", "orphaned_state"), `entry` = affected path (knowledge entry, lock file, or null for orphaned state), `last_task` = null (not task-specific for passive warnings), `distance` = null. All schema fields except `type` are `required: false` — this fits without schema changes.
- **Commit:** `moira(audit): add passive audit checks to orchestrator pipeline`

### Task 6.3: Mandatory checkpoint at >60%
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D3 §2
- **Key points:**
  - In Section 6, Budget Monitoring, modify the `critical` (>60%) threshold action:
  - Current text (lines 246-256): offers checkpoint as choice
  - New behavior: mandatory checkpoint
    - Call `moira_checkpoint_create <task_id> <current_step> context_limit`
    - Display:
      ```
      🔴 MANDATORY CHECKPOINT — Context Critical
      Context usage: ~{pct}% ({est_used}k/1000k)

      Pipeline state saved. Quality will degrade if continued.
      Resume in a new session: /moira resume

      Checkpoint saved at step: {step}
      ```
    - Stop pipeline execution (do NOT offer "proceed" option)
    - Set `current.yaml` step_status to `checkpointed`
- **Commit:** `moira(checkpoint): implement mandatory checkpoint at critical context level`

### Task 6.4: Checkpoint cleanup in completion flow
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D3 §3
- **Key points:**
  - In Section 7, Completion Flow, `done` action, after metrics collection line:
  - Add: call `moira_checkpoint_cleanup <task_id>` — removes manifest.yaml if it exists
  - This handles the case where a task was checkpointed and then completed without re-checkpointing
- **Commit:** `moira(checkpoint): add checkpoint cleanup to completion flow`

### Task 6.5: Checkpoint at repeatable group gates
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D3 §1
- **Key points:**
  - In Section 2, Handling Repeatable Groups (lines 144-151):
  - The `checkpoint` option handling already exists in skeleton form (line 148: "write manifest, set status to `checkpointed`, stop")
  - Expand to:
    - Call `moira_checkpoint_create <task_id> <current_step> user_pause`
    - Set `current.yaml` step_status to `checkpointed` via state transition
    - Display: "Checkpoint saved. Resume with `/moira resume`."
    - Stop pipeline execution (return from main loop)
- **Commit:** `moira(checkpoint): implement checkpoint option at repeatable group gates`

---

## Chunk 7: Orchestrator — Epic Integration

**Goal:** Add sub-pipeline execution model for decomposition pipeline.

### Task 7.1: Add epic sub-pipeline handling
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D5, D-094(i)
- **Key points:**
  - In Section 2, Handling Repeatable Groups, add a new subsection: **Sub-Pipeline Execution (Decomposition Pipeline)**
  - When `repeatable_group` has `role: sub-pipeline` (from decomposition.yaml):
    1. After decomposition gate approval:
       - Call `moira_epic_validate_dag <task_id>` → if `cycle_detected`: display error from errors.md DAG cycle section, offer modify/abort
    2. Sub-task execution loop:
       - Call `moira_epic_next_tasks <task_id>` → get eligible sub-tasks
       - For each eligible sub-task (sequentially by default):
         - Call `moira_epic_check_dependencies` (safety check)
         - Create sub-task state: write `state/tasks/{subtask_id}/input.md` from decomposition artifact's task description
         - Dispatch Apollo (classifier) to classify sub-task → determine pipeline type
         - **Nested pipeline execution:** Re-enter Section 2 Main Loop with sub-task's pipeline definition. The same orchestrator session runs the sub-task pipeline. Budget tracking is cumulative.
       - After sub-task completion: call `moira_epic_update_progress <task_id> <subtask_id> completed`
       - Present per-task gate (from decomposition.yaml)
       - On `proceed`: call `moira_epic_next_tasks` again → next batch
       - On `checkpoint`: call `moira_checkpoint_create` for the epic (includes queue.yaml progress), stop
       - On `abort`: stop
    3. When all sub-tasks completed: proceed to integration step
  - **Parallel option:** After getting eligible sub-tasks, if more than one eligible:
    - Display: "N independent sub-tasks available. Execute in parallel? (uses more context)"
    - If user approves: dispatch multiple sub-task pipelines. Note: practical parallelism depends on orchestrator context budget
    - If user declines: execute sequentially (default)
  - **Queue file handling:** Decomposition pipeline writes queue to `state/tasks/{task_id}/queue.yaml`. Also write global pointer `state/queue.yaml` with `epic_id` pointing to task_id for resume discovery.
- **Commit:** `moira(pipeline): implement epic sub-pipeline execution in orchestrator`

---

## Chunk 8: Orchestrator — Tweak + Redo + Xref

**Goal:** Implement tweak flow, redo flow, and xref enforcement in orchestrator Section 7.

### Task 8.1: Implement tweak flow
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D6, `architecture/tweak-redo.md`
- **Key points:**
  - In Section 7, expand the `tweak` completion action (currently lines 332-337):
  - Full flow:
    1. Ask user to describe what needs changing
    2. Dispatch Hermes (explorer) — quick scope check, identify affected files
    3. **Scope check:** Get task's modified files via git diff against pre-task HEAD. Compare against Explorer's tweak file list.
       - If `tweak_files ⊆ task_files ∪ directly_connected(task_files)` → proceed
       - Otherwise → present tweak scope gate (from gates.md)
       - On `force-tweak` → proceed anyway
       - On `new-task` → display recommendation to create separate task, return to final gate
       - On `cancel` → return to final gate
    4. Dispatch Hephaestus (implementer) with: original plan context (from `plan.md`) + current state + tweak description + "change ONLY what the tweak describes"
    5. Dispatch Themis (reviewer) — review ONLY changed lines + integration points
    6. Dispatch Aletheia (tester) — update affected tests
    7. Increment `completion.tweak_count` in status.yaml
    8. Present final gate again
- **Commit:** `moira(pipeline): implement tweak flow in orchestrator completion`

### Task 8.2: Implement redo flow
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D7, `architecture/tweak-redo.md`
- **Key points:**
  - In Section 7, expand the `redo` completion action (currently lines 339-345):
  - Full flow:
    1. Present redo re-entry gate (from gates.md): ask user for reason and re-entry point
    2. On `cancel` → return to final gate
    3. **Git revert:** Dispatch Hephaestus (implementer) with explicit instructions:
       - "Revert these commits: {commit_list}. Use `git revert` in reverse chronological order. Do NOT make any other changes."
       - Get commit list from git log since task start
    4. **Archive artifacts:**
       - Read current redo_count from status.yaml → N = redo_count + 1
       - Rename: `architecture.md` → `architecture-v{N}.md`, `plan.md` → `plan-v{N}.md`
       - These are within `state/tasks/{task_id}/` — orchestrator CAN write here
    5. **Knowledge capture:** Write failure entry to `knowledge/failures/full.md`:
       - Append section: `## [{task_id}-v{N}] {approach} rejected\nCONTEXT: {description}\nAPPROACH: {architecture_summary}\nREJECTED BECAUSE: {user_reason}\nLESSON: {extracted_lesson}\nAPPLIES TO: {scope}`
       - Also update `knowledge/failures/index.md` and `knowledge/failures/summary.md` L0/L1 entries
       - Use `moira_knowledge_write` equivalent (consistency check per Art 5.3)
    6. **Re-enter pipeline:**
       - `architecture` → re-dispatch Metis with: exploration.md + requirements.md + REJECTED approach context
       - `plan` → re-dispatch Daedalus with: architecture.md (current, not archived) + REJECTED plan context
       - `implement` → re-dispatch implementation batch with: plan.md (current)
       - In all cases: agent receives rejected approach + reason as additional context
    7. Increment `completion.redo_count` in status.yaml
    8. Pipeline continues normally from re-entry point
- **Commit:** `moira(pipeline): implement redo flow in orchestrator completion`

### Task 8.3: Implement xref mechanical enforcement
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D10, D-077, D-093(g)
- **Key points:**
  - In Section 7, after implementation completes and BEFORE presenting the final gate:
  - Add **Xref Consistency Check** subsection:
    1. Read `~/.claude/moira/core/xref-manifest.yaml`
    2. Get list of files modified in this task via `git diff --name-only` against pre-task HEAD
    3. For each xref entry:
       - Check if any `dependents[].file` matches a modified file
       - If match found AND `sync_type` is `value_must_match` or `enum_must_match`:
         - Read canonical source file
         - Read dependent file
         - Compare tracked values
         - If mismatch → add to warnings list
    4. If warnings list non-empty: present xref warning gate (from gates.md)
       - On `fix`: dispatch Hephaestus with xref context (canonical value, target file, field to update)
       - On `ignore`: proceed to final gate with warning noted
    5. If no warnings: proceed to final gate silently
  - Note: orchestrator reads `~/.claude/moira/core/` (global, read-only) — this is within allowed scope
- **Commit:** `moira(pipeline): implement xref mechanical enforcement at final gate`

---

## Chunk 9: Commands — Resume + Upgrade

**Goal:** Replace resume.md placeholder, create upgrade.md command.

### Task 9.1: Implement resume command
- **File:** `src/commands/moira/resume.md`
- **Source:** Spec D2, `subsystems/checkpoint-resume.md`
- **Key points:**
  - Frontmatter: keep `name: moira:resume`, keep `allowed-tools: [Agent, Read, Write]`
  - Command flow:
    1. Read `state/current.yaml` → check for `step_status: checkpointed`
    2. If not checkpointed: scan `state/tasks/*/manifest.yaml` for any checkpoint
    3. If no checkpoint found → "No checkpointed tasks found."
    4. Read `manifest.yaml` → display checkpoint summary (task, step, reason, timestamp)
    5. Validate: perform the 3 checks described in spec D1 (moira_checkpoint_validate logic — the command reads files and validates directly since Bash is not an allowed tool)
    6. Route by result:
       - `valid` → ask user to confirm resume
       - `inconsistent` → display details per `checkpoint-resume.md` §5 (re-explore / re-plan / explain options)
       - `branch_changed` → display mismatch, ask user to switch branch or abort
       - `external_changes` → display per `checkpoint-resume.md` §6 (accept / revert / re-plan options)
    7. On confirmed resume:
       - Load `resume_context` from manifest
       - Load `plan.md` from task directory
       - Set `current.yaml` step_status back to `in_progress`
       - Re-enter pipeline at checkpoint step (dispatch next agent per pipeline definition)
    8. Post-resume quality check:
       - After the first post-resume step completes, dispatch Themis (reviewer) for integration check
       - Reviewer receives: pre-resume artifacts + post-resume output
       - If issues found → display warning, ask user to proceed or address
  - Note: since the resume command is a markdown skill (not bash), the validation checks are performed by Claude reading the relevant files and comparing values
- **Commit:** `moira(checkpoint): implement resume command`

### Task 9.2: Create upgrade command
- **File:** `src/commands/moira/upgrade.md`
- **Source:** Spec D8b, `architecture/distribution.md`
- **Key points:**
  - Frontmatter: `name: moira:upgrade`, `allowed-tools: [Agent, Read, Write, Bash]`
  - Command flow:
    1. Read `~/.claude/moira/.version` → current version
    2. Check for new version source (env var `$MOIRA_SOURCE` or argument)
    3. If no source provided → display instructions for obtaining update
    4. Compare versions
    5. If current >= available → "Moira is up to date (v{version})"
    6. Categorize changes using three-way logic (per upgrade.sh spec)
    7. Present upgrade gate (per spec D8b gate template)
    8. On `apply`:
       - Apply safe changes (auto_apply + new_file)
       - Create new version snapshot
       - Update `.version`
       - Display summary of applied changes
       - Recommend `/moira audit`
    9. On `diff` → show per-file diff for all categories
    10. On `skip` → "Staying on v{current}"
  - Version pinning check: read `.claude/moira/config.yaml` → `moira.version` and `moira.auto_upgrade`. If pinned → warning + extra confirmation
- **Commit:** `moira(pipeline): implement upgrade command`

---

## Chunk 10: Install + Scaffold + Overview

**Goal:** Update install.sh, scaffold, overview.md for Phase 12 artifacts.

### Task 10.1: Update install.sh
- **File:** `src/install.sh`
- **Source:** Spec Files Modified table
- **Key points:**
  - After global layer install (install_global function):
    - Add version snapshot creation: source upgrade.sh, call `moira_upgrade_snapshot "$MOIRA_HOME"` (creates initial .version-snapshot/)
  - In install_commands function:
    - upgrade.md is already copied by the generic `cp -f "$SCRIPT_DIR/commands/moira/"*.md` (line 166)
  - In verify function, add Phase 12 checks:
    - Check: checkpoint.sh exists and is sourceable
    - Check: epic.sh exists and is sourceable
    - Check: upgrade.sh exists and is sourceable
    - Check: upgrade.md command exists
    - Check: `.version-snapshot/` directory exists
    - Add to lib_file loop: `checkpoint.sh epic.sh upgrade.sh`
    - Add `upgrade` to commands array
- **Commit:** `moira(pipeline): update install.sh for Phase 12 artifacts`

### Task 10.2: Update overview.md file tree
- **File:** `design/architecture/overview.md`
- **Source:** Spec Files Modified table
- **Key points:**
  - In Global Layer file tree (lines 82-176):
    - Under `lib/` section, add: `checkpoint.sh`, `epic.sh`, `upgrade.sh` (in alphabetical order among existing entries)
    - Add `.version-snapshot/` directory under `moira/` (after `.version`)
  - In commands section, add: `upgrade.md` to the list
- **Commit:** `moira(design): add Phase 12 files to architecture overview`

---

## Chunk 11: Tier 3 Bench Tests

**Goal:** Create Tier 3 bench test cases and configuration for Phase 12 features.

### Task 11.1: Create tier3-config.yaml
- **File:** `src/tests/bench/tier3-config.yaml`
- **Source:** Spec D11
- **Key points:**
  - Tier 3 configuration with budget (300k tokens, 30 tests, warn at 200k)
  - Trigger matrix: 8 triggers from testing.md
  - Match format of existing bench configuration files
- **Commit:** `moira(pipeline): add Tier 3 bench configuration`

### Task 11.2: Create Phase 12 bench test cases
- **Files:**
  - `src/tests/bench/cases/tier3-checkpoint-resume.yaml`
  - `src/tests/bench/cases/tier3-epic-decomposition.yaml`
  - `src/tests/bench/cases/tier3-tweak.yaml`
  - `src/tests/bench/cases/tier3-redo.yaml`
- **Source:** Spec D11, `subsystems/testing.md` (Test Cases format)
- **Key points:**
  - Follow existing test case format: meta, fixture, task, gate_responses, expected_structural, expected_quality
  - `tier3-checkpoint-resume.yaml`: medium task on mature-webapp, gate_responses trigger checkpoint at phase gate, validate resume flow, post-resume quality check
  - `tier3-epic-decomposition.yaml`: epic task on mature-webapp with 3 sub-tasks (1 independent, 2 dependent), validate DAG scheduling and per-task gates
  - `tier3-tweak.yaml`: medium task on mature-webapp, final gate → tweak (in-scope change) → verify implementer-only modification, then second tweak (out-of-scope) → verify scope gate recommendation
  - `tier3-redo.yaml`: medium task on mature-webapp, final gate → redo at each re-entry point (3 gate_responses variants: architecture, plan, implement). Verify artifact archiving and failure knowledge capture
- **Commit:** `moira(pipeline): add Tier 3 bench test cases for Phase 12 features`

---

## Chunk 12: Tier 1 Tests + Regression

**Goal:** Create Tier 1 structural tests for Phase 12 artifacts, verify regression.

### Task 12.1: Create test-checkpoint-resume.sh
- **File:** `src/tests/tier1/test-checkpoint-resume.sh`
- **Source:** Spec D12
- **Key points:**
  - Follow existing test file pattern (source test-helpers.sh, use assert functions)
  - Tests: checkpoint.sh exists, defines moira_checkpoint_create/validate/build_resume_context/cleanup
  - manifest.schema.yaml has checkpointed-related fields
  - resume.md is not placeholder (no "Phase 12" text), has allowed-tools Agent/Read/Write
  - current.schema.yaml step_status enum includes `checkpointed`
  - state.sh valid_statuses includes `checkpointed`
- **Commit:** `moira(checkpoint): add Tier 1 tests for checkpoint/resume`

### Task 12.2: Create test-epic.sh
- **File:** `src/tests/tier1/test-epic.sh`
- **Source:** Spec D12
- **Key points:**
  - Tests: epic.sh exists, defines moira_epic_parse_queue/validate_dag/next_tasks/update_progress/check_dependencies
  - queue.schema.yaml has required fields
  - decomposition.yaml references repeatable_group with role: sub-pipeline
- **Commit:** `moira(pipeline): add Tier 1 tests for epic execution`

### Task 12.3: Create test-tweak-redo.sh
- **File:** `src/tests/tier1/test-tweak-redo.sh`
- **Source:** Spec D12
- **Key points:**
  - Tests: orchestrator.md contains tweak flow logic (grep for "tweak" section, scope check, force-tweak)
  - orchestrator.md contains redo flow logic (grep for "redo" section, re-entry, git revert)
  - orchestrator.md references knowledge/failures/ write
  - gates.md contains tweak scope gate template
  - gates.md contains redo re-entry gate template
- **Commit:** `moira(pipeline): add Tier 1 tests for tweak/redo`

### Task 12.4: Create test-upgrade.sh
- **File:** `src/tests/tier1/test-upgrade.sh`
- **Source:** Spec D12
- **Key points:**
  - Tests: upgrade.sh exists, defines moira_upgrade_check_version/diff_files/apply/snapshot
  - upgrade.md exists, is not placeholder, has allowed-tools Agent/Read/Write/Bash
  - scaffold.sh creates .version-snapshot directory
- **Commit:** `moira(pipeline): add Tier 1 tests for upgrade`

### Task 12.5: Create test-passive-audit.sh
- **File:** `src/tests/tier1/test-passive-audit.sh`
- **Source:** Spec D12
- **Key points:**
  - Tests: orchestrator.md contains passive audit check points (grep for "stale locks", "Knowledge drift", "Convention drift")
  - gates.md contains passive audit warning format
- **Commit:** `moira(audit): add Tier 1 tests for passive audit checks`

### Task 12.6: Update existing Tier 1 tests
- **Files:**
  - `src/tests/tier1/test-file-structure.sh`
  - `src/tests/tier1/test-install.sh`
- **Source:** Spec D12, Files Modified table
- **Key points:**
  - test-file-structure.sh: add checks for checkpoint.sh, epic.sh, upgrade.sh, upgrade.md, .version-snapshot/
  - test-install.sh: add Phase 12 installation verification (new libs exist, upgrade command exists, version snapshot created)
- **Commit:** `moira(pipeline): update existing Tier 1 tests for Phase 12 artifacts`

### Task 12.7: Run full Tier 1 regression
- **Action:** Run `src/tests/tier1/run-all.sh` — verify all existing and new tests pass
- **Note:** run-all.sh auto-discovers test-*.sh files, so no modification to run-all.sh needed
- **Commit:** No commit — verification step only

---

## Dependency Graph

```
Chunk 1 (schemas/state)
├──→ Chunk 2 (checkpoint.sh)
│    ├──→ Chunk 6 (orchestrator checkpoint + passive audit)
│    │    ├──→ Chunk 7 (orchestrator epic)
│    │    ├──→ Chunk 8 (orchestrator tweak/redo/xref)
│    │    └──→ Chunk 9 (resume command)
│    └──→ Chunk 10 (install/scaffold/overview)
├──→ Chunk 3 (epic.sh)
│    ├──→ Chunk 7 (orchestrator epic)
│    └──→ Chunk 10 (install/scaffold/overview)
├──→ Chunk 4 (upgrade.sh) ──→ Chunk 9 (upgrade command) ──→ Chunk 10
│
└──→ Chunk 5 (gates + errors skills)
     ├──→ Chunk 6
     ├──→ Chunk 7
     └──→ Chunk 8

Chunk 11 (Tier 3 bench) ← depends on Chunks 6, 7, 8
Chunk 12 (Tier 1 tests) ← depends on ALL previous chunks
```

**Parallelizable groups:**
- Chunks 2, 3, 4, 5 can all start after Chunk 1 (independent of each other)
- Chunks 6, 7, 8 can partially overlap (all modify orchestrator.md but different sections)
- Chunk 9 tasks (resume, upgrade) are independent of each other
- Chunks 11, 12 are sequential (Tier 1 tests verify everything)
