# Error Handling Procedures

Reference: `design/subsystems/fault-tolerance.md`

This skill defines how the orchestrator detects, recovers from, and displays errors during pipeline execution.

---

## E1-INPUT: Missing Data

### Detection

Agent returns `STATUS: blocked` with `REASON` and `NEED` fields.

### Recovery

1. Parse the agent's `REASON` (what is missing) and `NEED` (what question to ask)
2. Set `gate_pending: blocked` in `current.yaml`
3. Present the BLOCKED display to user
4. Wait for user response
5. On `answer`: re-dispatch the same agent with the original context + user's answer appended
6. On `point`: read the file/doc the user indicated, include its content, re-dispatch agent
7. On `skip`: instruct agent to mark the blocked item as TODO and proceed with remaining work
8. On `abort`: set pipeline status to `failed`, record reason in `status.yaml`

### Display

```
═══════════════════════════════════════════
 ⏸ BLOCKED: Missing Information
═══════════════════════════════════════════

 Agent: {Name} ({role})
 Step: {step_number}/{total_steps} — {step_description}

 Problem: {agent REASON}

 Need from you:
 → {agent NEED}

 1) answer — provide the information
 2) point  — point to a file/doc with the answer
 3) skip   — mark as TODO in code
 4) abort  — stop task
═══════════════════════════════════════════
```

### State Updates

- `current.yaml`: `step_status: awaiting_gate`, `gate_pending: blocked_e1`
- `status.yaml`: append to `gates` block with gate=`blocked_e1_{step}`, decision=user choice

### Escalation

None — user always resolves E1.

---

## E2-SCOPE: Scope Change Detected

### Detection

Explorer or Architect signals that the task is larger/more complex than classified. Look for scope change indicators in agent SUMMARY:
- "Task is larger than classified"
- "Scope exceeds {size} classification"
- Agent explicitly recommends pipeline upgrade

### Recovery

1. STOP current pipeline immediately
2. Preserve ALL existing work (exploration, analysis artifacts are valid data)
3. Present scope change display to user
4. On `upgrade`: re-classify at new size, re-enter pipeline at Architect step (reuse Explorer/Analyst data)
5. On `split`: dispatch Planner to break task into multiple independent tasks
6. On `reduce`: ask user what to cut, update task description, re-enter at current step
7. On `continue`: display warning ("proceeding at original classification — quality risk"), continue pipeline

### Display

```
═══════════════════════════════════════════
 ⚠ SCOPE CHANGE DETECTED
═══════════════════════════════════════════

 Agent: {Name} ({role})
 Step: {step_number}/{total_steps}

 Original classification: {original_size} → {original_pipeline}
 Detected scope: {detected_size}

 Reason: {agent's scope change reasoning}

 Existing work preserved:
 {list of valid artifacts from completed steps}

 1) upgrade  — re-plan at {detected_size} size (recommended)
 2) split    — break into separate tasks
 3) reduce   — simplify scope (you decide what to cut)
 4) continue — proceed as-is (⚠ quality risk)
═══════════════════════════════════════════
```

### State Updates

- `current.yaml`: `step_status: awaiting_gate`, `gate_pending: scope_change_e2`
- `status.yaml`: append to `gates` block, record decision and original/new classification

### Escalation

None — user always resolves E2.

---

## E3-CONFLICT: Contradictions

### Detection

Agent documents conflicting requirements, code patterns, or conventions in its output. Look for:
- "Conflict detected" in agent SUMMARY
- Agent returns `STATUS: blocked` with conflict details

### Recovery

1. Parse the agent's conflict documentation (both sides, pros/cons)
2. Present conflict display to user with agent's recommendation (informational only)
3. User chooses resolution
4. Re-dispatch agent with user's chosen resolution as additional context

### Display

