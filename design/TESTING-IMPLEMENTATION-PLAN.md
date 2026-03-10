# Testing Subsystem — Implementation Plan

> **Spec:** `design/subsystems/testing.md`
> **Approach:** Testing is woven into existing roadmap phases, not a standalone phase.
> Each section below maps to a Forge roadmap phase and lists concrete deliverables.

---

## Phase 2 Deliverables (with Core Agent Definitions)

**Goal:** Constitutional checks and agent contract validation — automated, 0 tokens.

### Files to Create

```
src/testing/
├── structural/
│   ├── verify.sh                  # Entry point: runs all checks, outputs report
│   ├── checks/
│   │   ├── constitution.sh        # 23 invariant checks from CONSTITUTION.md
│   │   └── agents.sh              # Agent contract validation
│   └── lib/
│       └── utils.sh               # Shared helpers (yaml parsing, reporting)
```

### constitution.sh — What It Checks

Each check maps to a constitutional article. Binary pass/fail.

| Check | Article | How |
|-------|---------|-----|
| Orchestrator has no Read/Write/Edit of project files | 1.1 | grep orchestrator skill for tool calls |
| Each agent has NEVER constraints | 1.2 | grep agent definitions for "NEVER" |
| No agent file exceeds role boundaries | 1.3 | check agent file count and scope |
| Pipeline selection is pure function of classification | 2.1 | grep pipeline selection for conditional logic |
| All required gates present per pipeline type | 2.2 | parse pipeline definitions, match gate lists |
| Anti-assumption directives in agent rules | 2.3 | grep for "Never assume" / "Never guess" |
| Every pipeline step writes to state files | 3.1 | verify output paths in pipeline definition |
| Budget report in pipeline completion | 3.2 | check pipeline completion handler |
| No catch-and-ignore error patterns | 3.3 | grep for silent error handling |
| Fabrication prohibition in all agents | 4.1 | grep agent base rules |
| All gates require user action | 4.2 | grep for auto-proceed patterns |
| Git-backed reversibility | 4.3 | verify git integration in implementation steps |
| Bypass requires exact command + confirmation | 4.4 | check bypass activation logic |
| Knowledge entries have evidence references | 5.1 | validate knowledge entry format |
| Rule change threshold = 3+ observations | 5.2 | check reflector logic |
| Knowledge writes include consistency check | 5.3 | check knowledge write path |
| No code path modifies CONSTITUTION.md | 6.1 | grep all code for constitution file writes |
| Design docs are authoritative | 6.2 | verify pre-implementation check exists |
| Invariant verification runs before changes | 6.3 | verify pre-commit hook exists |

### agents.sh — What It Checks

For each agent definition file in `src/agents/`:

- Has `# Identity` section with single-sentence purpose
- Has `# Rules` section with at least one `NEVER` constraint
- Has `# Output` section specifying file path and STATUS format
- STATUS format matches contract: `STATUS: success|failure|blocked|budget_exceeded`
- Has `# Quality Checklist` section (where applicable)
- Anti-fabrication rule present

### verify.sh — Output Format

```
STRUCTURAL VERIFICATION
═══════════════════════
Constitution:  22/23 PASS  (1 FAIL)
  FAIL: Art 3.3 — silent error handling found in src/agents/explorer.md:45
Agents:        8/8 PASS
───────────────
Overall: FAIL
```

### Done Criteria

- `verify.sh` runs in <5 seconds
- All checks are deterministic (same input = same output)
- Exit code 0 on all pass, 1 on any fail
- Can be called from pre-commit hook

---

## Phase 3 Deliverables (with Pipeline Engine)

**Goal:** Complete Structural Verifier + live telemetry writer.

### Files to Create

```
src/testing/
├── structural/
│   ├── checks/
│   │   ├── pipelines.sh           # Pipeline definition integrity
│   │   └── rules.sh               # Rules consistency
│   └── verify.sh                  # Updated: includes new checks
├── live/
│   ├── telemetry-writer.sh        # Writes telemetry.yaml after task completion
│   └── aggregator.sh              # Merges into monthly metrics
```

### pipelines.sh — What It Checks

- Quick pipeline has exactly 2 gates: classification + final
- Standard pipeline has exactly 4 gates: classification + architecture + plan + final
- Full pipeline has 5+ gates: classification + architecture + plan + per-phase + final
- Decomposition pipeline has: classification + decomposition + per-task gates
- No conditional skip logic for gates
- Pipeline selection logic maps classification → pipeline type without branching

### rules.sh — What It Checks

- `base.yaml` exists and contains inviolable rules
- Each role file in `core/rules/roles/` corresponds to a defined agent
- No conflict between layers (higher layer can override, except inviolable)
- Quality checklist files exist for Q1-Q5

### telemetry-writer.sh

Called by pipeline completion handler. Receives pipeline state as arguments or reads from state files.

**Input:** task state directory (`state/tasks/{id}/`)
**Output:** `state/tasks/{id}/telemetry.yaml`

