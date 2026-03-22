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
| **Behavioral** (prompt-only, no automated verification) | NEVER constraints (Art 1.2), fabrication prohibition (Art 4.1), agent role boundaries, knowledge consistency execution (Art 5.3) | Enforced by prompt instructions only | Reviewer = primary per-task defense (see `quality.md` Q4 checklist for behavioral defense items). Reflector = primary systemic defense. Auditor = periodic cross-validation. |

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

**Markov retry optimization (post-v1, per D-111):** V1 uses fixed retry limits (max_attempts per pipeline, see D-095). Post-v1, a Markov retry optimizer may reduce retry count based on historical success probability. See D-094 and D-111 for the deferred design.

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

**Markov retry optimization (post-v1, per D-111):** V1 uses fixed retry limit (1 retry). Post-v1, a Markov retry optimizer may recommend skipping the retry based on historical success probability.

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

## Analytical Pipeline Error Extensions

The Analytical Pipeline uses the same E1-E11 taxonomy with the following extensions:

### E5-QUALITY in Analytical Pipeline: Re-Analyze vs Re-Synthesize

At the analytical final gate, E5-QUALITY has two distinct recovery paths depending on which QA gate failed:

- **QA3 (actionability) or QA1 partial (document structure):** → `modify` at final gate → re-synthesis by Calliope with Themis feedback. Same as implementation pipeline's E5 path.
- **QA2 (evidence quality) or QA4 (analytical rigor):** → `re-analyze` at final gate → route back to analysis step with specific QA failure feedback injected into agent instructions. Re-synthesis alone cannot fix an evidence gap — the analysis phase must produce better evidence first.

The `re-analyze` branch counts toward the E5 max_attempts (3 total). After exhaustion, escalate to user with the specific QA failures that could not be resolved.

### E10-DIVERGE in Analytical Pipeline: Parallel Agent Cross-Check

For `audit` and `weakness` subtypes, Metis and Argus analyze in parallel. The organize step (CS-6 lattice construction) includes an explicit E10-DIVERGE check: before building the lattice, Metis compares findings from both agents on overlapping nodes/modules. Contradictions become first-class nodes in the lattice with type `disputed_finding` — both versions preserved, contradiction flagged for user visibility at depth checkpoint. Contradictions are NOT silently resolved by choosing one agent's version.

### E8-STALE: Ariadne Data Freshness

Ariadne graph data can become stale if the codebase has changed since the last `ariadne build/update`. Before Tier 1 baseline queries in the Gather phase, the orchestrator checks Ariadne's last-index timestamp (from `.ariadne/graph/meta.json`) against the last git commit timestamp. If the gap exceeds a configurable threshold (default: 50 commits or 7 days), the orchestrator warns the user at the scope gate:

```
⚠ Ariadne graph may be stale
Last indexed: 2026-03-15 (42 commits ago)
Structural metrics may not reflect recent changes.

▸ reindex — run `ariadne update` before analysis
▸ continue — proceed with current data (findings will note staleness)
▸ skip-ariadne — analyze without structural data
```

If the user chooses `continue`, all Ariadne-derived evidence in findings carries a staleness annotation.

### Mid-Analysis Ariadne Unavailability

If Ariadne MCP becomes unavailable during an analysis pass (Tier 2 agent-driven queries fail):

1. Agent notes the failure and continues with code-level analysis only
2. CS-2 coverage is computed from explored files, not Ariadne graph
3. Tier B CS methods (CS-1/CS-2/CS-4/CS-5 per D-127) deactivate for the remainder of the pass
4. Themis reports at depth checkpoint: "Ariadne unavailable during pass N — structural coverage not computed"
5. No automatic retry — the user decides at the depth checkpoint whether to deepen (hoping Ariadne recovers) or proceed with code-level findings

### Calliope Conflict Resolution

When Calliope's findings contradict existing document content:

1. **Supersession:** If a finding explicitly refutes a previous claim (e.g., "Module X was documented as low-coupling but analysis shows fan-in: 47"), Calliope updates the document section with the new finding AND notes the change: `[Updated: previous assessment superseded by analysis task-{id}]`.
2. **Qualification:** If a finding adds nuance without fully refuting (e.g., "coupling is high but intentional"), Calliope adds the qualification alongside the existing content rather than replacing it.
3. **Blocked:** If Calliope cannot determine whether to supersede or qualify (e.g., the existing document uses different terminology or scope), Calliope returns `STATUS: blocked` with the specific conflict for user resolution.

Calliope NEVER silently overwrites existing content. Every change to existing text is traceable via the `[Updated]` annotation.

## Error Precedence

When multiple error types fire simultaneously (compound errors), handle in priority order:

1. **Budget errors (E4)** — stop spending first; context overflow makes all other recovery unreliable
2. **Structural errors (E1, E2, E3, E6)** — missing data, scope changes, conflicts, and agent failures block forward progress
3. **Quality errors (E5, E9, E10)** — quality failures, semantic errors, and data disagreements require rework but don't threaten resource exhaustion
4. **Informational (E7, E8, E11)** — drift, stale knowledge, and truncation are logged and addressed but don't block recovery of higher-priority errors

When compound errors occur, handle the highest-priority error first. Lower-priority errors may resolve as a side effect of higher-priority recovery (e.g., fixing E4 by splitting work may also resolve an E5 quality failure caused by context pressure).

## Session Concurrency Protection

A session lock file (`.claude/moira/state/.session-lock`) prevents concurrent Moira pipeline executions on the same branch:

1. **At pipeline start:** Create `.session-lock` containing `{ pid: <process_id>, started: <timestamp>, task_id: <id>, ttl: 3600 }`.
2. **If lock exists:** Check if the PID is still alive and the TTL hasn't expired.
   - PID alive + TTL valid → warn: "Another Moira session is active (task {task_id}, started {timestamp}). Running concurrent sessions on the same branch can corrupt state. Proceed anyway? (y/n)"
   - PID dead OR TTL expired → stale lock, remove and proceed
3. **At pipeline completion (or abort):** Delete `.session-lock`.
4. **On unexpected session termination:** The TTL (default: 1 hour) ensures stale locks are auto-detected by the next session.

This protects against accidental concurrent sessions writing to the same `manifest.yaml` and `current.yaml`. It is advisory — the user can force past it — but prevents silent state corruption.

## Gate Timeout and Abandonment

Gate timeout/abandonment is an accepted limitation for v1. Claude Code sessions are interactive — if the user walks away while a gate is waiting for input, the session state persists until they return. No automated timeout mechanism exists or is planned. Gates wait indefinitely; the user resumes where they left off.

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