```
═══════════════════════════════════════════
 ⚡ CONFLICT DETECTED
═══════════════════════════════════════════

 Agent: {Name} ({role})
 Step: {step_number}/{total_steps}

 What conflicts:
 {conflict description}

 Option A: {option_a_description}
   ✓ {pro_1}
   ✗ {con_1}

 Option B: {option_b_description}
   ✓ {pro_1}
   ✗ {con_1}

 Agent recommendation: {agent's recommendation} (informational)

 1) a — choose Option A
 2) b — choose Option B
═══════════════════════════════════════════
```

### State Updates

- `current.yaml`: `step_status: awaiting_gate`, `gate_pending: conflict_e3`
- `status.yaml`: append gate record with chosen option

### Escalation

None — user always resolves E3.

---

## E4-BUDGET: Context Overflow

### Detection

**Pre-execution:** Planner estimates context usage exceeds agent budget limit.
**Mid-execution:** Agent returns `STATUS: budget_exceeded` with `COMPLETED` and `REMAINING` fields.

### Recovery — Pre-execution

Handled by Daedalus (planner) during plan creation:
1. Planner estimates context usage per step (file sizes + knowledge + MCP)
2. If estimate exceeds 70% of agent budget → Planner auto-splits into sub-steps with independent file sets
3. Split is logged in plan artifact with reasoning
4. No gate needed (technical optimization, transparent in plan)

### Recovery — Mid-execution

When agent returns `STATUS: budget_exceeded` with `COMPLETED` and `REMAINING` fields:
1. Read agent's partial result file (it wrote output before stopping)
2. Parse `COMPLETED` and `REMAINING` from agent response
3. Call `moira_budget_handle_overflow <task_id> <role> <completed> <remaining>` to handle the overflow (increments `retries.budget_splits`, returns continuation or escalation data)
4. Record partial result in budget tracking
5. Spawn NEW continuation agent with:
   - Task-specific instruction: "Continue work. Previously completed: {completed}. Your task: {remaining}."
   - Reference to partial result file in `.claude/moira/state/tasks/{task_id}/`
   - Same budget allocation as original agent

### Display — Mid-execution

```
═══════════════════════════════════════════
 ⚠ BUDGET OVERFLOW
═══════════════════════════════════════════

 Agent: {Name} ({role})

 Completed: {completed_items}
 Remaining: {remaining_items}

 Spawning continuation agent for remaining work...
═══════════════════════════════════════════
```

### State Updates

- `status.yaml`: increment `retries.budget_splits` counter
- `current.yaml`: update `context_budget.total_agent_tokens`

### Escalation — Double Overflow

If continuation agent ALSO returns `budget_exceeded` (budget_splits >= 2):

```
═══════════════════════════════════════════
 🔴 REPEATED BUDGET OVERFLOW
═══════════════════════════════════════════

 Agent: {Name} ({role})

 This step has overflowed twice.
 Original estimate may be significantly wrong.

 Completed so far: {all completed items}
 Still remaining: {remaining items}

 1) split   — manually split remaining work
 2) retry   — try again with larger budget (not recommended)
 3) abort   — stop task, keep partial results
═══════════════════════════════════════════
```

State: record gate as `moira_state_gate("budget_overflow_e4", decision)`

### Critical Level Override

When `context_budget.warning_level` is `critical` (>60%), E4-BUDGET mid-execution recovery changes:

1. Instead of spawning a continuation agent, route to mandatory checkpoint flow
2. Call `moira_checkpoint_create <task_id> <current_step> context_limit`
3. Display context warning with mandatory checkpoint message:

```
═══════════════════════════════════════════
 🔴 CONTEXT BUDGET CRITICAL (>60%)
═══════════════════════════════════════════

 Orchestrator context usage has reached critical level.
 Mandatory checkpoint — cannot continue in this session.

 Progress saved. Resume in a new session:
 → /moira resume
═══════════════════════════════════════════
```

4. Stop pipeline — user must resume in new session via `/moira resume`

This overrides the default E4-BUDGET mid-exec recovery only at critical level. Normal and warning levels continue to use the standard continuation agent flow.

---

## E5-QUALITY: Quality Gate Failed

### Detection

