# Agent Architecture

## Core Agents

10 agents, each with strict responsibility boundaries (D-028: Classifier added as 10th agent).

## Agent Response Contract

Every agent MUST:
1. Write detailed results to: `.claude/moira/state/tasks/{id}/{agent}.md`
2. Return to orchestrator ONLY:

```
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <1-2 sentences>
ARTIFACTS: <list of file paths>
NEXT: <recommended next step>
QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)
```

**Enforcement:** This is a behavioral contract enforced by prompting. The orchestrator MUST validate response format and treat malformed responses as E6-AGENT (see Enforcement Model in fault-tolerance.md).

Orchestrator NEVER reads full artifact files. It reads only summaries and decides next pipeline step. If orchestrator needs a detail — it spawns an agent to extract specific information.

**Knowledge access authoritative source:** `src/global/core/knowledge-access-matrix.yaml`. Per-agent access levels below are summaries; the YAML file is the source of truth (D-039).

---

## Apollo (classifier)

**Purpose:** Determines task size and confidence. First step of every pipeline (D-028).

**Input:** User's task description + optional size hint + project-model summary
**Output:** Classification result

**Response format:**
```
STATUS: success
SUMMARY: size=medium, confidence=high
ARTIFACTS: [classification.md]
NEXT: explore+analyze
```

Note: Classifier does NOT return `pipeline=` — pipeline selection is the orchestrator's responsibility (Art 2.1, D-062).

**Rules:**
- Classification is a pure function of task analysis (Art 2.1)
- Does NOT read project source code
- Does NOT propose solutions or architecture
- Does NOT change the task description
- NEVER skip classification — always return a result
- If user provides size hint, may agree or override with reasoning

**Pipeline mapping (Art 2.1):**
- small + high confidence → Quick Pipeline
- small + low confidence → Standard Pipeline
- medium → Standard Pipeline
- large → Full Pipeline
- epic → Decomposition Pipeline

**Monorepo scoping:** For monorepo projects (detected at bootstrap), Classifier uses the package map from project-model knowledge to determine which packages are relevant to the task. Output includes `packages: [list]` in classification result. Explorer and subsequent agents receive scoped instructions targeting only those packages (D-066).

**Knowledge access:** L1 (project-model summary)

**Budget:** 20k (minimal — fast classification)

---

## Hermes (explorer)

**Purpose:** The only agent that reads project source code.

**Input:** Question or area to investigate
**Output:** Structured report with facts only

**Rules:**
- Reports FACTS, not opinions or recommendations
- Does not propose solutions
- Scans breadth-first, then depth on relevant areas
- Always checks: shared/, utils/, types/, config/ (commonly missed)
- Documents what it found AND what it looked for but didn't find

**Monorepo mode:** When dispatched with package-scoped instructions, Explorer limits exploration to the specified packages and their direct dependencies. If Explorer discovers that additional packages are relevant (e.g., shared utilities not in scope), it reports E2-SCOPE (monorepo subtype, D-070) for scope expansion rather than silently expanding.

**Knowledge access:** L0 (project-model index only — must be unbiased)
**Write access:** project_model

**Budget:** 140k (needs room for large codebases)

---

## Athena (analyst)

**Purpose:** Formalizes requirements, identifies edge cases, acceptance criteria.

**Input:** Task description + project-model summary
**Output:** Formal requirements document

**Rules:**
- Does NOT propose technical implementation
- Must complete Requirements Completeness Checklist:
  - [ ] Happy path defined
  - [ ] Error cases enumerated
  - [ ] Edge cases identified (empty state, max values, concurrent access)
  - [ ] Input validation rules specified
  - [ ] Output format defined (NOT assumed)
  - [ ] Performance expectations stated
  - [ ] Security implications assessed
  - [ ] Backwards compatibility impact assessed
- Missing items → STATUS: blocked with specific questions

**Knowledge access:** L1 (project-model summary), L0 (decisions index), L0 (failures index)

**Budget:** 80k

---

## Metis (architect)

**Purpose:** Makes technical decisions. Chooses approaches, defines structure.

**Input:** Requirements (from Analyst) + Exploration data (from Explorer)
**Output:** Architecture decision document with alternatives considered

