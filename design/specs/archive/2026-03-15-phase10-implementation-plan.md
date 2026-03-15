# Phase 10: Reflection Engine & LLM-Judge — Implementation Plan

**Spec:** `design/specs/2026-03-15-phase10-reflection-engine.md`
**Date:** 2026-03-15

## Overview

14 deliverables + 16 ripple effect updates, organized into 7 chunks with explicit dependencies. 24 tasks, 8 commits.

---

## Chunk 1: Decision Log + Design Doc Updates (prerequisite)

No code changes. Updates design docs per Art 6.2 — design docs must be authoritative before implementation.

### Task 1.1: Add D-086 through D-092 to decision log
- **File:** `design/decisions/log.md`
- **Source:** Spec section "Architectural Decisions" (AD-1 through AD-7)
- **What:** Add 7 new decision entries in standard format (Context, Decision, Alternatives rejected, Reasoning)
  - D-086: Observations in Task State Files (Not Separate Database)
  - D-087: Judge as Agent Tool Call (Not Direct API)
  - D-088: Three Rubric Variants by Task Category
  - D-089: Pattern Key Registry for Efficient Cross-Task Counting
  - D-090: `/moira health` as Separate Command (Not Bench Subcommand)
  - D-091: Libraries Knowledge Access Matrix
  - D-092: Periodic Deep Reflection Every 5 Tasks
- **Commit:** `moira(design): add D-086 through D-092 reflection engine decisions`

### Task 1.2: Update design docs
- **Files:**
  - `design/architecture/overview.md` — add `reflection.sh`, `judge.sh` to lib/ list; add `templates/reflection/`, `templates/judge/` to templates listing; add `state/reflection/` to state directory listing
- **Source:** Spec "Ripple Effect Updates" item 16
- **Commit:** `moira(design): update overview.md for phase 10`

**Dependency:** None. Must complete before all other chunks.

---

## Chunk 2: Foundation Libraries + Templates (new files only)

Creates all new files that other chunks depend on. No modifications to existing files.

### Task 2.1: Create reflection library
- **File:** `src/global/lib/reflection.sh` (NEW)
- **Source:** Spec D1, D5c
- **What:** 9 functions:
  - `moira_reflection_task_history <state_dir> [count]` — scan `state/tasks/*/status.yaml` for completed tasks, return last N (default 10) sorted by completion time. Output: task_id, pipeline_type, first_pass_accepted, retry_count, classification_correct
  - `moira_reflection_observation_count <state_dir> <pattern_key>` — scan `state/tasks/*/reflection.md` for `OBSERVATION: [pattern_key:` lines matching key. Return integer count
  - `moira_reflection_get_observations <state_dir> <pattern_key>` — return task_id, observation text, evidence per match
  - `moira_reflection_mcp_call_frequency <state_dir>` — scan `state/tasks/*/telemetry.yaml` → `mcp_calls[]`. Aggregate by server:tool:query_summary. Return entries with 3+ occurrences
  - `moira_reflection_pending_proposals <state_dir>` — read `state/reflection/proposals.yaml`, return status=pending entries
  - `moira_reflection_record_proposal <state_dir> <proposal_yaml>` — append to `state/reflection/proposals.yaml`, set status=pending
  - `moira_reflection_resolve_proposal <state_dir> <proposal_id> <resolution>` — update proposal status (approved/rejected/deferred)
  - `moira_reflection_deep_counter <state_dir> [increment|reset]` — read/increment/reset `state/reflection/deep-reflection-counter.yaml`. Returns current count. Used for periodic escalation (D-092)
  - `moira_reflection_auto_defer_stale <state_dir>` — scan proposals.yaml for pending entries with `created` older than 30 days, set status=deferred. Called by reflection skill before presenting proposals (spec D5c)
- **Key points:**
  - Source `yaml-utils.sh` (same pattern as other libs)
  - All functions prefixed `moira_reflection_`
  - `moira_reflection_task_history` uses `moira_yaml_get` on each `status.yaml` to extract completion fields
  - `moira_reflection_mcp_call_frequency` requires `mcp_calls` section in telemetry (D6d, Chunk 3)
  - `mkdir -p` defensively for `state/reflection/` in proposal/counter functions (scaffold.sh also creates it)

