# Phase 6: Implementation Plan — Quality Gates & Review System

## Chunk Dependency Graph

```
         ┌──────────────────┐
         │  Chunk 1:        │
         │  Schema + Config │
         └────────┬─────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 2:        │
         │  Quality Library  │
         └────────┬─────────┘
                  │
    ┌─────────────┼──────────────┐
    │             │              │
┌───▼───┐  ┌─────▼─────┐  ┌────▼────┐
│Chunk 3│  │  Chunk 4   │  │ Chunk 5 │
│Dispatch│  │Orchestrator│  │Deep Scan│
│Updates │  │  Updates   │  │Templates│
└───┬───┘  └─────┬─────┘  └────┬────┘
    │             │              │
    └─────────────┼──────────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 6:        │
         │  Quality Map     │
         │  + CONFORM/EVOLVE│
         └────────┬─────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 7:        │
         │  Bench Infra     │
         └────────┬─────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 8:        │
         │  Tests + Install │
         └──────────────────┘
```

---

## Chunk 0: Pre-Implementation Housekeeping

**Dependencies:** None

### Task 0.1: Update decision log

- [ ] **Modify** `design/decisions/log.md`
- **Key points:**
  - Verify D-049 through D-054 are recorded (QUALITY line, deep scan timing, structural evolution, minimal fixtures, WARNING gate, config reconciliation)
  - These decisions were made during spec authoring and must be logged before implementation per D-018
- **Commit:** `moira(design): record Phase 6 architectural decisions D-049 through D-054`

**Note:** D-049 through D-054 have already been added to the decision log during review. This task is a verification step — confirm they are present and accurate.

---

## Chunk 1: Schema & Config Foundations

**Dependencies:** Chunk 0 (decisions verified)

### Task 1.1: Create findings schema

- [ ] **Create** `src/schemas/findings.schema.yaml`
- **Source:** Spec D1 (Quality Findings Schema)
- **Key points:**
  - Fields: `_meta` (task_id, gate, agent, timestamp, mode), `checklist.items[]` (id, check, result, severity, detail, evidence), `summary` (total, passed, failed, na, critical_count, warning_count, suggestion_count, verdict)
  - `result` enum: pass, fail, na, skip
  - `severity` enum: critical, warning, suggestion
  - `verdict` enum: pass, fail_critical, fail_warning
  - Verdict derivation: critical_count > 0 → fail_critical; warning_count > 0 → fail_warning; else → pass
- **Commit:** `moira(quality): add findings schema for quality gate results`

### Task 1.2: Update config schema for quality mode

- [ ] **Modify** `src/schemas/config.schema.yaml`
- **Source:** Spec D6a (Config Schema Update), D-054 (Config reconciliation)
- **Key points:**
  - `quality.mode` already exists (conform/evolve enum) — verify, no change needed
  - Replace `quality.evolution_threshold` and `quality.review_severity_minimum` with:
    - `quality.evolution.current_target` (string, default: "")
    - `quality.evolution.cooldown_remaining` (number, default: 0)
  - Rationale per D-054: evolution_threshold superseded by Art 5.2 hardcoded 3-observation rule; review_severity_minimum superseded by fixed severity routing (Art 2.1)
  - All fields optional with defaults
- **Note:** This schema change was already applied during pre-implementation review. Verify it matches spec D6a.
- **Commit:** `moira(quality): reconcile config schema quality fields for Phase 6 (D-054)`

### Task 1.3: Update response contract

- [ ] **Modify** `src/global/core/response-contract.yaml`
- **Source:** Spec D12 (Updated Response Contract)
- **Key points:**
  - Add `quality_response` section for agents with quality gates
  - Add QUALITY line format: `QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)`
  - Include example showing the QUALITY line in a full response
  - This is ADDITIONAL to the existing contract, not replacing it
- **Commit:** `moira(quality): add QUALITY line to agent response contract`

---

## Chunk 2: Quality Library

**Dependencies:** Chunk 1 (uses findings schema)

### Task 2.1: Create quality.sh

