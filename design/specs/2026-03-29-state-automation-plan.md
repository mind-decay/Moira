# State Automation — Implementation Plan

**Spec:** `design/specs/2026-03-29-state-automation.md`
**Decisions:** D-178 (state automation), open questions resolved in conversation

---

## Chunk 1: `task-init.sh` + `task-submit.sh` hook

**Dependencies:** None (foundation)

### Task 1.1: Create `src/global/lib/task-init.sh`

Shell library with `moira_task_init <description> [size_hint] [state_dir]`:
- Sources `yaml-utils.sh`, `task-id.sh`
- Generates task ID via `moira_task_id`
- Creates task directory
- Writes `manifest.yaml` via `moira_yaml_init manifest` + sets fields
- Writes `status.yaml` via `moira_yaml_init status` + sets fields
- Writes `input.md` (template with description, size hint, timestamp)
- Writes `current.yaml` via `moira_yaml_init current` + sets fields (task_id, step=classification, step_status=pending)
- Creates `.session-lock` (pid=session, started, task_id, ttl=3600)
- Creates `.guard-active` (empty marker)
- Outputs task_id to stdout

**Design source:** `task.md` Steps 2-7, `status.schema.yaml`, `current.schema.yaml`, `manifest.schema.yaml`

**Commit:** `moira(foundation): add task-init.sh — task scaffold shell library`

### Task 1.2: Create `src/global/hooks/task-submit.sh`

UserPromptSubmit hook:
- Reads prompt from stdin JSON (`prompt` field)
- Detects `/moira:task` or `/moira task` prefix via regex
- If no match → exit 0 silently
- If match:
  - Extracts description (text after prefix)
  - Extracts optional size hint (`small:`, `medium:`, `large:`, `epic:` prefix)
  - Finds state dir (same `find_state_dir` pattern as other hooks)
  - Sources `task-init.sh`, calls `moira_task_init`
  - Outputs `additionalContext`: "MOIRA TASK INITIALIZED: task_id={id}, state pre-scaffolded"
- Guard: if state dir doesn't exist (not a Moira project), exit 0

**Commit:** `moira(hooks): add task-submit.sh — auto-scaffold on /moira:task`

### Task 1.3: Update `src/commands/moira/task.md`

