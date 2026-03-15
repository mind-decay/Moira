# Moira System Audit Report

**Date:** 2026-03-15
**Scope:** Full system — agents, pipelines, schemas, shell libs, design docs
**Previous audit:** 2026-03-14 (archived)

## Summary

| Severity | Count |
|----------|-------|
| Critical | 4 |
| High | 9 |
| Medium | 20 |
| Low | 12 |
| **Total** | **45** |

**Overall health:** The system has improved since the 2026-03-14 audit (many prior findings fixed). Remaining critical items center on: a design doc broken link, a long-standing D-039 contradiction, a constitutional ambiguity, and a configurable-gates risk to Art 2.2. Distribution.md is significantly out of sync with overview.md and reality. Several schema fields lack corresponding skill/shell-lib references.

---

## Critical

### C-01 — SYSTEM-DESIGN.md links to non-existent `TESTING-IMPLEMENTATION-PLAN.md`
- **Source:** DD-001
- **Files:** `design/SYSTEM-DESIGN.md:33`
- **Current:** Links to `TESTING-IMPLEMENTATION-PLAN.md` which was archived to `design/specs/archive/`
- **Target:** Remove stale link (testing design covered by `subsystems/testing.md` already indexed)
- **Fix:** Delete line 33 from SYSTEM-DESIGN.md

### C-02 — SYSTEM-DESIGN.md links to non-existent `decisions/2026-03-11-blocker-resolution-design.md`
- **Source:** DD-002
- **Files:** `design/SYSTEM-DESIGN.md:44`
- **Current:** Links to a file that was moved to `design/specs/archive/`
- **Target:** Update path to `specs/archive/2026-03-11-blocker-resolution-design.md`
- **Fix:** Update link target on line 44

### ~~C-03~~ — RESOLVED: D-039 Daedalus quality_map was already L2
- **Source:** DD-003 (carried over from previous audit H-18)
- **Resolution:** False positive. D-039 text already says `daedalus=L2`. All 5 sources agree. Added verification note to D-039 to prevent future audit confusion.
- **Status:** Closed 2026-03-15

### C-04 — Config schema allows gate list configuration, violating Art 2.2
- **Source:** PG-010
- **Files:** `src/schemas/config.schema.yaml:38-65`, `design/CONSTITUTION.md:56-64`
- **Current:** `pipelines.*.gates` are configurable arrays. Art 2.2: "Gates MUST NOT be skipped, reordered, or made optional by any rule, prompt, or **configuration**"
- **Target:** Either remove `pipelines.*.gates` from config schema, or add validation rejecting configs that remove constitutional gates
- **Fix:** Remove gate arrays from config.schema.yaml (simpler, aligns with Art 2.2 intent)

---

## High

### H-01 — Orchestrator context thresholds: 3 levels vs 4 in design docs
- **Source:** PG-001, SS-002
- **Files:** `src/global/skills/orchestrator.md:220-225`, `design/subsystems/context-budget.md:171-178`, `src/schemas/config.schema.yaml:70`
- **Current:** orchestrator.md has Normal/Warning/Critical (3). Design docs and config schema description have Healthy/Monitor/Warning/Critical (4)
- **Target:** orchestrator.md should use all 4 levels matching design docs
- **Fix:** Add Healthy (<25%) and Monitor (25-40%) bands to orchestrator.md Section 6

### ~~H-02~~ — RESOLVED: Architecture gate added to decomposition pipeline (D-085)
- **Source:** PG-004
- **Resolution:** D-085 adds `architecture_gate` between `architecture` and `decomposition` steps. Updated: decomposition.yaml, pipelines.md, decision log, Constitution Art 2.2.
- **Status:** Closed 2026-03-15

### H-03 — Daedalus Q3 checklist injection incorrectly classified as "post-planning" in dispatch.md
- **Source:** AA-005
- **Files:** `src/global/skills/dispatch.md:280-281`
- **Current:** Line 281 groups Daedalus Q3 with post-planning agents. But Daedalus IS the planner — it runs before instruction files exist
- **Target:** Daedalus Q3 should be in the pre-planning (simplified assembly) group
- **Fix:** Move Daedalus Q3 from post-planning to pre-planning list on lines 280-281

### H-04 — `moira_state_agent_done` signature mismatch in orchestrator.md and dispatch.md
- **Source:** SS-001, SS-013
- **Files:** `src/global/skills/orchestrator.md:245`, `src/global/skills/dispatch.md:202`, `src/global/lib/state.sh:142-148`
- **Current:** orchestrator.md says `<task_id> <step_name> <role> <tokens_used>` (4 args). dispatch.md omits `role`. Actual signature: `<step> <role> <status> <duration> <tokens> <summary>` (6 args)
- **Target:** Both skill files should reference the correct 6-arg signature
- **Fix:** Update orchestrator.md line 245 and dispatch.md line 202