- [ ] **Create** `src/global/lib/quality.sh`
- **Source:** Spec D4 (Quality Findings Validator)
- **Key points:**
  - Source `yaml-utils.sh` for YAML parsing
  - `moira_quality_parse_verdict <findings_path>`:
    - Read `summary.critical_count` and `summary.warning_count` from findings YAML
    - If critical_count > 0 → echo "fail_critical"
    - If warning_count > 0 → echo "fail_warning"
    - Else → echo "pass"
    - Return 0 on success, 1 if file not found or parse error
  - `moira_quality_validate_findings <findings_path> <gate_checklist_path>`:
    - Load checklist item IDs from Q* YAML (items where required=true)
    - Load findings item IDs from findings YAML
    - Check every required item has a finding entry
    - Echo missing item IDs if any, return 1
    - Return 0 if all present
  - `moira_quality_aggregate_task <task_dir>`:
    - Scan `findings/` directory for `*-Q*.yaml` files
    - Aggregate: per-gate verdicts, total findings by severity, overall verdict
    - Write `findings/summary.yaml`
  - `moira_quality_format_warnings <findings_path>`:
    - Read items where severity=warning
    - Format each as: `⚠ {id}: {check}\n  Detail: {detail}\n  Evidence: {evidence}`
    - Echo formatted string
  - All functions follow existing lib conventions (moira_ prefix, return codes, stderr for errors)
- **Commit:** `moira(quality): implement quality findings validator library`

---

## Chunk 3: Dispatch Updates

**Dependencies:** Chunk 2 (quality.sh exists), Chunk 1 (response contract updated)

### Task 3.1: Update dispatch.md with quality checklist injection

- [ ] **Modify** `src/global/skills/dispatch.md`
- **Source:** Spec D2 (Quality Enforcement in Agent Dispatch)
- **Key points:**
  - Add section "Quality Checklist Injection" — for agents with quality gates, append checklist to prompt
  - Agent-to-gate mapping table: Athena→Q1, Metis→Q2, Daedalus→Q3, Themis→Q4, Aletheia→Q5
  - Checklist items loaded from `~/.claude/moira/core/rules/quality/q{N}-*.yaml`
  - Append explicit instructions: evaluate every item, write findings to `findings/{agent}-{gate}.yaml`
  - Include anti-skip directive: "Do not skip items. Do not mark as pass without verifying."
  - Pre-planning agents (Athena Q1): inject via simplified assembly path
  - Post-planning agents (Metis Q2, Daedalus Q3, Themis Q4, Aletheia Q5): inject via instruction files
  - Add section "Quality Map Injection" — include quality-map/summary.md in relevant agent instructions
  - Agents that receive quality map: Metis (L1), Themis (L1), Daedalus (L0)
  - Add section "Quality Mode Communication" — include CONFORM/EVOLVE mode in assembled instructions
  - Template for mode section per spec D6b
- **Commit:** `moira(quality): add quality checklist and quality map injection to dispatch`

---

## Chunk 4: Orchestrator Updates

**Dependencies:** Chunk 2 (quality.sh for verdict parsing), Chunk 1 (config schema for quality mode)

### Task 4.1: Add quality gate routing to orchestrator

- [ ] **Modify** `src/global/skills/orchestrator.md`
- **Source:** Spec D3 (Quality Gate Routing), D9 (Updated Orchestrator)
- **Key points:**
  - After Section 2 main loop step (e), add quality gate check:
    - If agent has associated quality gate (Athena/Q1, Metis/Q2, Daedalus/Q3, Themis/Q4, Aletheia/Q5):
    - Read QUALITY line from agent response summary
    - Route by verdict: pass → proceed, fail_critical → E5-QUALITY retry, fail_warning → WARNING gate
  - Add bench mode check: at each gate, if `current.yaml` has `bench_mode: true`:
    - Read gate responses from test case file path (stored in `current.yaml` as `bench_test_case`)
    - Auto-respond with predefined response
    - Record in state as normal
  - Add quality mode read: at pipeline start, read `config.yaml` → `quality.mode` and store for dispatch
  - Complete deep scan implementation: replace "NOTE: not yet implemented" stub in Section 2 Bootstrap Deep Scan Check with actual dispatch of 4 deep scan Explorer agents in background
- **Commit:** `moira(quality): add quality gate routing and bench mode to orchestrator`

