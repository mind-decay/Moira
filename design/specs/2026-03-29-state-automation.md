# State Management Automation

**Date:** 2026-03-29
**Risk:** ORANGE (pipeline flow changes, hook additions)
**Design sources:** orchestrator.md Sections 1-7, hooks-guide, hooks reference, state.sh, budget.sh, current.schema.yaml, status.schema.yaml, manifest.schema.yaml

---

## Problem

The orchestrator performs ~20 manual YAML Read/Write operations per pipeline run to manage state. Each operation costs ~500-1000 tokens of context. This creates three problems:

1. **Context waste:** ~10-20k tokens per task spent on mechanical YAML writes the orchestrator performs directly
2. **Logic duplication:** Shell libraries (`state.sh`, `budget.sh`, etc.) define canonical state logic, but the orchestrator can't call them (Bash is not an allowed tool). Instead, it reads the `.sh` files as reference and reproduces the same logic through Read/Write — a fragile, error-prone pattern
3. **Drift risk:** When shell libraries change, the orchestrator skill must be updated to match. Any divergence causes state corruption silently

## Goal

Move mechanical state operations out of the orchestrator's context window and into hooks/shell scripts that fire automatically. The orchestrator focuses on decisions (gate presentation, error routing, pipeline selection) while hooks handle the bookkeeping.

## Design Constraint

**The orchestrator cannot use Bash.** This is a constitutional boundary (Art 1.1). Therefore, state automation must use one of:

- **Claude Code hooks** — fire automatically on lifecycle events (SubagentStart, SubagentStop, PostToolUse, etc.)
- **Structured JSON output from hooks** — hooks inject additionalContext that includes computed state, so the orchestrator doesn't need to Read files to know state values

The orchestrator still Reads state files when it needs data for decisions (e.g., reading classification for pipeline selection). But it should NEVER Write state files that a hook could write automatically.

---

## Current State Operations (Audit)

### What the orchestrator writes manually today:

| # | Operation | File | When | Tokens est. |
|---|-----------|------|------|-------------|
| 1 | Create task directory + scaffold | `state/tasks/{id}/` | Pipeline start | ~800 |
| 2 | Write initial `manifest.yaml` | `manifest.yaml` | Pipeline start | ~600 |
| 3 | Write initial `status.yaml` | `status.yaml` | Pipeline start | ~800 |
| 4 | Write initial `current.yaml` | `current.yaml` | Pipeline start | ~1000 |
| 5 | Write `.session-lock` | `.session-lock` | Pipeline start | ~300 |
| 6 | Write `.guard-active` | `.guard-active` | Pipeline start | ~200 |
| 7 | Update `current.yaml` step transition | `current.yaml` | Before each agent dispatch (~5-8×) | ~500×N |
| 8 | Update `current.yaml` history (agent done) | `current.yaml` | After each agent return (~5-8×) | ~500×N |
| 9 | Update `current.yaml` budget fields | `current.yaml` | After each agent return (~5-8×) | ~400×N |
| 10 | Set `gate_pending` in `current.yaml` | `current.yaml` | Before each gate (~3-5×) | ~300×N |
| 11 | Record gate decision in `status.yaml` | `status.yaml` | After each gate (~3-5×) | ~400×N |
| 12 | Clear `gate_pending` in `current.yaml` | `current.yaml` | After each gate (~3-5×) | ~300×N |
| 13 | Write `completion.action` to `status.yaml` | `status.yaml` | Completion | ~300 |
| 14 | Delete `.session-lock` | `.session-lock` | Completion | ~200 |
| 15 | Delete `.guard-active` | `.guard-active` | Completion | ~200 |
| 16 | Set pipeline status in `current.yaml` | `current.yaml` | Completion | ~300 |
| 17 | Write `input.md` | `input.md` | Pipeline start | ~400 |
| 18 | Write `classification.md` from Apollo | `classification.md` | After classification | Handled by agent |
| 19 | Update analytical state fields | `current.yaml` | Analytical pipeline only | ~400×N |
| 20 | Write `graph_available`/`temporal_available` | `current.yaml` | Bootstrap checks | ~300 |

**Total estimated per standard pipeline:** ~12-18k tokens on state writes alone.

### What hooks already handle:

