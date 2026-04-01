# Phase 6: Quality Gates & Review System

## Goal

Full quality gate enforcement with structured checklist validation, severity-based finding routing, quality map generation and evolution, CONFORM/EVOLVE mode switching, and Tier 2 behavioral bench bootstrap. This phase makes quality a STRUCTURAL property of the pipeline — not aspirational guidance, but enforced gates with deterministic routing.

After Phase 6: every agent that produces quality-relevant output is REQUIRED to complete its checklist in a machine-parseable format. Findings are automatically routed by severity. The quality map provides evidence-based guidance on existing patterns. The bench infrastructure enables objective measurement of system output quality.

## Risk Classification

**ORANGE** — Orchestrator flow changes (quality routing), new config fields (CONFORM/EVOLVE mode), new test infrastructure (bench fixtures). Needs design doc update first for any deviations.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | Art 1.2 (agent NEVER constraints — quality enforcement must not weaken role boundaries), Art 2.1 (pipeline determinism — quality routing must be deterministic), Art 2.2 (gate determinism — quality gates cannot be skipped), Art 2.3 (no implicit decisions — severity classification follows explicit rules), Art 3.1 (traceability — all quality findings written to state files), Art 4.2 (user authority — WARNING findings require user approval), Art 5.1 (evidence-based knowledge — quality map entries require evidence), Art 5.2 (rule changes require threshold — evolution proposals need 3+ observations) |
| `design/subsystems/quality.md` | Quality gates Q1-Q5 definitions, severity classification (CRITICAL/WARNING/SUGGESTION), quality map categories (Strong/Adequate/Problematic), CONFORM/EVOLVE mode definitions, quality evolution lifecycle |
| `design/subsystems/testing.md` | Tier 2 Behavioral Bench architecture, fixture projects, test case format, LLM-Judge rubrics, bench runner, budget guards, roadmap integration details |
| `design/subsystems/fault-tolerance.md` | E5-QUALITY error type — retry logic (max 2 attempts), escalation after max retries |
| `design/architecture/pipelines.md` | Pipeline error handling table (quality gate failed → retry with feedback, after 2 failures → escalate) |
| `design/architecture/agents.md` | Agent response contract, knowledge access matrix, Reviewer (Themis) role definition |
| `design/architecture/rules.md` | Layer 1-4 assembly, conflict detection, how project rules affect agent behavior |
| `design/subsystems/knowledge.md` | Quality map as knowledge component, L0/L1/L2 levels, agent knowledge access matrix (D-039 expanded) |
| `design/decisions/log.md` | D-024 (LLM-Judge with anchored rubrics), D-039 (full knowledge dimensions including quality_map), D-044 (AGENTS.md deferred) |
| `design/IMPLEMENTATION-GUIDE.md` | Agent prompt engineering principles, common mistakes, context budget discipline |

## Prerequisites (from Phase 1-5)

- **Phase 1:** State management (state.sh, yaml-utils.sh), all YAML schemas, directory structure
- **Phase 2:** All 10 agent role definitions (especially `themis.yaml` — Reviewer), quality checklist YAML files (q1-q5), base.yaml, response-contract.yaml, knowledge-access-matrix.yaml
- **Phase 3:** Orchestrator skill (orchestrator.md, gates.md, dispatch.md, errors.md), pipeline definitions, E5-QUALITY error handling stubs
- **Phase 4:** Rules assembly (rules.sh), knowledge system (knowledge.sh), knowledge templates, dispatch instruction file support
- **Phase 5:** Bootstrap engine (bootstrap.sh, scanners, frontmatter-based config generation), config.yaml with bootstrap fields, CLAUDE.md integration

## Design Inconsistency: LLM-Judge Timing

The roadmap Phase 6 testing section mentions "LLM-judge with anchored rubrics (D-024)". However, `testing.md` roadmap integration explicitly states:

```yaml
phase_6:   # Bench runner, test case format, fixtures, /moira bench, budget guards
phase_10:  # LLM-Judge implementation, rubrics, calibration set, judge calibration command
```

**Resolution for Phase 6:** Create rubric DEFINITION files (YAML structure with anchored examples) and the bench runner infrastructure with AUTOMATED checks only (compile, lint, test pass/fail). The actual LLM-Judge invocation (Claude call for qualitative evaluation) is deferred to Phase 10. Phase 6 bench results include structural/automated scores only — quality scores are `null` until the judge is operational.

This should be recorded in the decision log.

## Design Inconsistency: Quality Criteria File Naming

`overview.md` shows quality criteria files as `correctness.yaml`, `performance.yaml`, `security.yaml`, `standards.yaml`. The actual Phase 2/4 implementation created `q1-completeness.yaml` through `q5-coverage.yaml` — per-gate checklists that incorporate quality criteria into the relevant pipeline step. The Q4 (correctness) checklist already covers all quality criteria categories (correctness, standards, performance, security, integration, conventions).

