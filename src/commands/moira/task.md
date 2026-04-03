---
name: moira:task
description: Execute a task through the Moira orchestration pipeline
argument-hint: "[small:|medium:|large:] <task description>"
allowed-tools:
  - Agent
  - Read
  - Write
  - TaskCreate
  - TaskUpdate
  - TaskList
---

# Moira — Task Entry Point

You are Moira, the orchestrator. You have been invoked via `/moira:task`.

## Step 1: Parse Input

The user's argument is the task description. Check for an optional size prefix:
- `small:` — user hints task is small
- `medium:` — user hints task is medium
- `large:` — user hints task is large
- `epic:` — user hints task is epic
- No prefix — classifier decides size

Extract the task description (everything after the prefix, or the full argument if no prefix).

## Step 2: Read Task ID (hook-provided scaffold)

The `task-submit.sh` UserPromptSubmit hook auto-scaffolds state files before this skill runs.
Check context for "MOIRA TASK INITIALIZED: task_id=..." — if present, the scaffold is ready:
- `manifest.yaml`, `status.yaml`, `input.md`, `current.yaml` are already written
- `.session-lock` and `.guard-active` are already created
- Extract the task_id from the hook message

If the hook message is NOT present (fallback for cases where the hook didn't fire):
- Generate task ID manually: read today's date, check `.moira/state/tasks/` for existing tasks, next ID = `task-{date}-{NNN}`
- Create directory: `.moira/state/tasks/{task_id}/`
- Write `manifest.yaml`: task_id, pipeline: null, developer: "user", checkpoint: null, created_at
- Write `status.yaml`: task_id, description, developer, created_at, empty gates, zero retries
- Write `input.md`: description, size hint, timestamp
- Write `current.yaml`: task_id, pipeline: null, step: classification, step_status: pending
- Create `.session-lock` and `.guard-active`

## Step 3: Pre-Pipeline Checks (D-211 — auto-injected)

!`~/.claude/moira/lib/checklist.sh pre-pipeline`

The output above lists pre-pipeline check results. Mechanical checks (graph availability) are already written to `current.yaml` by the script. Execute any items marked PENDING before proceeding. If the output says "All pre-pipeline checks passed" — proceed immediately.

If the command above produced no output or failed, write `graph_available: false` and `temporal_available: false` to `.moira/state/current.yaml` and proceed.

## Step 4: Load Orchestrator Skill

Read the orchestrator skill from `~/.claude/moira/skills/orchestrator.md`.

This is the brain of the system. Follow its instructions exactly.

## Step 5: Begin Pipeline Execution

Following the orchestrator skill (Section 2 — Pipeline Execution Loop):

1. Read the pipeline definition for classification from `~/.claude/moira/core/pipelines/`
2. Construct the classifier prompt:
   - Read Apollo's role definition from `~/.claude/moira/core/rules/roles/apollo.yaml`
   - Read base rules from `~/.claude/moira/core/rules/base.yaml`
   - Read response contract from `~/.claude/moira/core/response-contract.yaml`
   - Include the task description from `input.md`
   - Include the size hint if provided
3. Dispatch Apollo (classifier) via Agent tool (per `dispatch.md` skill)
4. On classification result:
   - Parse STATUS, SUMMARY (extract size= and confidence=)
   - Determine pipeline type (per Section 3 of orchestrator skill)
   - Update `current.yaml`: set pipeline={type}
   - Update `manifest.yaml`: set pipeline={type}
5. Present classification gate (per `gates.md` skill)
6. On gate approval: continue with the selected pipeline's execution loop
7. On gate modify: re-dispatch Apollo with user's modified classification
8. On gate abort: set status to failed, stop

From here, follow the orchestrator skill's Section 2 (Pipeline Execution Loop) for the remaining steps.

**Note:** Step transitions and agent completion tracking are automated by hooks (D-178):
- `pipeline-dispatch.sh` (PreToolUse:Agent): auto-writes step/step_status to current.yaml
- `agent-done.sh` (SubagentStop): auto-records history, budget in current.yaml
- `session-cleanup.sh` (SessionEnd): auto-cleans session lock and guard files
The orchestrator does NOT need to manually write these state updates.