Remove Steps 2-7 (manual scaffold). Replace with:
- Step 2: Read task_id from context (injected by task-submit.sh hook)
- If no task_id in context → fallback: generate and scaffold manually (for cases where hook didn't fire)
- Rest of steps unchanged (Step 8: load orchestrator, Step 9: begin pipeline)

**Commit:** `moira(skills): update task.md — use hook-provided scaffold`

---

## Chunk 2: `pipeline-dispatch.sh` (merge compliance + step transition)

**Dependencies:** Chunk 1

### Task 2.1: Create `src/global/hooks/pipeline-dispatch.sh`

PreToolUse(Agent) hook. Merges `pipeline-compliance.sh` + new step transition logic:

**Section A — Existing compliance logic (from pipeline-compliance.sh):**
- Parse description → role, find state dir, check guard-active
- Read tracker state
- L1: review_pending check
- L2: test_pending check
- L3: Per-pipeline transition table
- On violation: DENY with reason

**Section B — New: step transition (if not denied):**
- Map role → step:
  - classifier → classification
  - explorer → exploration (analytical: gather)
  - analyst → analysis (analytical: scope or analysis depending on tracker)
  - architect → architecture (analytical: organize)
  - planner → plan
  - implementer → implementation
  - reviewer → review (analytical: depth_checkpoint or review)
  - tester → testing
  - scribe → synthesis
- Source `state.sh`, call `moira_state_transition <step> in_progress`
- Write `dispatched_role=<role>` to `pipeline-tracker.state`

**Section C — Analytical step mapping:**
- If pipeline=analytical:
  - explorer: always → gather
  - analyst: if last_role=explorer → scope, else → analysis
  - architect: → organize
  - reviewer: if last_role=analyst/architect → depth_checkpoint, if last_role=scribe → review
  - scribe: → synthesis

**No output** (pipeline-tracker.sh handles additionalContext on PostToolUse)

**Commit:** `moira(hooks): add pipeline-dispatch.sh — merged compliance + step transition`

### Task 2.2: Remove `src/global/hooks/pipeline-compliance.sh`

Delete old file. Update settings.json to reference pipeline-dispatch.sh.

### Task 2.3: Update `src/global/hooks/pipeline-tracker.sh`

Since `pipeline-dispatch.sh` now writes `dispatched_role` in PreToolUse, the tracker doesn't need to re-extract role from description. But for backward compatibility and because PostToolUse runs after the agent completes (not just dispatched), keep role extraction.

Only change: the tracker now also reads `dispatched_role` from tracker state to verify consistency.

**Commit for 2.2+2.3:** `moira(hooks): replace pipeline-compliance with pipeline-dispatch`

---

## Chunk 3: `agent-done.sh` (SubagentStop state recording)

**Dependencies:** Chunk 2 (needs dispatched_role in tracker)

### Task 3.1: Create `src/global/hooks/agent-done.sh`

SubagentStop hook:
- Parse from stdin: `stop_hook_active`, `agent_type`, `last_assistant_message`, `agent_transcript_path`
- If `stop_hook_active=true` → exit 0 (prevent re-entry)
- Find state dir, check guard-active
- Skip non-pipeline agent types (Explore, Plan, Bash)
- Read `dispatched_role` from `pipeline-tracker.state` (written by pipeline-dispatch.sh in PreToolUse)
- If no dispatched_role → exit 0 (not a tracked dispatch)
- Extract STATUS from last_assistant_message (regex: `STATUS:\s*(success|failure|blocked|budget_exceeded)`)
- Extract SUMMARY (regex: `SUMMARY:\s*(.+)`)
- Compute duration: read `step_started_at` from current.yaml, diff with current time
- Estimate tokens: parse agent_transcript_path for usage data (or use 0 as fallback)
- Source state.sh, call `moira_state_agent_done <step> <role> <status> <duration> <tokens> <summary>`
- Read back `orchestrator_percent` and `warning_level` from current.yaml (updated by budget check inside state_agent_done)
- Clear `dispatched_role` from tracker state (agent is done)
- Output additionalContext: "AGENT DONE — {role}: {status}. Budget: {pct}% ({level}). Step: {step}."

**Important:** This hook runs IN PARALLEL with `agent-output-validate.sh`. Both fire on SubagentStop. No file write conflicts because:
- agent-output-validate.sh: reads last_assistant_message, may output decision:block (no file writes)
- agent-done.sh: writes to current.yaml and status.yaml (no decision output)

If agent-output-validate.sh blocks the agent, SubagentStop fires again when agent eventually stops. agent-done.sh handles this via stop_hook_active check.

**Commit:** `moira(hooks): add agent-done.sh — auto-record agent completion and budget`

---

## Chunk 4: `session-cleanup.sh` + settings update

**Dependencies:** Chunks 1-3

### Task 4.1: Create `src/global/hooks/session-cleanup.sh`

SessionEnd hook:
- Find state dir (may not exist — not all sessions are Moira projects)
- If no state dir → exit 0
- If `.guard-active` doesn't exist → exit 0 (not in pipeline)
- Read current.yaml → step_status
- If step_status is `completed`:
  - Delete `.session-lock`
  - Delete `.guard-active`
  - Delete `pipeline-tracker.state`
- If step_status is `checkpointed`:
  - Delete `.session-lock`
  - Delete `.guard-active`
  - Keep `pipeline-tracker.state` (needed for resume)
- Otherwise (abnormal exit — in_progress, pending, etc.):
  - Leave everything for /moira:resume
  - Write `.session-lock` TTL to 0 (mark as stale for next session detection)

**Commit:** `moira(hooks): add session-cleanup.sh — automatic lifecycle cleanup`

### Task 4.2: Update `.claude/settings.json`

Add new hooks:
- `UserPromptSubmit`: task-submit.sh
- `PreToolUse(Agent)`: pipeline-dispatch.sh (replaces pipeline-compliance.sh)
- `SubagentStop`: agent-done.sh (alongside existing agent-output-validate.sh)
- `SessionEnd`: session-cleanup.sh

**Commit:** `moira(hooks): register new state automation hooks in settings`

### Task 4.3: Update `src/install.sh`

Ensure new hooks are copied. Remove pipeline-compliance.sh from install (replaced by pipeline-dispatch.sh).

### Task 4.4: Update `src/global/skills/orchestrator.md`

In Section 4 (State Management):
- Note that step transitions are automated by `pipeline-dispatch.sh` hook
- Note that agent completion recording is automated by `agent-done.sh` hook
- Note that session lifecycle is automated by hooks
- Remove manual state write instructions for these operations
- Keep: gate recording, pipeline selection, error routing, analytical convergence state, bootstrap checks

In Section 1 (State Management Mechanism):
- Update to reflect that hooks now handle mechanical state writes
- The orchestrator still reads state files for decisions but no longer writes step/agent/lifecycle state

In Section 2 (Pipeline Execution Loop):
- Remove step 2a ("Update state: set step and status to in_progress") — automated by hook
- Remove step d ("record completion") for agent done — automated by hook
- Keep references to gate recording (still manual)

In Section 7 (Completion Flow):
- Remove manual .session-lock and .guard-active deletion — automated by SessionEnd hook

**Commit:** `moira(skills): update orchestrator.md — remove automated state writes`

---

## Chunk 5: Tests + decision log

**Dependencies:** Chunks 1-4

### Task 5.1: Add tests to `src/tests/tier1/test-hooks-system.sh`

- Test task-submit.sh: mock /moira:task prompt → verify scaffold created
- Test pipeline-dispatch.sh: verify step transition written to current.yaml
- Test agent-done.sh: verify history entry and budget updated
- Test session-cleanup.sh: verify cleanup on completed/checkpointed/abnormal

### Task 5.2: Add D-178 to decision log

**Commit:** `moira(design): add D-178 state automation decision + tests`

---

## Dependency Graph

```
Chunk 1 (task-init + task-submit)
    │
    ▼
Chunk 2 (pipeline-dispatch — merge compliance + step transition)
    │
    ▼
Chunk 3 (agent-done — SubagentStop recording)
    │
    ▼
Chunk 4 (session-cleanup + settings + orchestrator update)
    │
    ▼
Chunk 5 (tests + decision log)
```
