# Testing Subsystem

## Purpose

Automated testing system for Moira that provides objective metrics on both orchestration health (pipelines, gates, constitutional invariants) and result quality (code produced by agents). Enables data-driven development decisions instead of intuition-based ones.

## Design Decisions

- **Two aspects tested:** orchestration correctness (deterministic) + agent output quality (stochastic)
- **Test data:** synthetic tasks (Bench mode) + real task telemetry (Live mode)
- **Evaluation:** automated checks (compile/lint/test) + LLM-judge with anchored rubrics
- **Reproducibility:** deterministic tests run once (must be 100% stable), stochastic metrics accumulate over time
- **Budget-conscious:** tiered testing, statistical accumulation instead of expensive multiple runs
- **Privacy-first:** metrics without content, local-only by default, opt-in anonymized export
- **No external dependencies:** YAML storage, bash scripts, file-based, consistent with Moira philosophy

---

## Architecture

### Three Layers

```
Layer 1: Structural Verifier
  Purpose: deterministic checks on Moira integrity
  Tools: bash + grep + yaml-parse
  Cost: 0 Claude tokens
  Speed: seconds
  Checks:
    - Constitutional invariants (19 checks)
    - Pipeline definition integrity
    - Agent contract compliance
    - Rules consistency
    - File structure validation

Layer 2: Behavioral Bench
  Purpose: end-to-end testing of Moira on controlled tasks
  Tools: Moira pipelines + Claude (LLM-judge)
  Cost: high (agents + judge per test)
  Speed: minutes per test
  Process:
    - Load fixture project
    - Submit task with predefined gate responses
    - Collect artifacts from state files
    - Run automated checks (compile, lint, tests)
    - Run LLM-judge with rubrics
    - Compare with baseline

Layer 3: Live Telemetry
  Purpose: passive metric collection during real usage
  Tools: built-in pipeline logging
  Cost: ~0 (write-only during pipeline, judge only on demand)
  Speed: transparent to user
  Process:
    - Structured logging to state files on task completion
    - Monthly aggregation into existing metrics
    - On-demand evaluation via /moira health
```

### File Structure

```
.claude/moira/testing/
├── bench/
│   ├── results/              # per-run results (max 5 retained)
│   │   ├── run-{NNN}/
│   │   │   ├── summary.yaml  # per-run report
│   │   │   └── tests/        # per-test results
│   │   └── aggregate.yaml    # rolling statistics
│   ├── fixtures/             # test projects
│   │   ├── greenfield-webapp/
│   │   ├── mature-webapp/
│   │   └── legacy-webapp/
│   ├── cases/                # test case definitions
│   ├── rubrics/              # LLM-judge rubrics with anchors
│   └── calibration/          # judge calibration examples
├── live/
│   ├── telemetry/            # per-task telemetry (gitignored)
│   └── index.yaml            # L0 summary (~200 tokens)
└── reports/                  # generated reports
```

---

## Composite Score

```
Moira Health Score (0-100)
├── Structural Conformance (0-100), weight 30%
│   ├── Constitutional invariants pass rate
│   ├── Pipeline definition integrity
│   ├── Agent contract compliance
│   └── Rules consistency
├── Result Quality (0-100), weight 50%
│   ├── First-pass acceptance rate
│   ├── Code correctness (LLM-judge)
│   ├── Architecture quality (LLM-judge)
│   └── Requirements coverage (LLM-judge)
└── Efficiency (0-100), weight 20%
    ├── Orchestrator context usage vs budget
    ├── Agent context usage vs budget
    └── Retry/escalation rate
```

Weights are preliminary and can be recalibrated as data accumulates.

### Score Normalization

LLM-judge returns scores on a 1-5 scale. Conversion to 0-100 for Health Score:

```yaml
quality_score_formula:
  # Step 1: Weighted average of judge criteria (1-5 scale)
  judge_composite: weighted_avg(requirements_coverage, code_correctness,
                                architecture_quality, conventions_adherence)

  # Step 2: Linear mapping 1-5 → 0-100
  #   1 → 0,  2 → 25,  3 → 50,  4 → 75,  5 → 100
  judge_normalized: (judge_composite - 1) * 25

  # Step 3: Automated checks as binary gate
  automated_pass: compile_ok AND lint_ok AND tests_pass  # true/false

  # Step 4: Final quality score
  #   If automated_pass = false → quality capped at 20 (regardless of judge)
  #   If automated_pass = true  → quality = judge_normalized
  result_quality:
    if automated_pass: judge_normalized
    if not automated_pass: min(judge_normalized, 20)
```

---

## Data Management and Rotation

### Three-Level Model (consistent with Knowledge System)

```
L0 — Index (~100-200 tokens)
  "Last bench: 2026-03-10, score 78/100, 3 regressions"

L1 — Summary (~500-2k tokens)
  Aggregated metrics per period, trends, top issues

L2 — Full (unlimited, never loaded into context)
  Full logs per run, artifacts, raw judge output
```

### Lifecycle

```
Raw Output → Per-run Report → Aggregate Summary → Archive
(L2, transient) (L2, 5 runs)   (L1, 30 runs)    (one-line records)
```

### Rotation Rules

**Bench mode:**
- Raw artifacts: deleted after per-run report generated
- Per-run reports: 5 most recent retained. Older archived to one-line: `{date, composite_score, regressions_count}`
- Aggregate summary: recalculated each run. Rolling averages, trends, top-5 issues. Only thing loaded into context for `/moira bench report`

**Live mode:**
- Per-task telemetry: written to existing `state/tasks/{id}/telemetry.yaml` (~200 bytes). Lives as long as task state
- Monthly aggregate: merged into `metrics/monthly-{YYYY-MM}.yaml` (already defined in metrics.md design). Testing metrics added there, not duplicated
- Live index: `testing/live/index.yaml` — L0, updated per task

### Context Budget for Testing Subsystem

```yaml
structural_verifier:
  context_cost: 0  # bash scripts, not Claude

bench_runner:
  loads: test_case.yaml (~500 tokens per test)
  never_loads: previous results, raw artifacts

bench_report:
  loads: aggregate_summary.yaml (L1, ~1-2k tokens)
  never_loads: per-run reports (L2)
  drill_down: agent reads specific L2 file on demand

llm_judge:
  loads: rubric (~1k) + task artifacts (~varies)
  never_loads: other test results, historical data

live_telemetry:
  pipeline_overhead: ~200 tokens per task (telemetry.yaml write)
  context_overhead: 0 (write-only during pipeline)

moira_test_command:
  loads: live/index.yaml (L0, ~200 tokens)
  drill_down: agent reads specific period on demand
```

### Protection Against Growth

1. **Hard cap on files:** `bench/results/` — maximum 5 directories. On 6th run, oldest is archived automatically
2. **Size cap on aggregate:** if `aggregate_summary.yaml` exceeds 10KB — rotation: old data compressed to one-line records
3. **Never load L2 into orchestrator.** Drill-down only through agent reading specific file
4. **Live telemetry** tied to existing metrics rotation (monthly aggregation already in design)

---

## Statistical Model and Decision Thresholds

### Baseline + Confidence Band

For each test and each metric, we store a statistical profile:

```yaml
baseline:
  score: 78          # mean over last N runs
  variance: ±4       # observed spread
  n_observations: 8  # runs counted
  confidence_band:
    low: 74
    high: 82
```

### Three Evaluation Zones

```
  ┌─────────┬──────┬─────────────────────┬──────┬─────────┐
  │  ALERT  │ WARN │      NORMAL         │ WARN │  ALERT  │
  │  <-2σ   │-1-2σ │    baseline ±σ      │+1-2σ │  >+2σ   │
  └─────────┴──────┴─────────────────────┴──────┴─────────┘
  regression         statistical noise         improvement
```

- **NORMAL (within confidence band):** Statistical noise. Log, don't react.
- **WARN (1-2 variance outside band):** Possible change. Single WARN — observe. Two consecutive WARNs on same metric — signal requiring attention.
- **ALERT (>2 variance outside band):** Significant change. Single ALERT — investigate.