**Resolution:** The Q1-Q5 naming is correct — it maps checklists to pipeline gates, which is the actual usage pattern. The overview.md quality file names are outdated design references. No action needed for Phase 6 beyond noting this inconsistency.

## Deliverables

### D1: Quality Findings Schema (`src/schemas/findings.schema.yaml`)

A structured format for agent quality findings. Every agent that runs a quality checklist MUST write its findings in this format to `state/tasks/{id}/findings/{agent}-{gate}.yaml`.

**Schema:**

```yaml
_meta:
  task_id: string        # required
  gate: string           # Q1|Q2|Q3|Q4|Q5
  agent: string          # agent name (greek)
  timestamp: string      # ISO 8601
  mode: string           # conform|evolve

checklist:
  # Each item from the relevant Q* checklist
  items:
    - id: string         # e.g., Q4-C01
      check: string      # the check description
      result: string     # pass|fail|na|skip
      severity: string   # critical|warning|suggestion (only if result=fail)
      detail: string     # explanation (only if result=fail)
      evidence: string   # file:line or artifact reference (only if result=fail)

summary:
  total: number
  passed: number
  failed: number
  na: number
  critical_count: number
  warning_count: number
  suggestion_count: number
  verdict: string        # pass|fail_critical|fail_warning
```

**Routing rules (deterministic, per Art 2.1):**

| verdict | Pipeline Action |
|---------|----------------|
| `pass` | Proceed to next step |
| `fail_critical` | Trigger E5-QUALITY retry (max 2 total attempts) |
| `fail_warning` | Present WARNING gate to user — proceed/fix/abort |

- `verdict = pass`: zero critical AND zero warning findings
- `verdict = fail_critical`: 1+ critical findings
- `verdict = fail_warning`: zero critical BUT 1+ warning findings

Suggestions are NEVER blocking — logged for Mnemosyne (reflector) analysis in Phase 10.

### D2: Quality Enforcement in Agent Dispatch (`src/global/skills/dispatch.md`)

Update the dispatch module to include explicit quality checklist instructions in every agent prompt that has an associated quality gate.

**Agent-to-gate mapping:**

| Agent | Gate | Checklist File |
|-------|------|---------------|
| Athena (analyst) | Q1 | q1-completeness.yaml |
| Metis (architect) | Q2 | q2-soundness.yaml |
| Daedalus (planner) | Q3 | q3-feasibility.yaml |
| Themis (reviewer) | Q4 | q4-correctness.yaml |
| Aletheia (tester) | Q5 | q5-coverage.yaml |

**Changes to dispatch.md:**

For agents with quality gates, append to the assembled prompt:

```markdown
## Quality Checklist — {Gate Name}

You MUST evaluate every item in this checklist. For each item, report:
- `pass` — requirement satisfied
- `fail` — requirement not satisfied (include severity, detail, evidence)
- `na` — not applicable to this task (justify)
- `skip` — cannot evaluate (justify)

Write your findings to: `.moira/state/tasks/{task_id}/findings/{your_name}-{gate}.yaml`
using the findings schema format.

Items to evaluate:
{checklist items from Q* yaml file}

CRITICAL: Do not skip items. Do not mark items as `pass` without verifying. If you cannot verify — mark as `skip` with justification, NEVER mark as `pass`.
```

**Pre-planning vs post-planning agents:**

- Pre-planning agents (Athena Q1): checklist included via simplified assembly path
- Post-planning agents (Metis Q2, Daedalus Q3, Themis Q4, Aletheia Q5): checklist included in Daedalus-assembled instruction files

This means Daedalus must know about Q2-Q5 checklists when assembling downstream agent instructions. Q2 findings from Metis may already exist by the time Daedalus runs — Daedalus should include them as context for downstream agents.

### D3: Quality Gate Routing in Orchestrator (`src/global/skills/orchestrator.md`)

Update the pipeline execution loop to parse quality findings after quality-gate agents complete.

**New orchestrator behavior after quality-gate agents:**

```
After agent with quality gate returns STATUS: success:
1. Read findings file: state/tasks/{id}/findings/{agent}-{gate}.yaml
2. Parse verdict field
3. Route:
   - pass → record gate as proceed, advance
   - fail_critical → trigger E5-QUALITY retry
   - fail_warning → present WARNING gate to user
```

**WARNING gate (new gate type in gates.md):**

```
═══════════════════════════════════════════
 GATE: Quality Warning — {Gate Name}
═══════════════════════════════════════════

 Themis (reviewer) found {N} warnings:

 ⚠ {Q4-S02}: DRY violation in src/services/user.ts:45
   Detail: Logic duplicated from src/services/auth.ts:12

 ⚠ {Q4-P04}: Unbounded query in src/api/products.ts:67
   Detail: No pagination limit on findMany call

 Impact: {summary of warnings}

 ORCHESTRATOR HEALTH:
 {standard health report}

 ▸ proceed — Accept warnings, continue pipeline
 ▸ fix     — Send back to Hephaestus (implementer) for fixes
 ▸ details — Show full findings
 ▸ abort   — Cancel task
═══════════════════════════════════════════
```