| Hook | Event | What it does |
|------|-------|-------------|
| `guard.sh` | PostToolUse | Logs tool usage, detects violations |
| `guard-prevent.sh` | PreToolUse(Read\|Write) | Blocks boundary violations |
| `pipeline-compliance.sh` | PreToolUse(Agent) | Validates step transitions |
| `pipeline-tracker.sh` | PostToolUse(Agent) | Tracks last role, pending flags, injects next-step guidance |
| `pipeline-stop-guard.sh` | Stop | Blocks premature completion |
| `compact-reinject.sh` | SessionStart(compact) | Re-injects pipeline state after compaction |
| `agent-inject.sh` | SubagentStart | Injects response contract into agents |
| `agent-output-validate.sh` | SubagentStop | Validates agent output format |
| `budget-track.sh` | PostToolUse | Logs tool-level budget, reads real context from transcript |

### What's NOT hooked yet (the gap):

1. **Task scaffold + initial state files** — orchestrator writes ~5 files manually
2. **Step transitions in `current.yaml`** — orchestrator does Read/modify/Write cycle
3. **Agent completion recording in `current.yaml`** — orchestrator writes history, budget
4. **Gate recording in `status.yaml`** — orchestrator appends gate decisions
5. **Session lifecycle (lock, guard-active)** — orchestrator creates/deletes files
6. **Completion cleanup** — orchestrator deletes lock/guard files (completion processor handles the rest via Bash)

---

## Automation Plan

### Phase 1: Task Initialization (`task-init.sh`)

**Hook event:** None directly. This is a **shell command** called by the `moira:task` skill before entering the orchestrator.

**Why not a hook:** Task creation happens before the pipeline starts. There's no hookable event that fires "when user runs `/moira:task`". The skill itself can call Bash to scaffold.

**What it does:**
1. Generate task ID (`moira_task_id`)
2. Create task directory (`mkdir -p`)
3. Write `manifest.yaml` (task_id, pipeline: null (set later), developer, checkpoint: null, created_at)
4. Write `status.yaml` (task_id, description, developer, created_at, empty gates, zero retries)
5. Write `input.md` (task description)
6. Write `current.yaml` (task_id, pipeline: null, step: classification, step_status: pending)
7. Write `.session-lock` (pid, started, task_id, ttl)
8. Write `.guard-active` (empty marker)
9. Output task_id to stdout for the orchestrator to consume

**Orchestrator change:** Instead of writing 5-6 files manually, the orchestrator reads the task_id from the skill's output. `current.yaml` already exists with the task scaffold.

**New file:** `src/global/lib/task-init.sh`

**Estimated savings:** ~3500 tokens per task start.

### Phase 2: Step Transition Automation (`step-transition.sh`)

**Hook event:** `PreToolUse` (matcher: `Agent`) — fires before every agent dispatch.

**Design insight:** The existing `pipeline-compliance.sh` already fires on `PreToolUse(Agent)` and knows the pipeline + role. We extend it (or add a sibling hook) to also write the step transition to `current.yaml`.

**What it does:**
1. Parse `description` field for agent role (same pattern as pipeline-compliance.sh)
2. Map role → pipeline step (classifier→classification, explorer→exploration, architect→architecture, planner→plan, implementer→implementation, reviewer→review, tester→testing, scribe→synthesis, analyst→analysis)
3. Call `moira_state_transition <step> in_progress` on `current.yaml`
4. No output needed (pipeline-compliance already handles additionalContext)

**Why PreToolUse, not SubagentStart:** SubagentStart fires for ALL agents including non-pipeline agents (scanners, completion processor, reflector). PreToolUse(Agent) has the `description` field needed for role extraction AND already has the guard-active check pattern.

**Complication — role-to-step mapping isn't 1:1:**
- Analytical pipeline: `analyst` maps to either `scope` or `analysis` or `depth_checkpoint` depending on position
- Solution: the hook reads `pipeline-tracker.state` to determine the correct step. For analytical: if last_role was explorer → step is `scope`. If in a deepen loop → step is `analysis`.

**New file:** `src/global/hooks/step-transition.sh`

**Orchestrator change:** Remove ~5-8 manual `current.yaml` step/step_status writes per pipeline.

**Estimated savings:** ~2500-4000 tokens per pipeline.

### Phase 3: Agent Completion Recording (`agent-done.sh`)

**Hook event:** `SubagentStop` — fires when any agent finishes.