### Task 4.2: Add WARNING gate to gates.md

- [ ] **Modify** `src/global/skills/gates.md`
- **Source:** Spec D3 (WARNING gate), D10 (Updated Gates)
- **Key points:**
  - Add new section "Quality Warning Gate" between existing "Final Gate" and "Error/Blocked Gates" sections
  - Template per spec D3: shows warning findings with severity, detail, evidence
  - Options: proceed (accept warnings), fix (send back to implementer), details (full findings), abort
  - Gate state: map `proceed` → `proceed`, `fix` → `modify`, `abort` → `abort`
  - Agent naming: "Themis (reviewer)" format per D-034
- **Commit:** `moira(quality): add quality warning gate template`

---

## Chunk 5: Deep Scan Templates

**Dependencies:** None (parallel with Chunks 3-4, only needs Phase 5 scanner pattern)

### Task 5.1: Create deep scan agent instructions

- [ ] **Create** `src/global/templates/scanners/deep/deep-architecture-scan.md`
- [ ] **Create** `src/global/templates/scanners/deep/deep-dependency-scan.md`
- [ ] **Create** `src/global/templates/scanners/deep/deep-test-coverage-scan.md`
- [ ] **Create** `src/global/templates/scanners/deep/deep-security-scan.md`
- **Source:** Spec D8 (Deep Scan Agent Instructions), Phase 5 scanner template pattern
- **Key points:**
  - Follow exact same structure as Phase 5 quick scan templates (Objective, Scan Strategy, Output Format, Output Path, Constraints)
  - Agent: Hermes (explorer) — same role, different L4 instructions
  - Deep scans are MORE comprehensive: up to 50 files per scan (vs 25-30 quick)
  - Output enhances existing knowledge (append/extend, not replace)
  - Include Explorer NEVER constraints in each template
  - **Architecture scan:** Service boundaries, dependency graph, data flow paths, external integrations, API contracts
  - **Dependency scan:** Package versions, outdated packages (check dates), unused imports (scan for imports not referenced), circular dependencies (import chains)
  - **Test coverage scan:** Test file mapping (which tests cover which source files), untested files, test quality observations (brittle tests, missing assertions)
  - **Security scan:** Hardcoded strings that look like secrets (API keys, tokens, passwords), input validation gaps at system boundaries, auth middleware coverage, unsafe patterns (eval, exec, dangerouslySetInnerHTML)
  - Output paths: update existing `knowledge/{type}/full.md` files — prepend "Deep scan additions" section
- **Commit:** `moira(quality): add deep scan agent instruction templates`

---

## Chunk 6: Quality Map + CONFORM/EVOLVE

**Dependencies:** Chunk 2 (quality.sh), Chunk 3 (dispatch includes quality map injection)

### Task 6.1: Enhance quality map generation in bootstrap

- [ ] **Modify** `src/global/lib/bootstrap.sh`
- **Source:** Spec D5b (Quality Map Generator in Bootstrap)
- **Key points:**
  - Enhance existing `moira_bootstrap_populate_knowledge` function
  - Quality map generation from pattern scanner results:
    - Consistent patterns across multiple files → ✅ Strong (medium confidence)
    - Inconsistent patterns → ⚠️ Adequate (medium confidence)
    - Obvious issues noted → 🔴 Problematic (medium confidence)
  - Quality map format per spec D5a: category, location, evidence, confidence, example
  - All entries marked `medium` confidence (from scan, not task evidence)
  - Freshness marker: `<!-- moira:freshness init {date} -->`
  - Preliminary marker: `<!-- moira:preliminary — deep scan required -->`

### Task 6.2: Add quality map evolution to knowledge.sh

- [ ] **Modify** `src/global/lib/knowledge.sh`
- **Source:** Spec D5c (Quality Map Evolution)
- **Key points:**
  - Add function `moira_knowledge_update_quality_map <task_dir> <quality_map_dir>`:
    - Read `findings/themis-Q4.yaml` (Reviewer findings)
    - For each finding: check if it matches an existing quality map entry (keyword match on pattern name + location)
    - If match: increment observation_count
    - If new: add entry with observation_count=1, tag "🆕 NEW"
    - Confidence upgrade: observation_count reaches 3 → confidence from `medium` to `high`
    - Category transitions per spec D5c rules
    - Update quality-map/full.md and quality-map/summary.md
    - Update freshness marker
  - This is STRUCTURAL (keyword matching, counting) — not semantic analysis
  - Evolution lifecycle tags: 🆕 NEW (1 obs), ⚠️ CONFIRMED (2 obs), 📊 MEASURED (3+ obs)