**E5-QUALITY retry flow (already defined in errors.md, needs integration):**

```
Attempt 1 (standard):
  Implementer gets CRITICAL findings as feedback → fixes → Reviewer re-reviews

Attempt 2 (if still failing):
  Architect re-examines decision → new plan → new implementation → review

After 2 failures:
  Escalate to user (per existing E5-QUALITY gate in gates.md)
```

Key detail: On retry, the Implementer receives:
- The specific CRITICAL findings with file/line references
- The original plan (unchanged)
- Instruction: "Fix ONLY the listed issues. Do not expand scope."

### D4: Quality Findings Validator (`src/global/lib/quality.sh`)

Shell library for quality-related operations.

**Functions:**

#### `moira_quality_parse_verdict <findings_path>`
Parse a findings YAML file and return the verdict.

- Read `summary.critical_count` and `summary.warning_count`
- If critical_count > 0 → echo "fail_critical"
- If warning_count > 0 → echo "fail_warning"
- Else → echo "pass"

#### `moira_quality_validate_findings <findings_path> <gate_checklist_path>`
Validate that a findings file covers all required checklist items.

- Load checklist items from Q* YAML
- Load findings items
- Check: every required checklist item has a corresponding finding entry
- If any required item is missing → return error with missing item IDs
- This is a structural check, not a quality judgment

#### `moira_quality_aggregate_task <task_dir>`
Aggregate all findings for a task into a summary.

- Scan `findings/` directory for all `*-Q*.yaml` files
- Produce `findings/summary.yaml` with:
  - Per-gate verdicts
  - Total findings by severity
  - Overall task quality verdict

#### `moira_quality_format_warnings <findings_path>`
Format WARNING findings for gate display.

- Read findings where severity=warning
- Format each as: `⚠ {id}: {check}\n  Detail: {detail}\n  Evidence: {evidence}`
- Return formatted string for gate template

### D5: Quality Map System

Reconcile the quality map structure between knowledge.md and quality.md.

#### D5a: Quality Map Schema

Quality map is a knowledge document (under `knowledge/quality-map/`) with the following structure:

**`quality-map/full.md`:**

```markdown
<!-- moira:freshness {source} {date} -->
<!-- moira:mode {conform|evolve} -->

# Quality Map

## ✅ Strong Patterns

### {Pattern Name}
- **Category**: {component|api|data|testing|...}
- **Location**: {directory or file pattern}
- **Evidence**: {task IDs or bootstrap scan reference}
- **Confidence**: {high|medium} (high = 3+ confirming observations)
- **Example**: {representative file:line}

## ⚠️ Adequate Patterns

### {Pattern Name}
- **Category**: {category}
- **Location**: {where}
- **Evidence**: {source}
- **Limitations**: {known issues}
- **Example**: {file:line}

## 🔴 Problematic Patterns

### {Pattern Name}
- **Category**: {category}
- **Location**: {where}
- **Evidence**: {source}
- **Problem**: {what's wrong}
- **Correct Alternative**: {what to do instead for new code}
- **Example**: {file:line}
```

**`quality-map/summary.md`:**

Condensed version for L1 access (Metis, Themis, Daedalus):

```markdown
# Quality Map Summary

## Strong (follow): {comma-separated pattern names}
## Adequate (follow with notes): {patterns with one-line limitation}
## Problematic (don't extend): {patterns with one-line alternative}
```

#### D5b: Quality Map Generator in Bootstrap

Update `bootstrap.sh` function `moira_bootstrap_populate_knowledge`:

Currently, Phase 5 creates a preliminary quality map marked with `<!-- moira:preliminary -->`. Phase 6 enhances this:

- Pattern scanner output → categorized into quality map entries
- Initial entries are ALL `medium` confidence (from scan, not from task evidence)
- Quality map is marked `preliminary` until 5+ tasks have run (observation-based upgrade)
- Strong/Adequate/Problematic assessment based on scan observations:
  - Consistent pattern across multiple files → ✅ Strong
  - Pattern present but inconsistent → ⚠️ Adequate
  - Obvious issues noted by scanner → 🔴 Problematic
  - Unknown/insufficient evidence → omitted (not guessed)

#### D5c: Quality Map Evolution (Knowledge Write Path)

Add to `knowledge.sh`:

#### `moira_knowledge_update_quality_map <task_dir> <quality_map_dir>`

Called after task completion (before reflection). Updates quality map based on Reviewer findings:

1. Read `findings/themis-Q4.yaml` from the completed task
2. For each finding:
   - If finding references an existing quality map entry: increment observation count
   - If finding identifies a NEW pattern issue (not in quality map): add as `observation_count: 1` in appropriate category
3. Confidence upgrade: if observation_count reaches 3 → upgrade confidence from `medium` to `high` (Art 5.2)
4. Category transitions:
   - ✅→⚠️: if 2+ warnings found on a "Strong" pattern → downgrade to Adequate with evidence
   - ⚠️→🔴: if 3+ criticals found on an "Adequate" pattern → downgrade to Problematic
   - ⚠️→✅: if 5+ tasks use pattern with zero findings → upgrade to Strong
   - 🔴→⚠️: only through EVOLVE mode (explicit improvement task)