### Task 2.2: Create judge library
- **File:** `src/global/lib/judge.sh` (NEW)
- **Source:** Spec D7
- **What:** 4 functions:
  - `moira_judge_invoke <task_dir> <rubric_path> [model_tier]` — construct judge prompt from template + task artifacts + rubric, output the assembled prompt to stdout for the caller (orchestrator/bench) to dispatch via Agent tool. Write evaluation result to `task_dir/judge-evaluation.yaml`. Return 0/1
  - `moira_judge_composite_score <evaluation_path> [automated_pass]` — read scores, apply weights (req=25, code=30, arch=25, conv=20), return 1-5 composite. If `automated_pass=false`, set a `quality_capped: true` flag in output
  - `moira_judge_normalize_score <score_1_5>` — `(score - 1) * 25`, return 0-100 integer
  - `moira_judge_calibrate <calibration_dir> <rubric_path>` — run judge on each calibration example, compare vs expected scores (±1 tolerance), return 0 if all pass
- **Key points:**
  - Source `yaml-utils.sh`
  - `moira_judge_invoke` assembles the prompt text from `templates/judge/judge-prompt.md` by substituting task artifacts. The actual Agent tool dispatch is done by the CALLER (orchestrator or bench runner) — judge.sh only prepares the prompt and parses the result
  - Judge model tier is passed through to the caller for Agent tool `model` parameter
  - Automated pass cap per testing.md: if `automated_pass=false`, normalized score capped at 20

### Task 2.3: Create reflection templates
- **Files:** (all NEW)
  - `src/global/templates/reflection/lightweight.md`
  - `src/global/templates/reflection/standard.md`
  - `src/global/templates/reflection/deep.md`
  - `src/global/templates/reflection/epic.md`
- **Source:** Spec D2a-D2d
- **What:**
  - **lightweight.md** — Template text for the minimal note the orchestrator writes directly. Contains placeholders: `{task_id}`, `{pipeline_type}`, `{final_gate_action}`, `{retry_count}`, `{budget_pct}`
  - **standard.md** — Full Mnemosyne instruction template. Sections: context loading (list of task artifacts), 6-dimension analysis instructions, knowledge update instructions using `moira_knowledge_write`, evidence tracking with `OBSERVATION: [pattern_key:...]` format, rule proposal check (call `moira_reflection_observation_count`, propose if 3+), MCP caching check (call `moira_reflection_mcp_call_frequency`, propose if 3+), exit criteria reminder (5 minimum output items)
  - **deep.md** — Extends standard with: cross-task pattern analysis (read last 5-10 reflections), knowledge freshness audit, quality trend analysis, evolution readiness assessment
  - **epic.md** — Extends deep with: subtask coherence check, cross-subtask duplication analysis, decomposition quality assessment, integration gap analysis
- **Key points:**
  - Templates are markdown instruction files — they tell Mnemosyne WHAT to do, not executable code
  - Standard template must include the observation tagging format: `OBSERVATION: [pattern_key:name] description\n  EVIDENCE: task-{id} artifact.md line N`
  - Include Mnemosyne's behavioral defense role instructions (systemic drift detection, constraint degradation per agents.md)

### Task 2.4: Create judge prompt template
- **File:** `src/global/templates/judge/judge-prompt.md` (NEW)
- **Source:** Spec D8
- **What:** Template with placeholders for: task context (from input.md), requirements, architecture, implementation artifacts, review findings, test results, rubric criteria with anchored examples, output format (YAML per testing.md lines 627-653)
- **Key points:**
  - Placeholder format: `{task_description}`, `{requirements}`, `{architecture}`, etc.
  - Include explicit instruction: "Return ONLY valid YAML"
  - Include judge independence note: "You are NOT part of the pipeline. You evaluate AFTER the fact."

### Task 2.5: Create/update rubric files
- **Files:**
  - `src/tests/bench/rubrics/feature-implementation.yaml` (EXISTS — update with anchored examples)
  - `src/tests/bench/rubrics/bugfix-quality.yaml` → RENAME to `bugfix.yaml` (simpler name, matches test case `meta.category` values)
  - `src/tests/bench/rubrics/refactor-quality.yaml` → RENAME to `refactor.yaml` (same rationale)