Reviewer returns findings with severity `CRITICAL`. Parse the review artifact for CRITICAL items.

### Recovery

Before retrying, consult retry optimizer: `moira_retry_should_retry E5_QUALITY {agent_type}`. If optimizer recommends skipping retry (low success probability), present recommendation to user with probability and suggest escalation instead.

**Attempt 1 (retry with feedback):**

1. Extract CRITICAL findings from review
2. Re-dispatch Implementer with: original instructions + reviewer feedback
3. Re-dispatch Reviewer on updated code
4. If review passes → continue pipeline

**Attempt 2 (different approach):**

1. If Attempt 1 review still has CRITICAL findings
2. Re-dispatch Architect to re-examine the decision
3. Re-dispatch Planner with new approach
4. Re-dispatch Implementer with new plan
5. Re-dispatch Reviewer
6. If passes → continue pipeline

**After 2 retries (3 total attempts) → escalate:**

Present quality failure gate to user.

### Display — During Retry

```
═══════════════════════════════════════════
 🔄 QUALITY RETRY (attempt {n}/3, including original)
═══════════════════════════════════════════

 Reviewer found {count} CRITICAL issue(s):
 {list of critical findings}

 Re-dispatching Hephaestus (implementer) with feedback...
═══════════════════════════════════════════
```

### Display — After Max Retries

```
═══════════════════════════════════════════
 🔴 QUALITY GATE FAILED (2 retries exhausted)
═══════════════════════════════════════════

 Step: {step_description}

 Attempt 1: {attempt_1_issue}
 Fix applied: {attempt_1_fix}

 Attempt 2: {attempt_2_issue}

 Root cause analysis:
 {analysis of why both attempts failed}

 1) redesign — send back to Metis (architect)
 2) manual   — you'll handle this part
 3) simplify — remove feature, find simpler approach
═══════════════════════════════════════════
```

### State Updates

- `status.yaml`: increment `retries.quality` counter per attempt
- Track each attempt's findings in status.yaml retries block

### Escalation

After 2 retries (3 total attempts) → present quality failure gate. User decides next action.

**Pipeline-specific:** Quick Pipeline limits E5 retries to max_attempts=2 (single retry only).

---

## E6-AGENT: Agent Failure

### Detection

- Agent returns `STATUS: failure`
- Agent returns nonsensical output (cannot parse STATUS line)
- Agent times out (no response)

### Recovery

Before retrying, consult retry optimizer: `moira_retry_should_retry E6_AGENT {agent_type}`. If optimizer recommends skipping retry (low success probability), present recommendation to user with probability and suggest escalation instead.

**Retry 1x:**

1. Re-dispatch same agent with identical input
2. If succeeds → continue pipeline normally

**If retry also fails → diagnose:**

1. Check: was input valid? (files exist, instructions complete)
2. Check: were instructions clear? (no ambiguity, no contradictions)
3. Check: was context budget within limits?
4. Compile diagnostic report

**Escalate with report:**

### Display — During Retry

```
═══════════════════════════════════════════
 🔄 AGENT RETRY
═══════════════════════════════════════════

 {Name} ({role}) failed. Retrying (attempt 2/2)...
═══════════════════════════════════════════
```

### Display — After Failure

```
═══════════════════════════════════════════
 🔴 AGENT FAILURE
═══════════════════════════════════════════

 Agent: {Name} ({role})

 Failure: {description of failure}
 Retry: Same result.

 Diagnosis:
 - Input valid: {yes/no}
 - Instructions clear: {yes/no}
 - Context budget: {percentage}% {status_emoji}
 - Likely cause: {diagnosis}

 Other agents: {status of other agents in pipeline}

 Recommendation: {recommendation}

 1) retry-split — split work and retry (recommended if budget issue)
 2) retry-as-is — retry same task
 3) manual      — handle manually
 4) rollback    — undo all, re-plan
═══════════════════════════════════════════
```

### State Updates

- `status.yaml`: increment `retries.agent_failures` counter
- Log failure details in retries block

