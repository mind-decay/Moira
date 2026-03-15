# Moira System Audit Report

**Date:** 2026-03-15 (post-Phase 10)
**Scope:** Full system — agents, pipelines, schemas, shell libs, design docs
**Auditors:** 4 parallel agents (Agent Architecture, Pipeline & Gate, Schema & State, Design Cross-Reference)
**Previous audit:** `design/reports/2026-03-15-system-audit.md`

## Summary

| Severity | Count |
|----------|-------|
| Critical | 2 |
| High | 8 |
| Medium | 19 |
| Low | 11 |
| **Total** | **40** |

**Overall health:** The system is structurally sound — budgets, NEVER constraints, quality gates, and Art 2.2 mandatory gates are all correct. The main issues stem from Phase 10 (reflection engine) additions not being fully propagated across all cross-references, the `libraries` knowledge type (D-091) not yet reflected in all files, and several orphaned/dead config fields. One critical runtime bug exists in `reflection.sh` reading nonexistent schema fields.

**Previous audit status:** Of 45 findings from the same-day audit, 15 were verified as fixed, 2 were false positives, and the remainder are included below where still relevant.

---

## Critical

### C-01 — agents.md Apollo "Purpose" contradicts D-062

- **Files:** `design/architecture/agents.md:31`
- **Current:** Line 31 says `**Purpose:** Determines task size and selects pipeline type.`
- **Problem:** D-062 explicitly states "Classifier Does Not Return Pipeline Type." Art 2.1 makes pipeline selection the orchestrator's responsibility. Line 44 of the same file correctly says "Classifier does NOT return `pipeline=`" — the Purpose line directly contradicts the clarification 13 lines later.
- **Target:** `**Purpose:** Determines task size and confidence. First step of every pipeline (D-028).`
- **Fix:** Update line 31 to remove "selects pipeline type."

### C-02 — knowledge.md access matrix missing `libraries` column (D-091)

- **Files:** `design/subsystems/knowledge.md:19-30`, `src/global/core/knowledge-access-matrix.yaml:12-21`
- **Current:** The design-level matrix has 6 columns (project-model, conventions, decisions, patterns, quality-map, failures). Missing the `libraries` knowledge type added by D-091.
- **Target:** Matrix must include 7th column `libraries` with values: null for most agents, L0 for Daedalus, L1 for Hephaestus, L2 for Mnemosyne, L2 for Argus.
- **Fix:** Add `libraries` column to the matrix table in knowledge.md.

---

## High

### H-01 — `warning_level` enum supports 3 levels but orchestrator/gates describe 4

- **Files:** `src/schemas/current.schema.yaml:67` (`enum: [normal, warning, critical]`), `src/global/lib/budget.sh:296-301`, `src/global/skills/orchestrator.md:225-230` (Healthy/Monitor/Warning/Critical), `src/global/skills/gates.md:54`
- **Current:** Schema and shell code only support 3 levels. Orchestrator and gates describe 4 levels (Healthy <25%, Monitor 25-40%, Warning 40-60%, Critical >60%). No way to distinguish "healthy" from "monitor" in state.
- **Target:** Add `monitor` to schema enum and budget.sh.
- **Fix:** Change `current.schema.yaml:67` to `enum: [normal, monitor, warning, critical]`. Add `elif [[ "$percentage" -gt 25 ]]; then level="monitor"` to budget.sh.

### H-02 — `reflection.sh` reads nonexistent fields from status.yaml

- **Files:** `src/global/lib/reflection.sh:38-51`, `src/schemas/status.schema.yaml`
- **Current:** `moira_reflection_task_history` reads:
  - `step` (line 38) — does NOT exist in status schema (should be `status`)
  - `first_pass_accepted` (line 48) — should be `completion.final_review_passed`
  - `retry_count` (line 49) — should be `retries.total`
  - `classification_correct` (line 50) — only exists in `telemetry.schema.yaml`
  - Checks `"$step" != "done"` — `done` is not a valid status enum value (`completed` is)