Extracts from pipeline state:
- pipeline type, classification confidence
- agents called (role, status, context_pct, duration)
- gates triggered (name, result, retry_count)
- total retries, total tokens
- reviewer findings summary
- final result (done/tweak/redo)
- constitutional pass (from verify.sh run)

**On failure:** appends warning to budget report, does NOT block pipeline.

### aggregator.sh

Called periodically or by `/forge health`. Reads all `telemetry.yaml` files for current month, produces aggregated metrics for the `testing:` section in `metrics/monthly-{YYYY-MM}.yaml`.

### Done Criteria

- `verify.sh` now checks all 4 domains (constitution, agents, pipelines, rules)
- `telemetry-writer.sh` produces valid YAML matching schema from design
- Telemetry contains no project content (only numbers/enums)
- Pipeline completion calls telemetry-writer, shows warning on failure

---

## Phase 6 Deliverables (with Quality Gates)

**Goal:** Bench runner — can execute test cases against fixture projects.

### Files to Create

```
src/testing/
├── bench/
│   ├── runner.sh                  # Orchestrates bench runs
│   ├── scorer.sh                  # Calculates composite score
│   ├── reporter.sh                # Generates reports, comparisons
│   ├── tier-detector.sh           # Classifies changes → tier recommendation
│   ├── cases/
│   │   ├── quick-bugfix-mature-001.yaml
│   │   ├── std-feature-mature-001.yaml
│   │   ├── std-feature-greenfield-001.yaml
│   │   ├── std-bugfix-legacy-001.yaml
│   │   ├── std-feature-rejection-001.yaml
│   │   ├── full-feature-mature-001.yaml
│   │   └── ... (initial set, ~10-15 cases)
│   ├── fixtures/
│   │   ├── greenfield-webapp/     # Minimal project (~5 files)
│   │   │   ├── .forge-fixture.yaml
│   │   │   ├── package.json
│   │   │   ├── tsconfig.json
│   │   │   └── src/index.ts
│   │   ├── mature-webapp/         # Consistent project (~25 files)
│   │   │   ├── .forge-fixture.yaml
│   │   │   └── ... (full project structure)
│   │   └── legacy-webapp/         # Messy project (~45 files)
│   │       ├── .forge-fixture.yaml
│   │       └── ... (inconsistent structure)
│   └── results/                   # Created at runtime
│       └── aggregate.yaml
```

### runner.sh — Core Logic

```
1. Parse arguments (tier, specific tests, budget limit)
2. If no tier specified → call tier-detector.sh → recommend
3. Show user: tests to run, estimated cost, options
4. For each test case:
   a. Reset fixture (git checkout clean && git clean -fd)
   b. Verify clean state
   c. Invoke Forge pipeline with task description
   d. Inject gate_responses at gates
   e. Inject blocked_responses if agent blocks
   f. On completion: collect artifacts from state/
   g. Run automated checks (compile, lint, test)
   h. Record structural results (pipeline type, agents, gates)
   i. Track token usage against budget
   j. Show progress
5. Calculate scores via scorer.sh
6. Generate report via reporter.sh
7. Update aggregate.yaml
8. Show results with NORMAL/WARN/ALERT zones
```

### scorer.sh — Score Calculation

Without LLM-judge (added in Phase 10), quality scoring uses only automated checks:

```
Phase 6 scoring (no judge yet):
  Conformance = structural verifier results (0-100)
  Quality = automated checks pass rate (compile + lint + tests)
  Efficiency = context usage + retry rate

Phase 10 scoring (with judge):
  Quality = judge_normalized with automated gate (full formula from design)
```

### tier-detector.sh

```
1. Get git diff since last bench run (read from aggregate.yaml timestamp)
2. Classify each changed file against trigger matrix
3. Return max tier + list of matching test tags
```

### Fixture Projects — Requirements

**greenfield-webapp:**
- package.json, tsconfig.json, src/index.ts
- Express hello-world, one route
- jest configured but 0 tests
- Clean, standard structure

**mature-webapp:**
- ~25 files across src/api/, src/models/, src/services/, src/utils/
- 3-4 existing endpoints with consistent patterns
- Prisma schema with 2-3 models
- 10+ existing tests
- Clear conventions (naming, error handling, response format)

**legacy-webapp:**
- ~45 files, inconsistent structure
- Mix of old and new patterns
- Some god-files (>200 lines)
- Incomplete test coverage
- Deprecated code still present

Each fixture is a git repo with a `clean` branch as reset point.

### Test Case Initial Set

| ID | Size | Type | State | Pipeline | Tests |
|----|------|------|-------|----------|-------|
| quick-bugfix-mature-001 | small | bugfix | mature | quick | happy path |
| quick-bugfix-legacy-001 | small | bugfix | legacy | quick | happy path |
| std-feature-mature-001 | medium | feature | mature | standard | happy path |
| std-feature-greenfield-001 | medium | feature | greenfield | standard | happy path |
| std-bugfix-legacy-001 | medium | bugfix | legacy | standard | happy path |
| std-refactor-mature-001 | medium | refactor | mature | standard | happy path |
| std-feature-rejection-001 | medium | feature | mature | standard | gate rejection |
| std-feature-blocked-001 | medium | feature | mature | standard | agent blocked |
| std-feature-retry-001 | medium | feature | mature | standard | reviewer critical |
| full-feature-mature-001 | large | feature | mature | full | happy path |
| full-refactor-legacy-001 | large | refactor | legacy | full | happy path |