### H-05 — distribution.md significantly out of sync with overview.md and implementation
- **Source:** DD-005, DD-006, DD-008, DD-009, DD-018
- **Files:** `design/architecture/distribution.md:204-254`
- **Current:** Missing: `schemas/`, `response-contract.yaml`, `knowledge-access-matrix.yaml`, `pipelines/`, `mcp.sh`, `scanners/` templates. Lists 5 non-existent template files. Skills section lists only orchestrator.md (should list 4 files)
- **Target:** distribution.md global layer map should match overview.md
- **Fix:** Comprehensive update of distribution.md file listings to match overview.md and reality

### ~~H-06~~ — RESOLVED: Constitution Art 1.2 already correct
- **Source:** DD-004 (carried over from previous audit H-13)
- **Resolution:** Verified line 23 reads "Classifier: determines task size and confidence". Already amended. No action needed.
- **Status:** Closed 2026-03-15

### H-07 — overview.md quality-map knowledge directory missing index.md
- **Source:** DD-007, DD-021
- **Files:** `design/architecture/overview.md:223-225`
- **Current:** All other knowledge directories have index.md/summary.md/full.md. quality-map has only summary.md/full.md
- **Target:** Add index.md or document the exception
- **Fix:** Add `index.md` entry to quality-map in overview.md

### H-08 — Mnemosyne NEVER constraint "Never modify project or system files" contradicts write_access grants
- **Source:** AA-009
- **Files:** `src/global/core/rules/roles/mnemosyne.yaml:34,44-50`
- **Current:** NEVER says "Never modify project or system files" but write_access grants full write to all knowledge types (which are YAML files in the system directory)
- **Target:** Wording should distinguish knowledge writes from direct file modification
- **Fix:** Change line 34 to "Never modify project source files or moira configuration files (knowledge writes go through the knowledge management subsystem)"

### H-09 — `completion.action` enum mismatch between status and telemetry schemas
- **Source:** SS-004
- **Files:** `src/schemas/status.schema.yaml:123-125`, `src/schemas/telemetry.schema.yaml:130-133`
- **Current:** status has `[done, tweak, redo, diff, test]` (missing `abort`). telemetry has `[done, tweak, redo, abort]` (missing `diff`, `test`)
- **Target:** status should include `abort`. telemetry should note `diff`/`test` are intermediate, not final results
- **Fix:** Add `abort` to status enum. Add comment to telemetry explaining intermediate vs final actions

---

## Medium

### M-01 — Gates.md health report emoji uses 3 zones vs 4-level design thresholds
- **Source:** PG-002
- **Files:** `src/global/skills/gates.md:53-54`
- **Fix:** Update emoji rules to 4 zones or document intentional collapse

### M-02 — Quick pipeline final gate missing "test" option
- **Source:** PG-003
- **Files:** `src/global/core/pipelines/quick.yaml:67-76`, `src/global/skills/gates.md:283-290`
- **Fix:** Add `test` to quick.yaml final gate, or update gates.md to note Quick excludes it

### M-03 — Full pipeline phase_gate "modify" option undocumented in gates.md
- **Source:** PG-006
- **Files:** `src/global/core/pipelines/full.yaml:141-151`, `src/global/skills/gates.md:201-206`
- **Fix:** Add `modify` option to gates.md Phase Gate section

### M-04 — Quick pipeline E5-QUALITY max_attempts diverges from errors.md universal spec
- **Source:** PG-009
- **Files:** `src/global/core/pipelines/quick.yaml:102`, `src/global/skills/errors.md:229-248`
- **Fix:** Add note to errors.md that Quick Pipeline limits E5 retries to 1

### M-05 — Standard pipeline YAML doesn't model batching from design
- **Source:** PG-015
- **Files:** `src/global/core/pipelines/standard.yaml:55-61`, `design/architecture/pipelines.md:88-97`
- **Fix:** Add comment in standard.yaml noting batching is handled dynamically by orchestrator

### M-06 — agents.md knowledge access format inconsistent across agents
- **Source:** AA-001, AA-002, AA-003, AA-011
- **Files:** `design/architecture/agents.md` (various agent sections)
- **Current:** Some agents list all 6 knowledge types, others list only non-null. Mnemosyne/Argus use prose ("Full access") without levels
- **Fix:** Standardize: list only non-null types with level notation for all agents