- **Target:** Function must use correct field names matching the schemas.
- **Fix:** Change line 38 to read `status`, line 41 to check `!= "completed"`, line 48 to `completion.final_review_passed`, line 49 to `retries.total`, line 50 to read from telemetry.yaml or skip.

### H-03 — All 10 role YAML files missing `libraries` knowledge type

- **Files:** All files in `src/global/core/rules/roles/*.yaml`
- **Current:** Every role YAML knowledge_access block lists only 6 types, omitting `libraries`. The authoritative matrix defines 7 types. Daedalus should have L0, Hephaestus L1, Mnemosyne L2, Argus L2, others null.
- **Fix:** Add `libraries:` with correct value to each YAML file's knowledge_access block.

### H-04 — Mnemosyne YAML write_access missing `libraries: true`

- **Files:** `src/global/core/rules/roles/mnemosyne.yaml:44-50`, `src/global/core/knowledge-access-matrix.yaml:26`
- **Current:** write_access lists 6 types but omits `libraries: true`. Matrix grants Mnemosyne write access to all 7 types.
- **Fix:** Add `libraries: true` to mnemosyne.yaml write_access block.

### H-05 — dispatch.md Assembly Path table incorrectly lists Metis as "Pre-assembled"

- **Files:** `src/global/skills/dispatch.md:37-39,283`
- **Current:** The table lists Metis under "Pre-assembled (instruction file)" for Standard, Full, and Decomposition pipelines. Pre-assembled means Daedalus writes the instruction file. But Metis runs BEFORE Daedalus in all pipelines — Daedalus cannot write an instruction file for an agent that runs before it. Line 283 also classifies Metis Q2 as "post-planning."
- **Target:** Metis should be "Simplified (fallback)." Q2 injection should be pre-planning.
- **Fix:** Move Metis from pre-assembled to simplified column. Change line 282 to include Metis Q2 in pre-planning group.

### H-06 — distribution.md out of sync with Phase 10 additions

- **Files:** `design/architecture/distribution.md:234-272`
- **Current:** Missing from distribution.md:
  - Skills section (line 234-238): missing `reflection.md`
  - Templates section (line 244-248): missing `reflection/` and `judge/` directories
  - Lib section (line 260-272): missing `reflection.sh` and `judge.sh`
  - Core section (line 208-233): missing `response-contract.yaml` and `knowledge-access-matrix.yaml`
- **Fix:** Add all missing entries to match overview.md.

### H-07 — `moira_state_increment_retry` missing type parameter, unreferenced by skills

- **Files:** `src/global/lib/state.sh:190-208`, `src/global/skills/errors.md:617-632`
- **Current:** errors.md describes incrementing `retries.quality`, `retries.agent_failures`, `retries.budget_splits`, and `retries.total`. But `moira_state_increment_retry` only increments `retries.total`. No function handles per-type counters. No skill references this function by name.
- **Fix:** Add type parameter to function. Update errors.md to reference it.

### H-08 — Quick pipeline design doc missing `test` in final gate options

- **Files:** `design/architecture/pipelines.md:46`, `src/global/core/pipelines/quick.yaml:75`
- **Current:** Design doc shows `done / tweak / redo / diff`. YAML includes `test`. orchestrator.md Section 7 defines `test` as dispatching Aletheia on demand.
- **Fix:** Add `test` to pipelines.md Quick Pipeline final gate options.

---

## Medium

### M-01 — agents.md Hephaestus and Daedalus knowledge access omit `libraries`

- **Files:** `design/architecture/agents.md:201` (Hephaestus), `design/architecture/agents.md:178` (Daedalus)
- **Current:** Hephaestus omits L1 libraries. Daedalus omits L0 libraries. Matrix grants both.
- **Fix:** Add `libraries` to both agents' knowledge access lines.

### M-02 — orchestrator.md completion.action comment omits 3 valid values

- **Files:** `src/global/skills/orchestrator.md:294`
- **Current:** Comment says `(done/tweak/redo)`. Status schema enum is `[done, tweak, redo, diff, test, abort]`.
- **Fix:** Update comment to `(done/tweak/redo/diff/test/abort)`.