### Decision Rules

```yaml
regression_confirmed:
  - single_alert: score dropped into ALERT zone (>2σ below baseline)
  - sustained_warn: 2+ consecutive runs in WARN zone
  - multi_metric_warn: 3+ metrics simultaneously in WARN zone

improvement_confirmed:
  - single_alert: score rose into ALERT zone (>2σ above baseline)
  - sustained_warn: 3+ consecutive runs in WARN+ zone
    # higher threshold than regression — conservatism

noise:
  - score within confidence band
  - single WARN without repetition

baseline_update:
  trigger: improvement_confirmed OR regression_confirmed
  method: recalculate mean with new data
  requires: minimum 5 observations for new baseline
```

### Cold Start

```yaml
cold_start:
  phase_1_calibration:
    runs: 3-5
    purpose: establish initial baseline and variance
    decisions: none — only collecting data

  phase_2_provisional:
    runs: 5-10
    band_width: wide (±2σ instead of ±1σ)
    decisions: only ALERT triggers reaction

  phase_3_stable:
    runs: 10+
    band_width: normal
    decisions: full model
```

### Safeguards Against False Conclusions

1. **Deterministic tests — separate.** Structural Verifier gives binary results. No variance — if constitutional check fails, it's 100% regression. Statistical model applies ONLY to stochastic metrics (LLM-judge, quality scores).

2. **Paired comparison, not absolute.** When evaluating a Moira change — run same test set before and after. Compare pairwise, not against historical baseline. Removes drift influence.

3. **Variable isolation.** One Moira change → one bench run. Multiple changes → warning in report:
```yaml
moira_changes_since_last_run:
  - file: src/agents/explorer.md
    type: prompt_change
  - file: src/agents/reviewer.md
    type: prompt_change
warning: "Multiple changes detected. Attribution may be unreliable."
```

4. **Minimum effect size.** Even if statistically significant, ignore if absolute difference below threshold:
```yaml
minimum_effect_size:
  composite_score: 3 points
  sub_metric: 5 points
  conformance: 0  # binary — any change is significant
```

---

## Tiered Testing

### Three Tiers

```
Tier 1: Structural Smoke       Cost: 0 tokens    Time: ~5 sec
  Bash scripts. Always runs on any change.

Tier 2: Targeted Bench          Cost: low         Time: ~5-15 min
  3-5 tests targeting changed component.
  LLM-judge only on affected metrics.

Tier 3: Full Bench              Cost: high        Time: ~30-60 min
  Full test suite across entire matrix.
  All rubrics, all fixtures, all pipeline types.
```

### Trigger Matrix

```yaml
tier_1:  # structural smoke only
  - documentation_changes
  - knowledge_entries
  - config_defaults
  - new_test_cases
  - rubric_updates

tier_2:  # structural + targeted bench
  - agent_prompt_change:
      run_tests_tagged: [changed_agent_role]
  - quality_checklist_change:
      run_tests_tagged: [quality_gate]
  - rule_wording_change:
      run_tests_tagged: [affected_rule_layer]
  - threshold_adjustment:
      run_tests_tagged: [affected_metric]
  - single_bug_fix:
      run_tests_tagged: [related_component]

tier_3:  # structural + full bench
  - pipeline_flow_change
  - gate_logic_change
  - agent_role_boundary
  - orchestrator_skill
  - rules_assembly_logic
  - new_agent_type
  - constitution_amendment
  - major_version_release
```

### Tier Auto-Detection

On `/moira bench`:
1. Scan git diff since last bench run
2. Classify changed files by trigger matrix
3. Select maximum tier across all changes
4. Present to user with option to override (up or down)

### Budget Guards

```yaml
bench_budget:
  tier_2:
    max_tokens: 50k
    max_tests: 5
    warn_at: 35k

  tier_3:
    max_tokens: 300k
    max_tests: 30
    warn_at: 200k

  abort_behavior:
    on_budget_exceeded: pause_and_ask
```

