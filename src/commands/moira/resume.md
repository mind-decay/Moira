---
name: moira:resume
description: Resume an interrupted task from the last checkpoint
allowed-tools:
  - Agent
  - Read
  - Write
---

# Moira — Resume

Resume a checkpointed task from where it left off. Validates state consistency before continuing and performs a post-resume quality check.

## Setup

- **Project state:** `.moira/state/`
- **Task state:** `.moira/state/tasks/{task_id}/`
- **Manifest:** `.moira/state/tasks/{task_id}/manifest.yaml`
- **Current state:** `.moira/state/current.yaml`
- **Write scope:** `.moira/` paths ONLY

## Step 1: Find Checkpoint

### 1a. Check current.yaml

Read `.moira/state/current.yaml`.

- If `step_status` is `checkpointed`: use the `task_id` from current.yaml. Proceed to Step 2.

### 1b. Scan for checkpointed tasks

If current.yaml does not show `checkpointed` status (or does not exist):

- Read `.moira/state/tasks/` directory listing
- For each task directory, read `manifest.yaml`
- Look for any manifest where `checkpoint.step` is non-null and `checkpoint.reason` is set
- If multiple checkpoints found: display list and ask user to choose
- If exactly one found: use that task_id

### 1c. No checkpoint found

If no checkpointed task is found anywhere:

```
No checkpointed tasks found.
Use /moira:task to start a new task.
```

Stop execution.

## Step 2: Display Checkpoint Summary

Read the manifest at `.moira/state/tasks/{task_id}/manifest.yaml`.

Display:

```
═══════════════════════════════════════════
 MOIRA — Resume Checkpoint
═══════════════════════════════════════════
 Task:      {task_id}
 Pipeline:  {pipeline}
 Step:      {checkpoint.step}
 Reason:    {checkpoint.reason}
 Saved at:  {checkpoint.created_at}
═══════════════════════════════════════════
```

If `resume_context` is non-null, also display:

```
 Context:
   {resume_context text, indented}
```

## Step 3: Validate Checkpoint

Perform three validation checks by reading files and comparing values. Since this command does not have Bash in its allowed tools, validation is done by reading YAML files and dispatching lightweight agents for git operations.

### Check 1: Artifact Existence

Read `.moira/state/current.yaml` and parse the `history` block. For each entry where `status` is `success`, verify that the corresponding artifact file exists at `.moira/state/tasks/{task_id}/artifacts/{step}.md` (or the `result_file` path listed in the history entry if present).

Track any missing artifacts.

### Check 2: Git Branch and Ancestry

Read `validation.git_branch` and `validation.git_head_at_checkpoint` from the manifest.

Dispatch a lightweight agent to check git state:

**Agent — Git Validator:**
- description: "Check git branch and ancestry for resume validation"
- subagent_type: general-purpose
- prompt: Read the current git branch name (run `git rev-parse --abbrev-ref HEAD`), the current HEAD commit (run `git rev-parse HEAD`), and check if commit `{validation.git_head_at_checkpoint}` is an ancestor of HEAD (run `git merge-base --is-ancestor {checkpoint_head} HEAD`). Report back: current_branch={branch}, ancestor_check={pass|fail}.

Compare the agent's reported `current_branch` against `validation.git_branch`. If they differ, the branch has changed.

### Check 3: External File Changes

If branch and ancestry are valid, check for external modifications since the checkpoint.

Dispatch the same or a new lightweight agent:

**Agent — Diff Checker:**
- description: "Check for file changes since checkpoint"
- subagent_type: general-purpose
- prompt: Run `git diff --name-only {validation.git_head_at_checkpoint}` and report the list of changed files (or "none" if no changes).

If `validation.external_changes_expected` is `false` and changed files exist, record them.

### Determine Result

Evaluate the three checks in priority order:

1. If artifacts are missing → result is `inconsistent:missing_artifacts:{list}`
2. If branch changed → result is `branch_changed:{expected}:{actual}`
3. If external changes detected (and not expected) → result is `external_changes:{file_list}`
4. If all checks pass → result is `valid`

## Step 4: Route by Validation Result

### Result: `valid`

Ask user for confirmation:

```
Checkpoint is valid. Resume task {task_id} at step "{checkpoint.step}"?

 1) resume  — continue from checkpoint
 2) abort   — cancel resume
```

On `resume` → proceed to Step 5.
On `abort` → stop execution.

### Result: `inconsistent`

Display the inconsistency details:

```
═══════════════════════════════════════════
 RESUME INCONSISTENCY
═══════════════════════════════════════════
 {details of what's inconsistent}

 Possible causes:
 - Manual changes between sessions
 - Git operations (stash, checkout, reset)

 1) re-explore — rescan and update manifest
 2) re-plan    — go back to planning
 3) explain    — tell system what happened
═══════════════════════════════════════════
```

- `re-explore`: Set `current.yaml` step to `exploration`, step_status to `pending`, and re-enter the pipeline at exploration.
- `re-plan`: Set `current.yaml` step to `plan`, step_status to `pending`, and re-enter the pipeline at planning.
- `explain`: Ask the user to describe what happened. Record their explanation in the manifest's `resume_context` field (append to existing context). Then re-validate (go back to Step 3).