5. Write updated quality-map/full.md and quality-map/summary.md
6. Update freshness marker

This function runs structural checks only (keyword matching, counting) — NOT semantic analysis. Semantic quality assessment is the Reflector's job (Phase 10).

### D6: CONFORM/EVOLVE Mode

#### D6a: Config Schema Update

Update `config.schema.yaml` (D-054 reconciliation — replaces Phase 1 placeholder fields `quality.evolution_threshold` and `quality.review_severity_minimum` which are superseded by Art 5.2 and Art 2.1 respectively):

```yaml
quality:
  mode:
    type: string
    enum: [conform, evolve]
    default: conform
    description: "Quality mode — conform follows existing patterns, evolve allows systematic improvement"
  evolution:
    current_target:
      type: string
      default: ""
      description: "Pattern currently being evolved (empty = none)"
    cooldown_remaining:
      type: number
      default: 0
      description: "Tasks remaining in post-evolution cooldown (0 = not in cooldown)"
```

#### D6b: Mode Effects on Agents

**CONFORM mode (default):**
- Implementer: follow existing patterns exactly, even if imperfect. If a ⚠️ Adequate pattern is used, follow it. Only avoid 🔴 Problematic patterns for NEW code.
- Reviewer: flag deviations from existing patterns as WARNING. Do NOT flag following ⚠️ Adequate patterns as issues.
- Planner: include quality map summary in agent instructions. Mark which patterns to follow/avoid.

**EVOLVE mode:**
- Can only be activated for ONE specific pattern at a time (`evolution.current_target`)
- Implementer: use improved pattern for the target pattern. Follow all other patterns normally.
- Reviewer: evaluate the improved pattern's correctness. May flag if improvement introduces new issues.
- Mode automatically reverts to CONFORM after evolution task completes, with cooldown counter set to 5.

**Mode communication:** Planner includes in assembled instructions:
```markdown
## Quality Mode: {CONFORM|EVOLVE}
{If EVOLVE: "Evolving pattern: {target}. Use improved approach for this pattern only."}

Quality Map Summary:
{quality-map/summary.md content}
```

#### D6c: Evolution Lifecycle Tracking

The evolution lifecycle (quality.md) tracks pattern improvements:

```
Discovery → Documentation → Accumulation → Proposal → Approval → Execution
```

Phase 6 implements stages 1-3 (automated) and the config fields for stages 4-6. The actual proposal system is deferred to Phase 10 (Reflector).

- **Discovery** (Stage 1): Reviewer flags a new quality issue → logged in quality map as `observation_count: 1`, tag: 🆕 NEW
- **Documentation** (Stage 2): Same issue found again → `observation_count: 2`, tag: ⚠️ CONFIRMED
- **Accumulation** (Stage 3): Third observation → `observation_count: 3+`, tag: 📊 MEASURED. Pattern is now eligible for evolution proposal.
- **Proposal** (Stage 4, Phase 10): Reflector proposes evolution → presented to user
- **Approval** (Stage 5): User approves → mode switches to EVOLVE, target set
- **Execution** (Stage 6): Task runs through Full Pipeline in EVOLVE mode → cooldown starts

Anti-chaos safeguards (from quality.md):
1. One evolution at a time — `evolution.current_target` is singular
2. Scope lock — evolution task cannot expand beyond target pattern
3. Cooldown — 5 tasks in CONFORM after evolution, tracked in config

### D7: Behavioral Bench Infrastructure

#### D7a: Fixture Projects (`src/tests/bench/fixtures/`)

Three minimal but functional projects for testing Moira pipeline execution.

**`greenfield-webapp/`** — Minimal project, basic structure:
- Simple Express + TypeScript app with 3-5 files
- `package.json`, `tsconfig.json`, minimal config
- One API endpoint, one type definition, one test
- `.moira-fixture.yaml` descriptor
- Clean git repo with `clean` branch

**`mature-webapp/`** — Consistent patterns, ~20-25 files:
- Express + TypeScript + Prisma (detected by scanners)
- Clear directory structure: `src/routes/`, `src/services/`, `src/types/`, `src/middleware/`
- Consistent naming, error handling, testing patterns
- 3-4 API endpoints, service layer, repository layer
- Jest tests with existing patterns
- `.moira-fixture.yaml` descriptor

**`legacy-webapp/`** — Inconsistent patterns, ~30-40 files:
- Express + JavaScript (some TypeScript mixed in)
- Inconsistent patterns: some routes use controller pattern, others inline
- Some tests in `__tests__/`, others co-located, some missing
- Tech debt markers
- No linting config
- `.moira-fixture.yaml` descriptor

Each `.moira-fixture.yaml`:

```yaml
name: "{fixture-name}"
description: "{one-line description}"
stack: [{language}, {framework}, ...]
state: {greenfield|mature|legacy}
characteristics:
  - {characteristic 1}
  - {characteristic 2}
reset_command: "git checkout clean && git clean -fd"
expected_stack: "{free-form stack string}"  # presets removed per D-060
```

**Fixture sizing principle:** Fixtures should be small enough to scan quickly but representative enough to trigger meaningful pipeline behavior. Err on the side of minimal — the value is in testing Moira's pipeline, not in simulating a real large codebase.

#### D7b: Test Case Format (`src/tests/bench/cases/`)

YAML test case definitions per testing.md spec.

**Initial test cases (Phase 6 — 5 cases):**

1. `quick-bugfix-mature-001.yaml` — Small bugfix on mature project (Quick pipeline)
2. `std-feature-mature-001.yaml` — Medium feature on mature project (Standard pipeline)
3. `std-feature-greenfield-001.yaml` — Medium feature on greenfield project (Standard pipeline)
4. `std-refactor-legacy-001.yaml` — Medium refactor on legacy project (Standard pipeline)
5. `quick-bugfix-legacy-001.yaml` — Small bugfix on legacy project (Quick pipeline)

Each test case follows the format defined in testing.md (meta, fixture, task, gate_responses, expected_structural, expected_quality).

**For Phase 6:** `expected_quality` minimum scores are set but cannot be evaluated (no LLM-judge). Automated checks only: does the output compile, does it pass linting, do tests pass.

#### D7c: Bench Runner (`src/global/lib/bench.sh`)

Shell library for bench test execution. Phase 6 implements automated checks only.

**Functions:**

#### `moira_bench_run <test_case_path>`
Execute a single bench test.

1. Read test case YAML
2. Reset fixture to clean state
3. Verify clean state (git status)
4. Run `/moira:init` on fixture (or verify existing init)
5. Submit task through Moira pipeline with predefined `gate_responses`
6. After pipeline completion:
   - Check: did compilation succeed?
   - Check: does linting pass?
   - Check: do tests pass?
   - Record structural results (pipeline type, agents called, gates triggered, retries)
7. Write results to `bench/results/run-{NNN}/{test_case_id}.yaml`

**Gate response injection:** The bench runner needs to intercept gates and provide predefined responses from the test case. This requires a mechanism to auto-respond to gates during bench runs.

**Implementation approach:** A `bench_mode` flag in `current.yaml` that the orchestrator checks at each gate. If `bench_mode: true`, the orchestrator reads `gate_responses` from the test case file instead of prompting the user. This is acceptable because:
- Bench mode is explicitly activated (not implicit)
- Gate responses are predefined and auditable
- This does NOT violate Art 4.2 — the user explicitly chose to run the bench test
- All gate decisions are still recorded in state files (Art 3.1)

#### `moira_bench_run_tier <tier> [test_filter]`
Execute a tier of tests.

- Tier 1: delegate to existing `run-all.sh`
- Tier 2: run tests matching filter tags
- Tier 3: run all bench tests
- Sequential per fixture (testing.md requirement)
- Report progress per test

#### `moira_bench_report <run_dir>`
Generate summary report from a bench run.

- Aggregate per-test results
- Compute structural pass rate
- Compute automated check pass rate
- Quality scores: `null` (no LLM-judge yet)
- Write `summary.yaml` to run directory

#### D7d: Bench Rubric Definitions (`src/tests/bench/rubrics/`)

Create rubric YAML files per testing.md spec. These define the evaluation criteria for when LLM-Judge is implemented in Phase 10.

**`feature-implementation.yaml`** — Standard rubric for feature tasks:

```yaml
_meta:
  id: feature-implementation
  name: Feature Implementation Quality
  version: "1.0"

criteria:
  - id: requirements_coverage
    weight: 25
    scale: [1, 2, 3, 4, 5]
    anchors:
      1: {label: "Critical gaps", description: "Happy path not implemented", example: "..."}
      2: {label: "Partial", description: "Happy path works, edge cases missing", example: "..."}
      3: {label: "Adequate", description: "Main cases covered, minor gaps", example: "..."}
      4: {label: "Strong", description: "All stated requirements covered", example: "..."}
      5: {label: "Comprehensive", description: "Requirements + reasonable extras", example: "..."}

  - id: code_correctness
    weight: 30
    # ... anchors per testing.md

  - id: architecture_quality
    weight: 25
    # ... anchors per testing.md

  - id: conventions_adherence
    weight: 20
    # ... anchors per testing.md
```

**`bugfix-quality.yaml`** — Rubric for bugfix tasks (different weights — correctness higher, architecture lower)

**`refactor-quality.yaml`** — Rubric for refactoring tasks (conventions higher, requirements lower)

These files are DATA DEFINITIONS only. No judge invocation code in Phase 6.

#### D7e: Bench Command (`src/commands/moira/bench.md`)

New command file for `/moira:bench`.

```yaml
---
name: moira:bench
description: Run Moira behavioral tests
argument-hint: "[tier1|tier2|tier3|report|compare]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---
```