- **Source:** Spec D9a-D9c
- **What:** Update/create YAML files with criteria structure per testing.md lines 586-623:
  - Each criterion: `id`, `name`, `weight`, `scale: [1,2,3,4,5]`, `anchors` (per-score label + description + concrete example)
  - **feature-implementation.yaml** (MODIFY existing): add anchored examples to existing criteria. Weights: req=25, code=30, arch=25, conv=20. Anchors from testing.md
  - **bugfix.yaml** (RENAME + MODIFY): req=20, code=40, arch=15, conv=25. Anchors adjusted for bugfix context
  - **refactor.yaml** (RENAME + MODIFY): req=15, code=30, arch=35, conv=20. Anchors adjusted for refactor context
- **Key points:**
  - Anchor text must be concrete enough for judge calibration stability. Each anchor level (1-5) should have a one-word label, 1-sentence description, and 1 concrete example
  - After rename, verify no other files reference the old names (`bugfix-quality.yaml`, `refactor-quality.yaml`). bench.sh currently does not reference rubrics by name (quality_scores=null), so no breakage expected

### Task 2.6: Create calibration examples
- **Files:** (all NEW, directories with mock artifacts)
  - `src/tests/bench/calibration/good-implementation/` — mock input.md, requirements.md, architecture.md, implementation.md, review.md, test-results.md
  - `src/tests/bench/calibration/mediocre-implementation/` — same files, lower quality
  - `src/tests/bench/calibration/poor-implementation/` — same files, poor quality
- **Source:** Spec D10a
- **What:** Each directory contains 6 mock task artifacts simulating a completed task. Expected scores stored in `expected.yaml` per directory:
  - good: {req: 4, code: 4, arch: 4, conv: 4, tolerance: 1}
  - mediocre: {req: 3, code: 2, arch: 3, conv: 3, tolerance: 1}
  - poor: {req: 2, code: 1, arch: 2, conv: 2, tolerance: 1}
- **Key points:**
  - Artifacts should be realistic enough for judge evaluation but minimal (not full project code)
  - Good implementation: clean structure, all requirements met, proper tests
  - Mediocre: works but messy, partial tests, some requirements missed
  - Poor: missing requirements, runtime errors, no structure, no tests

**Commit:** `moira(reflection): add reflection and judge foundation libraries and templates`

**Dependency:** Chunk 1 must be complete (design docs updated).

---

## Chunk 3: Knowledge + Telemetry Integration (existing file modifications)

Updates existing systems to support Phase 10 features.

### Task 3.1: Update knowledge.sh — add libraries type
- **File:** `src/global/lib/knowledge.sh`
- **Source:** Spec D6a
- **What:**
  - Line 17: Add `libraries` to `_MOIRA_KNOWLEDGE_TYPES`: `"project-model conventions decisions patterns failures quality-map libraries"`
  - Update the comment on line 16 to note libraries is now included
  - Line 85 in `moira_knowledge_read_for_agent`: Add `libraries` to the hardcoded `dimensions` variable: `"project_model conventions decisions patterns quality_map failures libraries"`
  - Handle L2 special case: In `moira_knowledge_read`, when type is `libraries` and level is `L2`, return empty (not error) — libraries L2 means individual per-library files, not a single full.md. For `moira_knowledge_read_for_agent`, libraries at L2 loads `summary.md` (L1 content) as best available aggregate.
  - Add new helper function `moira_knowledge_read_library <knowledge_dir> <library_name>` — reads individual library file at `knowledge/libraries/{library_name}.md`. Returns content or empty if not found.
  - Add `moira_reflection_auto_defer_stale` — scan proposals.yaml for pending entries older than 30 days, set status=deferred (spec D5c)
- **Key points:**
  - `moira_knowledge_read_for_agent` will now include libraries data for agents that have access per matrix
  - The L2 special handling ensures no "file not found" errors when the standard path tries to read `libraries/full.md`

### Task 3.2: Update knowledge-access-matrix.yaml
- **File:** `src/global/core/knowledge-access-matrix.yaml`
- **Source:** Spec D6a, AD-6 (→D-091)
- **What:** Add `libraries` dimension to every agent row in both read_access and write_access:
  - read_access: apollo=null, hermes=null, athena=null, metis=null, daedalus=L0, hephaestus=L1, themis=null, aletheia=null, mnemosyne=L2, argus=L2
  - write_access: mnemosyne: libraries=true. All others: libraries=false or not listed