### Result: `branch_changed`

Display branch mismatch:

```
═══════════════════════════════════════════
 BRANCH MISMATCH
═══════════════════════════════════════════
 Expected: {expected_branch}
 Actual:   {actual_branch}

 The git branch has changed since the checkpoint.

 1) switch  — switch to {expected_branch} and resume
 2) abort   — cancel resume
═══════════════════════════════════════════
```

- `switch`: Inform the user to run `git checkout {expected_branch}` and then re-run `/moira:resume`. (This command cannot run git checkout since Bash is not in allowed tools.)
- `abort`: Stop execution.

### Result: `external_changes`

Display changed files:

```
═══════════════════════════════════════════
 EXTERNAL CHANGES DETECTED
═══════════════════════════════════════════
 Files modified since last session:
 {list of changed files, one per line with - prefix}

 1) accept   — incorporate changes, continue
 2) revert   — undo external changes, continue as planned
 3) re-plan  — re-plan remaining work with new state
═══════════════════════════════════════════
```

- `accept`: Update manifest's `validation.external_changes_expected` to `true`. Proceed to Step 5 (resume).
- `revert`: Inform the user to run `git checkout {checkpoint_head} -- {files}` to revert, then re-run `/moira:resume`.
- `re-plan`: Set `current.yaml` step to `plan`, step_status to `pending`, preserve existing artifacts, and re-enter the pipeline at planning.

## Step 5: Execute Resume

### 5a. Load Context

1. Read `resume_context` from manifest.yaml
2. Read `plan.md` from `.moira/state/tasks/{task_id}/plan.md` (if it exists)
3. Read `decisions_made` from manifest.yaml (if non-null)

### 5b. Update State

Write to `.moira/state/current.yaml`:
- Set `step_status` to `in_progress`
- Set `step` to the value from `checkpoint.step`
- Set `step_started_at` to current ISO 8601 timestamp
- Preserve all other fields (task_id, pipeline, history, context_budget, etc.)

### 5c. Re-enter Pipeline

Read the orchestrator skill from `~/.claude/moira/skills/orchestrator.md`.

Follow its instructions to re-enter the pipeline at the checkpoint step:

1. Read the pipeline definition for the current pipeline type from `~/.claude/moira/core/pipelines/`
2. Determine which agent to dispatch for the current step
3. When constructing the agent prompt, prepend the resume context:
   ```
   RESUME CONTEXT (from previous session):
   {resume_context}

   Key decisions made before checkpoint:
   {decisions_made}
   ```
4. Dispatch the agent for the checkpoint step per normal pipeline execution
5. Continue the pipeline execution loop from that point forward

## Step 6: Post-Resume Quality Check (D-094h)

After the **first** post-resume step completes (the agent dispatched in Step 5c returns):

### 6a. Dispatch Integration Reviewer

Dispatch Themis (reviewer) via Agent tool for an integration check:

**Agent — Post-Resume Integration Check:**
- description: "Themis — post-resume integration review"
- subagent_type: general-purpose
- prompt: Combine Themis identity from `~/.claude/moira/core/rules/roles/themis.yaml` with base rules from `~/.claude/moira/core/rules/base.yaml`, then provide:
  - Pre-resume artifacts: list the completed step artifacts from `.moira/state/tasks/{task_id}/artifacts/`
  - Post-resume output: the output from the step that just completed
  - Resume context: the `resume_context` from the manifest
  - Instructions: "Check that the post-resume work integrates correctly with pre-resume work. Verify contracts are maintained, code style is consistent, and no context was lost. Report: PASS or FAIL with specific issues."

### 6b. Handle Review Result

Parse the reviewer's response:

- **PASS**: Continue pipeline execution normally. Display brief confirmation:
  ```
  Post-resume integration check: PASSED
  ```

- **FAIL**: Display warning with the specific issues found:
  ```
  ═══════════════════════════════════════════
   POST-RESUME INTEGRATION WARNING
  ═══════════════════════════════════════════
   {issues found by reviewer}

   1) proceed — continue despite issues
   2) address — fix issues before continuing
  ═══════════════════════════════════════════
  ```

  - `proceed`: Continue pipeline execution, noting the warning in status.yaml.
  - `address`: Re-dispatch the current step's agent with the reviewer's feedback appended, then re-run the integration check.

### 6c. Cleanup

After the task completes (all pipeline steps finish), remove the checkpoint manifest:
- Delete `.moira/state/tasks/{task_id}/manifest.yaml` (or reset its checkpoint fields to null)

## Constitutional Compliance

- **Art 1.2:** Agents dispatched are read-only for validation; state modifications are made by this command only.
- **Art 4.2:** User must confirm resume before execution continues. All inconsistency resolutions require user choice.
- **Art 3.1:** Pipeline execution follows the standard orchestrator skill — no gates are skipped.
- **Write scope:** This command writes ONLY to `.moira/` paths. NEVER to project source files.