**What it does:**
1. Parse `agent_type`, `last_assistant_message` from hook input
2. Extract STATUS, SUMMARY from `last_assistant_message` (regex: `STATUS: (success|failure|blocked|budget_exceeded)`)
3. Extract role from `agent_type` or infer from tracker state
4. Compute duration (read `step_started_at` from `current.yaml`, diff with now)
5. Call `moira_state_agent_done <step> <role> <status> <duration> <tokens> <summary>` — this updates:
   - `current.yaml` history block
   - `current.yaml` context_budget.total_agent_tokens
   - `status.yaml` budget.by_agent (via budget.sh)
   - Runs `moira_budget_orchestrator_check` to update orchestrator_percent and warning_level
6. Output: `additionalContext` with computed budget state (orchestrator_percent, warning_level) so the orchestrator doesn't need to Read current.yaml for budget data

**Token tracking:** The hook can't know the agent's token usage from `SubagentStop` input directly (it only gets `last_assistant_message`). However, `budget-track.sh` already extracts real context tokens from the transcript. For agent token tracking, we can estimate from the agent's transcript path (available in `SubagentStop` input as `agent_transcript_path`).

**Important:** This hook must NOT conflict with `agent-output-validate.sh` which also fires on `SubagentStop`. Since hooks run in parallel, both can write to different files safely. But if `agent-output-validate.sh` blocks the agent (exit 2 / decision:block), the agent hasn't actually stopped — so `agent-done.sh` must check for `stop_hook_active` to avoid recording partial completions.

**New file:** `src/global/hooks/agent-done.sh`

**Orchestrator change:** Remove ~5-8 manual Read/Write cycles for recording agent results. The orchestrator still reads the agent's response for gate presentation (SUMMARY, STATUS, QUALITY) but doesn't need to write the bookkeeping.

**Estimated savings:** ~3000-4000 tokens per pipeline.

### Phase 4: Gate Recording (`gate-record.sh`)

**Hook event:** This is the trickiest operation to automate. Gate decisions happen through orchestrator-user interaction. There's no hook event for "user chose option 1 at a gate."

**Options considered:**

1. **PostToolUse(Write) hook** — detect when orchestrator writes to status.yaml gates block → but this IS the manual write we're trying to eliminate
2. **New shell function called by orchestrator via a different path** — orchestrator can't call Bash
3. **Keep manual** — gate recording stays in the orchestrator

**Decision: Keep gate recording manual, but simplify it.**

Gate recording is inherently a decision point — the orchestrator MUST know the gate decision to route the pipeline. Writing 1 gate entry to `status.yaml` is ~400 tokens. With ~3-5 gates per pipeline, that's ~1200-2000 tokens. The cost is modest and eliminating it would require a new hook event type or a communication channel that doesn't exist.

**However, we can simplify by batching:** Instead of the orchestrator doing separate Read + Edit + Write for each gate, we provide a dedicated Write template that the orchestrator fills in once. The `pipeline-tracker.sh` can be extended to record the gate decision when it detects a post-gate agent dispatch (the gate decision is implied by which agent is dispatched next).

**Partial automation:** The `pipeline-tracker.sh` already fires on PostToolUse(Agent). After a gate, the next Agent dispatch implies the gate decision:
- Dispatch implementer after plan gate → plan gate: proceed
- Dispatch reviewer after implementation → no gate implied (automatic)
- Dispatch architect after plan gate → plan gate: rearchitect (modify)

This doesn't cover all cases cleanly (explicit proceed vs rearchitect), so we **keep manual gate recording** but reduce the Write overhead:

**Optimization:** Instead of Read-modify-Write for each gate, the orchestrator can Write the full status.yaml once at pipeline end (all gate decisions accumulated in memory during the session). But this risks data loss on crash.

**Final decision:** Keep gate recording manual. The savings from phases 1-3 are sufficient (~9-12k tokens per pipeline).

### Phase 5: Session Lifecycle Automation

**Hook event:** `SessionStart(startup)` + `SessionEnd`

#### `session-lock.sh` (SessionStart)

**What it does:**
1. Check if `.claude/moira/` exists (is this a Moira project?)
2. Check existing `.session-lock` for stale locks
3. If stale → delete
4. If live → output warning as `additionalContext`: "Another Moira session may be active"
5. Does NOT create lock (task-init.sh does this when a task actually starts)

#### `session-cleanup.sh` (SessionEnd)