### Task 3.3: Update telemetry.schema.yaml — add mcp_calls section
- **File:** `src/schemas/telemetry.schema.yaml`
- **Source:** Spec D6d
- **What:** Add `mcp_calls` section at the end:
  ```yaml
  mcp_calls:
    type: list
    required: false
    description: "MCP tool calls made during this task"
    item_schema:
      server: { type: string, required: true }
      tool: { type: string, required: true }
      query_summary: { type: string, required: true, description: "Sanitized query pattern (privacy per D-027)" }
      tokens_used: { type: number, required: true }
      agent: { type: string, required: true }
  ```
- **Key point:** `required: false` — tasks without MCP calls have no `mcp_calls` section

### Task 3.4: Update scaffold.sh — add state/reflection/ directory
- **File:** `src/global/lib/scaffold.sh`
- **Source:** Spec ripple effect item 14
- **What:** Add `mkdir -p "$base"/state/reflection` after the existing `state/audits` directory creation

**Commit:** `moira(reflection): integrate libraries knowledge type and MCP telemetry`

**Dependency:** Chunk 1 (design docs). Chunk 2 NOT required — these are independent modifications.

---

## Chunk 4: Reflection Engine (skill + evidence + proposals + MCP caching)

Wires the reflection system together.

### Task 4.1: Create reflection dispatch skill
- **File:** `src/global/skills/reflection.md` (NEW)
- **Source:** Spec D3
- **What:** Skill document with sections:
  1. **Level determination:** Read `post: reflection:` from pipeline YAML. Check periodic escalation counter (`moira_reflection_deep_counter`): if counter >= 5 and level is `background` → escalate to `deep`, reset counter. Otherwise increment counter.
  2. **Lightweight handling:** Write minimal note to `state/tasks/{id}/reflection.md` using lightweight.md template. No agent dispatch.
  3. **Prompt assembly for background/deep/epic:**
     - Load appropriate template from `templates/reflection/`
     - Assemble knowledge context: all types at L2 (per Mnemosyne access matrix)
     - Include task artifact list: `state/tasks/{id}/*.md` paths
     - Include `moira_reflection_task_history` output (last 5-10 tasks)
     - Include pending observations from `state/reflection/pattern-keys.yaml`
  4. **Dispatch mode:** background=background agent, deep/epic=foreground agent
  5. **Post-reflection processing:**
     - Parse KNOWLEDGE_UPDATES → `moira_knowledge_validate_consistency` then `moira_knowledge_write` for each
     - Parse RULE_PROPOSALS → `moira_reflection_record_proposal` for each
     - If proposals exist: display non-blocking notification with approve/defer/reject/details options
     - Parse MCP caching recommendations → display cache/ignore prompt
     - Update `state/reflection/pattern-keys.yaml` from new observations
- **Key points:**
  - Skill is consumed by orchestrator's Section 7 Completion Flow
  - Non-blocking proposals: display and continue, don't wait for user response at this point. User can respond later via `/moira:proposals` or when next seen
  - Post-processing happens in orchestrator context after Mnemosyne returns
  - Anti-chaos safeguards (D5): check `config.yaml` `quality.evolution.cooldown_remaining` before presenting proposals. If in cooldown, accumulate but don't present.

### Task 4.2: Update orchestrator.md — reflection skill reference + mcp_calls telemetry write
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec ripple effect item 12, spec D6d
- **What:**
  1. In Section 7 (Completion Flow), after the Reflection Dispatch table (lines 303-310), add:
     ```
     **Reference:** `reflection.md` skill for full dispatch instructions, prompt assembly,
     periodic escalation, and post-reflection processing (knowledge updates, rule proposals,
     MCP caching recommendations).
     ```
  2. In Section 7 Completion Flow `done` action (near line 291 where telemetry is written), add `mcp_calls` population logic:
     - If MCP was enabled for this task: extract MCP call data from Planner's instruction files (authorized MCP tools) and Reviewer's MCP verification findings
     - Write `mcp_calls[]` entries to `telemetry.yaml` with: server, tool, query_summary (sanitized per D-027), tokens_used, agent
     - If no MCP calls: omit `mcp_calls` section (field is `required: false` in schema)
- **Key point:** Without this write logic, `moira_reflection_mcp_call_frequency` in reflection.sh would never find data. This is the critical bridge between MCP usage (Phases 3/9) and MCP caching detection (Phase 10).

### Task 4.3: Update dispatch.md — Mnemosyne alternative path note
- **File:** `src/global/skills/dispatch.md`
- **Source:** Spec ripple effect item 13
- **What:** Add a note in the "Which Agents Use Which Path" section (near line 41 where Mnemosyne is mentioned):
  ```
  **Note:** Mnemosyne (reflector) dispatch bypasses the standard dispatch flow.
  The `reflection.md` skill handles prompt assembly directly, using reflection templates
  instead of the standard simplified/full assembly paths.
  ```

