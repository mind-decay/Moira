# Fault Tolerance System

## Principle: Fail Forward, Never Guess

The system NEVER guesses. If data is missing — stop and ask. If there's doubt — escalate. This is a feature, not a limitation.

## Error Taxonomy

| Code | Category | Description |
|------|----------|-------------|
| E1-INPUT | Missing data | Insufficient information to complete step |
| E2-SCOPE | Scope change | Task is bigger/more complex than classified |
| E3-CONFLICT | Contradiction | Conflicting requirements, code, or patterns |
| E4-BUDGET | Context overflow | Agent context exceeds safe limit |
| E5-QUALITY | Quality failure | Result doesn't pass quality gate |
| E6-AGENT | Agent failure | Timeout, crash, or nonsensical output |
| E7-DRIFT | Rule violation | Orchestrator broke its own rules |
| E8-STALE | Stale knowledge | Knowledge base contains outdated information |

## Recovery Strategies

### E1-INPUT: Missing Data

**Trigger:** Agent cannot proceed without information it doesn't have.

**Agent behavior:**
1. STOP immediately (do NOT improvise or assume)
2. Return: `STATUS: blocked, REASON: "<specific missing info>", NEED: "<specific question>"`

**Orchestrator behavior:**
```
⏸ BLOCKED: Missing Information
Agent: Implementer
Step: 3/7 — Implement user API handler

Problem: Cannot determine API response format.
No existing examples or documentation found.

Need from you:
→ What format should GET /api/users return?

▸ answer — provide the information
▸ point  — point to a file/doc with the answer
▸ skip   — mark as TODO in code
▸ abort  — stop task
```

**HARD RULE:** Agent NEVER fabricates answers. "I'll assume it returns JSON array" is FORBIDDEN.

### E2-SCOPE: Scope Change Detected

**Trigger:** Explorer or Architect discovers task is bigger than classified.

**Recovery:**
1. Current pipeline STOPS
2. Orchestrator presents scope change analysis
3. Previous work (exploration, analysis) is PRESERVED — it's valid data
4. Options:
   - **upgrade** — re-plan at new size (re-enter at Architect, reuse Explorer/Analyst data)
   - **split** — break into separate tasks
   - **reduce** — simplify scope (user decides what to cut)
   - **continue** — proceed as-is (not recommended, shown with warning)

### E3-CONFLICT: Contradictions

**Trigger:** Agent finds contradicting requirements, code patterns, or conventions.

**Recovery:**
1. Agent documents BOTH sides of conflict
2. Agent does NOT choose a side (that's the engineer's decision)
3. Orchestrator presents:
   - What conflicts
   - Option A with pros/cons
   - Option B with pros/cons
   - Agent's recommendation (informational, not binding)
4. User chooses

### E4-BUDGET: Context Overflow

**Pre-execution (detected by Planner):**
- Planner auto-splits into smaller batches
- No gate needed (technical optimization)
- Logged in plan

**Mid-execution (detected by agent):**
1. Agent STOPS
2. Writes partial result to file with clear boundary marker
3. Returns: `STATUS: budget_exceeded, COMPLETED: "A,B done", REMAINING: "C,D"`
4. Orchestrator spawns new agent for remaining work
5. New agent reads partial results as context

### E5-QUALITY: Quality Gate Failed

**MAX RETRY: 2 attempts total**

**Attempt 1:** Implementer gets review feedback, fixes issues → re-review

**Attempt 2 (if still failing):** Different approach:
- Architect re-examines decision
- New plan with different approach
- New implementation

**After 2 failures:** Escalate to user:
```
🔴 QUALITY GATE FAILED (2 attempts)
Step: Implement caching layer

Attempt 1: Race condition in cache invalidation
Fix applied: Added mutex lock

Attempt 2: Mutex causes deadlock under concurrent requests

Root cause analysis:
The chosen caching approach (in-memory with manual invalidation)
may not be suitable. Consider alternatives.

▸ redesign — send back to Architect
▸ manual   — you'll handle this part
▸ simplify — remove feature, find simpler approach
```

### E6-AGENT: Agent Failure

**Recovery:**
1. Retry 1x with same input (may be transient)
2. If repeat failure → diagnostic analysis:
   - Was input valid?
   - Were instructions clear?
   - Was context budget within limits?
3. Escalate with full report:

```
🔴 AGENT FAILURE
Agent: Implementer-2 (Batch B)

Failure: Agent produced code that doesn't compile.
Retry: Same result.

Diagnosis:
- Input valid ✅
- Instructions clear ✅
- Context budget: 68% ⚠️ (near limit)
- Likely cause: complex type inference exceeded capacity at this context load

Other agents: Impl-1 ✅, Impl-3 ✅

Recommendation: Split Batch B into 2 smaller batches

▸ retry-split — split and retry (recommended)
▸ retry-as-is — retry same batch
▸ manual      — handle manually
▸ rollback    — undo all, re-plan
```

### E7-DRIFT: Orchestrator Rule Violation

**Detection:** Guard hook blocks prohibited tool calls. Reflector audits post-task.

**Prevention:**
- Hook-based enforcement (see self-monitoring.md)
- Strict rules in CLAUDE.md
- Post-task audit by Reflector

**If detected:**
- Violation logged
- Reflector flags in task reflection
- Audit system tracks frequency
- If recurring → rules may need strengthening

### E8-STALE: Outdated Knowledge

**Detection:**
- Explorer finds reality ≠ knowledge
- Audit checks freshness markers
- Reviewer finds code contradicts conventions

**Recovery:**
1. Flag specific stale entries
2. Explorer verifies current state
3. Knowledge updated with new freshness marker
4. If stale knowledge caused a pipeline issue → logged in failures

## Tweak & Redo System

### Tweak (targeted modification after completion)

```
User describes what needs changing
  │
  ├─ Quick Explorer → what files affected
  ├─ Scope check → is tweak within original scope?
  │   ├─ YES → Implementer modifies specific files
  │   └─ NO → suggest separate task (user can force)
  ├─ Reviewer → reviews changes
  └─ [GATE: user reviews]
```

Tweak Implementer receives: original plan + current file state + tweak description + scope limits.

### Redo (full rollback)

```
User chooses re-entry point + provides reason
  │
  ├─ Git revert of task changes
  ├─ Archive previous attempt (architecture-v1.md, plan-v1.md)
  ├─ Re-enter pipeline at chosen point
  │   Agent receives:
  │   - Original requirements (unchanged)
  │   - REJECTED approach with reason (learn from mistake)
  │   - Updated constraints
  └─ Pipeline continues normally
```

Redo entry points:
- **architecture** — change approach entirely
- **plan** — keep architecture, change execution
- **implement** — keep plan, re-do code from scratch

Every redo is captured in failures.md for future learning.