### Task 6.3: Add CONFORM/EVOLVE mode handling

- [ ] **Modify** `src/global/lib/quality.sh` (add mode functions)
- **Source:** Spec D6 (CONFORM/EVOLVE Mode)
- **Key points:**
  - Add function `moira_quality_get_mode <config_path>`:
    - Read `quality.mode` from config.yaml
    - Default: "conform" if field not present
  - Add function `moira_quality_check_cooldown <config_path>`:
    - Read `quality.evolution.cooldown_remaining`
    - If > 0: echo "cooldown {N}" — system is in post-evolution cooldown
    - If 0: echo "ready"
  - Add function `moira_quality_start_evolve <config_path> <target_pattern>`:
    - Check cooldown is 0
    - Set `quality.mode` to "evolve"
    - Set `quality.evolution.current_target` to target pattern
    - Return 0 on success, 1 if cooldown active
  - Add function `moira_quality_complete_evolve <config_path>`:
    - Set `quality.mode` to "conform"
    - Set `quality.evolution.current_target` to ""
    - Set `quality.evolution.cooldown_remaining` to 5
  - Add function `moira_quality_tick_cooldown <config_path>`:
    - Read cooldown_remaining
    - If > 0: decrement by 1, write back
    - Called after each task completion (from orchestrator completion flow)

- **Commit for 6.1+6.2+6.3:** `moira(quality): implement quality map system and CONFORM/EVOLVE mode`

---

## Chunk 7: Bench Infrastructure

**Dependencies:** Chunk 4 (orchestrator bench mode support), Chunk 1 (schemas)

### Task 7.1: Create fixture projects

- [ ] **Create** `src/tests/bench/fixtures/greenfield-webapp/` — minimal Express+TS app
- [ ] **Create** `src/tests/bench/fixtures/mature-webapp/` — consistent Express+TS+Prisma app
- [ ] **Create** `src/tests/bench/fixtures/legacy-webapp/` — inconsistent Express+JS/TS app
- **Source:** Spec D7a (Fixture Projects)
- **Key points:**
  - **greenfield-webapp:** package.json, tsconfig.json, src/index.ts (Express server), src/routes/health.ts (one endpoint), src/types/index.ts, tests/health.test.ts. 5-6 files total. Jest config.
  - **mature-webapp:** Express+TS+Prisma. Directories: src/routes/, src/services/, src/types/, src/middleware/, prisma/. 3-4 API endpoints (users, products, health). Service layer with repository pattern. Error handling middleware. Jest tests with consistent patterns. .eslintrc, .prettierrc. 20-25 files.
  - **legacy-webapp:** Express, mixed JS/TS. Some routes use controller pattern, others inline handlers. Inconsistent naming (some camelCase files, some kebab-case). Tests scattered: some in `__tests__/`, some `.test.js` co-located, some missing. No linting config. Some TODO/FIXME comments. 30-40 files.
  - Each fixture: git init, create `clean` branch, `.moira-fixture.yaml` descriptor
  - Keep fixtures MINIMAL — they test pipeline behavior, not codebase handling
- **Commit:** `moira(quality): create behavioral bench fixture projects`

### Task 7.2: Create test cases

