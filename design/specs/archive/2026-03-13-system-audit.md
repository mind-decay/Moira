# Moira System Audit Report

**Date:** 2026-03-13
**Scope:** Full system cross-reference audit — design docs, skills, schemas, shell libs, pipeline YAMLs, role files (~50 files)
**Trigger:** Post first-task-execution analysis + D-062/D-063/D-064 changes

---

## Summary

- **Consistent cross-references:** 40+
- **Findings:** 2 critical, 5 high, 17 medium, 7 low (31 total)
- **System health:** Structurally sound. Core architecture (pipeline determinism, agent isolation, gate flow) implemented correctly. Issues concentrated in: (a) D-064 propagation to shell code, (b) knowledge access documentation drift, (c) overview.md staleness.

---

## Critical — Breaks Runtime

### C-1: budget.sh hardcodes 200k orchestrator capacity

**Location:** `src/global/lib/budget.sh:31`
**Issue:** `_MOIRA_BUDGET_ORCHESTRATOR_CAPACITY=200000` — should be `1000000` per D-064. Also hardcoded `"200k"` strings in `moira_budget_generate_report` (lines 388, 393-394). All percentage calculations and threshold warnings are based on 200k.
**Impact:** Orchestrator health report shows inflated percentages (e.g., 80k = "40%" instead of "8%"). Warning triggers at 80k instead of 400k.
**Fix:** Update constant to `1000000`, update display strings to `1000k`.

### C-2: budget.sh writes invalid enum values to warning_level

**Location:** `src/global/lib/budget.sh:288-299` vs `src/schemas/current.schema.yaml`
**Issue:** `moira_budget_orchestrator_check` writes `healthy` and `monitor` to `context_budget.warning_level`, but schema enum is `[normal, warning, critical]`. Two of four level names are invalid.
**Impact:** Any code reading `warning_level` and checking against schema enum will get unexpected values.
**Fix:** Map `healthy` → `normal`, decide whether `monitor` maps to `normal` or add `monitor` to enum.

---

## High — Schema Gaps, Data Loss

### H-1: bench_mode fields missing from current.schema.yaml

**Location:** `src/global/skills/orchestrator.md:77-79` vs `src/schemas/current.schema.yaml`
**Issue:** Orchestrator Section 2 Pre-Pipeline Setup reads `bench_mode` and `bench_test_case` from `current.yaml`, but neither field exists in the schema. Added by D-048 design but never added to schema.
**Fix:** Add `bench_mode` (boolean, default false) and `bench_test_case` (string, default "") to `current.schema.yaml`.

### H-2: state.sh loses estimated token data

**Location:** `src/global/lib/state.sh:182`
**Issue:** `moira_state_agent_done` passes `$tokens_used` as both `estimated_tokens` and `actual_tokens` to `moira_budget_record_agent`. Daedalus pre-estimates are never captured separately. The `budget.estimated_tokens` vs `budget.actual_tokens` distinction in `status.yaml` is meaningless.
**Fix:** Either extend `moira_state_agent_done` to accept separate estimated parameter, or pass 0 as placeholder until real estimates exist.

### H-3: dispatch.md Daedalus quality_map "L0 (full)" contradicts level convention

**Location:** `src/global/skills/dispatch.md:321`
**Issue:** Quality Map Injection table says `| Daedalus (planner) | L0 (full) | quality-map/full.md |`. But L0 = index, L1 = summary, L2 = full per system convention. Either the label or the matrix entry is wrong. `knowledge-access-matrix.yaml` has `daedalus.quality_map: L0`.
**Decision needed:** Should Daedalus get quality-map index (L0) or full (L2)? Daedalus assembles instruction files for downstream agents including quality context — L0 (index) seems insufficient.
**Fix:** Likely update matrix to `daedalus.quality_map: L2` and dispatch.md to `L2 (full)`.

### H-4: overview.md quality file names don't match dispatch.md

**Location:** `design/architecture/overview.md` vs `src/global/skills/dispatch.md:270`
**Issue:** overview.md lists `correctness.yaml`, `performance.yaml`, `security.yaml`, `standards.yaml`. dispatch.md references `q1-completeness.yaml`, `q2-soundness.yaml`, `q3-feasibility.yaml`, `q4-correctness.yaml`, `q5-coverage.yaml`. These are different naming schemes for the quality checklist files.
**Context:** The actual files in `src/global/core/rules/quality/` use the q1-q5 naming convention. overview.md is stale.
**Fix:** Update overview.md quality file tree to match q1-q5 naming.

### H-5: knowledge.md Agent Access Matrix missing failures column and Reflector/Auditor rows

**Location:** `design/subsystems/knowledge.md:17-28`
**Issue:** Matrix has 5 columns (project-model, conventions, decisions, patterns, quality-map) but D-039 added `failures` as 6th dimension. Also missing rows for Mnemosyne (L2 all) and Argus (L2 all). The implemented `knowledge-access-matrix.yaml` is correct — the design doc is stale.
**Fix:** Add `failures` column and Mnemosyne/Argus rows to knowledge.md matrix.

