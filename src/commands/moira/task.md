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

## Step 2: Generate Task ID

Generate a task ID using this pattern:
- Read the current date (YYYY-MM-DD format)
- Check existing task directories in `~/.claude/moira/state/tasks/` for today's date
- Next ID = `task-{date}-{NNN}` where NNN is zero-padded next number (001, 002, etc.)

## Step 3: Create Task Directory

Create directory: `~/.claude/moira/state/tasks/{task_id}/`

## Step 4: Write Input File

Write `~/.claude/moira/state/tasks/{task_id}/input.md`:

```
# Task: {task_id}

## Description
{user's original task description}

## Size Hint
{size prefix if provided, otherwise "none — classifier decides"}

## Created
{ISO 8601 timestamp}
```

## Step 5: Initialize Status File

Write `~/.claude/moira/state/tasks/{task_id}/status.yaml`:

```yaml
task_id: "{task_id}"
description: "{first 100 chars of task description}"
developer: "user"
created_at: "{ISO 8601 timestamp}"
gates: []
retries:
  quality: 0
  agent_failures: 0
  budget_splits: 0
  total: 0
```

## Step 6: Initialize Current State

Write `~/.claude/moira/state/current.yaml`:

```yaml
task_id: "{task_id}"
pipeline: null
step: "classification"
step_status: "pending"
step_started_at: "{ISO 8601 timestamp}"
gate_pending: null
context_budget:
  total_agent_tokens: 0
history: []
```

## Step 7: Create Stub Manifest

Write `~/.claude/moira/state/tasks/{task_id}/manifest.yaml` (foundation for Phase 12 resume):

```yaml
task_id: "{task_id}"
pipeline: null
developer: "user"
checkpoint: null
created_at: "{ISO 8601 timestamp}"
```

## Step 8: Load Orchestrator Skill

Read the orchestrator skill from `~/.claude/moira/skills/orchestrator.md`.

This is the brain of the system. Follow its instructions exactly.

## Step 9: Begin Pipeline Execution

Following the orchestrator skill:

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
