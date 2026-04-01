# Agent Architecture

## Core Agents

11 agents, each with strict responsibility boundaries (D-028: Classifier added as 10th agent, D-118: Calliope added as 11th agent for analytical pipeline).

## Agent Response Contract

Every agent MUST:
1. Write detailed results to: `.moira/state/tasks/{id}/{agent}.md`
2. Return to orchestrator ONLY:

```
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <1-2 sentences>
ARTIFACTS: <list of file paths>
NEXT: <recommended next step>
QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)
```

**Enforcement:** This is a behavioral contract enforced by prompting. The orchestrator MUST validate response format and treat malformed responses as E6-AGENT (see Enforcement Model in fault-tolerance.md).

**Instruction size limits:** Assembled instructions (Layers 1-4 + knowledge + graph data + MCP rules) must be checked for total size before dispatch. If total instruction size exceeds 50k tokens (estimated), the dispatcher reduces knowledge/graph data to lower access levels (L2→L1→L0) until the instruction fits. Layer 4 (task-specific) instructions must never be truncated — they are the most critical part of the assembled instructions. This prevents silent truncation of trailing instructions by the Agent tool platform.

Orchestrator NEVER reads full artifact files. It reads only summaries and decides next pipeline step. If orchestrator needs a detail — it spawns an agent to extract specific information.

**Knowledge access authoritative source:** `src/global/core/knowledge-access-matrix.yaml`. Per-agent access levels below are summaries; the YAML file is the source of truth (D-039).

---

## Apollo (classifier)

**Purpose:** Determines task size and confidence. First step of every pipeline (D-028).

**Input:** User's task description + optional size hint + project-model summary
**Output:** Classification result

**Response format:**
```
STATUS: success  # Example of success response; full options: success|failure|blocked|budget_exceeded
SUMMARY: size=medium, confidence=high
ARTIFACTS: [classification.md]
NEXT: explore+analyze
```

> Note: NEXT is a step recommendation for the orchestrator, not a pipeline selection (see D-062).

Note: Classifier does NOT return `pipeline=` — pipeline selection is the orchestrator's responsibility (Art 2.1, D-062).

**Artifact output contract (D-184):** Classification artifact (`classification.md`) MUST contain these sections:
```
## Problem Statement       — task restated in agent's own words (not copy-paste from user input)
## Scope
### In Scope               — explicit list of what this task covers
### Out of Scope            — explicit list of what is excluded
## Acceptance Criteria      — mechanical, testable conditions for "done" (not subjective quality)
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion. These sections propagate through the pipeline via cross-gate traceability injection: Metis and Daedalus receive scope + criteria as system-injected context; final gate checks acceptance results against these criteria.

**Rules:**
- Classification is a pure function of task analysis (Art 2.1)
- Does NOT read project source code
- Does NOT propose solutions or architecture
- Does NOT change the task description
- NEVER skip classification — always return a result
- Does NOT select or specify the pipeline type (orchestrator responsibility per Art 2.1, D-062)
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

**Purpose:** The only agent that gathers facts about the project — source code, structural graph data, and system state.

**Input:** Question or area to investigate
**Output:** Structured report with facts only

**Quality stance (D-185):** Thoroughness — report the full picture, not just the first matches. A context report that misses key files wastes downstream budget.

**Exploration strategy (D-187):** Graph-first navigation:
1. `ariadne_context(seed_files, task_type, budget)` → ranked file list with relevance scores (replaces breadth-first scan)
2. Read files by relevance ranking, not by directory structure
3. For deeper exploration: `ariadne_subgraph` / `ariadne_callees` / `ariadne_reading_order` (replaces grep-based import tracing)
4. Grep/glob as FALLBACK — for non-structural queries or when graph data unavailable

**Q1 Gap Analysis (D-189):** In Standard and Full pipelines, Hermes includes a `## Gap Analysis` section in exploration.md covering the Q1 completeness checklist: happy path coverage, error cases, edge cases, input validation, output format, performance expectations, security implications, backwards compatibility. This is fact-reporting ("this edge case has no handler"), not requirements proposal. When gap analysis reveals requirements ambiguity that Hermes cannot resolve from code inspection, Hermes reports STATUS: blocked with specific questions — or the user can dispatch Athena via plan gate `analyze` option.