### M-03 — Decomposition pipeline gates missing `details` option

- **Files:** `src/global/core/pipelines/decomposition.yaml:99-116`, `src/global/skills/gates.md:233-238`
- **Current:** Both `architecture_gate` and `decomposition_gate` only have proceed/modify/abort. Standard pipeline's architecture gate includes `details`. The standard gate template (pipelines.md) includes "details — show full document."
- **Fix:** Add `details` option to both gates in decomposition.yaml and to gates.md Decomposition Gate section.

### M-04 — Shell helper functions unreferenced by skills

- **Files:** `src/global/lib/budget.sh:316,408,432`, `src/global/lib/quality.sh:112`
- **Current:** `moira_budget_generate_report`, `moira_budget_write_telemetry`, `moira_budget_handle_overflow`, `moira_quality_aggregate_task` exist but no skill references them. Skills describe equivalent behavior inline.
- **Fix:** Add function references to orchestrator.md, errors.md, and gates.md.

### M-05 — telemetry `quality.final_result` never written by orchestrator

- **Files:** `src/schemas/telemetry.schema.yaml:132`, `src/global/skills/orchestrator.md`
- **Current:** Telemetry defines `quality.final_result` enum `[done, tweak, redo, abort]`. No skill instructs writing this field. Only `completion.action` in status.yaml is mentioned.
- **Fix:** Add instruction to orchestrator.md Section 7 to write `quality.final_result` to telemetry.yaml.

### M-06 — Config `pipelines.*.max_retries` fields appear unused/dead

- **Files:** `src/schemas/config.schema.yaml:35-50`
- **Current:** Fields exist with defaults but neither orchestrator.md nor errors.md references them. Each pipeline YAML defines its own per-handler `max_attempts`.
- **Fix:** Add description marking as reserved, or remove the fields.

### M-07 — `warnings` block in status schema never written by shell function

- **Files:** `src/schemas/status.schema.yaml:112-121`, `src/global/skills/orchestrator.md:202`
- **Current:** Schema defines warnings block. orchestrator.md says to use `moira_yaml_block_append` directly. No dedicated shell function exists.
- **Fix:** Add `moira_state_write_warning` to state.sh, or document inline construction.

### M-08 — Bypass command format inconsistency

- **Files:** `src/global/skills/orchestrator.md:43`, `design/CONSTITUTION.md:112`
- **Current:** orchestrator.md uses `/moira:bypass`. Other docs use `/moira bypass:` (with space). Format differs.
- **Fix:** Verify canonical format in commands.md and standardize.

### M-09 — self-protection.md verification schema missing decomposition architecture gate (D-085)

- **Files:** `design/subsystems/self-protection.md:253`
- **Current:** `decomposition_gates: ["classification", "decomposition", "per_task", "final"]` — missing "architecture."
- **Target:** `["classification", "architecture", "decomposition", "per_task", "final"]`
- **Fix:** Add "architecture" to the list.

### M-10 — `/moira continue` vs `/moira resume` inconsistency

- **Files:** `design/subsystems/checkpoint-resume.md:98`, `design/architecture/onboarding.md:64`, `design/architecture/commands.md:30`
- **Current:** commands.md defines `/moira resume`. checkpoint-resume.md and onboarding.md use `/moira continue`.
- **Fix:** Standardize on `/moira resume` everywhere.

### M-11 — rules.md references non-archive path for spec

- **Files:** `design/architecture/rules.md:117`
- **Current:** References `design/specs/2026-03-13-bootstrap-scanner-reform.md` — file moved to `design/specs/archive/`.
- **Fix:** Update path to `design/specs/archive/2026-03-13-bootstrap-scanner-reform.md`.

### M-12 — quality-map index.md in overview.md but knowledge.sh explicitly skips L0

- **Files:** `design/architecture/overview.md:231`, `src/global/lib/knowledge.sh:55-56`
- **Current:** overview.md shows `quality-map/index.md` exists. knowledge.sh returns empty for quality-map L0. File exists but is never populated.
- **Fix:** Remove `index.md` from quality-map in overview.md, add comment explaining no L0 for quality-map.