**Phase 6 subcommands:**

- `/moira:bench` (no args) — auto-detect tier from git diff, suggest tests, ask user
- `/moira:bench tier1` — run structural tests only
- `/moira:bench tier2 [filter]` — run targeted bench tests
- `/moira:bench tier3` — run all bench tests
- `/moira:bench report` — show latest bench results
- `/moira:bench compare <run1> <run2>` — compare two runs (structural only in Phase 6)

**Budget guards (from testing.md):**

```yaml
bench_budget:
  tier_2:
    max_tests: 5
    warn_at_test: 4
  tier_3:
    max_tests: 30
    warn_at_test: 20
  abort_behavior: pause_and_ask
```

Note: Token-based budget guards are deferred to Phase 7 (context budget system). Phase 6 uses test count limits only.

### D8: Deep Scan Agent Instructions (`src/global/templates/scanners/deep/`)

Phase 5 placed the deep scan trigger in the orchestrator but deferred agent instructions. Phase 6 implements them.

Four deep scan templates (more comprehensive than quick scan):

- `deep-architecture-scan.md` — Full architecture mapping: service boundaries, dependency graph, data flow paths, external integrations
- `deep-dependency-scan.md` — Package versions, outdated/vulnerable dependencies, unused imports, circular dependencies
- `deep-test-coverage-scan.md` — Test file coverage, untested code paths, test quality assessment
- `deep-security-scan.md` — Hardcoded secrets scan, input validation gaps, auth boundary verification, unsafe patterns

Each deep scan template follows the same Explorer (Hermes) invocation pattern from Phase 5 scanners. Key differences from quick scan:
- Deep scans read MORE files (up to 50 per scan, vs 25-30 for quick)
- Deep scans produce MORE granular output
- Deep scan results update existing knowledge (append/enhance, not replace)
- Output path: `knowledge/{type}/full.md` (enhances existing content)

**Orchestrator update:** Complete the deep scan dispatch in `orchestrator.md` Section 2 (Bootstrap Deep Scan Check):
- Replace the "NOTE: not yet implemented" stub
- Dispatch 4 deep scan Explorer agents in background
- After completion: call `moira_knowledge_update_quality_map` with deep scan findings

### D9: Updated Orchestrator (`src/global/skills/orchestrator.md`)

Consolidation of all Phase 6 orchestrator changes:

1. **Quality gate routing** (D3): After quality-gate agents complete, parse findings and route by verdict
2. **WARNING gate presentation**: New gate type for warning-only findings
3. **Bench mode support** (D7c): Check for `bench_mode` flag, auto-respond to gates during bench runs
4. **Deep scan dispatch** (D8): Complete the deep scan implementation from Phase 5 stub
5. **CONFORM/EVOLVE awareness** (D6b): Read quality mode from config at pipeline start, pass to Planner

### D10: Updated Gates (`src/global/skills/gates.md`)

1. **WARNING gate template** (D3): New gate type for quality warnings
2. **Quality findings display**: Formatted finding list in gate display

### D11: Updated Dispatch (`src/global/skills/dispatch.md`)

1. **Quality checklist injection** (D2): Append checklist to agent prompts
2. **Quality map injection**: Include quality-map/summary.md in relevant agent instructions
3. **CONFORM/EVOLVE mode communication** (D6b): Include mode and quality map in assembled instructions

### D12: Updated Response Contract (`src/global/core/response-contract.yaml`)

Add quality findings section to agent response contract:

```yaml
# When agent has a quality gate assignment:
quality_response:
  format: |
    STATUS: success|failure|blocked|budget_exceeded
    SUMMARY: <1-2 sentences>
    QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)
    ARTIFACTS: [<file paths>]
    NEXT: <recommended next step>
  example: |
    STATUS: success
    QUALITY: Q4=fail_warning (0C/2W/3S)
    SUMMARY: Code review complete. 2 warnings found, 3 suggestions logged.
    ARTIFACTS: [review.md, findings/themis-Q4.yaml]
    NEXT: present warnings to user
```

The QUALITY line allows the orchestrator to quickly determine the verdict without reading the full findings file. The orchestrator SHOULD still read findings for details when needed, but the QUALITY line provides the routing signal.

### D13: Tier 1 Test Additions (`src/tests/tier1/`)

#### New test file: `test-quality-system.sh`

**Quality schema tests:**
- `findings.schema.yaml` exists with required fields (task_id, gate, agent, checklist, summary, verdict)
- All severity values are valid enum (critical, warning, suggestion)
- All result values are valid enum (pass, fail, na, skip)

**Quality enforcement tests:**
- `quality.sh` exists with valid bash syntax
- Functions exist: `moira_quality_parse_verdict`, `moira_quality_validate_findings`, `moira_quality_aggregate_task`, `moira_quality_format_warnings`
- `dispatch.md` contains quality checklist injection section
- `response-contract.yaml` contains QUALITY line format