---

## Test Cases

### Format

```yaml
meta:
  id: "std-feature-mature-001"
  name: "Add paginated API endpoint to mature project"
  category: feature          # feature | bugfix | refactor
  size: medium               # small | medium | large | epic
  project_state: mature      # greenfield | mature | legacy
  tags: [standard, explorer, analyst, architect, planner,
         implementer, reviewer, quality_gates, batching]
  estimated_tokens: 40000

fixture:
  project: "fixtures/mature-webapp"
  branch: "clean"

task:
  description: |
    Add GET /api/products endpoint with pagination,
    sorting by name/price, and filtering by category.

gate_responses:
  classification: proceed
  architecture: proceed
  plan: proceed
  final: done

expected_structural:
  pipeline_type: standard
  agents_called: [apollo, hermes, athena, metis, daedalus,
                  hephaestus, themis, aletheia]
  gates_triggered: [classification, architecture, plan, final]
  constitution_pass: true

expected_quality:
  rubric: "rubrics/feature-implementation.yaml"
  minimum_scores:
    requirements_coverage: 3
    code_correctness: 3
    architecture_quality: 3
    conventions_adherence: 3
```

### Failure Path Testing

Test cases with non-happy-path gate responses:

```yaml
gate_responses:
  classification: proceed
  architecture:
    action: modify
    feedback: "Don't use a new ORM model, extend the existing Product model"
    then: proceed
  plan: proceed
  final: done

expected_structural:
  architect_calls: 2
  retry_reason: "gate_rejection"

expected_quality:
  additional_check:
    feedback_incorporated: true
```

### Agent Blocked Simulation

When testing `agent_blocked` failure paths, test cases use `blocked_responses` to simulate missing information scenarios and provide synthetic answers:

```yaml
# Test case for agent_blocked scenario
blocked_responses:
  explorer:
    trigger: "missing_dependency_info"
    synthetic_answer: "Project uses PostgreSQL 15 with Prisma ORM"
  analyst:
    trigger: "ambiguous_requirement"
    synthetic_answer: "Pagination should use cursor-based approach"

expected_structural:
  agent_blocks: 1
  block_recovery: "synthetic_answer_provided"
  pipeline_resumed: true
```

The bench runner intercepts `STATUS: blocked` from agents and injects the corresponding `synthetic_answer` as if the user provided it. If no `blocked_responses` entry matches — the test is marked as `unexpected_block` and fails.

### Test Matrix

```
                    │ greenfield │ mature │ legacy │
────────────────────┼────────────┼────────┼────────┤
Small  │ bugfix     │            │   ●    │   ●    │
       │ refactor   │            │   ●    │   ●    │
────────────────────┼────────────┼────────┼────────┤
Medium │ feature    │     ●      │   ●    │   ●    │
       │ bugfix     │            │   ●    │        │
       │ refactor   │            │   ●    │   ●    │
────────────────────┼────────────┼────────┼────────┤
Large  │ feature    │     ●      │   ●    │        │
       │ refactor   │            │   ●    │   ●    │
────────────────────┼────────────┼────────┼────────┤
Epic   │ feature    │     ●      │   ●    │        │

Failure path overlays per test:
  × gate_rejection
  × agent_blocked
  × reviewer_critical → retry
  × budget_exceeded
```

### Fixture Projects

```
bench/fixtures/
├── greenfield-webapp/      # minimal project, basic structure
├── mature-webapp/          # 20-30 files, consistent patterns
└── legacy-webapp/          # 40-60 files, inconsistent, tech debt
```

Each fixture has `.moira-fixture.yaml`:

```yaml
name: "mature-webapp"
description: "Express + TypeScript + Prisma, ~25 files, consistent patterns"
stack: [typescript, express, prisma, jest]
state: mature
characteristics:
  - consistent naming conventions
  - clear project structure
  - existing test patterns
  - documented API contracts
reset_command: "git checkout clean && git clean -fd"
```

### Fixture Lifecycle