### Escalation

After retry failure → present agent failure gate. User decides next action.

**Note:** Resume validation failures (inconsistent, branch_changed, external_changes) are command-level errors handled by `/moira resume` command, not pipeline-level error handlers.

---

## E7-DRIFT: Orchestrator Rule Violation

**Scope:** Orchestrator-level violations only. Agent-level violations are handled by the post-agent guard check (D-099) via the Guard Violation Gate in `gates.md`.

### Detection

Guard hook (`guard.sh`) detects violations in real-time via PostToolUse:
- Orchestrator uses Read/Write/Edit on files outside `.claude/moira/`
- Violation logged to `state/violations.log` with `VIOLATION` prefix
- Warning injected into orchestrator context via hookSpecificOutput

Note: guard.sh is registered in `settings.json` and fires only in the orchestrator session — `settings.json` hooks do not propagate to subagent sessions (D-099, D-116). Agent violations are detected via post-agent git diff check in the pipeline execution loop (orchestrator.md Section 2, step d1).

### During Pipeline

On violation detection (guard hook fires):
1. Violation is ALREADY logged (guard.sh handles this)
2. Warning message appears in orchestrator context
3. Orchestrator MUST acknowledge the violation in its next output
4. Include violation count in next health report

### Post-Task Audit

After pipeline completion, check orchestrator violations:
1. Count orchestrator violations: count lines with `VIOLATION` prefix in `state/violations.log` (exclude `AGENT_VIOLATION` lines)
2. If orchestrator violations > 0:
   - Include in completion summary: "{N} orchestrator violations detected"
   - Log in telemetry: `compliance.orchestrator_violation_count` (integer)
   - Flag for Reflector analysis (Phase 10)
   - If violations > 3: recommend rule strengthening

### Display

When violations exist, add to health report:

```
ORCHESTRATOR HEALTH:
├─ Context: ~22k/1M (2%) ✅
├─ Violations: {count} 🔴  ← highlighted when > 0
...
```

### State Updates

- `state/violations.log`: appended by guard.sh on each orchestrator violation (`timestamp VIOLATION tool_name file_path`). Agent violations are appended by the post-agent guard check (`timestamp AGENT_VIOLATION agent_role file_path`) — see D-099, D-116.
- `state/tool-usage.log`: appended by guard.sh on every orchestrator tool call (audit trail)
- `telemetry.yaml`: `compliance.orchestrator_violation_count` written at task completion (orchestrator `VIOLATION` lines only)

### Recovery

No automated recovery — violations are informational.
- `allowed-tools` prevents most violations structurally
- Guard hook catches edge cases
- Reflector tracks patterns for trend analysis (Phase 10)
- Audit recommends rule changes if violations are recurring (via `/moira audit`)

### Escalation

No automated escalation. Violations are informational only.
- If violations > 3 in a single task: recommend rule strengthening in completion summary
- Reflector (Phase 10) analyzes patterns across tasks
- Audit tracks frequency trends (via `/moira audit`)

---

## E8-STALE: Outdated Knowledge

### Detection

At pipeline start (after classification, before dispatching exploration agents), check knowledge freshness:

1. Read the current task number from status files (count of completed tasks)
2. Call freshness check on all knowledge types used by the current pipeline
3. If any entries are `stale` (confidence below 30% via exponential decay):

### Display

```
═══════════════════════════════════════════
 ⚠ STALE KNOWLEDGE WARNING
═══════════════════════════════════════════

 The following knowledge entries have confidence
 below 30% (exponential decay):
   - {type}: last confirmed at task {task_id}
     ({distance} tasks ago)
   ...

 Stale knowledge may lead to incorrect agent decisions.

 1) proceed — continue (agents may use outdated info)
 2) refresh — run /moira:refresh to update first
═══════════════════════════════════════════
```

### Non-blocking

This is a WARNING, not a gate. Pipeline continues after display.
The user can choose to refresh or proceed.

### State

Log stale entries to `status.yaml` under `warnings:` block.