---

## Medium — Inconsistencies, Documentation Gaps

### M-1: mnemosyne.yaml and argus.yaml missing quality_map and failures

**Location:** `src/global/core/rules/roles/mnemosyne.yaml:34-39`, `argus.yaml:41-46`
**Issue:** Both agents have "full access" per agents.md but their knowledge_access blocks list only 4 of 6 dimensions. Missing: `quality_map: L2`, `failures: L2`. The `knowledge-access-matrix.yaml` has all 6 correctly.
**Impact:** If instruction assembly reads from role .yaml instead of matrix, these agents won't get quality_map/failures knowledge.
**Fix:** Add `quality_map: L2` and `failures: L2` to both role files.

### M-2: agents.md Knowledge access lines omit quality_map

**Location:** `design/architecture/agents.md:129,160,206`
**Issue:** Knowledge access lines for Metis, Daedalus, Themis list only 4 dimensions but all three have quality_map access per matrix and dispatch.md.
**Fix:** Add quality_map access to Knowledge access lines for Metis (L1), Daedalus (L0→L2 per H-3), Themis (L1).

### M-3: Full pipeline architecture_gate uses Standard options in YAML

**Location:** `src/global/core/pipelines/full.yaml:111-119` vs `src/global/skills/gates.md:129-137`
**Issue:** gates.md defines Full Pipeline architecture gate with alternative-selection UI (user CHOOSES architecture from numbered alternatives). full.yaml encodes standard proceed/details/modify/abort options instead.
**Fix:** Add `pipeline_variant: full` or encode Full Pipeline options directly in full.yaml.

### M-4: quick.yaml missing E2/E3/E4 error handlers

**Location:** `src/global/core/pipelines/quick.yaml:error_handlers`
**Issue:** Has only E1, E5, E6, E7, E8. Missing E2-SCOPE, E3-CONFLICT, E4-BUDGET. Other pipelines have all. Orchestrator skill logic handles these generically, but pipeline YAML should be complete.
**Fix:** Add E2, E3, E4 handlers to quick.yaml, or add comment documenting intentional omission.

### M-5: budgets.orchestrator_max_percent unused

**Location:** `src/schemas/config.schema.yaml:67-69` vs `src/global/skills/orchestrator.md` Section 6
**Issue:** Config field exists (default 25) but orchestrator hardcodes 40%/60% thresholds without reading config. Dead configuration.
**Fix:** Either remove field from schema or document that thresholds are derived from this value.

### M-6: Decomposition subtask_gate not documented in gates.md

**Location:** `src/global/core/pipelines/decomposition.yaml:101-111`
**Issue:** decomposition.yaml defines subtask_gate with proceed/checkpoint/abort. gates.md has no "Subtask Gate" section — only Phase Gate which says "Full Pipeline."
**Fix:** Add Subtask Gate section to gates.md, or extend Phase Gate to cover both pipelines.

### M-7: pipelines.md Decomposition gate count omits "final"

**Location:** `design/architecture/pipelines.md:12`
**Issue:** Table says "Many (classify, decomp, per-task)" but Art 2.2 requires classification + decomposition + per-task + **final**. decomposition.yaml correctly includes final_gate.
**Fix:** Update table to "Many (classify, decomp, per-task, final)".

### M-8: manifest.schema.yaml checkpoint.reason required but undocumented

**Location:** `src/schemas/manifest.schema.yaml` vs `src/global/skills/gates.md`
**Issue:** `checkpoint.reason` is `required: true` with enum `[context_limit, user_pause, error, session_end]` but no skill documents which value to write in which scenario.
**Fix:** Document reason selection logic in gates.md Phase Gate section.

### M-9: status.schema.yaml missing warnings block

**Location:** `src/global/skills/errors.md` E8-STALE vs `src/schemas/status.schema.yaml`
**Issue:** E8-STALE says "Log stale entries to status.yaml under warnings: block" but no such field in schema.
**Fix:** Add `warnings` block field to status.schema.yaml.

### M-10: overview.md project layer uses English role names

**Location:** `design/architecture/overview.md` project layer tree
**Issue:** Shows `classifier.yaml`, `explorer.yaml` etc. Global layer and all code uses Greek names (`apollo.yaml`, `hermes.yaml`).
**Fix:** Update project layer tree to use Greek names.

### M-11: Decomposition pipeline has no Explorer step

**Location:** `src/global/core/pipelines/decomposition.yaml`
**Issue:** Epic-sized tasks get classification → analysis → architecture → decomposition without code exploration. Athena (analyst) and Metis (architect) operate without exploration data.
**Context:** May be intentional — decomposition is high-level, sub-pipelines include exploration. But this rationale is not documented.
**Fix:** Either add Hermes step or document the intentional omission with rationale.

### M-12: Roadmap Phase 6 still lists LLM-judge

