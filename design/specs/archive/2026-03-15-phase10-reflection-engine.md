# Phase 10: Reflection Engine & LLM-Judge

## Goal

Implement the post-task reflection system and LLM-judge for quality evaluation. After Phase 10: Mnemosyne (reflector) runs after every task at the appropriate depth level (lightweight/standard/deep/epic), observations accumulate across tasks with evidence tracking, rule change proposals surface after 3+ confirming observations (Art 5.2), knowledge updates from reflection, MCP documentation caching based on repeated call detection, and the LLM-judge provides objective quality scores for bench testing and `/moira health`.

**Why now:** The full pipeline is operational (Phases 1-9). Agents produce artifacts, quality gates generate findings, telemetry captures metrics. The orchestrator already defines reflection dispatch levels (`post: reflection:` in pipeline YAMLs) and the Reflection Dispatch table in `orchestrator.md`. Mnemosyne's role definition exists (`mnemosyne.yaml`). Bench infrastructure exists (`bench.sh`, `bench.md`) but quality scores are `null` — the judge was deferred to Phase 10 per D-046. Phase 9 created `knowledge/libraries/` structure for MCP caching (D-081) — Phase 10 provides the intelligence.

## Risk Classification

**YELLOW (overall)** — New shell libraries, new templates, updates to existing bench infrastructure and knowledge system. No pipeline gate changes. No agent role boundary changes. Needs regression check + impact analysis.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: Reflection Library | YELLOW | New shell library with cross-task state access |
| D2: Reflection Templates | GREEN | New template files, additive |
| D3: Reflection Dispatch Skill | YELLOW | New skill wiring orchestrator to reflection templates |
| D4: Evidence Tracking | YELLOW | New storage format, cross-task accumulation |
| D5: Rule Change Proposal System | YELLOW | New workflow, touches knowledge system |
| D6: MCP Knowledge Caching Logic | YELLOW | Extends knowledge.sh, adds libraries type |
| D7: LLM-Judge Library | YELLOW | New shell library, Claude API invocation |
| D8: Judge Prompt Template | GREEN | New template file, additive |
| D9: Rubric Files | GREEN | New YAML files, additive |
| D10: Calibration Set & Command | GREEN | New files + bench.md update |
| D11: Bench Runner Integration | YELLOW | Modifies bench.sh to invoke judge |
| D12: `/moira health` Command | YELLOW | New command with judge-based scoring |
| D13: Statistical Confidence Bands | YELLOW | New statistical functions in bench.sh |
| D14: Tier 1 Tests | GREEN | New test file, additive |

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/architecture/agents.md` | Mnemosyne definition: 6 analysis dimensions, exit criteria, minimum output structure, knowledge access (L2 all), write access (all types) |
| `design/subsystems/testing.md` | LLM-judge architecture (lines 552-679), rubric structure, calibration, statistical model (lines 205-256), composite score formula, bench commands |
| `design/subsystems/knowledge.md` | Knowledge write operations, freshness system, consistency validation, MCP caching section, archival rotation |
| `design/subsystems/quality.md` | CONFORM/EVOLVE modes, evolution lifecycle (Discovery→Documentation→Accumulation→Proposal→Approval→Execution), anti-chaos safeguards, 3-confirmation rule |
| `design/subsystems/metrics.md` | Quality metrics (first-pass acceptance, tweak rate), knowledge metrics (patterns, freshness), evolution metrics |
| `design/CONSTITUTION.md` | Art 5.1 (knowledge is evidence-based), Art 5.2 (rule changes require 3+ observations), Art 5.3 (knowledge consistency validation), Art 4.2 (user authority — proposals need approval) |
| `design/decisions/log.md` | D-024 (LLM-judge with anchored rubrics), D-025 (statistical confidence bands), D-046 (judge deferred to Phase 10), D-081 (MCP caching structure now, logic later) |
| `design/architecture/overview.md` | File structure: `state/tasks/{id}/reflection.md`, reflection engine in global layer |

## Prerequisites (from Phase 1-9)

- **Phase 1:** State management, scaffold, knowledge directory structure
- **Phase 2:** Agent role definitions — `mnemosyne.yaml` exists with 6 analysis dimensions, exit criteria, minimum output structure
- **Phase 3:** Pipeline definitions with `post: reflection: lightweight|background|deep|epic` (quick=lightweight, standard=background, full=deep, decomposition=epic). Orchestrator skill Section 7 (Completion Flow) with Reflection Dispatch table
- **Phase 4:** Knowledge system (`knowledge.sh`) with CRUD, freshness tracking, consistency validation, archive rotation. Knowledge access matrix with Mnemosyne at L2 all + write all
- **Phase 5:** Bootstrap engine, knowledge generation
- **Phase 6:** Quality gates, findings format (`findings/{agent}-{gate}.yaml`), bench infrastructure (`bench.sh`, `bench.md`), fixture projects, test case format. Rubric DEFINITION files deferred to Phase 10 per D-046
- **Phase 7:** Budget tracking, telemetry.yaml with per-agent token usage
- **Phase 9:** MCP registry, `knowledge/libraries/` directory and templates (D-081)

## Existing Infrastructure Audit

### Already Implemented (no changes needed)

1. **Mnemosyne role rules** (`mnemosyne.yaml`): 6 analysis dimensions, NEVER constraints, exit criteria, minimum output structure, knowledge access L2 all, write access all types
2. **Pipeline reflection dispatch**: All 4 pipelines define `post: reflection:` with appropriate level (quick=lightweight, standard=background, full=deep, decomposition=epic)
3. **Orchestrator Reflection Dispatch table** (`orchestrator.md` Section 7): Routes lightweight/background/deep/epic to appropriate Mnemosyne invocations
4. **Knowledge system** (`knowledge.sh`): Full CRUD with freshness, consistency validation, archive rotation, quality map updates
5. **Knowledge access matrix** (`knowledge-access-matrix.yaml`): Mnemosyne has L2 read + write access to all 6 knowledge types
6. **Bench runner** (`bench.sh`): Test execution, tier routing, budget guards, report generation — quality_scores=null
7. **Bench command** (`bench.md`): Subcommands for tier1/tier2/tier3/report/compare — notes "no LLM-judge"
8. **Telemetry schema** (`telemetry.schema.yaml`): Per-task telemetry with pipeline, execution, quality, structural sections
9. **State file structure**: `state/tasks/{id}/reflection.md` already defined in file structure
10. **Quality findings format**: Structured YAML in `findings/{agent}-{gate}.yaml` (D-047)

### Not Yet Implemented (Phase 10 scope)

1. **Reflection library**: No `reflection.sh` for cross-task analysis utilities
2. **Reflection templates**: No instruction templates for Mnemosyne at each depth level
3. **Reflection dispatch skill**: No `reflection.md` skill for orchestrator
4. **Evidence tracking**: No cross-task observation accumulation mechanism
5. **Rule change proposal workflow**: No format or presentation for proposals
6. **MCP caching logic**: `knowledge/libraries/` structure exists but no detection/proposal logic
7. **LLM-Judge library**: No `judge.sh` for judge invocation
8. **Judge prompt template**: No template for judge Claude call
9. **Rubric files**: No YAML rubric files with anchored examples (definitions deferred from Phase 6)
10. **Calibration set**: No calibration examples for judge stability validation
11. **Judge calibration command**: `bench.md` lists `calibrate` but not implemented
12. **`/moira health` full version**: Command doesn't exist yet (testing.md defines it)
13. **Statistical confidence bands**: No baseline/variance tracking or zone classification
14. **Libraries knowledge type**: `knowledge.sh` excludes `libraries` type — needs to be wired in

## Deliverables

### D1: Reflection Library (`src/global/lib/reflection.sh`)

Shell library for cross-task reflection utilities.

#### `moira_reflection_task_history <state_dir> [count]`

Read recent completed task summaries for pattern detection.
- Scans `state/tasks/*/status.yaml` for completed tasks
- Returns last N tasks (default 10) sorted by completion time
- Output per task: task_id, pipeline_type, first_pass_accepted, retry_count, classification_correct
- Returns 1 if no completed tasks found

#### `moira_reflection_observation_count <state_dir> <pattern_key>`

Count observations matching a pattern key across task reflections.
- Scans `state/tasks/*/reflection.md` for `OBSERVATION:` lines matching pattern_key
- Returns integer count
- Used for 3-confirmation threshold check (Art 5.2)

#### `moira_reflection_get_observations <state_dir> <pattern_key>`

Get all observations for a specific pattern with evidence.
- Returns: task_id, observation text, evidence reference per match
- Used when constructing rule change proposals

#### `moira_reflection_mcp_call_frequency <state_dir>`

Detect repeated MCP calls across tasks for caching recommendations.
- Scans `state/tasks/*/telemetry.yaml` → `mcp_calls[]` section (added by Phase 10, see D6d)
- Aggregates by server:tool:query pattern
- Returns entries with 3+ occurrences (D-081 caching threshold matches Art 5.2)
- Output: server, tool, query_pattern, count, total_tokens_spent

#### `moira_reflection_pending_proposals <state_dir>`

List pending rule change proposals awaiting user approval.
- Reads `state/reflection/proposals.yaml`
- Returns proposals with status=pending

#### `moira_reflection_record_proposal <state_dir> <proposal_yaml>`

Record a new rule change proposal.
- Appends to `state/reflection/proposals.yaml`
- Sets status=pending, timestamp, evidence citations

#### `moira_reflection_deep_counter <state_dir> [increment|reset]`

Manage the periodic deep reflection counter (D-092).
- No args: read `state/reflection/deep-reflection-counter.yaml`, return current count (0 if missing)
- `increment`: increment counter by 1, write back
- `reset`: set counter to 0, write back
- Used by reflection dispatch skill (D3) for every-5-tasks escalation

### D2: Reflection Templates

Instruction templates for Mnemosyne at each depth level. Located at `src/global/templates/reflection/`.

#### D2a: Lightweight Template (`lightweight.md`)

Minimal per-task note. NOT a full Mnemosyne dispatch — orchestrator writes this directly.

**Content written to `reflection.md`:**
```
## Lightweight Reflection — {task_id}
Pipeline: {pipeline_type}
Result: {final_gate_action}
Retries: {retry_count}
Budget: {budget_pct}%
```

No agent dispatch. No knowledge updates. Quick pipeline only.

#### D2b: Standard Template (`standard.md`)

Full Mnemosyne dispatch for standard tasks (background).

**Template sections:**
1. **Context loading**: Task artifacts to read (classification, requirements, architecture, plan, review, test-results, telemetry, findings)
2. **Analysis instructions**: Run all 6 dimensions (accuracy, efficiency, predictions, architecture, gaps, orchestrator)
3. **Knowledge update instructions**: What to write and where, using `moira_knowledge_write` patterns
4. **Evidence tracking**: Tag observations with pattern keys for cross-task accumulation
5. **Rule proposal check**: Call `moira_reflection_observation_count` for recurring patterns, propose if 3+
6. **MCP caching check**: Call `moira_reflection_mcp_call_frequency`, propose caching for 3+ repeated calls
7. **Exit criteria reminder**: Must produce all 5 minimum output items

**Observation tagging format:**
```
OBSERVATION: [pattern_key:naming_inconsistency] Explorer missed utils/ directory in 3 recent tasks
  EVIDENCE: task-{id} exploration.md line 42 — utils/ not listed in scanned directories
```

Pattern keys are lowercase-kebab identifiers that enable cross-task grouping. Mnemosyne chooses keys based on the observation category (e.g., `naming_inconsistency`, `missing_edge_case`, `budget_overrun`, `mcp_unnecessary_call`).

#### D2c: Deep Template (`deep.md`)

Extended analysis for explicitly requested deep reflection.

**Additional sections beyond standard:**
1. **Cross-task pattern analysis**: Read last 5-10 task reflections, identify recurring themes
2. **Knowledge freshness audit**: Check all knowledge types for staleness
3. **Quality trend analysis**: Compare recent task quality metrics against historical
4. **Evolution readiness assessment**: Are any patterns mature enough for EVOLVE proposal?

#### D2d: Epic Template (`epic.md`)

Cross-subtask pattern analysis for decomposition pipelines.

**Additional sections beyond deep:**
1. **Subtask coherence check**: Did decomposed subtasks maintain architectural consistency?
2. **Cross-subtask duplication**: Were patterns repeated unnecessarily across subtasks?
3. **Decomposition quality**: Was the Planner's decomposition effective?
4. **Integration gap analysis**: Were integration points between subtasks handled correctly?

### D3: Reflection Dispatch Skill (`src/global/skills/reflection.md`)

Skill that tells the orchestrator HOW to construct Mnemosyne dispatch prompts.

**Responsibilities:**
1. Read the reflection level from pipeline definition (`post: reflection:`)
2. **Periodic escalation check:** Count completed tasks since last deep reflection (read `state/reflection/deep-reflection-counter.yaml`). If count >= 5 and pipeline level is `background` → escalate to `deep` (per roadmap "Pattern analysis per 5 tasks"). Reset counter after deep reflection.
3. For `lightweight`: write minimal reflection note directly (no agent dispatch)
4. For `background`/`deep`/`epic`: construct Mnemosyne prompt from template + task context
5. Assemble knowledge context per Mnemosyne's access matrix (L2 all)
6. Include list of task artifacts for Mnemosyne to read
7. For `background`: dispatch as background agent (non-blocking)
8. For `deep`/`epic`: dispatch as foreground agent (blocking)
9. On Mnemosyne return: process knowledge updates and rule proposals

**Prompt assembly pattern:**
```
{reflection template for level}

## Task Context
Task ID: {task_id}
Pipeline: {pipeline_type}
Task artifacts: {list of state/tasks/{id}/*.md paths}

## Knowledge Context
{assembled knowledge per access matrix — all types at L2}

## Recent History (for pattern detection)
{moira_reflection_task_history output — last 5-10 tasks}

## Pending Observations
{observations from recent tasks matching active pattern keys}
```

**Post-reflection processing:**
1. Parse Mnemosyne's KNOWLEDGE_UPDATES section
2. For each update: call `moira_knowledge_write` with appropriate type/level/content
3. Run `moira_knowledge_validate_consistency` before writing (Art 5.3)
4. Parse RULE_PROPOSALS section
5. For each proposal: call `moira_reflection_record_proposal`
6. If proposals exist: display notification to user (non-blocking)
7. Parse MCP caching recommendations (if any)
8. For each recommendation: display to user with cache/ignore options

### D4: Evidence Tracking & Pattern Detection

Cross-task observation accumulation for the 3-confirmation rule (Art 5.2).

#### D4a: Observation Storage

Observations live in individual task reflection files (`state/tasks/{id}/reflection.md`), tagged with pattern keys. The `moira_reflection_observation_count` function in D1 scans these files to count occurrences.

No separate observation database — uses existing task state files as source of truth. This avoids a new state file and leverages the existing task lifecycle.

#### D4b: Pattern Key Registry

File: `state/reflection/pattern-keys.yaml`

Tracks known pattern keys with metadata:
```yaml
patterns:
  naming_inconsistency:
    first_seen: "t-2026-03-15-001"
    observation_count: 3
    last_seen: "t-2026-03-15-008"
    status: proposal_ready  # observed | accumulating | proposal_ready | proposed | resolved
  missing_edge_case:
    first_seen: "t-2026-03-15-003"
    observation_count: 1
    last_seen: "t-2026-03-15-003"
    status: observed
```

Updated by Mnemosyne after each reflection. Status transitions:
- `observed` (1 occurrence) → `accumulating` (2) → `proposal_ready` (3+) → `proposed` (proposal created) → `resolved` (proposal accepted/rejected)

#### D4c: Evidence Validation

Before recording an observation, Mnemosyne must:
1. Cite specific evidence (task ID + artifact + line/section)
2. Verify evidence exists (the cited file and content are real — Art 5.1)
3. Check if pattern key already exists in registry
4. If new key: create entry with status `observed`
5. If existing key: increment count, update `last_seen`

### D5: Rule Change Proposal System

Workflow for proposing and managing rule changes.

#### D5a: Proposal Format

File: `state/reflection/proposals.yaml`

```yaml
proposals:
  - id: "prop-001"
    created: "2026-03-15T10:00:00Z"
    status: pending  # pending | approved | rejected | deferred
    pattern_key: "naming_inconsistency"
    observation_count: 3
    evidence:
      - task_id: "t-2026-03-15-001"
        observation: "Explorer output uses camelCase for file descriptions but project uses snake_case"
        artifact: "state/tasks/t-2026-03-15-001/exploration.md"
      - task_id: "t-2026-03-15-004"
        observation: "Same inconsistency in exploration output"
        artifact: "state/tasks/t-2026-03-15-004/exploration.md"
      - task_id: "t-2026-03-15-008"
        observation: "Naming mismatch propagated to architecture"
        artifact: "state/tasks/t-2026-03-15-008/architecture.md"
    proposed_change:
      target: "core/rules/roles/hermes.yaml"
      type: "rule_addition"
      description: "Add naming convention enforcement to Explorer identity section"
    resolution: null
    resolved_at: null
```

#### D5b: Proposal Presentation

When Mnemosyne generates a proposal, the orchestrator (via reflection skill D3) presents it non-blockingly:

```
Mnemosyne (reflector) — Rule Change Proposal

Pattern: naming_inconsistency (observed 3 times)
Proposed: Add naming convention enforcement to Explorer rules

Evidence:
  1. Task t-...-001: Explorer used camelCase vs project snake_case
  2. Task t-...-004: Same inconsistency repeated
  3. Task t-...-008: Propagated to architecture output

  approve  — apply the proposed change
  defer    — revisit later
  reject   — dismiss proposal
  details  — show full evidence
```

User approval required (Art 4.2). Approved proposals are applied as a dedicated task (through the standard pipeline in EVOLVE mode, per quality.md evolution lifecycle: Discovery→Documentation→Accumulation→Proposal→Approval→Execution).

**Anti-Chaos Safeguards (per quality.md):**
- **One evolution at a time:** Only one approved proposal can be in-progress as an EVOLVE task. Additional approved proposals queue until the current one completes.
- **Scope lock:** The EVOLVE task addresses exactly what the proposal specifies — no "while we're at it" expansions.
- **Regression detection:** After an EVOLVE task completes, run relevant bench tests. If regression detected → proposal marked as `reverted`.
- **Cooldown period:** 5 tasks in CONFORM mode after any evolution task completes. During cooldown, new proposals still accumulate but are not presented. The `moira_quality_tick_cooldown` function (already in quality.sh) manages this.

#### D5c: Proposal Management

Functions in `reflection.sh`:
- `moira_reflection_resolve_proposal <state_dir> <proposal_id> <resolution>` — update proposal status
- `moira_reflection_auto_defer_stale <state_dir>` — scan proposals.yaml for entries with status=pending and `created` older than 30 days, set status=deferred. Called by reflection dispatch skill before presenting new proposals.
- Resolved proposals remain in file for audit trail

### D6: MCP Knowledge Caching Logic

Implements the intelligence layer for MCP documentation caching (D-081).

#### D6a: Add `libraries` to Knowledge System

Update `knowledge.sh`:
- Add `libraries` to `_MOIRA_KNOWLEDGE_TYPES` (line 17)
- **Also update** the hardcoded `dimensions` list in `moira_knowledge_read_for_agent` (line 85) — this is a SEPARATE list from `_MOIRA_KNOWLEDGE_TYPES` that must also include `libraries`
- Libraries L0/L1 follow standard pattern (`index.md`, `summary.md`), but L2 is different:
  - L0 (`index.md`): list of cached libraries with timestamps
  - L1 (`summary.md`): key API facts per library
  - L2: individual library files (`knowledge/libraries/{library-name}.md`) — NOT `full.md`
- **L2 special handling:** Add a special case in `moira_knowledge_read`: when type is `libraries` and level is `L2`, return empty (not error) since libraries L2 means individual per-library files, not a single `full.md`. Agents that need library L2 content read individual files via `moira_knowledge_read_library <knowledge_dir> <library_name>` (new helper function). For `moira_knowledge_read_for_agent`, libraries dimension at L2 loads `summary.md` (L1 content) as the best available aggregate — individual library files are too numerous to concatenate.

Update `knowledge-access-matrix.yaml`:
- Add `libraries` dimension to all agent rows
- Access: Mnemosyne=L2 (read+write), Hephaestus=L1, Daedalus=L0, Argus=L2 (read-only, per agents.md "L2 all knowledge types"), all others=null

#### D6b: Caching Detection (in Mnemosyne standard template)

Mnemosyne checks `moira_reflection_mcp_call_frequency` during standard reflection. For any server:tool:query with 3+ occurrences:

1. Extract the essential information from MCP response history
2. Propose caching with estimated savings
3. Present to user (via reflection skill post-processing)

**User presentation:**
```
MCP Caching Recommendation

context7:query-docs("react-datepicker") called 4 times
Estimated savings: ~14k tokens per task

  cache  — create knowledge/libraries/react-datepicker.md
  ignore — library changes too often, always fetch fresh
```

On `cache`: Mnemosyne extracts essential API reference from MCP responses and writes to `knowledge/libraries/{library-name}.md`. Updates `knowledge/libraries/index.md` and `summary.md`.

On `ignore`: Records ignore decision in `state/reflection/mcp-cache-decisions.yaml` to avoid re-proposing.

#### D6c: Cache Freshness

Cached library docs use the standard freshness system. Mnemosyne marks freshness on each use. When stale (>20 tasks), the next MCP call refreshes the cache rather than using stale content.

#### D6d: Telemetry MCP Extension

The current `telemetry.schema.yaml` has no MCP usage fields. Add a `mcp_calls` section to the telemetry schema so that `moira_reflection_mcp_call_frequency` has data to scan.

**New fields in `telemetry.schema.yaml`:**
```yaml
mcp_calls:
  type: list
  description: "MCP tool calls made during this task"
  item_schema:
    server:
      type: string
      required: true
    tool:
      type: string
      required: true
    query_summary:
      type: string
      required: true
      description: "Sanitized query pattern (no content — privacy per D-027)"
    tokens_used:
      type: number
      required: true
    agent:
      type: string
      required: true
      description: "Which agent made the call (e.g., hephaestus)"
```

**Integration point:** The orchestrator's completion flow already writes telemetry data. MCP call data is extracted from agent status summaries and Reviewer (Themis) MCP verification findings. Planner's instruction files contain the authorized MCP calls — compare with Reviewer's findings to determine which calls were actually made.

**Privacy note (D-027):** `query_summary` records the pattern (e.g., "react-datepicker docs") not the full query content. Follows the existing sanitization rules: allowed types are string from whitelist only.

### D7: LLM-Judge Library (`src/global/lib/judge.sh`)

Shell library for LLM-judge invocation and result management.

#### `moira_judge_invoke <task_dir> <rubric_path> [model_tier]`

Invoke the LLM-judge on a completed task.
- Reads task artifacts from `task_dir` (implementation.md, review.md, test-results.md, requirements.md, architecture.md)
- Reads rubric from `rubric_path`
- Constructs judge prompt from template (`templates/judge/judge-prompt.md`)
- Dispatches judge as a separate Agent call (NOT part of pipeline — D-024)
- Model tier: `sonnet-tier` (default) or `opus-tier` (calibration). Resolved to actual model ID at runtime.
- Parses structured YAML response
- Writes evaluation to `task_dir/judge-evaluation.yaml`
- Returns 0 on success, 1 on failure

**Judge independence:** Judge SHOULD use a different model tier than agents (D-024). If agents ran on sonnet-tier and judge also uses sonnet-tier, mark evaluation as `same_tier: true` in output.

#### `moira_judge_composite_score <evaluation_path> [automated_pass]`

Calculate weighted composite score from judge evaluation with automated check gate.
- Reads scores from evaluation YAML
- Applies weights: requirements_coverage=25%, code_correctness=30%, architecture_quality=25%, conventions_adherence=20%
- Returns composite score (1-5 scale)
- **Automated pass cap (per testing.md):** If `automated_pass` is `false` (compile/lint/tests failed), the normalized 0-100 quality score is capped at 20 regardless of judge scores. The 1-5 composite is still computed but the cap applies at the normalized level in health/bench reporting.

#### `moira_judge_normalize_score <score_1_5>`

Convert 1-5 judge score to 0-100 for Health Score.
- Formula: `(score - 1) * 25`
- Returns integer 0-100

#### `moira_judge_calibrate <calibration_dir> <rubric_path>`

Run calibration check against known examples.
- Reads calibration examples from `calibration_dir`
- Runs judge on each example
- Compares actual scores against expected scores (±1 tolerance)
- Reports: pass/fail per example, overall calibration status
- Returns 0 if all examples within tolerance, 1 otherwise

### D8: Judge Prompt Template (`src/global/templates/judge/judge-prompt.md`)

Template for the judge Claude call.

**Template structure:**

```markdown
# Quality Evaluation — LLM Judge

You are evaluating the quality of code produced by an AI agent pipeline.
You are NOT part of the pipeline. You evaluate AFTER the fact.

## Task Context
{task description from input.md}

## Requirements
{requirements from requirements.md}

## Architecture Decision
{architecture from architecture.md}

## Implementation
{implementation artifacts}

## Review Findings
{review from review.md}

## Test Results
{test results from test-results.md}

## Rubric

Evaluate each criterion on a 1-5 scale using the anchored examples below.
For each criterion, provide:
- score (integer 1-5)
- justification (1-2 sentences)
- evidence (specific references to artifacts above)

{rubric criteria with anchored examples}

## Output Format

Return ONLY valid YAML in this exact format:
{judge output format from testing.md lines 627-653}
```

### D9: Rubric Files (`src/tests/bench/rubrics/`)

YAML rubric files with anchored examples per testing.md specification. Located at `src/tests/bench/rubrics/` — consistent with testing.md file structure (`.claude/moira/testing/bench/rubrics/`) and Phase 6 bench infrastructure.

#### D9a: Feature Implementation Rubric (`feature-implementation.yaml`)

Standard rubric for feature tasks. 4 criteria from testing.md lines 586-623:
- `requirements_coverage` (weight 25, anchors 1-5)
- `code_correctness` (weight 30, anchors 1-5)
- `architecture_quality` (weight 25, anchors 1-5)
- `conventions_adherence` (weight 20, anchors 1-5)

Each anchor has: label, description, concrete example.

#### D9b: Bugfix Rubric (`bugfix.yaml`)

Adjusted weights for bugfix tasks:
- `requirements_coverage` (weight 20) — was the bug actually fixed?
- `code_correctness` (weight 40) — higher weight — no regressions?
- `architecture_quality` (weight 15) — lower weight — fix shouldn't restructure
- `conventions_adherence` (weight 25) — fix should match codebase style

#### D9c: Refactor Rubric (`refactor.yaml`)

Adjusted weights for refactoring tasks:
- `requirements_coverage` (weight 15) — behavioral equivalence maintained?
- `code_correctness` (weight 30) — no regressions?
- `architecture_quality` (weight 35) — higher weight — main purpose of refactor
- `conventions_adherence` (weight 20) — consistent with project style

### D10: Calibration Set & Command

#### D10a: Calibration Examples (`src/tests/bench/calibration/`)

Three examples per testing.md lines 657-679:

1. **`good-implementation/`** — well-structured feature with tests
   - Expected scores: {req: 4, code: 4, arch: 4, conv: 4}
   - Tolerance: ±1

2. **`mediocre-implementation/`** — working but messy, partial tests
   - Expected scores: {req: 3, code: 2, arch: 3, conv: 3}
   - Tolerance: ±1

3. **`poor-implementation/`** — missing requirements, bugs, no structure
   - Expected scores: {req: 2, code: 1, arch: 2, conv: 2}
   - Tolerance: ±1

Each example contains: mock `input.md`, `requirements.md`, `architecture.md`, `implementation.md`, `review.md`, `test-results.md` — sufficient for judge evaluation.

#### D10b: Calibration Command

Update `bench.md` to implement `calibrate` subcommand:
1. Source `judge.sh`
2. Call `moira_judge_calibrate` with calibration dir and default rubric
3. Display per-example results with pass/fail
4. Display overall calibration status
5. If any example fails: warn that judge may be unreliable

**Recalibration triggers** (per testing.md):
- Rubric version change
- Judge model change
- Every 20 bench runs

### D11: Bench Runner Integration

Update `bench.sh` to invoke LLM-judge after test execution.

#### D11a: Judge Integration in `moira_bench_run`

After recording structural results (existing logic), add:
1. Check if judge is available (judge.sh sourced, rubric exists)
2. Select rubric based on test case `meta.category` (feature/bugfix/refactor)
3. Call `moira_judge_invoke` on task artifacts
4. Read evaluation, extract composite score
5. Write quality scores to run result YAML (replacing `quality_scores: null`)

```yaml
quality_scores:
  requirements_coverage: 4
  code_correctness: 3
  architecture_quality: 4
  conventions_adherence: 4
  composite: 3.75
  automated_pass: true  # compile_ok AND lint_ok AND tests_pass
  normalized_score: 69  # (3.75-1)*25=68.75, rounded; capped at 20 if automated_pass=false
  judge_model: "<resolved>"
  same_tier: false
```

#### D11b: Report Update

Update `moira_bench_report` to include quality scores:
- Display per-test quality scores alongside structural results
- Calculate aggregate quality score across all tests in run
- Show zone indicator (NORMAL/WARN/ALERT) when baseline exists

### D12: `/moira health` Command (`src/commands/moira/health.md`)

Full health check command per testing.md lines 796-802.

**Flow:**
1. Run Structural Verifier (Tier 1) — instant, 0 tokens
2. Load live telemetry aggregate (`testing/live/index.yaml`)
3. If judge available: calculate Result Quality score from recent telemetry
4. Calculate Efficiency score from telemetry
5. Compute composite Moira Health Score (0-100):
   - Structural Conformance: 30% weight
   - Result Quality: 50% weight (null if no judge data)
   - Efficiency: 20% weight
6. Display composite score + sub-metrics + trends
7. Show top issues from recent reflections
8. Offer drill-down

**Display format:**
```
Moira Health Score: 82/100

  Structural Conformance:  95/100 (30%)  ✅
  Result Quality:          78/100 (50%)  ⚠
  Efficiency:              71/100 (20%)  →

Quality breakdown:
  Requirements coverage:   4.1 avg  (NORMAL)
  Code correctness:        3.8 avg  (NORMAL)
  Architecture quality:    3.2 avg  (WARN ↓)
  Conventions adherence:   4.0 avg  (NORMAL)

Top issues:
  1. Architecture quality declining — 2 consecutive WARN
  2. 3 stale knowledge entries (patterns, failures, quality-map)

  details  — show per-metric breakdown
  history  — show trend over last 5 periods
```

### D13: Statistical Confidence Bands

Implement the statistical model from testing.md lines 205-256.

#### D13a: Baseline Storage

Extend `bench/results/aggregate.yaml` with statistical profiles:

```yaml
baselines:
  composite_score:
    mean: 78
    variance: 4
    n_observations: 8
    confidence_band:
      low: 74
      high: 82
  requirements_coverage:
    mean: 4.1
    variance: 0.3
    n_observations: 8
    confidence_band:
      low: 3.8
      high: 4.4
  # ... per criterion
```

#### D13b: Statistical Functions in `bench.sh`

Add functions:

- `moira_bench_update_baseline <aggregate_path> <metric> <new_value>` — recalculate mean, variance, bands
- `moira_bench_classify_zone <aggregate_path> <metric> <value>` — return NORMAL/WARN/ALERT
- `moira_bench_check_regression <aggregate_path>` — check all metrics, return regression/improvement/noise decisions per testing.md decision rules

#### D13c: Cold Start Protocol

Per testing.md lines 260-276:
- Phase 1 (3-5 runs): collect data, no decisions
- Phase 2 (5-10 runs): wide bands (±2σ), only ALERT triggers
- Phase 3 (10+ runs): full model

`moira_bench_classify_zone` adjusts behavior based on `n_observations`.

#### D13d: Minimum Effect Size

Per testing.md lines 294-300:
- Composite score: ignore changes < 3 points
- Sub-metric: ignore changes < 5 points
- Conformance: any change is significant (binary)

### D14: Tier 1 Tests (`src/tests/tier1/test-reflection-system.sh`)

Structural verification for Phase 10 artifacts.

**Reflection tests:**
- `reflection.sh` exists in `lib/`
- `reflection.sh` has valid bash syntax
- Functions exist: `moira_reflection_task_history`, `moira_reflection_observation_count`, `moira_reflection_get_observations`, `moira_reflection_mcp_call_frequency`, `moira_reflection_pending_proposals`, `moira_reflection_record_proposal`, `moira_reflection_resolve_proposal`, `moira_reflection_deep_counter`, `moira_reflection_auto_defer_stale`
- Reflection templates exist: `templates/reflection/lightweight.md`, `standard.md`, `deep.md`, `epic.md`
- Reflection skill exists: `skills/reflection.md`

**Judge tests:**
- `judge.sh` exists in `lib/`
- `judge.sh` has valid bash syntax
- Functions exist: `moira_judge_invoke`, `moira_judge_composite_score`, `moira_judge_normalize_score`, `moira_judge_calibrate`
- Judge prompt template exists: `templates/judge/judge-prompt.md`
- Rubric files exist: `tests/bench/rubrics/feature-implementation.yaml`, `bugfix.yaml`, `refactor.yaml`
- Calibration examples exist: `tests/bench/calibration/good-implementation/`, `mediocre-implementation/`, `poor-implementation/`

**Knowledge integration tests:**
- `knowledge-access-matrix.yaml` has `libraries` dimension for mnemosyne, hephaestus, daedalus
- `knowledge.sh` `_MOIRA_KNOWLEDGE_TYPES` includes `libraries`
- `knowledge.sh` `moira_knowledge_read_for_agent` dimensions list includes `libraries`

**Telemetry tests:**
- `telemetry.schema.yaml` has `mcp_calls` section with server, tool, query_summary, tokens_used, agent fields

**Integration tests:**
- `mnemosyne.yaml` exists and has NEVER constraints (unchanged from Phase 2)
- Pipeline definitions have `post: reflection:` field (unchanged from Phase 3)
- `bench.sh` has judge-related functions and sources `judge.sh`
- `health.md` command exists in `commands/moira/`
- `scaffold.sh` creates `state/reflection/` directory

## Ripple Effect Updates

1. **`install.sh` lib verify list** — Add `reflection.sh` and `judge.sh` to the hardcoded lib file verification loop (12→14 files)
2. **`install.sh` template copy blocks** — Add new `cp` blocks for `templates/reflection/*.md` (4 files), `templates/judge/judge-prompt.md` (1 file). Rubrics and calibration files go to `tests/bench/` (existing copy path).
3. **`install.sh` command verify list** — Add `health` to the command list
4. **`test-file-structure.sh` lib checks** — Add `reflection.sh` and `judge.sh` to lib existence/syntax check list
5. **`test-file-structure.sh` command list** — Add `health` to the hardcoded commands list
6. **`test-file-structure.sh` skill list** — Add `reflection` to the skills file check (currently: orchestrator, gates, dispatch, errors)
7. **`test-file-structure.sh` template checks** — Add directory checks for `templates/reflection/` and `templates/judge/`
8. **`knowledge.sh` libraries type** — Add `libraries` to `_MOIRA_KNOWLEDGE_TYPES` AND the hardcoded `dimensions` list in `moira_knowledge_read_for_agent` (deferred from Phase 9)
9. **`knowledge-access-matrix.yaml`** — Add `libraries` dimension with access levels for all agents
10. **`bench.sh`** — Source `judge.sh` as dependency. Integrate judge invocation into `moira_bench_run` and quality scores into `moira_bench_report`. Update run result YAML template.
11. **`bench.md`** — Update to implement `calibrate` subcommand, remove "Phase 6 Limitations" section ("no LLM-judge" notes)
12. **`orchestrator.md` Section 7** — Add reference to `reflection.md` skill in the Reflection Dispatch section: "Reference: `reflection.md` skill for dispatch instructions." Without this, the orchestrator won't know to consult the new skill.
13. **`dispatch.md`** — Add note that Mnemosyne dispatch uses an alternative assembly path via `reflection.md` skill (not the standard dispatch flow)
14. **`scaffold.sh`** — Add `mkdir -p state/reflection` to `moira_scaffold_project` for the new state subdirectory
15. **`telemetry.schema.yaml`** — Add `mcp_calls` section (D6d)
16. **`design/architecture/overview.md`** — Add `reflection.sh`, `judge.sh` to lib listing; add `templates/reflection/` and `templates/judge/` to template listing; add `state/reflection/` to state directory listing

## Non-Deliverables (explicitly deferred)

- **Full metrics dashboard** (`/moira metrics`): Phase 11 scope. Phase 10 provides quality scores that feed into Phase 11 metrics.
- **5-domain audit system**: Phase 11 scope. Phase 10 reflection detects patterns; Phase 11 audit performs systematic verification.
- **Cross-reference manifest** (`xref-manifest.yaml`): Phase 11 scope (D-077).
- **Checkpoint/resume integration with reflection**: Phase 12 scope. Reflection runs post-completion; checkpoint is mid-pipeline.
- **Automated rule application**: Approved proposals generate tasks for the standard pipeline — the actual rule file modification goes through implementation pipeline. Phase 10 provides the PROPOSAL system, not automated execution.
- **Rubric versioning/evolution**: Rubrics are static files in v1. Future versions may evolve rubrics based on calibration data.
- **Team-shared reflection observations**: Observations are in gitignored state files (per-developer). Team knowledge sharing happens through committed knowledge files that Mnemosyne updates.

## Architectural Decisions

**Note:** All AD entries below must be added to `design/decisions/log.md` before implementation begins (per D-018 / Art 6.2).

### AD-1: Observations in Task State Files (Not Separate Database)

Observations from reflection are stored within each task's `reflection.md` file, tagged with pattern keys. Cross-task counting uses file scanning (grep), not a separate database.

**Rationale:**
1. Leverages existing task state lifecycle — observations live and die with task state
2. No new state file format to maintain
3. Pattern key registry (`pattern-keys.yaml`) provides the index for efficient counting
4. Consistent with file-based communication principle (D-002)
5. Scanning overhead is acceptable — Mnemosyne runs post-completion, not in hot path

### AD-2: Judge as Agent Tool Call (Not Direct API)

The LLM-judge is invoked via Claude Code's Agent tool, not via direct API call. The "separate Claude call" described in testing.md means a separate agent invocation.

**Rationale:**
1. Moira has no direct API access — it runs within Claude Code
2. Agent tool is the only mechanism for spawning separate Claude contexts
3. Judge independence (D-024) is achieved by model tier selection in Agent tool parameters
4. Consistent with Moira's agent-based architecture
5. `judge.sh` prepares the prompt; orchestrator/bench runner dispatches via Agent tool

### AD-3: Three Rubric Variants by Task Category

Instead of a single universal rubric, Phase 10 provides three rubric variants (feature/bugfix/refactor) with adjusted weights.

**Rationale:**
1. A bugfix that restructures architecture is over-engineering, not quality
2. A refactor that adds features is scope creep, not quality
3. Weight adjustment captures these distinctions without changing criteria
4. Test case `meta.category` determines which rubric to use — deterministic selection
5. Additional rubric variants can be added later without schema changes

### AD-4: Pattern Key Registry for Efficient Cross-Task Counting

Instead of scanning all task reflection files on every reflection, maintain a lightweight `pattern-keys.yaml` registry that tracks observation counts.

**Rationale:**
1. O(1) lookup for "is this pattern at threshold?" vs O(n) scanning all tasks
2. Registry updated incrementally by Mnemosyne after each reflection
3. Full scan (`moira_reflection_observation_count`) available for verification but not needed on every run
4. Registry is gitignored (in state/) — per-developer, rebuilt from task files if lost

### AD-5: `/moira health` as Separate Command (Not Bench Subcommand)

`/moira health` is a standalone command, not a `bench` subcommand, per testing.md command reference.

**Rationale:**
1. Health check uses live telemetry data, not bench fixture results
2. Different audience: `bench` is for Moira developers, `health` is for project developers
3. `health` runs Tier 1 structural checks + aggregates live metrics — different flow from bench
4. Consistent with testing.md design which lists them as separate commands

### AD-6: Libraries Knowledge Access Matrix

The `libraries` knowledge type has specific access levels: Mnemosyne=L2 (read+write — manages cache), Hephaestus=L1 (reads API summaries during implementation), Daedalus=L0 (knows what's cached for budget estimation), all others=null.

**Rationale:**
1. Mnemosyne needs full access to create and update cached library docs
2. Hephaestus (implementer) benefits from cached API reference — reduces MCP calls during implementation
3. Daedalus (planner) needs to know what's cached to decide whether to authorize MCP calls (if library is cached, no MCP call needed)
4. Other agents don't interact with external library documentation
5. Hermes (explorer) gets null because library docs are external references, not project code — Explorer's role is to read project code

### AD-7: Periodic Deep Reflection Every 5 Tasks

The roadmap specifies "Pattern analysis (per 5 tasks)" as a separate deliverable. The reflection dispatch skill implements this as a counter-based escalation: every 5th standard-pipeline task auto-escalates from `background` to `deep` template, enabling systematic cross-task pattern analysis.

**Rationale:**
1. Matches roadmap requirement for periodic pattern analysis at a fixed cadence
2. Counter stored in `state/reflection/deep-reflection-counter.yaml` — simple, stateless between sessions
3. Only escalates `background` → `deep` (lightweight tasks stay lightweight, epic stays epic)
4. Deep template includes cross-task pattern analysis, quality trend analysis, and evolution readiness assessment — exactly the "pattern analysis" the roadmap describes
5. User sees deep reflection as foreground (blocking) every 5th task — acceptable cadence for the richer analysis

## Success Criteria

1. **Reflection dispatches at correct level:** Quick pipeline writes lightweight note. Standard dispatches Mnemosyne background. Full dispatches Mnemosyne deep (foreground). Decomposition dispatches with epic scope. Every 5th standard-pipeline task auto-escalates to deep.
2. **Mnemosyne produces structured output:** All 5 exit criteria items present in reflection output.
3. **Knowledge updates from reflection:** Observations written to knowledge files with freshness markers and consistency validation.
4. **Evidence tracking works:** Observations tagged with pattern keys. Counts accumulate across tasks. 3-confirmation threshold triggers proposal.
5. **Rule change proposals surface:** Proposals stored in structured format. Presented to user non-blockingly. User can approve/defer/reject.
6. **MCP caching detects repeated calls:** 3+ identical MCP call patterns detected. User prompted to cache or ignore. Cache written to `knowledge/libraries/`.
7. **LLM-judge produces valid evaluations:** Judge invoked on task artifacts. Returns structured YAML with scores 1-5 per criterion.
8. **Calibration passes:** All 3 calibration examples score within ±1 of expected.
9. **Bench runner includes quality scores:** `quality_scores` populated in run results. Reports show quality metrics.
10. **`/moira health` shows composite score:** Health Score computed from structural + quality + efficiency. Sub-metrics with zone indicators displayed.
11. **Statistical bands function:** Baselines computed after 3+ runs. Zone classification (NORMAL/WARN/ALERT) applied. Cold start protocol respected.
12. **Tier 1 tests pass:** All existing + new Phase 10 structural tests pass.
13. **Constitutional compliance:** All 19 invariants satisfied.

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Orchestrator does not run reflection analysis. Mnemosyne (agent)
         does all analysis. Orchestrator only dispatches and processes summaries.
         Judge is a separate agent call, not orchestrator logic.
[✓] 1.2 — Agent roles maintained: Mnemosyne analyzes (NEVER changes rules directly).
         Judge evaluates (NOT part of pipeline). No agent crosses boundaries.
[✓] 1.3 — Reflection library is a focused utility (cross-task scanning).
         Judge library is a focused utility (judge invocation).
         No god components.

ARTICLE 2: Determinism
[✓] 2.1 — Reflection level is deterministic per pipeline type.
         Judge rubric selection is deterministic per task category.
[✓] 2.2 — No gate changes. Reflection is post-completion, not a gate.
         Rule proposals presented but don't affect current pipeline.
[✓] 2.3 — No implicit decisions. Rule proposals require 3+ evidence.
         MCP caching requires user confirmation.

ARTICLE 3: Transparency
[✓] 3.1 — Reflection output written to state/tasks/{id}/reflection.md.
         Judge evaluation written to judge-evaluation.yaml. All traceable.
[✓] 3.2 — Judge token costs included in bench budget tracking.
         Reflection dispatched within existing pipeline budget framework.
[✓] 3.3 — Judge failures reported (moira_judge_invoke returns 1).
         Reflection failures logged. No silent failures.

ARTICLE 4: Safety
[✓] 4.1 — Judge rubrics are evidence-based with anchored examples.
         Mnemosyne observations reference specific artifacts (Art 5.1).
[✓] 4.2 — Rule proposals require user approval. MCP caching requires
         user confirmation. No automated changes.
[✓] 4.3 — Rule proposals generate tasks through standard pipeline.
         Changes are git-backed and reversible.
[✓] 4.4 — N/A (reflection doesn't interact with escape hatch)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — Knowledge updates from reflection reference evidence (task IDs,
         artifact paths, specific observations).
[✓] 5.2 — Rule change proposals require 3+ confirming observations.
         Pattern key registry tracks counts.
[✓] 5.3 — Knowledge writes go through moira_knowledge_validate_consistency
         before committing.

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation (D-018)
[✓] 6.3 — Tier 1 tests validate Phase 10 artifacts
```