- [ ] **Create** `src/tests/bench/cases/quick-bugfix-mature-001.yaml`
- [ ] **Create** `src/tests/bench/cases/std-feature-mature-001.yaml`
- [ ] **Create** `src/tests/bench/cases/std-feature-greenfield-001.yaml`
- [ ] **Create** `src/tests/bench/cases/std-refactor-legacy-001.yaml`
- [ ] **Create** `src/tests/bench/cases/quick-bugfix-legacy-001.yaml`
- **Source:** Spec D7b (Test Case Format), testing.md test case format
- **Key points:**
  - Follow testing.md format: meta, fixture, task, gate_responses, expected_structural, expected_quality
  - `quick-bugfix-mature-001`: Fix a broken API response format in mature webapp. Size: small, confidence: high → Quick Pipeline. Gate responses: classification=proceed, final=done. Expected: quick pipeline, 4 agents (apollo, hermes, hephaestus, themis), 2 gates.
  - `std-feature-mature-001`: Add paginated GET /api/products endpoint. Size: medium → Standard Pipeline. Gate responses: all proceed. Expected: standard pipeline, 8 agents (apollo, hermes, athena, metis, daedalus, hephaestus, themis, aletheia), 4 gates.
  - `std-feature-greenfield-001`: Add user registration endpoint. Size: medium → Standard. Expected: standard pipeline, 8 agents, handles empty project gracefully.
  - `std-refactor-legacy-001`: Extract inline route handler to service pattern. Size: medium → Standard. Expected: standard pipeline, 8 agents, reviewer should flag inconsistency with existing patterns.
  - `quick-bugfix-legacy-001`: Fix broken import path. Size: small, high confidence → Quick. Expected: quick pipeline.
  - `expected_quality`: set minimum_scores but mark as `judge: null` (no LLM-judge in Phase 6)
- **Commit:** `moira(quality): create initial behavioral bench test cases`

### Task 7.3: Create bench rubric definitions

- [ ] **Create** `src/tests/bench/rubrics/feature-implementation.yaml`
- [ ] **Create** `src/tests/bench/rubrics/bugfix-quality.yaml`
- [ ] **Create** `src/tests/bench/rubrics/refactor-quality.yaml`
- **Source:** Spec D7d (Bench Rubric Definitions), testing.md rubric structure
- **Key points:**
  - `feature-implementation.yaml`: 4 criteria (requirements_coverage:25, code_correctness:30, architecture_quality:25, conventions_adherence:20), 5-point scale with anchored examples per testing.md
  - `bugfix-quality.yaml`: Adjusted weights (code_correctness:40, requirements_coverage:25, conventions_adherence:20, architecture_quality:15). Anchors specific to bugfix context.
  - `refactor-quality.yaml`: Adjusted weights (conventions_adherence:30, architecture_quality:30, code_correctness:25, requirements_coverage:15). Anchors specific to refactoring.
  - These are DATA DEFINITIONS only — no judge invocation code
  - Full anchored examples per score level (1-5) with concrete descriptions
- **Commit:** `moira(quality): create bench evaluation rubric definitions`

### Task 7.4: Create bench runner library

- [ ] **Create** `src/global/lib/bench.sh`
- **Source:** Spec D7c (Bench Runner)
- **Key points:**
  - `moira_bench_run <test_case_path>`:
    - Read test case YAML
    - Resolve fixture path
    - Reset fixture: run `reset_command` from `.moira-fixture.yaml`
    - Verify clean state: `git status --porcelain` == empty
    - Set bench_mode in current.yaml: `bench_mode: true`, `bench_test_case: {path}`
    - Execute task through Moira pipeline (dispatch via orchestrator with test case task description)
    - After completion: check automated results (compile, lint, test pass/fail)
    - Record results YAML: test_id, fixture, pipeline_type, agents_called, gates_triggered, automated_checks (compile/lint/tests), duration
    - Write to `bench/results/run-{NNN}/{test_case_id}.yaml`
    - Clear bench_mode from current.yaml
  - `moira_bench_run_tier <tier> [filter]`:
    - Tier 1: delegate to existing `run-all.sh`
    - Tier 2: find test cases matching filter tags, run sequentially per fixture
    - Tier 3: run all test cases, sequential per fixture
    - Progress display: per-test status line
  - `moira_bench_report <run_dir>`:
    - Aggregate per-test results
    - Compute pass rates (structural, automated)
    - Quality scores: null (no judge)
    - Write `summary.yaml` with timestamp, tier, test_count, pass_count, automated_pass_count
  - Budget guards: max test count per tier (tier_2: 5, tier_3: 30). Warn at 80%, abort at limit with prompt.
- **Commit:** `moira(quality): implement bench runner library`

### Task 7.5: Create bench command

