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
| E9-SEMANTIC | Semantic failure | Structurally valid but factually wrong output |
| E10-DIVERGE | Data disagreement | Multiple agents report contradictory facts |
| E11-TRUNCATION | Context truncation | Silent context loss causes incomplete/wrong output |

## Enforcement Model

The system uses three tiers of enforcement. Understanding which tier a constraint belongs to determines the appropriate defense strategy.

| Tier | Examples | Enforcement | Defense Layer |
|------|----------|-------------|---------------|
| **Structural** (platform-guaranteed) | `allowed-tools` restriction, pipeline selection logic (deterministic code), gate presence in pipeline YAML definitions | Platform blocks violations | No recovery needed — structurally impossible to violate |
| **Validated** (behavioral + verification) | Response contract format (orchestrator parser validates), quality findings (YAML schema validation), knowledge writes (consistency check against existing) | Agent produces output → orchestrator/system validates → fallback on failure | Parse failure → E6-AGENT. Schema failure → reject + retry. |
| **Behavioral** (prompt-only, no automated verification) | NEVER constraints (Art 1.2), fabrication prohibition (Art 4.1), agent role boundaries, knowledge consistency execution (Art 5.3) | Enforced by prompt instructions only | Reviewer = primary per-task defense. Reflector = primary systemic defense. Auditor = periodic cross-validation. |

This model acknowledges that behavioral rules enforced by prompting are not equivalent to structural platform guarantees. Behavioral constraints WILL be violated occasionally — the defense strategy is layered detection and correction, not prevention.

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

**MAX RETRY: max_attempts=3 for Standard/Full/Decomposition (1 original + 2 retries), max_attempts=2 for Quick (1 original + 1 retry). See D-095.**

Note: `max_attempts` means total executions including the original attempt (D-095).

**Markov retry optimization:** Retry count may be reduced from the hard maximum by the Markov retry optimizer (`retry.sh`) when historical data shows low success probability. The optimizer uses exponential moving average of past retry outcomes per (error_type, agent_type) pair to estimate success probability. Hard limits (2 attempts total) remain as upper bounds — the optimizer can recommend fewer retries, never more. Report includes: "Retry recommended (estimated N% success probability based on M historical observations)" or "Escalating to user (estimated N% success probability — retry unlikely to help)."

**Attempt 1:** Implementer gets review feedback, fixes issues → re-review

**Attempt 2 (if still failing):** Different approach:
- Architect re-examines decision
- New plan with different approach
- New implementation

**After max_attempts exhausted:** Escalate to user:
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

**Markov retry optimization:** Same as E5 — retry optimizer (`retry.sh`) may recommend skipping the retry if historical success probability is low. Hard limit (1 retry) remains as upper bound.

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

**Subtype: Malformed Output**

Agent returns text but response does not match the STATUS/SUMMARY/ARTIFACTS/NEXT contract format. This is distinct from nonsensical content (E9-SEMANTIC) — the response is structurally unparseable.

Detection: Orchestrator response parser fails to extract required STATUS field.
Recovery: Same as E6 — retry 1x with same input, then diagnostic + escalate.
Note: Validated tier constraint. The orchestrator parser is the verification layer.

### E7-DRIFT: Orchestrator Rule Violation

**Detection:** Guard hook detects prohibited tool calls. Reflector audits post-task.

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

### E9-SEMANTIC: Semantic Correctness Failure

**Trigger:** Agent returns structurally valid output (correct format, parses successfully) but the content is factually wrong — hallucinated API endpoints, incorrect architecture assumptions, subtly wrong implementation logic.

**Detection:**
- Reviewer checklist: "Verify factual claims against Explorer data" (primary automated defense)
- Architecture gate: user reviews proposed architecture and alternatives (primary human defense)
- Reflector: post-task analysis compares outcomes against predictions

**Primary defense:** Reviewer (per-task) + architecture gate (human in the loop)

**Recovery:**
- If caught at Reviewer → E5-QUALITY retry path (implementer fixes with specific feedback)
- If caught at architecture gate → user provides "modify" feedback, Architect revises
- If caught post-deployment → log in failures knowledge for future prevention

**User presentation:** Same as E5-QUALITY if caught at review. If caught at gate, the gate's "modify" option already handles this.

**Note:** This is the hardest failure mode to detect automatically. The architecture gate presenting alternatives is the primary user-facing defense. Quality gates check structure, not semantic correctness.

### E10-DIVERGE: Multi-Agent Factual Disagreement

**Trigger:** Multiple agents report contradictory facts about the same codebase. Example: Explorer reports 14 API endpoints, Analyst scopes requirements for 6 endpoints. Both outputs are individually valid but collectively inconsistent.

**Detection:**
- Architect mandate: explicitly compare Explorer and Analyst data before making technical decisions (primary defense)
- Reviewer: cross-reference implementation against exploration data

**Primary defense:** Architect (explicit contradiction detection mandate)

**Recovery:**
- Architect flags contradiction → presents both versions to user at architecture gate with analysis of which is likely correct
- User decides which data to trust
- If not caught until review → E5-QUALITY retry with note to verify factual basis against Explorer data

**User presentation:**
```
⚠ DATA CONFLICT DETECTED
Metis (architect) found inconsistency:

  Hermes (explorer): 14 API endpoints in src/api/
  Athena (analyst): 6 endpoints scoped in requirements

Analysis: Explorer counted all route files including deprecated.
          Analyst scoped only active endpoints per task description.

▸ use-explorer — trust exploration data (14 endpoints)
▸ use-analyst  — trust analyst scoping (6 endpoints)
▸ clarify      — provide additional context
▸ abort        — cancel task
```

### E11-TRUNCATION: Silent Context Truncation

**Trigger:** Agent's context window fills silently, causing early instructions (NEVER constraints, role boundaries, critical context) to be lost. Agent returns STATUS: success but output is incomplete or violates constraints it no longer "remembers."

**Detection:**
- Budget system: pre-execution estimation flags agents near budget limit (primary prevention)
- Agent "context loaded" summary: agent lists received instructions at start of execution — orchestrator can detect if critical instructions are missing
- Reviewer: catches output that violates known constraints (post-hoc detection)

**Primary defense:** Budget system (prevent overflow before it happens) + Reviewer (catch violations after the fact)

**Recovery:**
- If detected by budget system pre-execution → E4-BUDGET path (split work into smaller batches)
- If detected by Reviewer post-execution → E5-QUALITY retry with reduced scope
- If undetected during pipeline → Reflector post-task analysis, logged in failures knowledge

**User presentation:** Same as E4-BUDGET if caught pre-execution. Same as E5-QUALITY if caught post-execution.

**Note:** This failure mode is insidious because the agent itself cannot know it has lost context. The budget system's pre-execution estimation is the most reliable prevention mechanism. The 30% safety margin in budget allocation exists partly to mitigate this risk.

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