### M-13 — Config `budgets.orchestrator_max_percent` reserved but hardcoded in orchestrator

- **Files:** `src/schemas/config.schema.yaml:51-55`, `src/global/skills/orchestrator.md:227`
- **Current:** Config has field with default 25, marked "reserved." Orchestrator hardcodes 25%.
- **Fix:** Add comment clarifying future use. Low priority.

### M-14 — IMPLEMENTATION-ROADMAP.md not updated for Phase 10 completion

- **Files:** `design/IMPLEMENTATION-ROADMAP.md`
- **Current:** Phase 10 has been implemented but roadmap doesn't reflect completion status.
- **Fix:** Mark Phase 10 as complete. Commit archived spec/plan files.

### M-15 — bootstrap.sh generates `gates:` arrays in config despite no schema support

- **Files:** `src/global/lib/bootstrap.sh:161-170`, `src/schemas/config.schema.yaml:34`
- **Current:** bootstrap.sh generates gate arrays in config.yaml. Config schema says "Gates are fixed per Art 2.2 — defined in pipeline YAML definitions only." These are dead configuration entries.
- **Fix:** Remove `gates:` generation from bootstrap.sh.

### M-16 — telemetry schema uses unsupported validator types

- **Files:** `src/schemas/telemetry.schema.yaml` (lines 35, 54, 72-73, 108-109, 136-137, 146-147, 163)
- **Current:** Uses `object`, `integer`, `list` — the validator only supports `string`, `number`, `boolean`, `enum`, `block`, `array`. Telemetry files are never validated.
- **Fix:** Low priority. Schema header documents this. Future phase should extend validator.

### M-17 — budget.sh hardcoded 50% warning threshold undocumented

- **Files:** `src/global/lib/budget.sh:153`
- **Current:** `moira_budget_estimate_agent` hardcodes 50% warning threshold with no comment.
- **Fix:** Add comment documenting the fixed 50% threshold.

### M-18 — multi-developer.md directory tree indentation error

- **Files:** `design/subsystems/multi-developer.md:25`
- **Current:** `state/metrics/` shown at same level as `state/` instead of nested inside.
- **Fix:** Fix indentation.

### M-19 — agents.md Themis section missing write_access documentation

- **Files:** `design/architecture/agents.md` (between lines 231-233)
- **Current:** Hermes and Mnemosyne document write_access. Themis does not, despite YAML and matrix granting quality_map write access.
- **Fix:** Add `**Write access:** quality_map` to Themis section.

---

## Low

### L-01 — agents.md knowledge access summaries use inconsistent format

- **Files:** `design/architecture/agents.md` (lines 63, 85, 112, 142, 178, 201, 230, 256, 302, 324)
- **Current:** Some use parenthetical notation, others prose. None mention `libraries`.
- **Fix:** Standardize format across all agents.

### L-02 — knowledge.md matrix uses role names, not Greek names

- **Files:** `design/subsystems/knowledge.md:19-30`
- **Current:** Uses "Classifier, Explorer" etc. while D-034 says Greek names are canonical.
- **Fix:** Use `Apollo (classifier)` format, or add note about readability choice.

### L-03 — Quick pipeline Analyst exclusion undocumented

- **Files:** `src/global/core/pipelines/quick.yaml` (between lines 25-27)
- **Current:** No comment explaining why Analyst is absent (decomposition.yaml has explicit comment).
- **Fix:** Add comment.

### L-04 — `agent: null` step handling undocumented in orchestrator.md

- **Files:** `src/global/skills/orchestrator.md` Section 2 (~line 84)
- **Current:** Pipeline execution loop says "dispatch agent" but doesn't explain null-agent steps.
- **Fix:** Add note about orchestrator-handled steps.

### L-05 — overview.md project-layer `hooks/` directory serves no purpose