- [ ] **Create** `src/commands/moira/bench.md`
- **Source:** Spec D7e (Bench Command)
- **Key points:**
  - Frontmatter: name: moira:bench, allowed-tools: [Agent, Read, Write, Bash]
  - Parse argument: tier1, tier2, tier3, report, compare, or no args
  - No args: auto-detect tier from git diff (scan changed files, match against trigger matrix from testing.md), suggest tests, ask user
  - tier1/tier2/tier3: run corresponding tier via bench.sh
  - report: display latest bench results summary
  - compare: compare two run directories (structural metrics only)
  - Display formatted results per testing.md UX guidelines
- **Commit:** `moira(quality): add /moira:bench command`

---

## Chunk 8: Tests & Installation

**Dependencies:** All previous chunks

### Task 8.1: Create quality system tests

- [ ] **Create** `src/tests/tier1/test-quality-system.sh`
- **Source:** Spec D13 (Tier 1 Test Additions)
- **Key points:**
  - Quality schema tests: findings.schema.yaml exists, has required fields, valid enums
  - Quality enforcement tests: quality.sh exists, functions present, dispatch.md has checklist injection, response-contract.yaml has QUALITY line
  - CONFORM/EVOLVE tests: config.schema.yaml has quality.mode enum, evolution fields exist
  - Quality map tests: knowledge template files follow schema structure
  - Bench infrastructure tests: 3+ fixture dirs, each has .moira-fixture.yaml, 5+ test cases, rubric files exist, bench.sh exists
  - Deep scan tests: 4 templates exist, each has required sections, Explorer constraints present
  - Follow existing test file conventions (test count, pass/fail reporting, error messages)
- **Commit:** `moira(quality): add Tier 1 tests for quality system`

### Task 8.2: Update existing tests

- [ ] **Modify** `src/tests/tier1/test-file-structure.sh`
- [ ] **Modify** `src/tests/tier1/test-install.sh`
- **Key points:**
  - test-file-structure.sh: add checks for findings schema, quality.sh, bench directories, deep scan templates, bench.md command
  - test-install.sh: add verification for Phase 6 artifacts (quality.sh, bench.sh, deep scan templates, bench fixtures/cases/rubrics)

### Task 8.3: Update install.sh

- [ ] **Modify** `src/install.sh`
- **Source:** Spec D14 (Updated install.sh)
- **Key points:**
  - New copy operations: quality.sh, bench.sh, deep scan templates, bench fixtures/cases/rubrics, findings schema, bench command
  - New verification checks: quality.sh syntax, bench.sh syntax, deep scan template count, fixture count, test case count
  - Follow existing install.sh patterns for copy and verify

### Task 8.4: Update run-all.sh

- [ ] **Modify** `src/tests/tier1/run-all.sh`
- **Source:** Spec D15
- **Key points:**
  - Add `test-quality-system.sh` to the test runner

- **Commit for 8.1+8.2+8.3+8.4:** `moira(quality): update tests and install for Phase 6`

---

## Execution Order Summary

| Order | Chunk | Tasks | Commit Scope |
|-------|-------|-------|-------------|
| 0 | Pre-Implementation | 0.1 | 1 commit (verify decisions) |
| 1 | Schema + Config | 1.1, 1.2, 1.3 | 3 commits |
| 2 | Quality Library | 2.1 | 1 commit |
| 3a | Dispatch Updates | 3.1 | 1 commit (parallel with 3b, 3c) |
| 3b | Orchestrator Updates | 4.1, 4.2 | 2 commits (parallel with 3a, 3c) |
| 3c | Deep Scan Templates | 5.1 | 1 commit (parallel with 3a, 3b) |
| 4 | Quality Map + Mode | 6.1, 6.2, 6.3 | 1 commit |
| 5 | Bench Infrastructure | 7.1, 7.2, 7.3, 7.4, 7.5 | 5 commits |
| 6 | Tests + Install | 8.1, 8.2, 8.3, 8.4 | 1 commit |

**Total: 16 commits, 9 chunks**

Run Tier 1 tests after each chunk to verify no regressions.

Final verification: all Tier 1 tests pass (existing + new), constitutional compliance checklist from spec verified.
