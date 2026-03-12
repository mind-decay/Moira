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
⏸ BLOCKED: Missing Information
Agent: {Name} ({role})
Step: {step_number}/{total_steps} — {step_description}

Problem: {agent REASON}

Need from you:
→ {agent NEED}

▸ answer — provide the information
▸ point  — point to a file/doc with the answer
▸ skip   — mark as TODO in code
▸ abort  — stop task
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
⚠ SCOPE CHANGE DETECTED
Agent: {Name} ({role})
Step: {step_number}/{total_steps}

Original classification: {original_size} → {original_pipeline}
Detected scope: {detected_size}

Reason: {agent's scope change reasoning}

Existing work preserved:
{list of valid artifacts from completed steps}

▸ upgrade  — re-plan at {detected_size} size (recommended)
▸ split    — break into separate tasks
▸ reduce   — simplify scope (you decide what to cut)
▸ continue — proceed as-is (⚠ quality risk)
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
⚡ CONFLICT DETECTED
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

▸ a — choose Option A
▸ b — choose Option B
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
3. Increment `retries.budget_splits` in `status.yaml`
4. Record partial result in budget tracking
5. Spawn NEW continuation agent with:
   - Task-specific instruction: "Continue work. Previously completed: {completed}. Your task: {remaining}."
   - Reference to partial result file in `state/tasks/{task_id}/`
   - Same budget allocation as original agent

### Display — Mid-execution

```
⚠ BUDGET OVERFLOW
Agent: {Name} ({role})

Completed: {completed_items}
Remaining: {remaining_items}

Spawning continuation agent for remaining work...
```

### State Updates

- `status.yaml`: increment `retries.budget_splits` counter
- `current.yaml`: update `context_budget.total_agent_tokens`

### Escalation — Double Overflow

If continuation agent ALSO returns `budget_exceeded` (budget_splits >= 2):

```
🔴 REPEATED BUDGET OVERFLOW
Agent: {Name} ({role})

This step has overflowed twice.
Original estimate may be significantly wrong.

Completed so far: {all completed items}
Still remaining: {remaining items}

▸ split   — manually split remaining work
▸ retry   — try again with larger budget (not recommended)
▸ abort   — stop task, keep partial results
```

State: record gate as `moira_state_gate("budget_overflow_e4", decision)`

---

## E5-QUALITY: Quality Gate Failed

### Detection

Reviewer returns findings with severity `CRITICAL`. Parse the review artifact for CRITICAL items.

### Recovery

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

**After 2 failures → escalate:**

Present quality failure gate to user.

### Display — During Retry

```
🔄 QUALITY RETRY (attempt {n}/2)
Reviewer found {count} CRITICAL issue(s):
{list of critical findings}

Re-dispatching Hephaestus (implementer) with feedback...
```

### Display — After Max Retries

```
🔴 QUALITY GATE FAILED (2 attempts)
Step: {step_description}

Attempt 1: {attempt_1_issue}
Fix applied: {attempt_1_fix}

Attempt 2: {attempt_2_issue}

Root cause analysis:
{analysis of why both attempts failed}

▸ redesign — send back to Metis (architect)
▸ manual   — you'll handle this part
▸ simplify — remove feature, find simpler approach
```

### State Updates

- `status.yaml`: increment `retries.quality` counter per attempt
- Track each attempt's findings in status.yaml retries block

### Escalation

After 2 failures → present quality failure gate. User decides next action.

---

## E6-AGENT: Agent Failure

### Detection

- Agent returns `STATUS: failure`
- Agent returns nonsensical output (cannot parse STATUS line)
- Agent times out (no response)

### Recovery

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
🔄 AGENT RETRY
{Name} ({role}) failed. Retrying (attempt 2/2)...
```

### Display — After Failure

```
🔴 AGENT FAILURE
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

▸ retry-split — split work and retry (recommended if budget issue)
▸ retry-as-is — retry same task
▸ manual      — handle manually
▸ rollback    — undo all, re-plan
```

### State Updates

- `status.yaml`: increment `retries.agent_failures` counter
- Log failure details in retries block

### Escalation

After retry failure → present agent failure gate. User decides next action.

---

## E7-DRIFT: Orchestrator Rule Violation (STUB)

Phase 3 stub per D-038. Full detection in Phase 8.

### Detection

No automated detection in Phase 3. Guard hook (Phase 8) will detect violations.

### Recovery

If a violation is detected by any means:
1. Log violation to `state/violations.log`
2. Include violation count in health report
3. No automated recovery — user informed via health report

---

## E8-STALE: Outdated Knowledge

### Detection

At pipeline start (after classification, before dispatching exploration agents), check knowledge freshness:

1. Read the current task number from status files (count of completed tasks)
2. Call freshness check on all knowledge types used by the current pipeline
3. If any entries are `stale` (>20 tasks since last confirmation):

### Display

```
Warning: STALE KNOWLEDGE WARNING
The following knowledge entries have not been confirmed in 20+ tasks:
  - {type}: last confirmed at task {task_id} ({distance} tasks ago)
  ...

Stale knowledge may lead to incorrect agent decisions.

> proceed -- continue (agents may use outdated information)
> refresh -- run /moira:refresh to update knowledge base first
```

### Non-blocking

This is a WARNING, not a gate. Pipeline continues after display.
The user can choose to refresh or proceed.

### State

Log stale entries to `status.yaml` under `warnings:` block.

### NOT YET IMPLEMENTED

- Automatic knowledge refresh during pipeline (Phase 10)
- Impact assessment of stale knowledge on task quality (Phase 11)

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
1. Increment the specific counter
2. Increment `total`
3. Include retry count in health report at next gate