```yaml
fixture_lifecycle:
  # Reset runs BEFORE each test (not after), guaranteeing clean state
  before_each_test:
    1: run reset_command
    2: verify clean state (git status --porcelain == empty)
    3: if verification fails → skip test, report error

  # Tests against same fixture run SEQUENTIALLY within a bench run
  # No parallel execution against same fixture — prevents contamination
  concurrency: sequential_per_fixture

  # On bench interruption (pause_and_ask, abort, crash):
  on_interruption:
    - fixture state is UNDEFINED (may be dirty)
    - next test run will reset before starting (handled by before_each_test)
    - partial test results marked as "interrupted", excluded from scoring

  # On budget exceeded mid-test:
  on_budget_exceeded:
    - current test marked as "budget_exceeded"
    - fixture NOT reset immediately (user may want to inspect)
    - next test will reset before starting
```

Stack-agnostic expansion: start with one stack, add more to verify Moira works across stacks.

---

## LLM-Judge

### Architecture

Judge is a separate Claude call that:
1. Does NOT participate in the Moira pipeline
2. Receives artifacts from state files AFTER task completion
3. Evaluates against strict rubric with anchored examples
4. Returns structured YAML, not free-form text

### Judge Model

```yaml
judge_model:
  # Model tiers, not pinned versions. Actual model IDs resolved at runtime.
  default: sonnet-tier       # cheaper, sufficient for evaluation
  calibration: opus-tier     # calibration on best available model

  # Independence requirement: judge SHOULD use a different model tier
  # than the agents being evaluated, to avoid self-evaluation bias.
  # If agents run on sonnet-tier, judge should use a different tier
  # or the same tier is acceptable when budget constraints require it
  # (results marked as "same-tier evaluation" in reports).
```

### Rubric Structure

Each criterion has:
- `id`, `name`, `weight`
- `scale`: [1, 2, 3, 4, 5]
- `anchors`: per-score label + description + concrete example

### Standard Rubric Criteria

```yaml
criteria:
  - id: requirements_coverage
    weight: 25
    anchors:
      1: "Critical gaps — happy path not implemented"
      2: "Partial — happy path works, edge cases missing"
      3: "Adequate — main cases covered, minor gaps"
      4: "Strong — all stated requirements covered"
      5: "Comprehensive — requirements + reasonable extras"

  - id: code_correctness
    weight: 30
    anchors:
      1: "Broken — doesn't compile or runtime errors"
      2: "Fragile — happy path works, bugs in edge paths"
      3: "Functional — works correctly for documented cases"
      4: "Solid — correct + defensive, handles unexpected input"
      5: "Robust — correct + defensive + resilient"

  - id: architecture_quality
    weight: 25
    anchors:
      1: "Chaotic — no structure, god functions"
      2: "Disorganized — some structure, doesn't follow project"
      3: "Adequate — follows project structure, minor issues"
      4: "Clean — consistent, SOLID, clear boundaries"
      5: "Exemplary — reference implementation quality"

  - id: conventions_adherence
    weight: 20
    anchors:
      1: "Ignored — completely different style"
      2: "Inconsistent — some followed, others ignored"
      3: "Mostly consistent — minor deviations"
      4: "Consistent — indistinguishable from existing code"
      5: "Exemplary — follows + improves where weak"
```

### Judge Output Format

```yaml
evaluation:
  task_id: "std-feature-mature-001"
  judge_model: "<resolved-at-runtime>"  # actual model ID from judge_model config
  timestamp: "2026-03-11T15:00:00Z"

  scores:
    requirements_coverage:
      score: 4
      justification: "..."
      evidence: [...]
    code_correctness:
      score: 4
      justification: "..."
      evidence: [...]
    architecture_quality:
      score: 3
      justification: "..."
      evidence: [...]
    conventions_adherence:
      score: 4
      justification: "..."
      evidence: [...]

  composite_quality_score: 3.75  # weighted average
  summary: "..."
```

### Judge Calibration