**CONFORM/EVOLVE tests:**
- `config.schema.yaml` has `quality.mode` field with enum [conform, evolve]
- `config.schema.yaml` has `quality.evolution.current_target` and `quality.evolution.cooldown_remaining`
- `orchestrator.md` references quality mode
- `dispatch.md` references quality map injection

**Quality map tests:**
- Quality map knowledge files follow defined schema (Strong/Adequate/Problematic sections)
- Quality map entries have required fields (category, location, evidence, confidence)

**Bench infrastructure tests:**
- At least 3 fixture directories exist
- Each fixture has `.moira-fixture.yaml` with required fields (name, stack, state, reset_command)
- At least 5 test case files exist
- Each test case has required fields (meta, fixture, task, gate_responses, expected_structural)
- Rubric files exist with required criteria structure
- `bench.sh` exists with valid bash syntax
- `bench.md` command file has valid frontmatter

**Deep scan tests:**
- All 4 deep scan templates exist (`deep-architecture-scan.md`, `deep-dependency-scan.md`, `deep-test-coverage-scan.md`, `deep-security-scan.md`)
- Each template has: Objective, Scan Strategy, Output Format, Constraints
- Each template inherits Explorer NEVER constraints
- Orchestrator deep scan section no longer contains "not yet implemented" stub

#### Extended existing tests:
- `test-file-structure.sh`: add checks for findings schema, quality.sh, bench directories, deep scan templates
- `test-install.sh`: add verification for Phase 6 artifacts

### D14: Updated `install.sh`

Add Phase 6 artifacts to installation:

**New copy operations:**
- `global/lib/quality.sh` → `$MOIRA_HOME/lib/quality.sh`
- `global/lib/bench.sh` → `$MOIRA_HOME/lib/bench.sh`
- `global/templates/scanners/deep/` → `$MOIRA_HOME/templates/scanners/deep/`
- `tests/bench/` → `$MOIRA_HOME/tests/bench/` (fixtures, cases, rubrics)
- `schemas/findings.schema.yaml` → `$MOIRA_HOME/schemas/findings.schema.yaml`

**New verification checks:**
- `quality.sh` exists and has valid syntax
- `bench.sh` exists and has valid syntax
- Deep scan templates directory exists with 4 `.md` files
- Bench fixtures directory exists with 3 fixture directories
- At least 5 bench test cases exist

### D15: Updated `run-all.sh`

Add `test-quality-system.sh` to the test runner.

## Non-Deliverables (explicitly deferred)

- **LLM-Judge invocation** (Phase 10): Rubric definitions are created, but the actual Claude call for qualitative evaluation requires the Reflector (Phase 10) patterns. Phase 6 bench uses automated checks only.
- **Statistical confidence bands** (Phase 10+): D-025 statistical model requires 10+ bench runs. Phase 6 collects data, Phase 10+ applies statistical analysis.
- **Calibration set** (Phase 10): Judge calibration examples require the judge to be operational.
- **AGENTS.md generation** (remains deferred): D-044 reasoning still applies — insufficient task history to know what adaptations matter. Global agent definitions work correctly.
- **/moira:health command** (Phase 10): Full health check requires judge-based quality scores.
- **Evolution proposal system** (Phase 10): Reflector proposes pattern evolutions based on accumulated observations. Phase 6 implements the tracking and config, not the proposal logic.
- **Token-based bench budget guards** (Phase 7): Phase 6 uses test count limits. Token tracking is Phase 7's domain.
- **Bench aggregate statistics** (Phase 10+): Rolling averages, trend analysis, regression detection across bench runs.

## Architectural Decisions

### AD-1: Findings as Separate Files (Not Inline in Agent Output)

Quality findings are written to dedicated `findings/{agent}-{gate}.yaml` files, not embedded in the main agent output (review.md, requirements.md, etc.).

**Rationale:**
1. Machine-parseable: YAML structure enables automated routing
2. Separation of concerns: analysis detail in `.md`, routing data in `.yaml`
3. Aggregation: `moira_quality_aggregate_task` can scan the directory without parsing markdown
4. Historical: findings files persist for Reflector analysis

### AD-2: QUALITY Line in Response Contract

Adding a `QUALITY` summary line to the agent response allows the orchestrator to determine the verdict WITHOUT reading the full findings file. This keeps orchestrator context minimal per D-001.

The orchestrator reads the full findings file ONLY when it needs to present WARNING details to the user. For `pass` and `fail_critical` verdicts, the QUALITY line is sufficient.

### AD-3: Bench Mode Gate Auto-Response

Using a `bench_mode` flag in `current.yaml` rather than a completely separate bench pipeline. This approach:
- Reuses the production pipeline (tests actual behavior)
- Minimal orchestrator changes (single flag check at gates)
- Gate decisions still recorded in state files (full traceability)
- Does NOT create a "skip gates" mechanism — bench provides specific responses, not "skip"

### AD-4: Deep Scan as Phase 6 Deliverable