**Commit:** `moira(reflection): implement reflection dispatch skill and orchestrator integration`

**Dependency:** Chunks 2 and 3 (reflection.sh, templates, knowledge.sh libraries must exist).

---

## Chunk 5: Judge & Bench System (bench integration + stats + health command)

Wires the LLM-judge into bench infrastructure and creates health command.

### Task 5.1: Update bench.sh — judge integration + statistical functions
- **File:** `src/global/lib/bench.sh`
- **Source:** Spec D11, D13
- **What:**
  1. Add `source` for `judge.sh` at top (after yaml-utils.sh source)
  2. Update `moira_bench_run` (line 24):
     - After recording structural results (line 88-99 YAML block), add judge invocation:
     - Check if rubric exists for test case category: `meta.category` → `rubrics/{category}.yaml` (fallback to `feature-implementation.yaml`)
     - Call `moira_judge_invoke` to prepare prompt, note that actual Agent dispatch would be done by bench command (bench.md dispatches the agent)
     - After judge returns: read evaluation, call `moira_judge_composite_score`
     - Replace `quality_scores: null` in result YAML with actual scores including `automated_pass`, `normalized_score`, `judge_model`, `same_tier`
  3. Update `moira_bench_report` (line 176):
     - Include quality scores in summary: aggregate composite score across tests
     - Replace "Quality scores: not available (no LLM-judge)" with actual score display
     - Show zone indicators (NORMAL/WARN/ALERT) when baseline exists
  4. Add new statistical functions (D13b):
     - `moira_bench_update_baseline <aggregate_path> <metric> <new_value>` — incremental mean/variance update. Recalculate confidence_band (mean ± variance)
     - `moira_bench_classify_zone <aggregate_path> <metric> <value>` — read baseline, classify as NORMAL (within band), WARN (1-2σ), ALERT (>2σ). Adjust for cold start: <5 obs → always NORMAL; 5-10 obs → only ALERT; 10+ → full model. Apply minimum effect size: composite <3pts, sub-metric <5pts → NORMAL regardless
     - `moira_bench_check_regression <aggregate_path>` — check all metrics, apply decision rules: single_alert, sustained_warn (2+), multi_metric_warn (3+)