### M-07 — Daedalus has L2 quality_map access but agents.md rules don't explain why
- **Source:** AA-014
- **Files:** `design/architecture/agents.md:147-178`
- **Fix:** Add capability/rule explaining quality-map usage (inject pattern context into instruction files)

### M-08 — Apollo "NEVER select pipeline type" constraint in YAML but not in Constitution
- **Source:** AA-013
- **Files:** `design/CONSTITUTION.md:26`, `src/global/core/rules/roles/apollo.yaml:25`
- **Fix:** Consider adding to Constitution Art 1.2 (supports Art 2.1). Low urgency since YAML enforces it

### M-09 — Dispatch.md references runtime paths (`~/.claude/moira/`) — deployment not yet verified
- **Source:** AA-010
- **Files:** `src/global/skills/dispatch.md:45`
- **Fix:** Verify bootstrap copies `src/global/core/rules/roles/*.yaml` to `~/.claude/moira/core/rules/roles/`

### M-10 — Telemetry schema uses `{id}` instead of `{task_id}` in location
- **Source:** SS-003
- **Files:** `src/schemas/telemetry.schema.yaml:13`
- **Fix:** Change `{id}` to `{task_id}`

### M-11 — Telemetry gate name enum doesn't cover dynamic/error gates
- **Source:** SS-005
- **Files:** `src/schemas/telemetry.schema.yaml:86`
- **Fix:** Change field type from `enum` to `string` with pattern description

### M-12 — overview.md missing log files and `state/init/` from file tree
- **Source:** SS-006
- **Files:** `design/architecture/overview.md:229-254`
- **Fix:** Add `violations.log`, `tool-usage.log`, `budget-tool-usage.log`, `init/` to state section

### M-13 — `bypass.*` fields in current.schema.yaml have no skill/lib references
- **Source:** SS-007
- **Files:** `src/schemas/current.schema.yaml:77-88`
- **Fix:** Add comment noting fields are managed by `/moira:bypass` command

### M-14 — `tooling.post_implementation` config field not referenced in skills/libs
- **Source:** SS-008
- **Files:** `src/schemas/config.schema.yaml:167-171`
- **Fix:** Add post-implementation tooling injection to dispatch.md, or mark field as "not yet active"

### M-15 — `completion.*` status fields not written by any shell lib or skill
- **Source:** SS-009
- **Files:** `src/schemas/status.schema.yaml:122-138`
- **Fix:** Add instructions to orchestrator.md Section 7 to write completion fields

### M-16 — knowledge.md package-map access levels not in access matrix table
- **Source:** DD-010 (carried over from previous audit M-24)
- **Files:** `design/subsystems/knowledge.md:19-30,64-80`
- **Fix:** Add footnote to matrix table clarifying package-map access inherits from project-model

### M-17 — IMPLEMENTATION-ROADMAP.md Phase 1 missing `budgets.schema.yaml`
- **Source:** DD-011
- **Files:** `design/IMPLEMENTATION-ROADMAP.md:16-22`
- **Fix:** Add budgets schema to Phase 1 deliverables or note which phase introduced it

### M-18 — multi-developer.md shows `metrics/` at project root, should be under `state/`
- **Source:** DD-015
- **Files:** `design/subsystems/multi-developer.md:25`
- **Fix:** Change to `state/metrics/`

### M-19 — context-budget.md budget report example shows unrealistic 60% Classifier usage
- **Source:** DD-016
- **Files:** `design/subsystems/context-budget.md:137-138`
- **Fix:** Lower example to ~40% or add "illustrative" note

### M-20 — distribution.md `/moira init` flow step numbering gaps
- **Source:** DD-017
- **Files:** `design/architecture/distribution.md:284-355`
- **Fix:** Verify and renumber steps sequentially

---

## Low

### L-01 — E7-DRIFT and E8-STALE handlers still marked as stubs in all pipeline YAMLs
- **Source:** PG-007
- **Files:** All 4 pipeline YAMLs (`quick.yaml`, `standard.yaml`, `full.yaml`, `decomposition.yaml`)
- **Fix:** Replace stubs with proper handler fields matching errors.md

### L-02 — Quick pipeline "context.md" vs "exploration.md" naming difference (intentional)
- **Source:** PG-005
- **Fix:** Add comment in quick.yaml noting deliberate naming difference

### L-03 — Subtask gate missing "modify" option (may be intentional)
- **Source:** PG-011
- **Fix:** Add comment explaining rework is handled within sub-pipeline gates

### L-04 — `/moira continue` vs `/moira:resume` command name mismatch
- **Source:** PG-014
- **Files:** `design/subsystems/self-monitoring.md:115`, `src/global/skills/orchestrator.md:239`
- **Fix:** Update self-monitoring.md to use `/moira:resume`