### Done Criteria

- `runner.sh` can execute a test case end-to-end
- Fixture reset is reliable (verified by git status check)
- Gate responses are injected correctly
- Budget tracking works (warns at threshold, pauses at limit)
- `aggregate.yaml` accumulates across runs (max 5 detailed + archive)
- Tier detection recommends correctly based on git diff
- Report shows NORMAL/WARN/ALERT based on confidence bands

---

## Phase 10 Deliverables (with Reflection Engine)

**Goal:** LLM-Judge, rubrics, calibration, `/forge health` command.

### Files to Create

```
src/testing/
├── bench/
│   ├── judge-prompt.md            # Judge system prompt
│   ├── judge-runner.sh            # Invokes Claude as judge
│   ├── rubrics/
│   │   ├── feature-implementation.yaml
│   │   ├── bugfix.yaml
│   │   └── refactoring.yaml
│   ├── calibration/
│   │   ├── good-implementation/   # Pre-evaluated artifacts
│   │   ├── mediocre-implementation/
│   │   └── poor-implementation/
│   └── scorer.sh                  # Updated: includes judge scores
├── commands/
│   ├── forge-bench.md             # /forge bench skill definition
│   └── forge-health.md            # /forge health skill definition
```

### judge-prompt.md

System prompt for the judge agent. Key sections:
- Identity: independent evaluator, not part of the system being evaluated
- Input: list of artifact file paths to read
- Rubric: loaded from rubrics/*.yaml (included in prompt by runner)
- Output: strict YAML format matching design spec
- Constraints: NEVER give scores without evidence, NEVER fabricate file contents

### judge-runner.sh

```
1. Receive: test case ID, artifacts directory
2. Select rubric based on test case category (feature/bugfix/refactor)
3. Assemble judge prompt (system prompt + rubric + artifact paths)
4. Invoke Claude (sonnet-tier by default)
5. Parse YAML response
6. Validate: all criteria scored, justifications present, evidence non-empty
7. If parse/validation fails → retry once, then mark as "judge_error"
8. Return structured scores
```

### Rubrics

Three rubrics, each with 4 criteria and 5-level anchored scales (as defined in design). The rubrics share criteria IDs but differ in anchor examples:

- **feature-implementation.yaml** — anchors reference new functionality
- **bugfix.yaml** — anchors reference root cause identification, regression prevention
- **refactoring.yaml** — anchors reference behavior preservation, structural improvement

### Calibration Set

Three pre-evaluated implementations (good/mediocre/poor) for each fixture project. These are actual code changes with known quality levels. Used to verify judge produces scores within ±1 of expected.

### scorer.sh Update

Extends Phase 6 scorer with full formula:
```
quality = automated_pass ? (judge_composite - 1) * 25 : min((judge_composite - 1) * 25, 20)
composite = conformance * 0.3 + quality * 0.5 + efficiency * 0.2
```

### /forge bench Command

Skill definition that orchestrates the bench UX flow from design:
1. Scan changes → recommend tier
2. Show gate with options (run/full/smoke/pick/details/abort)
3. Execute via runner.sh
4. Display results

### /forge health Command

Skill definition for live health check:
1. Run verify.sh (Tier 1)
2. Read live/index.yaml
3. If judge available → read quality scores from telemetry
4. Display composite score + breakdown + trends
5. Offer drill-down

### Done Criteria

- Judge produces valid YAML scores for all test cases
- Calibration passes (judge within ±1 of expected on all calibration examples)
- Composite score calculation matches design formula
- `/forge bench` full flow works end-to-end
- `/forge health` shows meaningful data from live telemetry
- Reports show regression detection with NORMAL/WARN/ALERT

---

## Cross-Phase Dependencies

```
Phase 2 ──→ constitution.sh, agents.sh (need agent definitions)
Phase 3 ──→ pipelines.sh, rules.sh, telemetry-writer.sh (need pipeline engine)
Phase 6 ──→ runner.sh, fixtures, test cases (need quality gates)
Phase 10 ──→ judge, rubrics, calibration (need reflection patterns)
```

Each phase's testing deliverables depend ONLY on that phase's core deliverables. No forward dependencies.

## Implementation Order Within Each Phase

Within each phase, implement in this order:
1. Tests/checks first (verify.sh checks for Phase 2-3, test cases for Phase 6)
2. Core logic (telemetry writer, bench runner, judge runner)
3. Supporting tools (scorer, reporter, tier-detector)
4. Commands/UX (skill definitions)

This ensures we can validate each component before building on it.