- **Files:** `design/architecture/overview.md:271`, `src/global/lib/scaffold.sh:79`
- **Current:** Created by scaffold but never populated. Hook scripts live at global layer.
- **Fix:** Remove from scaffold.sh and overview.md, or document future use.

### L-06 — knowledge.sh libraries L2 special handling lacks context comment

- **Files:** `src/global/lib/knowledge.sh:60-62`
- **Current:** Returns empty for libraries L2 with brief comment. No design doc explains libraries lifecycle.
- **Fix:** Add comment explaining libraries are per-library MCP docs, no single full.md.

### L-07 — yaml_block_append workaround for nested `budget.by_agent` key

- **Files:** `src/global/lib/budget.sh:226-238`
- **Current:** Appends to `by_agent` directly instead of `budget.by_agent` due to yaml_block_append limitation. Has comment but no regression test.
- **Fix:** Add test, or accept existing comment as sufficient.

### L-08 — telemetry.schema.yaml uses `type: list` instead of `type: array`

- **Files:** `src/schemas/telemetry.schema.yaml:163`
- **Current:** Uses `list` (not in validator's supported types). Should be `array` for consistency.
- **Fix:** Change `type: list` to `type: array`.

### L-09 — agents.md Mnemosyne write_access says "all knowledge types" without listing them

- **Files:** `design/architecture/agents.md:303`
- **Current:** Says "all knowledge types" but doesn't mention the 7 specific types.
- **Fix:** Optional — add "(including libraries)" for explicitness.

### L-10 — D-039 verification note status unclear

- **Files:** `design/decisions/log.md`, D-039 section
- **Current:** Previous audit C-03 says verification note was added. Status unverified.
- **Fix:** Verify D-039 has the note.

### L-11 — IMPLEMENTATION-ROADMAP.md Phase 1 doesn't list telemetry/findings schemas

- **Files:** `design/IMPLEMENTATION-ROADMAP.md:16-22`
- **Current:** Phase 1 schema list doesn't include telemetry or findings (added in later phases). Roadmap reflects what was planned, not final state.
- **Fix:** No fix needed — roadmap is historical. Note for clarity only.

---

## Fix Dependency Graph

```
C-02 (knowledge.md libraries) ──┐
H-03 (role YAMLs libraries)  ───┤── All depend on D-091 being the source of truth
H-04 (mnemosyne write_access) ──┤
M-01 (agents.md libraries)  ────┘

H-01 (warning_level 4 levels) ── independent

H-02 (reflection.sh fields) ── independent (critical runtime bug)

H-05 (dispatch.md Metis) ── independent

H-06 (distribution.md sync) ── independent

H-07 (increment_retry type) ── depends on M-04 (skill function references)

H-08 (pipelines.md test option) ── independent

M-09 (self-protection.md) ── depends on verifying D-085
M-15 (bootstrap gates removal) ── depends on verifying Art 2.2 compliance
```

## Parallel Fix Groups

**Group 1 — Libraries propagation (C-02, H-03, H-04, M-01, L-01)**
All changes related to adding `libraries` knowledge type across the system. Can be done as one commit.

**Group 2 — Critical runtime fix (H-02)**
Fix reflection.sh field names. Independent, high priority.

**Group 3 — Schema/shell alignment (H-01, H-07, M-02, M-04, M-05, M-07)**
Fix enum mismatches, add shell function parameters, update skill references.

**Group 4 — Dispatch & pipeline docs (H-05, H-08, M-03, L-03, L-04)**
Fix dispatch.md assembly table, pipeline gate options, add comments.

**Group 5 — Distribution & cross-ref sync (H-06, M-09, M-10, M-11, M-14, M-18, M-19)**
Sync distribution.md, fix stale references, update roadmap.

**Group 6 — Dead config cleanup (M-06, M-13, M-15, M-17)**
Remove or document dead/reserved config fields.

**Group 7 — Low-priority docs (L-02 through L-11)**
Documentation improvements, comments, format standardization.

**Suggested execution order:** Group 2 > Group 1 > Group 3 > Group 4 > Group 5 > Group 6 > Group 7