**What it does:**
1. Check if `.guard-active` exists
2. If yes → check if `current.yaml` has step_status=completed or step_status=checkpointed
3. If completed/checkpointed: delete `.session-lock`, delete `.guard-active`, clean up `pipeline-tracker.state`
4. If NOT completed (abnormal exit): leave state files for `/moira:resume`

**New files:** `src/global/hooks/session-lock.sh`, `src/global/hooks/session-cleanup.sh`

**Orchestrator change:** Remove manual session-lock creation (moved to task-init.sh), remove manual cleanup at completion (moved to SessionEnd hook and completion.sh).

**Estimated savings:** ~500-1000 tokens.

### Phase 6: State Injection via Hook Output

Currently, after writing to `current.yaml`, the orchestrator has to Read it back to get values (e.g., orchestrator_percent, warning_level). With hooks writing state, the hooks can also **inject computed values** into the orchestrator's context via `additionalContext`.

**Extended hook output from `agent-done.sh`:**

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStop",
    "additionalContext": "AGENT COMPLETION — Role: reviewer, Status: success, Duration: 45s. BUDGET: orchestrator_percent=12%, warning_level=normal, total_agent_tokens=340k. PIPELINE: step=review, next=testing."
  }
}
```

This means the orchestrator knows the budget state WITHOUT reading `current.yaml`. For gate health reports, it can use the last injected values instead of a Read operation.

**Estimated savings:** ~1000-2000 tokens per pipeline (avoided Read operations).

---

## Summary of Changes

### New Files

| File | Type | Purpose |
|------|------|---------|
| `src/global/lib/task-init.sh` | Shell lib | Task scaffold + initial state files |
| `src/global/hooks/step-transition.sh` | Hook (PreToolUse:Agent) | Auto-update step/step_status in current.yaml |
| `src/global/hooks/agent-done.sh` | Hook (SubagentStop) | Record agent completion, budget, inject state |
| `src/global/hooks/session-cleanup.sh` | Hook (SessionEnd) | Clean up lock/guard files |

### Modified Files

| File | Change |
|------|--------|
| `src/global/skills/orchestrator.md` | Remove manual state writes for: task init, step transitions, agent completion recording, session lock management. Add note that hooks handle these. Keep: gate recording, pipeline selection, error routing, analytical state. |
| `src/global/hooks/pipeline-tracker.sh` | Extend with session lifecycle data. May be merged with step-transition logic to avoid two PreToolUse(Agent) hooks. |
| `src/global/skills/dispatch.md` | Note that step transitions are now automated |
| `src/global/lib/state.sh` | Add `moira_state_init_task()` function used by task-init.sh |
| `.claude/settings.json` | Register new hooks |
| `src/install.sh` | Copy new hooks to `~/.claude/moira/hooks/` |

### Settings Changes

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/pipeline-compliance.sh" },
          { "type": "command", "command": "bash ~/.claude/moira/hooks/step-transition.sh" }
        ]
      },
      {
        "matcher": "Read|Write",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/guard-prevent.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/guard.sh" },
          { "type": "command", "command": "bash ~/.claude/moira/hooks/budget-track.sh" }
        ]
      },
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/pipeline-tracker.sh" }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/pipeline-stop-guard.sh" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/compact-reinject.sh" }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/agent-inject.sh" }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/agent-output-validate.sh" },
          { "type": "command", "command": "bash ~/.claude/moira/hooks/agent-done.sh" }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          { "type": "command", "command": "bash ~/.claude/moira/hooks/session-cleanup.sh" }
        ]
      }
    ]
  }
}
```

### What Stays Manual (By Design)

| Operation | Why |
|-----------|-----|
| Gate recording | Decision point — orchestrator must know the decision to route. No hookable event. |
| Pipeline selection | Requires reading classifier output + applying selection logic. Decision, not bookkeeping. |
| Error routing | Requires reading agent STATUS + conditional logic. Decision, not bookkeeping. |
| Analytical convergence state | Complex state updates tied to gate decisions (deepen/redirect/sufficient). |
| Bootstrap checks (graph/temporal) | One-time reads + writes at pipeline start. Low volume. |
| `classification.md` write | Written by Apollo agent, not orchestrator. |
| Quality gate processing | Decision logic requiring QUALITY line parsing + routing. |

---

## Token Savings Estimate