- **Key points:**
  - `moira_bench_run` prepares the judge prompt but the actual agent dispatch happens in bench.md command (the shell function can't call Agent tool)
  - Statistical functions use bash arithmetic (integer approximations are acceptable for zone classification)
  - Baseline storage extends `aggregate.yaml` with `baselines:` section per D13a

### Task 5.2: Update bench.md — calibrate subcommand + remove limitations
- **File:** `src/commands/moira/bench.md`
- **Source:** Spec D10b, ripple effect item 11
- **What:**
  1. Add `calibrate` to the Usage section argument list
  2. Add `### Calibrate` section:
     - Source `judge.sh`
     - Read calibration examples from `~/.claude/moira/tests/bench/calibration/`
     - For each example: dispatch judge Agent with the example artifacts and default rubric
     - Compare returned scores against `expected.yaml` (±1 tolerance)
     - Display per-example pass/fail, overall calibration status
     - If any fail: warn "Judge may be unreliable — consider re-running after model update"
  3. Remove "Phase 6 Limitations" section (lines 58-63)
  4. Update Tier 2/3 execution to include judge invocation after structural checks
  5. Update report subcommand to show quality scores
- **Key point:** `calibrate` dispatches 3 separate Agent calls (one per calibration example), each with the judge prompt assembled by `moira_judge_invoke`

### Task 5.3: Create health command
- **File:** `src/commands/moira/health.md` (NEW)
- **Source:** Spec D12
- **What:** New command file with frontmatter:
  ```yaml
  ---
  name: moira:health
  description: Check Moira system health
  argument-hint: "[report|details|history]"
  allowed-tools:
    - Agent
    - Read
    - Bash
  ---
  ```
  Flow:
  1. Run Tier 1 structural verifier (`run-all.sh`) — instant, 0 tokens. Capture pass/fail count → Structural Conformance score
  2. Load `testing/live/index.yaml` for live telemetry aggregate
  3. If judge data available (telemetry has quality scores): calculate Result Quality score using `moira_judge_normalize_score` on aggregate composite
  4. Calculate Efficiency score from telemetry (orchestrator context avg, retry rate)
  5. Compute composite Health Score: Structural 30% + Quality 50% + Efficiency 20%
  6. Display formatted output per spec D12 display format
  7. Subcommands: `report` (same as no-args), `details` (per-metric breakdown), `history` (trend over last 5 periods)
- **Key point:** Quality score is null if no judge data exists yet. Display "Quality: no data (run /moira bench first)" in that case

**Commit:** `moira(reflection): integrate LLM-judge into bench system and add health command`

**Dependency:** Chunks 2 and 3 (judge.sh, rubrics, calibration from Chunk 2; telemetry schema from Chunk 3 needed for bench mcp_calls awareness). Independent of Chunk 4.

---

## Chunk 6: Ripple Effect Updates (install, tests, existing files)

### Task 6.1: Update install.sh
- **File:** `src/install.sh`
- **Source:** Spec ripple effects 1-3
- **What:**
  - Lib verify list (line ~185): add `reflection.sh` and `judge.sh` to the hardcoded name list in the for loop
  - Add copy blocks for `templates/reflection/*.md` (4 files) and `templates/judge/judge-prompt.md` (1 file)
  - Add copy block for `tests/bench/calibration/` directories (3 subdirs with mock artifacts) — current install.sh only copies `tests/bench/fixtures/`, `cases/`, and `rubrics/`, NOT `calibration/`
  - Command verify list (line ~200): add `health` to the hardcoded name list

### Task 6.2: Update test-file-structure.sh
- **File:** `src/tests/tier1/test-file-structure.sh`
- **Source:** Spec ripple effects 4-7
- **What:**
  - Add `reflection.sh` and `judge.sh` to lib existence + syntax checks
  - Add `health` to the commands list
  - Add `reflection` to skills file check (currently: orchestrator, gates, dispatch, errors)
  - Add template directory checks for `templates/reflection/` (4 .md files) and `templates/judge/` (1 .md file)
  - **Line 66**: Add `libraries` to the knowledge type loop (`for ktype in project-model conventions decisions patterns failures quality-map libraries`)

### Task 6.3: Update test-knowledge-system.sh, test-yaml-schemas.sh, test-budget-system.sh
- **Files:**
  - `src/tests/tier1/test-knowledge-system.sh`
  - `src/tests/tier1/test-yaml-schemas.sh`
  - `src/tests/tier1/test-budget-system.sh`
- **Source:** Impact analysis
- **What:**
  - `test-knowledge-system.sh`: Update ALL hardcoded 6-type loops to include `libraries` (lines 23, 76, 193). Update mnemosyne agent test expectations to include libraries L2 (line ~127, expects 7 types now). Update daedalus test expectations to include libraries L0 (line ~141). Update template count assertion if affected by new libraries knowledge templates.
  - `test-yaml-schemas.sh`: Add check that `telemetry.schema.yaml` contains `mcp_calls` section
  - `test-budget-system.sh`: If any hardcoded lib/file counts, update them

### Task 6.4: Update test-install.sh
- **File:** `src/tests/tier1/test-install.sh`
- **Source:** Impact analysis
- **What:**
  - Add `reflection.sh` and `judge.sh` to individual lib file checks (install.sh uses a hardcoded name list, not a count)
  - Update command count assertion from `"11"` to `"12"` (adding `health`)
  - Add `reflection` to the skill existence check loop (line ~131: `for skill in orchestrator gates dispatch errors reflection`)
  - Add `state/reflection` to scaffold directory assertions if present (lines ~175-189)
  - Add `tests/bench/calibration` to bench copy verification

**Commit:** `moira(reflection): update install and test infrastructure for phase 10`

**Dependency:** Chunks 2-5 (all files must exist for verification).

---

## Chunk 7: Tier 1 Tests (verification)

### Task 7.1: Create reflection system test
- **File:** `src/tests/tier1/test-reflection-system.sh` (NEW)
- **Source:** Spec D14
- **What:** New test file following existing test pattern. Test groups:

  **Reflection library tests:**
  - `reflection.sh` exists in `$MOIRA_HOME/lib/`
  - `reflection.sh` has valid bash syntax (`bash -n`)
  - Functions exist (grep): `moira_reflection_task_history`, `moira_reflection_observation_count`, `moira_reflection_get_observations`, `moira_reflection_mcp_call_frequency`, `moira_reflection_pending_proposals`, `moira_reflection_record_proposal`, `moira_reflection_resolve_proposal`, `moira_reflection_deep_counter`, `moira_reflection_auto_defer_stale`

  **Judge library tests:**
  - `judge.sh` exists in `$MOIRA_HOME/lib/`
  - `judge.sh` has valid bash syntax
  - Functions exist: `moira_judge_invoke`, `moira_judge_composite_score`, `moira_judge_normalize_score`, `moira_judge_calibrate`

  **Template tests:**
  - Reflection templates exist: `templates/reflection/lightweight.md`, `standard.md`, `deep.md`, `epic.md`
  - Judge prompt template exists: `templates/judge/judge-prompt.md`
  - Rubric files exist: `tests/bench/rubrics/feature-implementation.yaml`, `bugfix.yaml`, `refactor.yaml`
  - Calibration directories exist: `tests/bench/calibration/good-implementation/`, `mediocre-implementation/`, `poor-implementation/`

  **Skill tests:**
  - Reflection skill exists: `skills/reflection.md`

  **Knowledge integration tests:**
  - `knowledge-access-matrix.yaml` contains `libraries` for mnemosyne, hephaestus, daedalus
  - `knowledge.sh` `_MOIRA_KNOWLEDGE_TYPES` contains `libraries`
  - `knowledge.sh` `moira_knowledge_read_for_agent` dimensions contains `libraries`

  **Telemetry tests:**
  - `telemetry.schema.yaml` contains `mcp_calls`

  **Integration tests:**
  - `mnemosyne.yaml` exists and has NEVER constraints
  - Pipeline definitions have `post:` with `reflection:` field (all 4 pipelines)
  - `bench.sh` sources `judge.sh`
  - `health.md` exists in `commands/moira/`
  - `scaffold.sh` contains `state/reflection` in mkdir
  - `orchestrator.md` contains `reflection.md` reference
  - `dispatch.md` contains Mnemosyne alternative path note

- **Key points:**
  - Source `test-helpers.sh` for `pass`/`fail`/`assert_*` functions
  - Auto-discovered by `run-all.sh` (glob pattern `test-*.sh`)
  - Must be executable: `chmod +x`

**Commit:** `moira(reflection): add tier 1 reflection system tests`

**Dependency:** All previous chunks (tests verify everything exists).

---

## Final Verification

After all chunks complete:
1. Run `src/tests/tier1/run-all.sh` — all tests must pass
2. Verify no constitutional violations introduced
3. Verify spec success criteria 1-13

**Final commit (if verification passes):** `moira(reflection): phase 10 reflection engine complete`

---

## Dependency Graph

```
Chunk 1 (decisions + design docs)
  │
  ├──────────────────┐
  ▼                  ▼
Chunk 2            Chunk 3
(libs+templates)   (knowledge+telemetry)
  │                  │
  ├────────┬─────────┤
  ▼        ▼         │
Chunk 4  Chunk 5     │
(reflect) (judge)    │
  │        │         │
  ├────────┴─────────┘
  ▼
Chunk 6 (ripple effects)
  │
  ▼
Chunk 7 (tests)
```

Chunks 2 and 3 are INDEPENDENT and can be implemented in parallel.
Chunks 4 and 5 are INDEPENDENT and can be implemented in parallel (both depend on 2+3).

---

## Task Summary

| Chunk | Tasks | Files Created | Files Modified | Risk |
|-------|-------|---------------|----------------|------|
| 1 | 1.1-1.2 | 0 | 2 design docs | GREEN |
| 2 | 2.1-2.6 | ~20 new files | 0 | YELLOW |
| 3 | 3.1-3.4 | 0 | 4 (knowledge.sh, access-matrix, telemetry schema, scaffold.sh) | YELLOW |
| 4 | 4.1-4.3 | 1 (reflection.md skill) | 2 (orchestrator.md, dispatch.md) | YELLOW |
| 5 | 5.1-5.3 | 1 (health.md) | 2 (bench.sh, bench.md) | YELLOW |
| 6 | 6.1-6.4 | 0 | 5 (install.sh, 4 test files) | YELLOW |
| 7 | 7.1 | 1 (test-reflection-system.sh) | 0 | GREEN |
| **Total** | **24 tasks** | **~22 new files** | **14 modified** | |