### Automatic Knowledge Freshness During Pipeline

When an Explorer dispatched during pipeline execution discovers that a knowledge entry contradicts current code state:

1. Explorer reports the contradiction in its output (standard E8-STALE behavior)
2. The orchestrator flags the stale entry in the current task's `status.yaml` under `warnings:` block
3. At the next gate presentation, the orchestrator includes a note: "⚠ Stale knowledge detected: {entry} — flagged for refresh"
4. After pipeline completion, Mnemosyne's reflection includes the stale entry in its knowledge update observations
5. The stale entry is prioritized for verification at the next `/moira refresh`

This is passive detection — the pipeline does not stop for stale knowledge unless it directly blocks an agent (E1-INPUT). Active refresh of stale entries happens through `/moira refresh` or `/moira audit knowledge`.

---

## E9-SEMANTIC: Factually Wrong Content

### Detection

Reviewer verifies factual claims against Explorer data during quality review. Architecture gate provides human verification. Reflector catches post-hoc in systemic analysis.

Look for:
- Implementation references APIs, types, or patterns that don't exist in the codebase
- Architecture decisions based on incorrect assumptions about project structure
- Code that contradicts Explorer's findings about conventions or dependencies

### Recovery

**Reviewer-detected (during review step):**

Follow E5-QUALITY retry path:
1. Extract factual errors from review findings
2. Re-dispatch Hephaestus (implementer) with: original instructions + reviewer's factual corrections
3. Re-dispatch Themis (reviewer) on updated code
4. If still failing after max attempts → escalate per E5-QUALITY

**Note:** E9-SEMANTIC shares E5-QUALITY's retry counter. The E9 max_attempts value is capped by E5-QUALITY's budget.

**Gate-detected (user spots error at gate):**

1. User selects `modify` at the gate
2. Re-dispatch the responsible agent with user's correction
3. Continue pipeline from that point

### Display — Reviewer-detected

```
═══════════════════════════════════════════
 🔄 QUALITY RETRY — FACTUAL ERROR (attempt {n}/{max})
═══════════════════════════════════════════

 Themis (reviewer) found factual errors:
 {list of factual findings}

 Re-dispatching Hephaestus (implementer) with corrections...
═══════════════════════════════════════════
```

### State Updates

- Routed through E5-QUALITY state tracking (same retry counters)
- `status.yaml`: increment `retries.quality` counter per attempt

### Escalation

Same as E5-QUALITY — after max retry attempts, present quality failure gate to user.

---

## E10-DIVERGE: Agent Data Conflict

### Detection

Architect compares Explorer and Analyst data and finds contradictory facts about the same codebase. Examples:
- Explorer reports 14 API endpoints, Analyst scopes 6
- Explorer finds module A depends on B, Analyst reports no dependency
- Different agent outputs disagree on project structure or conventions

Look for:
- Metis (architect) signals "data conflict" or "contradiction" in SUMMARY
- Architect returns `STATUS: blocked` with contradiction details

### Recovery

1. Parse Metis (architect) contradiction report: both data sources, specific discrepancies
2. Present divergence display to user at architecture gate
3. User chooses which data source is correct (or requests clarification)
4. Re-dispatch Metis (architect) with user's resolution as additional context

### Display

```
═══════════════════════════════════════════
 ⚡ AGENT DATA CONFLICT
═══════════════════════════════════════════

 Metis (architect) found contradictory data
 from upstream agents:

 Source A — Hermes (explorer):
 {explorer's claim}

 Source B — Athena (analyst):
 {analyst's claim}

 Discrepancy: {description of contradiction}

 1) use-explorer — trust Hermes (explorer) data
 2) use-analyst  — trust Athena (analyst) data
 3) clarify      — provide additional context
 4) abort        — cancel task
═══════════════════════════════════════════
```

### State Updates

- `current.yaml`: `step_status: awaiting_gate`, `gate_pending: diverge_e10`
- `status.yaml`: append to `gates` block with gate=`diverge_e10`, decision=user choice