```yaml
calibration:
  calibration_set:
    - example_id: "cal-001"
      artifacts: "bench/calibration/good-implementation/"
      expected_scores: {req: 4, code: 4, arch: 4, conv: 4}
      tolerance: ±1

    - example_id: "cal-002"
      artifacts: "bench/calibration/mediocre-implementation/"
      expected_scores: {req: 3, code: 2, arch: 3, conv: 3}
      tolerance: ±1

    - example_id: "cal-003"
      artifacts: "bench/calibration/poor-implementation/"
      expected_scores: {req: 2, code: 1, arch: 2, conv: 2}
      tolerance: ±1

  recalibration_trigger:
    - rubric_version_change
    - judge_model_change
    - every_20_bench_runs
```

---

## Live Telemetry — Privacy

### Principle: Metrics Without Content

```
RECORDED:                           NOT RECORDED:
  pipeline_type                       task description
  agents_called                       file contents
  gate_results                        project file names
  retry_count                         code (written or read)
  constitutional_pass                 architecture decisions
  first_pass_accepted                 requirements
  orchestrator_context_pct            endpoint/entity names
  judge_scores                        gate feedback text
  duration_sec                        agent prompt contents
                                      variable/function names
```

### Per-Task Telemetry Format

```yaml
# .claude/moira/state/tasks/{id}/telemetry.yaml (gitignored)

task_id: "t-2026-03-11-004"
timestamp: "2026-03-11T14:32:00Z"
moira_version: "0.3.1"

pipeline:
  type: standard
  classification_confidence: high
  classification_correct: true

execution:
  agents_called:
    - role: explorer
      status: success
      context_pct: 42
      duration_sec: 35
    # ...
  gates:
    - name: classification
      result: proceed
    - name: architecture
      result: modify
      retry_count: 1
    - name: final
      result: done
  retries_total: 1
  budget_total_tokens: 45000

quality:
  reviewer_findings: {critical: 0, warning: 2, suggestion: 3}
  first_pass_accepted: false
  final_result: done

structural:
  constitutional_pass: true
  violations: []
```

### Three Privacy Levels

```yaml
local_only:            # default
  telemetry: state/ (gitignored)
  sharing: nothing leaves the machine

anonymized_export:     # opt-in via /moira test export
  export: aggregated numbers without identifiers
  review_before_send: true

team_sharing:          # for team metrics
  aggregate: monthly yaml (committed)
  content: numerical aggregates only
```

### Sanitization

```yaml
allowed_types: [number, boolean, enum, timestamp, uuid]
string_fields: whitelist only
  [pipeline_type, agent_role, gate_name, status, trend_direction]
unexpected_string: replace with "[REDACTED]" + log warning
```

---

## Commands and UX

### Command Reference

```
/moira bench              — run bench testing
/moira bench report       — report on recent runs
/moira bench compare      — compare two runs
/moira bench calibrate    — calibrate LLM-judge

/moira health              — health check on current project
/moira health report       — live metrics report
/moira health export       — anonymized export
```

### /moira bench Flow

1. Scan git diff since last bench run
2. Classify changes → recommend tier
3. Show user: recommended tier, selected tests, estimated cost
4. User chooses: run / full / smoke / pick / details / abort
5. Execute tests with progress display
6. Show results with zone indicators (NORMAL / WARN / ALERT)
7. On regression: show probable cause, recommend action

### /moira health Flow

1. Run Structural Verifier (Tier 1) — instant
2. Load live telemetry aggregate
3. Show composite score + sub-metrics + trends
4. Show top issues
5. Offer drill-down

---

## Integration with Existing Architecture

### Relationships

```
Testing Subsystem:
  reads from:    Constitution, Pipeline definitions, Agent definitions,
                 Rules, State files
  writes to:     testing/ directory, metrics/ (extends monthly aggregates)
  invokes:       Moira pipelines (bench), Claude (LLM-judge)
  invoked by:    /moira bench, /moira health, pipeline completion (passive)
  never touches: Project source code, Agent prompts, Pipeline engine,
                 Orchestrator skill
```

### Pipeline Integration Point