| Phase | Savings per pipeline | Notes |
|-------|---------------------|-------|
| Phase 1: Task init | ~3500 tokens | 5-6 file writes eliminated |
| Phase 2: Step transitions | ~3000 tokens | 5-8 Read/Write cycles eliminated |
| Phase 3: Agent completion | ~3500 tokens | 5-8 history/budget writes eliminated |
| Phase 4: Gate recording | 0 | Kept manual |
| Phase 5: Session lifecycle | ~700 tokens | Lock/guard management |
| Phase 6: State injection | ~1500 tokens | Avoided Read operations |
| **Total** | **~12,200 tokens** | **~25% of a quick pipeline's budget** |

---

## Risk Analysis

### What could go wrong

1. **Hook failure → state corruption:** If `step-transition.sh` fails silently, `current.yaml` has wrong step. The orchestrator would proceed on stale state.
   - **Mitigation:** Hooks MUST NOT fail silently on state writes. Use `set -euo pipefail` + explicit error handling. On write failure, output `additionalContext` warning so the orchestrator knows.

2. **Race condition between hooks:** `agent-done.sh` (SubagentStop) and `pipeline-tracker.sh` (PostToolUse:Agent) both fire when an agent completes. Both may write to `current.yaml`.
   - **Mitigation:** Clearly partition which fields each hook writes. `pipeline-tracker.sh` writes to `pipeline-tracker.state` (separate file). `agent-done.sh` writes to `current.yaml` history and budget fields. No overlap.

3. **Hook fires outside pipeline context:** hooks fire for ALL sessions, not just Moira pipelines. A normal Claude Code session would trigger `step-transition.sh` on any Agent call.
   - **Mitigation:** All hooks already check for `.guard-active` marker file. Only fire during active pipelines.

4. **SubagentStop hook can't determine agent role:** `SubagentStop` provides `agent_type` (e.g., "general-purpose") not the Moira role.
   - **Mitigation:** Read `last_role` from `pipeline-tracker.state` (written by `pipeline-tracker.sh` on PostToolUse:Agent, which fires before SubagentStop for the same agent).
   - **Ordering concern:** PostToolUse fires AFTER the tool completes. SubagentStop fires when the subagent finishes. These should be the same event in sequence. Need to verify: does PostToolUse(Agent) fire before or after SubagentStop? If SubagentStop fires first, agent-done.sh can't read tracker state yet.
   - **Fallback:** Parse role from the `last_assistant_message` (agents output their role in the STATUS line) or from the orchestrator's Agent dispatch description (cached in tracker).

5. **Orchestrator still writes state for things hooks should handle:** Prompt drift — over time, the orchestrator might fall back to manual writes.
   - **Mitigation:** Add a `PostToolUse(Write)` check in `guard.sh` that warns if orchestrator writes to fields that hooks should manage (e.g., `current.yaml` history block).

### Constitutional impact

- Art 1.1 (orchestrator boundaries): NOT affected — hooks run in shell, orchestrator still doesn't use Bash
- Art 2.2 (mandatory steps): NOT affected — step transitions are now more reliable (deterministic hook vs LLM remembering)
- Art 3.1 (audit trail): IMPROVED — hooks always log, no chance of orchestrator forgetting
- Art 4.2 (user authority): NOT affected — gates stay manual

---

## Success Criteria

1. All existing tests in `src/tests/` pass
2. `/moira:bench` behavioral tests pass with no regressions
3. Standard pipeline completes with ~12k fewer orchestrator tokens (measure via budget report)
4. No manual `current.yaml` writes for step transitions or agent completion (verified by guard.sh audit log)
5. Session lock/guard cleanup happens automatically on session end
6. Hook failures produce visible warnings, not silent state corruption

---

## Open Questions

1. **PostToolUse(Agent) vs SubagentStop ordering:** Need to verify which fires first. This determines whether `agent-done.sh` can read `pipeline-tracker.state` for role information.

2. **task-init.sh invocation:** The `moira:task` skill currently enters the orchestrator which writes state. Moving initialization to before the orchestrator requires changing the skill flow. Alternative: the orchestrator's first action is a single `source task-init.sh` equivalent Write — still manual but much simpler (one file write vs six).

3. **Merge step-transition into pipeline-compliance:** Both fire on PreToolUse(Agent). Running two hooks on the same event with the same matcher spawns two processes. Merging reduces overhead but increases complexity of one script.