### Escalation

None — user always resolves E10.

---

## E11-TRUNCATION: Context Truncation

### Detection

**Pre-execution:** Budget system estimates agent context usage near or exceeding limit during plan creation. Daedalus (planner) flags steps where estimated tokens exceed 70% of agent budget.

**Post-execution:** Themis (reviewer) catches output that is incomplete or violates known constraints, suggesting context window filled and early instructions were lost.

### Recovery — Pre-execution

Follow E4-BUDGET split path:
1. Planner auto-splits the step into sub-steps with independent file sets
2. Split is logged in plan artifact with reasoning
3. No gate needed (technical optimization, transparent in plan)

### Recovery — Post-execution

Follow E5-QUALITY retry with reduced scope:
1. Extract truncation indicators from review findings
2. Re-dispatch Hephaestus (implementer) with reduced scope (fewer files, smaller context)
3. Re-dispatch Themis (reviewer) on updated code
4. If still failing → escalate per E5-QUALITY

### Display — Pre-execution

```
═══════════════════════════════════════════
 ⚠ BUDGET PRE-CHECK: TRUNCATION RISK
═══════════════════════════════════════════

 Daedalus (planner) estimates step {step} may
 exceed context limits.

 Estimated usage: ~{est}k/{limit}k ({pct}%)

 Auto-splitting into sub-steps with independent
 file sets...
═══════════════════════════════════════════
```

### Display — Post-execution

```
═══════════════════════════════════════════
 🔄 QUALITY RETRY — TRUNCATION DETECTED (attempt {n}/{max})
═══════════════════════════════════════════

 Themis (reviewer) found signs of context truncation:
 {list of truncation indicators}

 Re-dispatching Hephaestus (implementer)
 with reduced scope...
═══════════════════════════════════════════
```

### State Updates

- Pre-execution: routed through E4-BUDGET state tracking (`retries.budget_splits`)
- Post-execution: routed through E5-QUALITY state tracking (`retries.quality`)

### Escalation

- Pre-execution: follows E4-BUDGET escalation (double overflow → user gate)
- Post-execution: follows E5-QUALITY escalation (max retries → user gate)

**Pipeline-specific:** Quick Pipeline limits E11 post-exec retries to max_attempts=1 (zero retries) for lightweight execution.

---

## DAG Cycle Detection

Not a separate error code — handled inline during epic decomposition.

### Detection

When `moira_epic_validate_dag` returns `cycle_detected` during Decomposition Pipeline planning.

### Display

```
═══════════════════════════════════════════
 🔴 EPIC DECOMPOSITION: CIRCULAR DEPENDENCIES
═══════════════════════════════════════════

 Epic decomposition contains circular
 dependencies: {cycle_path}

 1) modify — send back to Daedalus (planner)
    with cycle feedback
 2) abort  — cancel task
═══════════════════════════════════════════
```

### Recovery

- `modify`: re-dispatch Daedalus (planner) with the cycle path as feedback, requesting a DAG without circular dependencies
- `abort`: stop pipeline, record failure

No automatic retry — cycles are a planning error, not a transient failure.

### State Updates

- Recorded as part of decomposition gate flow (not a separate gate)
- If `modify`: Daedalus (planner) re-invoked with cycle feedback appended to original context

---

## Retry Counter Management

All retries are tracked in `status.yaml` retries block:

```yaml
retries:
  quality: 0
  agent_failures: 0
  budget_splits: 0
  total: 0
```

After each retry:
1. Increment the specific counter and `total` via `moira_state_increment_retry <task_id> <type>`:
   - E5-QUALITY retries: `moira_state_increment_retry <task_id> quality`
   - E6-AGENT retries: `moira_state_increment_retry <task_id> agent_failures`
   - E4-BUDGET splits: handled by `moira_budget_handle_overflow` (increments `retries.budget_splits` directly)
   - Generic retries: `moira_state_increment_retry <task_id>` (increments `total` only)
2. Include retry count in health report at next gate