**Rules:**
- Every decision must have: CONTEXT, DECISION, ALTERNATIVES REJECTED, REASONING
- Must pass Architecture Soundness Checklist:
  - [ ] Follows existing patterns (or justifies deviation)
  - [ ] Single Responsibility per component
  - [ ] Open/Closed — extends without modifying contracts
  - [ ] No circular dependencies
  - [ ] No God objects (>200 lines = split)
  - [ ] Unidirectional data flow where possible
  - [ ] External API contracts VERIFIED (never assumed)
  - [ ] No N+1 queries, no unbounded loops, no blocking I/O in hot paths
  - [ ] Error boundaries defined
- Checks quality-map for existing patterns (Strong → follow, Problematic → avoid)
- Checks UI component constraints when task involves frontend
- Defines contract interfaces for parallel implementation batches
- MUST compare Explorer and Analyst data for factual contradictions before making technical decisions. If disagreement found → report as E10-DIVERGE with both versions and analysis.

**Knowledge access:** L1 (project-model), L0 (conventions), L2 (decisions — FULL), L1 (patterns), L1 (quality-map), L0 (failures index)

**Budget:** 100k

---

## Daedalus (planner)

**Purpose:** Creates execution plan. Decomposes architect's decision into steps.

**Input:** Architecture decision
**Output:** Step-by-step plan with files, batches, dependencies, budget estimates

**Rules:**
- Does NOT make architectural decisions, only decomposes
- Uses quality-map (full) to inject quality pattern context into agent instruction files and align plan steps with existing quality patterns
- Must pass Plan Feasibility Checklist:
  - [ ] Every file in plan exists (or explicitly marked as new)
  - [ ] Dependencies between steps correctly ordered
  - [ ] Context budget per step within agent limits
  - [ ] No step requires knowledge that previous steps don't produce
  - [ ] Rollback path exists for each step
  - [ ] Contract interfaces defined for parallel batches
- Creates dependency graph for files
- Clusters files into independent batches
- Estimates context budget per batch
- If any batch exceeds budget → splits automatically
- Assembles agent instructions (Layer 1-4 rules) for each step
- Allocates MCP tools per step with justification

**Sub-phases (each with distinct success/failure conditions):**
1. **Decomposition** — Break architecture into implementation steps. Success: each step has clear input/output/files. Failure: circular dependencies or unreachable steps.
2. **Dependency Graph** — Map file dependencies between steps. Success: valid DAG. Failure: unresolvable cycles.
3. **Budget Estimation** — Estimate tokens per batch. Success: all batches within agent budget limits. Failure: batch exceeds limit after maximum splitting.
4. **Instruction Assembly** — Assemble Layer 1-4 rules per agent invocation. Success: each instruction set includes all required rule layers + knowledge. Failure: missing rule layer or inaccessible knowledge level.

**Knowledge access:** L1 (project-model), L1 (conventions), L0 (decisions), L0 (patterns), L2 (quality-map), L0 (libraries)

**Budget:** 70k

---

## Hephaestus (implementer)

**Purpose:** Writes code. Follows the plan exactly.

**Input:** Assembled instructions (from Planner) + conventions + specific files to modify
**Output:** Code changes in project files

**Rules:**
- Implements EXACTLY what plan specifies (no more, no less)
- Does NOT make architectural decisions
- Does NOT deviate from plan — if plan unclear → STATUS: blocked
- Never fabricates API endpoints, URLs, schemas, data structures
- Never guesses types or return formats
- Follows project conventions exactly (loaded in instructions)
- Uses only authorized MCP tools
- After code changes: runs post-implementation validation commands from `.claude/moira/config.yaml` → `tooling.post_implementation[]` (D-063). If commands fail, fixes errors before returning STATUS: success. If no commands configured, skips validation.

**Knowledge access:** L0 (project-model), L2 (conventions — FULL), L1 (patterns), L1 (libraries)

**Budget:** 120k

---

## Themis (reviewer)

**Purpose:** Checks code quality against standards and requirements.

**Behavioral defense role:** Primary per-task defense against upstream agent behavioral violations (E9/E10). Catches role boundary violations, factual errors, and semantic correctness failures.

**Input:** Written code + plan + requirements + conventions
**Output:** Issue list with severity (critical/warning/suggestion)

**Rules:**
- Does NOT fix code — only identifies issues
- Must complete Code Correctness Checklist (q4-correctness, see quality.md for full checklist):
  - [ ] Upstream agents stayed within role boundaries (Explorer didn't propose solutions, Architect didn't fabricate APIs)
  - [ ] Factual claims in architecture verified against Explorer data (E10-DIVERGE defense)
  - [ ] Implementation matches approved architecture (E9-SEMANTIC defense)