Single integration: after task completion, pipeline engine writes `telemetry.yaml` from pipeline state. ~10 lines of logic, 0 context cost, <100ms latency.

**Telemetry write failure behavior (Art 3.3 compliance):** If telemetry write fails, a non-blocking warning is appended to the budget report (which is always displayed at pipeline completion). The warning states: "Telemetry write failed: {reason}. Live metrics may be incomplete." Pipeline execution is NOT blocked — telemetry is observational, not functional. This satisfies Art 3.3 (user is notified) without degrading pipeline performance.

### Metrics Integration

Testing data extends existing `monthly-{YYYY-MM}.yaml` with a `testing:` section. No duplication.

### Audit Integration

Auditor can read `testing/` directory for:
- Bench score stability checks
- Live telemetry vs metrics consistency
- Auditor does NOT run bench — read-only

### Roadmap Integration

```
Tier 1 (Structural Verifier): implement WITH Phase 2-3
Live Telemetry:                implement WITH Phase 3
Tier 2-3 (Bench):             implement AFTER Phase 6
LLM-Judge:                    implement AFTER Phase 10
```

### Roadmap Integration Details

Testing is woven across existing phases, not a separate phase:

```yaml
phase_2:  # Core Agent Definitions
  deliverables:
    - Constitution check automation (bash scripts)
    - Agent contract validation (NEVER constraints, response format)
  rationale: "Constitution and agent definitions exist — can validate immediately"

phase_3:  # Pipeline Engine
  deliverables:
    - Full Structural Verifier (Tier 1) — adds pipeline integrity checks
    - Live telemetry writer (integrated into pipeline completion)
    - telemetry.yaml schema
    - Monthly aggregation extension
  rationale: "Pipeline engine exists — can validate pipeline definitions and write telemetry"

phase_6:  # Quality Gates
  deliverables:
    - Bench runner (Tier 2 + Tier 3)
    - Test case format and first test cases
    - Fixture projects (initial set)
    - /moira bench command
    - Budget guards
  rationale: "Full bench needs quality gates to test meaningful pipeline behavior"

phase_10:  # Reflection Engine
  deliverables:
    - LLM-Judge implementation
    - Rubrics with anchored examples
    - Calibration set
    - Judge calibration command
    - /moira health command (full version with judge-based quality scores)
  rationale: "Judge evaluates the same dimensions as Reflector, benefits from its patterns"
```

### Constitutional Compliance

```
ARTICLE 1: Separation of Concerns
Art 1.1 ✓  Testing does not read/write project source (bench uses fixtures)
Art 1.2 ✓  Existing agent NEVER constraints not weakened by testing
Art 1.3 ✓  Testing is separate component; judge is external call,
           not a pipeline participant or new agent type

ARTICLE 2: Determinism
Art 2.1 ✓  Does not affect pipeline selection
Art 2.2 ✓  Does not modify gate definitions or skip logic
Art 2.3 ✓  Bench uses predefined gate_responses — no implicit decisions

ARTICLE 3: Transparency
Art 3.1 ✓  All results written to testing/ state files
Art 3.2 ✓  Bench budget tracked and displayed to user
Art 3.3 ✓  Telemetry write failure → non-blocking warning in budget report
           (not silent — user is notified)

ARTICLE 4: Safety
Art 4.1 ✓  Judge rubrics are evidence-based, not fabricated
Art 4.2 ✓  Bench runs only on explicit user command
Art 4.3 ✓  Fixtures restored via git reset; bench results reversible
Art 4.4 ✓  Testing does not interact with escape hatch

ARTICLE 5: Knowledge Integrity
Art 5.1 ✓  Testing does not write to knowledge base
Art 5.2 ✓  Testing does not propose rule changes
Art 5.3 ✓  N/A — testing is read-only for knowledge

ARTICLE 6: Self-Protection
Art 6.1 ✓  Testing does not modify CONSTITUTION.md
Art 6.2 ✓  Design document created BEFORE implementation
Art 6.3 ✓  Structural Verifier runs constitutional invariant checks
```