**Artifact output contract (D-197):** Exploration artifact (`exploration.md`) MUST contain these sections:
```
## Relevant Files            — files examined with brief purpose of each
## Key Findings              — factual observations about the codebase
## Gap Analysis              — Q1 completeness gaps (D-189, Standard/Full only)
```
Quick pipeline variant (`context.md`) MUST contain:
```
## Context Summary           — brief overview of relevant code area
## Key Files                 — files relevant to the task
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Rules:**
- Reports FACTS, not opinions or recommendations
- Does not propose solutions
- Navigates graph-first when Ariadne data is available; grep/glob as fallback (D-187)
- Always checks: shared/, utils/, types/, config/ (commonly missed)
- Does NOT interpret or draw conclusions from findings (reports raw facts only)
- Does NOT make architectural suggestions
- Does NOT modify any files (read-only agent)
- Does NOT silently expand exploration scope (reports E2-SCOPE)
- Does NOT express opinions
- Documents what it found AND what it looked for but didn't find
- Gap analysis reports observed gaps as facts, does NOT propose how to fill them (D-189)

**Analytical pipeline mode (D-125):** In the Analytical Pipeline gather step, Hermes also executes Ariadne baseline queries (overview, smells, metrics, layers, cycles, clusters) and writes results to `ariadne-baseline.md` alongside `exploration.md`. This is fact-gathering from a structural analysis tool — consistent with Hermes's core responsibility. If Ariadne is unavailable, Hermes notes it and continues with code-only exploration.

**Monorepo mode:** When dispatched with package-scoped instructions, Explorer limits exploration to the specified packages and their direct dependencies. If Explorer discovers that additional packages are relevant (e.g., shared utilities not in scope), it reports E2-SCOPE (monorepo subtype, D-070) for scope expansion rather than silently expanding.

**Phase 4/5 tools:** PREFER `ariadne_symbol_search` over grep for finding functions, classes, or types by name. PREFER `ariadne_reading_order` for structured exploration of unfamiliar areas. PREFER `ariadne_dependencies` over manual import tracing for mapping file relationships. Uses `ariadne_cluster` to understand module boundaries and focus exploration within cohesive units. (D-187: PREFER language for graph-first navigation.)

**Knowledge access:** L0 (project-model index only — must be unbiased)
**Write access:** project_model

**Budget:** 140k (needs room for large codebases)

---

## Athena (analyst)

**Purpose:** Formalizes requirements, identifies edge cases, acceptance criteria.

**Quality stance (D-185):** Precision — requirements that leave ambiguity create implementation guesswork. Every criterion must be mechanically testable.

**Pipeline dispatch changes (D-189):** In Standard and Full pipelines, Athena is no longer dispatched by default. Hermes handles Q1 gap analysis as part of exploration (fact-reporting). Athena is dispatched on-demand via:
- Plan gate `analyze` option — when user decides detailed requirements formalization is needed
- Hermes STATUS: blocked on requirements — when exploration reveals ambiguity that Hermes cannot resolve from code inspection
- Decomposition pipeline — Athena remains default for epic-level requirement breakdown
This saves ~56k tokens per pipeline run while preserving the ability to use Athena when needed.

**Artifact output contract (D-197):** Scope artifact (`scope.md`) MUST contain these sections:
```
## Requirements              — formalized requirements list
## Constraints               — technical and business constraints
## Dependencies              — external dependencies and assumptions
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Input:** Task description + project-model summary + exploration.md (when available)
**Output:** Formal requirements document

**Rules:**
- Does NOT propose technical implementation
- Does NOT suggest specific technologies or patterns
- Does NOT write code or pseudocode
- Does NOT assume requirements — asks if unclear (STATUS: blocked)
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

**Phase 4/5 tools:** Uses `ariadne_plan_impact` to auto-populate impact analysis with blast radius, affected tests, layer analysis, and risk identification. Uses `ariadne_symbol_blast_radius` for precise function-level impact when requirements involve changing specific interfaces. Uses `ariadne_coupling` (temporal) to identify co-change patterns that may expand requirements scope.

**Knowledge access:** L1 (project-model summary), L0 (decisions index), L0 (failures index)

**Budget:** 80k

---

## Metis (architect)

**Purpose:** Makes technical decisions. Chooses approaches, defines structure.

**Quality stance (D-185):** Seek the best solution, not the first valid one. Alternatives exist to be genuinely evaluated, not to fill a template. Pre-mortem must find real weaknesses.

**Input:** Requirements (from Analyst) + Exploration data (from Explorer)
**Output:** Architecture decision document with alternatives considered

**Analytical pipeline mode (D-126):** In the Analytical Pipeline, Metis role rules include an `analytical_mode` section with CS method templates (CS-3 hypothesis-driven, CS-4 abductive reasoning, CS-5 information gain). Activated by orchestrator when pipeline=analytical.