### L-05 — Hermes, Themis, Mnemosyne write_access not documented in agents.md
- **Source:** AA-006, AA-007, AA-008
- **Files:** `design/architecture/agents.md` (Hermes, Themis, Mnemosyne sections)
- **Fix:** Add write_access notes to each agent's section

### L-06 — `warnings` block in status.schema.yaml never written by shell functions
- **Source:** SS-010
- **Fix:** Add orchestrator instructions or state.sh function to write stale warnings

### L-07 — Known H-06 TODO: yaml_block_append nested key workaround in budget.sh
- **Source:** SS-011
- **Files:** `src/global/lib/budget.sh:223-235`
- **Fix:** Implement nested block append or add test verifying workaround

### L-08 — Telemetry schema uses unsupported types (`object`, `integer`) for validator
- **Source:** SS-012
- **Fix:** Already noted in schema file. Low priority

### L-09 — `moira_budget_estimate_agent` uses hardcoded 70% instead of reading config
- **Source:** SS-014
- **Files:** `src/global/lib/budget.sh:148`
- **Fix:** Replace hardcoded 70 with `_moira_budget_get_max_load` call

### L-10 — `libraries` knowledge type missing from `_MOIRA_KNOWLEDGE_TYPES`
- **Source:** SS-015
- **Files:** `src/global/lib/knowledge.sh:16`
- **Fix:** Add comment explaining libraries follows different lifecycle (MCP cache)

### L-11 — overview.md shows phantom hook files in project layer
- **Source:** SS-016
- **Files:** `design/architecture/overview.md:256-260`
- **Fix:** Remove `guard.sh` and `budget-track.sh` from project layer tree

### L-12 — IMPLEMENTATION-ROADMAP.md Phase 11 references `xref-manifest.yaml` with no design doc
- **Source:** DD-014
- **Fix:** Note design gap for Phase 11 spec writing

---

## Fix Dependency Graph

```
C-03 (D-039 contradiction) ← requires user decision first
C-04 (configurable gates) ← standalone
H-06 (Constitution Art 1.2) ← requires user edit

H-01 (orchestrator thresholds) → M-01 (gates.md emoji zones)
H-04 (agent_done signature) → is standalone
H-05 (distribution.md sync) → is standalone (large)
H-08 (Mnemosyne NEVER) → is standalone
H-09 (completion enum) → M-15 (completion fields)

M-06 (agents.md format) → L-05 (write_access docs)
```

## Parallel Fix Groups

**Group 1 — Design doc fixes (no code changes):**
- C-01, C-02 (SYSTEM-DESIGN.md broken links)
- H-05 (distribution.md comprehensive update)
- H-07 (overview.md quality-map index.md)
- M-06 (agents.md knowledge access format)
- M-07 (agents.md Daedalus quality_map explanation)
- M-12 (overview.md missing log files)
- M-16 (knowledge.md package-map footnote)
- M-17 (roadmap budgets schema)
- M-18 (multi-developer.md metrics path)
- M-19 (context-budget.md example)
- M-20 (distribution.md step numbering)
- L-02, L-03, L-05, L-11, L-12

**Group 2 — Schema fixes:**
- C-04 (remove configurable gates)
- H-09 (completion enum alignment)
- M-10 (telemetry {id} → {task_id})
- M-11 (telemetry gate name type)
- M-13 (bypass fields comment)
- M-14 (post_implementation note)
- L-08 (telemetry type notes)

**Group 3 — Skill file fixes:**
- H-01 (orchestrator thresholds) + M-01 (gates emoji)
- H-03 (dispatch.md Daedalus Q3 injection)
- H-04 (agent_done signature in orchestrator.md + dispatch.md)
- M-02 (quick final gate test option)
- M-03 (gates.md modify option)
- M-04 (errors.md quick retry note)
- M-05 (standard.yaml batching comment)
- M-09 (dispatch.md runtime paths)
- M-15 (orchestrator.md completion fields)
- L-01 (pipeline YAML stubs)
- L-04 (self-monitoring.md command name)

**Group 4 — Shell lib fixes:**
- H-08 (mnemosyne.yaml NEVER wording)
- L-06 (status warnings writer)
- L-07 (yaml_block_append nested)
- L-09 (budget.sh hardcoded threshold)
- L-10 (knowledge.sh libraries comment)

**Group 5 — Requires user decision (cannot parallelize):**
- C-03 (D-039 Daedalus quality_map level)
- H-02 (decomposition architecture gate)
- H-06 (Constitution Art 1.2 amendment)
- M-08 (Constitution Apollo NEVER)

**Suggested execution order:** Group 5 decisions first → Groups 1-4 in parallel → verify