**Location:** `design/IMPLEMENTATION-ROADMAP.md:136`
**Issue:** Lists "LLM-judge with anchored rubrics (D-024)" as Phase 6 deliverable. D-046 explicitly deferred to Phase 10. Phase 6 spec correctly reflects D-046.
**Fix:** Update roadmap to show rubric definitions (Phase 6) vs LLM-judge invocation (Phase 10).

### M-13: D-021/D-022 structural corruption in decision log

**Location:** `design/decisions/log.md:192-210`
**Issue:** D-021's Alternatives/Reasoning paragraphs are positioned after D-022's content. D-021 is the only entry without these sections. The orphaned text contextually belongs to D-021.
**Fix:** Move the Alternatives/Reasoning block from after D-022 back into D-021.

### M-14: Hephaestus "never deviate from plan" — identity only, not in never: block

**Location:** `src/global/core/rules/roles/hephaestus.yaml:23-28`
**Issue:** agents.md states "Does NOT deviate from plan — if plan unclear → STATUS: blocked." In the YAML this is only in the `identity` text, not as an explicit `never:` entry. Weakens Art 1.2 machine-testability.
**Fix:** Add `"Never deviate from plan — if unclear, return STATUS: blocked"` to never: block.

### M-15: Themis checklist naming inconsistency

**Location:** `design/architecture/agents.md:198` vs `src/global/core/rules/roles/themis.yaml:38`
**Issue:** agents.md: "Code Review Checklist". Implementation: `q4-correctness`. Other agents' informal names map clearly to their IDs (e.g., "Requirements Completeness" → q1-completeness). "Code Review" → "correctness" is not obvious.
**Fix:** Rename in agents.md to "Code Correctness Checklist" or similar.

### M-16: Daedalus missing from dispatch.md assembly path table

**Location:** `src/global/skills/dispatch.md:34-39`
**Issue:** Table lists pre-assembled and simplified columns but Daedalus appears in neither. It uses simplified assembly (can't pre-assemble its own instructions).
**Fix:** Add Daedalus to Simplified column for Standard/Full/Decomposition pipelines.

### M-17: No budgets.schema.yaml

**Location:** `src/schemas/` — missing file
**Issue:** `config/budgets.yaml` has `agent_budgets.{role}` fields used by `budget.sh` and `dispatch.md` but no schema file for validation.
**Fix:** Create `budgets.schema.yaml` per D-029 (full schemas upfront).

---

## Low — Documentation Completeness

### L-1: overview.md lib/ tree incomplete

**Location:** `design/architecture/overview.md`
**Issue:** Shows 4 files (`state.sh`, `scaffold.sh`, `task-id.sh`, `yaml-utils.sh`) but actual `src/global/lib/` has 10 files (missing: `bootstrap.sh`, `budget.sh`, `bench.sh`, `knowledge.sh`, `quality.sh`, `rules.sh`).
**Fix:** Update tree to list all lib files.

### L-2: overview.md missing multiple entries

**Location:** `design/architecture/overview.md`
**Missing items:**
- `response-contract.yaml` in `core/`
- `templates/scanners/deep/` subdirectory
- `templates/budgets.yaml.tmpl`
- `core/knowledge-access-matrix.yaml`
- `schemas/` directory
- `state/tasks/{id}/findings/`
- `state/tasks/{id}/telemetry.yaml`
**Fix:** Add all to overview.md file trees.

### L-3: telemetry.schema.yaml missing _meta block

**Location:** `src/schemas/telemetry.schema.yaml`
**Issue:** Only schema without the `_meta` block (name, file, location, git) that all other schemas have.
**Fix:** Add `_meta` block consistent with other schemas.

### L-4: SYSTEM-DESIGN.md missing index entries

**Location:** `design/SYSTEM-DESIGN.md`
**Missing:**
- `design/reports/` directory (5 report files)
- `design/TESTING-IMPLEMENTATION-PLAN.md`
**Fix:** Add Reports section and testing implementation plan to index.

### L-5: D-033 and D-034 in wrong order in log

**Location:** `design/decisions/log.md:309,319`
**Issue:** D-034 appears before D-033. All other entries are sequential.
**Fix:** Swap order.

### L-6: Phase 7 and Phase 8 specs hardcode 200k

**Location:** `design/specs/2026-03-12-phase7-context-budget.md:181,183,331` and `design/specs/2026-03-13-phase8-hooks-self-monitoring.md:277`
**Issue:** Specs written before D-064, use 200k in display templates.
**Context:** Specs are historical implementation plans. Living design docs already updated.
**Fix:** Optional — add note "(pre-D-064, now 1M)" or leave as historical.

### L-7: blocker-resolution-design.md stale Classifier output

**Location:** `design/decisions/2026-03-11-blocker-resolution-design.md:17`
**Issue:** Still shows `pipeline: quick|standard|full|decomposition` in Classifier output spec. D-062 removed pipeline from Classifier response.
**Context:** This is a pre-implementation review document, not a living spec.
**Fix:** Optional — add note "(superseded by D-062)" or leave as historical.