**Artifact output contract (D-184):** Architecture artifact (`architecture.md`) MUST contain these sections:
```
## Alternatives              — minimum 2, for ALL pipelines (not just Full)
### Alternative 1: {name}
#### Trade-offs              — what you gain, what you lose
### Alternative 2: {name}
#### Trade-offs
## Recommendation            — which alternative chosen and WHY
## Assumptions
### Verified                 — claims backed by documentation (with source)
### Unverified               — claims without documentation (MUST exist even if empty)
### Load-bearing             — which assumptions, if wrong, would invalidate the architecture
## Verification Plan         — how to verify unverified assumptions
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion. Structural checks: `## Alternatives` must contain ≥2 `### Alternative` subsections. `## Assumptions` must contain `### Unverified` subsection (even if empty — explicit "nothing unverified"). Cross-gate: receives classification scope + acceptance criteria via traceability injection; UNVERIFIED items propagate downstream to Daedalus, Hephaestus, Themis, and final gate.

**Rules:**
- Every decision must have: CONTEXT, DECISION, ALTERNATIVES REJECTED, REASONING
- Does NOT write implementation code
- Does NOT decompose into tasks (Planner's responsibility)
- Does NOT make requirements decisions (Analyst's responsibility)
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
- When dispatched with `## External Documentation` section, grounds all external claims in provided documentation (D-165 closed-world constraint)
- For failure-driven tasks, produces Root Cause → Mechanism Mapping table with explicit mechanism types — structural, deterministic, prompt, visual (D-168)
- Produces mandatory Pre-mortem section describing how proposed solutions could fail (D-169)
- Architecture document MUST include a `## Structural Analysis` section recording graph-derived conclusions (coupling analysis, dependency patterns, parallel implementation safety, import fan-in/fan-out). Daedalus consumes this section as authoritative rather than independently re-querying graph data (prevents E10-DIVERGE between Architect and Planner).
- MUST compare Explorer and Analyst data for factual contradictions before making technical decisions. If disagreement found → report as E10-DIVERGE with both versions and analysis.
- Does NOT proceed with technical decisions when Explorer and Analyst data conflict (reports E10-DIVERGE)

**Knowledge access:** L1 (project-model), L0 (conventions), L2 (decisions — FULL), L1 (patterns), L1 (quality-map), L0 (failures index), L0 (libraries — verified-facts index)

**Budget:** 100k

---

## Daedalus (planner)

**Purpose:** Creates execution plan. Decomposes architect's decision into steps.

**Quality stance (D-185):** A plan that enables quality implementation — include context that helps Hephaestus write better code, not just correct code.

**Input:** Architecture decision
**Output:** Step-by-step plan with files, batches, dependencies, budget estimates

**Artifact output contract (D-184):** Plan artifact (`plan.md`) MUST contain these sections:
```
## Scope Check               — comparison with classification scope
### Added to scope           — what expanded beyond classification (with justification)
### Removed from scope       — what was dropped (with justification)
## Acceptance Test            — concrete test derived from classification acceptance criteria
## Risks                      — blocking risks with plan B for each
## Unverified Dependencies    — CONDITIONAL: required when architecture has UNVERIFIED items
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion. `## Unverified Dependencies` is conditionally required: hook checks architecture artifact for "UNVERIFIED" string; if found, this section must exist and address each UNVERIFIED item (verification step in plan, or risk acceptance justification). Cross-gate: receives classification scope + criteria + architecture recommendation + assumptions via traceability injection.

**Analysis paralysis guard (D-192):** If 5+ consecutive read-only tool calls (Read, Grep, Glob) occur without a write action (Edit, Write, Bash), STOP. State the blocker in one sentence, then either produce the plan or report STATUS: blocked with what specific information is missing.

**Embedded verification fields (D-191):** Every task in the plan MUST include:
- `Verify:` — concrete command that proves the task was completed correctly (e.g., `bash src/tests/tier1/test-X.sh`, `grep -q 'function_name' src/file.sh`)
- `Done:` — measurable success criteria (e.g., "all 34 tests pass", "function exists and returns JSON")
Hephaestus runs the verify command after each task. Plan-check (Themis) validates that every task has these fields.

**Rules:**
- Does NOT make architectural decisions, only decomposes
- Does NOT choose between technical alternatives (Architect's responsibility)
- Does NOT write implementation code
- Does NOT skip dependency analysis
- Uses quality-map (full) to inject quality pattern context into agent instruction files and align plan steps with existing quality patterns
- Must pass Plan Feasibility Checklist:
  - [ ] Every file in plan exists (or explicitly marked as new)
  - [ ] Dependencies between steps correctly ordered
  - [ ] Context budget per step within agent limits
  - [ ] No step requires knowledge that previous steps don't produce
  - [ ] Rollback path exists for each step
  - [ ] Contract interfaces defined for parallel batches
  - [ ] Every task has `Verify:` and `Done:` fields (D-191)
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

**Phase 4/5 tools:** Uses `ariadne_context` with task type and token budget to assemble graph context for instruction files, replacing manual assembly from 4-6 separate queries. Uses `ariadne_plan_impact` to assess structural impact of planned changes before decomposing into steps. `ariadne_context` returns token estimates (`total_tokens`, `budget_used`) for precise budget allocation per implementation batch.

**Structural baseline capture (D-186):** When graph data is available, Daedalus captures structural baseline for files in scope: current smell count/types (`ariadne_smells`), Martin metrics for affected clusters (`ariadne_metrics`), refactoring opportunities in affected area (`ariadne_refactor_opportunities`). Baseline recorded as `## Structural Baseline` section in plan artifact and propagated to Hephaestus and Themis instruction files.

**Pre-assembled context (D-187):** Daedalus includes `ariadne_context` results directly in Hephaestus instruction files as `## Pre-assembled Context`: ranked file list with relevance scores and token estimates, key symbols per file, dependency relationships. Hephaestus starts with a structural map instead of discovering it through grep.

**Knowledge access:** L1 (project-model), L1 (conventions), L0 (decisions), L0 (patterns), L2 (quality-map), L0 (libraries)

**Budget:** 70k

---

## Hephaestus (implementer)

**Purpose:** Writes code. Implements the plan faithfully with craftsmanship.

**Quality stance (D-185):** You own the quality of HOW code is written. The plan controls WHAT you build; you control the craftsmanship — clarity, efficiency, maintainability. Code should be good enough that you wouldn't need to explain it with comments.

**Artifact output contract (D-197):** Implementation artifact (`implementation.md`) MUST contain these sections:
```
## Changes Made              — list of files modified/created with description of change
## Verification Results      — results of running <verify> commands per task
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Input:** Assembled instructions (from Planner) + conventions + specific files to modify + pre-assembled context (D-187) + structural baseline (D-186)
**Output:** Code changes in project files

**Embedded task verification (D-191):** Each task in the plan includes a `<verify>` command and `<done>` criteria. After completing each task, Hephaestus runs the verify command. If verification fails, Hephaestus fixes the issue (up to 2 attempts per task) before proceeding to the next task. Verification results are recorded in implementation.md per task. If a task fails verification after 2 fix attempts, Hephaestus reports the failure in implementation.md and proceeds — final review (Themis) will catch it.

**Analysis paralysis guard (D-192):** If 5+ consecutive read-only tool calls (Read, Grep, Glob) occur without a write action (Edit, Write, Bash), STOP. State the blocker in one sentence, then either write code or report STATUS: blocked with what specific information is missing.

**Rules:**
- Implements the plan faithfully with craftsmanship — the plan defines WHAT to build; agent owns HOW it's built (D-185)
- Does NOT add scope beyond the plan — but within scope, writes quality code
- Does NOT make architectural decisions
- Does NOT deviate from plan — if plan unclear → STATUS: blocked
- Never fabricates API endpoints, URLs, schemas, data structures
- Never guesses types or return formats
- Follows project conventions exactly (loaded in instructions)
- Uses only authorized MCP tools
- Does NOT add features not in the plan
- Does NOT refactor code outside plan scope
- Does NOT add comments/docstrings/annotations to unchanged code
- Does NOT return STATUS: success when post-implementation validation commands have failed
- Runs `<verify>` command after each task completion (D-191)
- After code changes: runs post-implementation validation commands from `.moira/config.yaml` → `tooling.post_implementation[]` (D-063). If commands fail, fixes errors before returning STATUS: success. If no commands configured, skips validation.

**Phase 4/5 tools:** PREFER `ariadne_symbols` over Read+grep for finding symbol locations and verifying exports. PREFER `ariadne_callers` over grep for finding all usage sites of a changed function. Uses `ariadne_dependencies` to verify new imports respect existing dependency structure. Uses pre-assembled context from Daedalus instruction file (D-187) as primary structural map. (D-187: PREFER language for graph-first navigation.)

**Knowledge access:** L0 (project-model), L2 (conventions — FULL), L1 (patterns), L1 (libraries)

**Budget:** 120k

---

## Themis (reviewer)

**Purpose:** Checks code quality against standards and requirements. Also validates plans before execution (D-190).

**Quality stance (D-185):** Distinguish adequate from excellent. Correct code that is poorly structured, hard to read, or fragile is a WARNING, not a pass.

**Behavioral defense role:** Primary per-task defense against upstream agent behavioral violations (E9/E10). Catches role boundary violations, factual errors, and semantic correctness failures.

**Artifact output contract (D-197):** Review artifact (`review.md`) MUST contain these sections:
```
## Review Findings           — list of findings with severity classification
## Verdict                   — overall verdict (approve/request_changes/reject)
```
Plan-check variant (`plan-check.md`) MUST contain:
```
## Plan Check Findings       — validation results per check category
## Verdict                   — overall verdict (approve/request_changes/reject)
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Input (code review mode):** Written code + plan + requirements + conventions + structural baseline (D-186)
**Output (code review mode):** Issue list with severity (critical/warning/suggestion) + structural quality delta (D-186)

**Plan-check mode (D-190):** In Full pipeline, Themis is dispatched after Daedalus with a lightweight plan validation focus. Input: plan.md + architecture.md + exploration.md. Validates:
1. Scope alignment — plan covers all acceptance criteria from classification
2. File existence — every file in plan exists (or is explicitly new)
3. Dependency ordering — no step requires output from a later step
4. Contract completeness — batch interfaces are fully specified
5. Verification coverage — every task has a concrete `<verify>` command (D-191)
6. Budget feasibility — no batch exceeds agent limits
Output: plan-check findings with severity classification. Critical findings block the plan gate; warnings and suggestions are presented alongside the plan summary. Budget: ~40k (lighter than full code review).

**Rules:**
- Does NOT fix code — only identifies issues
- Does NOT modify project files
- Does NOT suppress findings
- Does NOT auto-approve (all findings must be reported)
- Must complete Code Correctness Checklist (q4-correctness, see quality.md for full checklist):
  - [ ] Upstream agents stayed within role boundaries (Explorer didn't propose solutions, Architect didn't fabricate APIs)
  - [ ] Factual claims in architecture verified against Explorer data (E10-DIVERGE defense)
  - [ ] Implementation matches approved architecture (E9-SEMANTIC defense)
- Severity classification:
  - CRITICAL: blocks pipeline, must fix (correctness, security, broken contracts)
  - WARNING: should fix, can proceed with user approval
  - SUGGESTION: logged for reflection, doesn't block
- Checks conformance with project quality-map
- Reviews architecture epistemic integrity — verifies factual premises about external systems are verified or marked UNVERIFIED (D-171)
- Evaluates Q4-E01 through Q4-E05 epistemic integrity checklist items
- **UNVERIFIED audit (D-184):** Receives full UNVERIFIED list via traceability injection. For each UNVERIFIED assumption: checks if implementation verified it (Context7/WebFetch evidence or code comment `// UNVERIFIED: {assumption}`). Reports unresolved UNVERIFIED items as WARNING findings.
- Verifies MCP calls were used correctly
- False positive awareness: if unsure, mark as WARNING not CRITICAL

**Phase 4/5 tools:** PREFER `ariadne_diff` over manual comparison for detecting structural changes. Uses `ariadne_cycles` to verify no new circular dependencies were introduced. Uses `ariadne_smells` to check for newly introduced architectural smells. Uses `ariadne_callers` to verify all call sites are updated after interface changes. Uses `ariadne_refactor_opportunities` scoped to changed area for quality delta assessment (D-186). (D-187: PREFER language for graph-first navigation.)

**Structural quality delta (D-186):** After graph auto-updates post-implementation, Themis computes structural quality delta by comparing current state against baseline from plan artifact. Reports delta as `## Structural Quality Delta` in review artifact with verdict: improved | neutral | degraded:minor (WARNING) | degraded:major (WARNING).

**Knowledge access:** L1 (project-model), L2 (conventions — FULL), L1 (decisions), L1 (patterns), L1 (quality-map)
**Write access:** quality_map

**Budget:** 100k

---

## Aletheia (tester)

**Purpose:** Writes and runs tests.

**Quality stance (D-185):** Tests that only verify happy path are incomplete. Tests that test implementation details are brittle. Find the balance.

**Pipeline dispatch changes (D-194, D-195):** Aletheia is removed from all default pipeline flows (Quick, Standard, Full, Decomposition). Its responsibilities are redistributed:
- **Running tests/build** → bash step (`tooling.post_implementation[]`, ~0 tokens)
- **Writing tests** → Hephaestus (tests are code; Daedalus includes test tasks in the plan)
- **Integration testing** → bash step + Hephaestus writes integration tests as plan tasks
- **Ad-hoc testing at final gate** → Hephaestus dispatch

Aletheia remains as an agent definition available for explicit user dispatch when specialized test work is needed.

**Artifact output contract (D-197):** Testing artifact (`testing.md`) MUST contain these sections:
```
## Test Cases                — tests written/run with descriptions
## Results Summary           — pass/fail counts and coverage assessment
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

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
- Does NOT skip running tests after writing them
- Does NOT write brittle tests (testing implementation details)
- Does NOT ignore test failures
- If test fails due to implementation bug → reports, doesn't fix

**Phase 4/5 tools:** Uses `ariadne_tests_for` to identify existing test files before writing new ones — avoids duplicating coverage. Uses `ariadne_blast_radius` on modified files to ensure tests cover the full structural impact zone. Uses `ariadne_callers`/`ariadne_callees` to understand call chains for integration test design.

**Knowledge access:** L0 (project-model), L1 (conventions), L0 (patterns)

**Budget:** 90k

---

## Mnemosyne (reflector)

**Purpose:** Analyzes completed tasks for learning.

**Behavioral defense role:** Primary defense against systemic behavioral drift. Detects patterns of agent boundary violations, recurring factual errors, and constraint degradation over time.

**Artifact output contract (D-197):** Reflection artifact (`reflection.md`) MUST contain these sections:
```
## Analysis                  — assessment across 6 dimensions (accuracy, efficiency, predictions, architecture, gaps, orchestrator)
## Recommendations           — concrete observations and proposals
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

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
- Does NOT modify project source files or moira configuration files directly (knowledge writes go through the knowledge management subsystem)
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

**Artifact output contract (D-197):** Audit artifact (`audit-findings.md`) MUST contain these sections:
```
## Findings                  — per-domain findings with evidence
## Risk Assessment           — risk classification per finding (low/medium/high)
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Input:** All moira files (rules, knowledge, config, state, metrics)
**Output:** Audit report with findings and recommendations

**Analytical pipeline mode (D-126):** In the Analytical Pipeline, Argus role rules include an `analytical_mode` section with CS method templates (CS-3 hypothesis-driven, CS-4 abductive reasoning). Activated by orchestrator when pipeline=analytical and subtype is `audit` or `weakness`.

**Rules:**
- Independent from pipeline (not part of task execution)
- READ-ONLY — never modifies moira or project files
- Does NOT make changes -- only reports findings
- Does NOT suppress audit findings
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

---

## Calliope (scribe)

**Purpose:** Synthesizes analytical findings into deliverable markdown documents. Participates only in the Analytical Pipeline (D-118).

**Artifact output contract (D-197):** Deliverables artifact (`deliverables.md`) MUST contain these sections:
```
## Sources                   — finding sources cited with evidence references
## Content                   — synthesized content organized per synthesis plan
```
Validated by `artifact-validate.sh` hook — missing sections block agent completion.

**Input:** Structured findings (lattice-organized) from analysis phase + existing documents to update
**Output:** New and/or updated markdown documentation in project

**Response format:**
```
STATUS: success|failure|blocked
SUMMARY: <documents written/updated>
ARTIFACTS: [list of created/modified file paths]
NEXT: review
```

**Rules:**
- Writes ONLY markdown documentation — NEVER source code
- Does NOT perform analysis — synthesizes findings produced by other agents
- Does NOT decide what to include/exclude — follows the synthesis plan from findings
- Does NOT add conclusions beyond what findings support
- Does NOT fabricate references, metrics, or evidence
- Preserves existing document structure when updating (targeted edits, not rewrites)
- When updating: reads current version, identifies sections to modify, applies changes
- Must cite evidence source for every claim (file path, Ariadne metric, agent finding)

**Knowledge access:** L1 (project-model), L1 (conventions), L0 (decisions)

**Capability profile:** Read + Edit + Write (markdown only, scoped to documentation paths)

**Budget:** 80k

---

Note: Bootstrap scanners (Tech/Structure/Convention/Pattern) are Explorer invocations with Layer 4 task-specific instructions, not separate agents (D-032).