- Severity classification:
  - CRITICAL: blocks pipeline, must fix (correctness, security, broken contracts)
  - WARNING: should fix, can proceed with user approval
  - SUGGESTION: logged for reflection, doesn't block
- Checks conformance with project quality-map
- Verifies MCP calls were used correctly
- False positive awareness: if unsure, mark as WARNING not CRITICAL

**Knowledge access:** L1 (project-model), L2 (conventions — FULL), L1 (decisions), L1 (patterns), L1 (quality-map)
**Write access:** quality_map

**Budget:** 100k

---

## Aletheia (tester)

**Purpose:** Writes and runs tests.

**Input:** Code + requirements + acceptance criteria
**Output:** Tests + execution results

**Rules:**
- Must complete Test Checklist:
  - [ ] Happy path tested
  - [ ] Each error case has a test
  - [ ] Edge cases have tests
  - [ ] Integration points tested
  - [ ] Tests run and pass
  - [ ] No brittle tests (testing implementation details)
  - [ ] Matches project testing patterns
- Does NOT modify application code
- If test fails due to implementation bug → reports, doesn't fix

**Knowledge access:** L0 (project-model), L1 (conventions), L0 (patterns)

**Budget:** 90k

---

## Mnemosyne (reflector)

**Purpose:** Analyzes completed tasks for learning.

**Behavioral defense role:** Primary defense against systemic behavioral drift. Detects patterns of agent boundary violations, recurring factual errors, and constraint degradation over time.

**Input:** Full task history (all state files)
**Output:** Lessons learned, pattern observations, rule change proposals

**Rules:**
- Runs AFTER task completion (not blocking)
- Analyzes:
  1. ACCURACY: result vs requirements match
  2. EFFICIENCY: retry loop count and causes
  3. PREDICTIONS: was classification correct
  4. ARCHITECTURE: was architect's decision right
  5. GAPS: what Explorer/Analyst missed
  6. ORCHESTRATOR: did orchestrator violate rules
- Does NOT change rules directly
- Writes observations to knowledge base
- Proposes rule changes only after 3+ confirming observations
- Rule change proposals require user approval

**Exit criteria (minimum required output):**
1. Accuracy assessment (result vs requirements)
2. Efficiency assessment (retry count, budget usage)
3. At least one concrete observation for knowledge update
4. Agent boundary compliance note (did any agent violate NEVER constraints?)
5. If rule change proposed: 3+ confirming observations cited

**Minimum output structure:**
```
ACCURACY: {match|partial|mismatch} — {detail}
EFFICIENCY: {retries}R, {budget_pct}% budget — {assessment}
OBSERVATIONS: [{observation with evidence reference}]
KNOWLEDGE_UPDATES: [{type}: {update}]
BOUNDARY_COMPLIANCE: {all_clear|violations_found} — {detail}
RULE_PROPOSALS: [{proposal with 3+ evidence citations}] (if any)
```

**Knowledge access:** L2 (all knowledge types, including libraries)
**Write access:** all knowledge types (including libraries)

**Budget:** 80k

---

## Argus (auditor)

**Purpose:** Independent system health verification.

**Input:** All moira files (rules, knowledge, config, state, metrics)
**Output:** Audit report with findings and recommendations

**Rules:**
- Independent from pipeline (not part of task execution)
- READ-ONLY — never modifies moira or project files
- Audits 5 domains: rules, knowledge, agents, config, cross-consistency
- Can read project files to verify knowledge accuracy
- Recommendations must be actionable and specific
- Classifies findings by risk: low/medium/high

**Knowledge access:** L2 (all knowledge types, including libraries — read-only)

**Budget:** 140k (needs to cross-reference many files)

---

## Agent Spawning Strategy

```
Sequential pipeline steps → FOREGROUND (orchestrator waits for result)
Parallel batches          → BACKGROUND (concurrent execution)
Post-task reflection      → BACKGROUND (non-blocking)
Audit                     → FOREGROUND (user requested, awaits results)
```

Rationale:
- Foreground for sequential: orchestrator MUST see previous step summary to decide next step
- Background for parallel: batches are independent by design (Planner guarantees this)
- Background for reflection: doesn't block user from starting next task

Note: Bootstrap scanners (Tech/Structure/Convention/Pattern) are Explorer invocations with Layer 4 task-specific instructions, not separate agents (D-032).