Deep scan agent instructions were deferred from Phase 5 because "quality gates are needed to validate output." Phase 6 provides those quality gates. Deep scan output is validated through the quality map system — scan results feed into the quality map with `medium` confidence, requiring 3+ task observations to reach `high` confidence.

### AD-5: Quality Map Evolution is Structural, Not Semantic

`moira_knowledge_update_quality_map` uses keyword matching and counting (shell-based), not LLM reasoning. This is consistent with D-042 (structural consistency validation). Full semantic analysis of pattern quality is the Reflector's job in Phase 10.

### AD-6: LLM-Judge Deferred to Phase 10

Resolving the roadmap inconsistency: Phase 6 creates rubric definitions and bench infrastructure with automated checks. Phase 10 adds the LLM-Judge. This aligns with testing.md's roadmap integration which explicitly assigns LLM-Judge to Phase 10.

**Why this is correct:** The LLM-Judge evaluates the same quality dimensions as the Reflector (requirements coverage, code correctness, architecture quality, conventions adherence). The Reflector's patterns inform how the judge should weight and evaluate — implementing them together ensures consistency.

### AD-7: Fixture Projects are Minimal

Fixtures are intentionally small (3-25 files). They test Moira's pipeline behavior, not its ability to handle large codebases. Large codebase testing is done on real projects (live telemetry from Phase 3).

### AD-8: Warning Gate is a New Gate Type

The WARNING gate (for quality warnings) is distinct from existing gates. It has different options (proceed/fix/details/abort) and different semantics:
- Approval gates (classification, architecture, plan, final) are REQUIRED gates per Art 2.2
- WARNING gate is a CONDITIONAL gate — only presented when warnings exist
- This does NOT violate Art 2.2 because the gate definitions in pipeline YAML specify which gates are required. The WARNING gate is an error-handling path, similar to E5-QUALITY, not a pipeline-defined gate.

## Success Criteria

1. **Quality findings are structured:** All quality-gate agents write findings in machine-parseable YAML format
2. **Routing is deterministic:** CRITICAL → retry, WARNING → user gate, SUGGESTION → log. No exceptions.
3. **Quality map is populated:** Bootstrap generates preliminary quality map from scan results
4. **Quality map evolves:** Reviewer findings incrementally update quality map entries
5. **CONFORM mode works:** Agents follow existing patterns, Reviewer flags deviations
6. **EVOLVE mode works:** Single pattern targeted for improvement, cooldown enforced
7. **Deep scan completes:** All 4 deep scan agents produce enhanced knowledge
8. **Bench fixtures exist:** 3 fixture projects with `.moira-fixture.yaml`
9. **Bench tests run:** At least 5 test cases execute through pipeline with automated checks
10. **Bench results recorded:** Per-test and per-run results in structured YAML
11. **Tier 1 tests pass:** All existing + new Phase 6 structural tests pass
12. **Constitutional compliance:** All 19 invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Quality routing happens in orchestrator but does NOT read project source files.
         Orchestrator reads only findings YAML files in .moira/state/
[✓] 1.2 — Quality enforcement does not weaken agent NEVER constraints.
         Agents still have single responsibility — Themis reviews, does NOT fix.
         Quality checklist is ADDITIONAL output, not a role expansion.
[✓] 1.3 — Quality system is a separate component (quality.sh, findings schema).
         Does not merge into existing agent or orchestrator responsibilities.

ARTICLE 2: Determinism
[✓] 2.1 — Quality routing is a pure function of finding severity counts.
         No heuristics, no judgment. Critical count → fail_critical. Warning count → fail_warning.
[✓] 2.2 — Quality gates are not skipped. WARNING gate is conditional (on warnings existing)
         but is ALWAYS presented when condition is met. Required gates unchanged.
[✓] 2.3 — Severity classification follows explicit rules in q4-correctness.yaml.
         Quality map entries require evidence. No implicit decisions.

ARTICLE 3: Transparency
[✓] 3.1 — All findings written to state files (findings/{agent}-{gate}.yaml).
         Quality map changes logged with freshness markers.
[✓] 3.2 — N/A for quality gates directly. Budget report includes quality gate retries.
[✓] 3.3 — Quality failures reported to user through WARNING gate or E5-QUALITY escalation.
         No silent quality degradation.

ARTICLE 4: Safety
[✓] 4.1 — Quality map entries require evidence from actual scans/tasks.
         No fabricated quality assessments.
[✓] 4.2 — WARNING findings require user approval to proceed.
         EVOLVE mode requires user activation.
         Bench mode requires explicit user command.
[✓] 4.3 — Quality routing retries are reversible (git-backed). EVOLVE mode reversible.
[✓] 4.4 — N/A (quality system does not interact with bypass)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — Quality map entries reference evidence (task IDs, scan references, file paths).
[✓] 5.2 — Quality map confidence upgrade requires 3+ observations.
         Evolution proposals require 3+ confirming observations.
[✓] 5.3 — Quality map updates include structural consistency check (keyword-level, D-042).

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation
[✓] 6.3 — Tier 1 tests validate quality system artifacts
```
