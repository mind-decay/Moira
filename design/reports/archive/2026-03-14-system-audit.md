# Moira System Audit Report

**Date:** 2026-03-14
**Scope:** Full system — agents, pipelines, gates, schemas, shell libs, design doc cross-references
**Auditors:** 4 parallel agents (Agent Architecture, Pipeline & Gate, Schema & State, Design Cross-Reference)

## Summary

| Severity | Count |
|----------|-------|
| Critical | 4     |
| High     | 18    |
| Medium   | 24    |
| Low      | 12    |
| **Total**| **58**|

**Overall system health:** The core design is internally consistent at the architectural level. The majority of findings are documentation staleness (distribution.md not updated across phases), schema under-specification (opaque `block` types with no sub-fields), and missing cross-references between documents. Four critical findings require immediate attention — one would cause runtime data corruption (`budget.sh` emitting an invalid enum value), one is a direct Constitutional contradiction (escape-hatch command format), one would produce schema-invalid telemetry files, and one would cause wrong quality map injection depth.

---

## Critical

### C-01 — `budget.sh` emits invalid enum value `"healthy"` for `warning_level`

**Files:** `src/global/lib/budget.sh:255`, `src/schemas/current.schema.yaml:66`
**Current:** When `current.yaml` doesn't exist, `moira_budget_orchestrator_check` outputs `level: healthy`. Schema enum is `[normal, warning, critical]`.
**Target:** Change `"healthy"` to `"normal"` at budget.sh:255.
**Fix:** Single-line string replacement.

### C-02 — Escape-hatch command format contradicts Constitution Art 4.4

**Files:** `design/architecture/escape-hatch.md:9,23,100`, `design/CONSTITUTION.md:111,177`, `design/architecture/commands.md:101`
**Current:** `escape-hatch.md` uses `/moira:bypass` (colon after `moira`). Constitution and `commands.md` use `/moira bypass:` (colon after `bypass`).
**Target:** Update `escape-hatch.md` to use `/moira bypass:` throughout — Constitution is authoritative.
**Fix:** Find/replace `/moira:bypass` → `/moira bypass:` in escape-hatch.md.

### C-03 — `telemetry.schema.yaml` required fields `structural.constitutional_pass` and `structural.violations` have no write source

**Files:** `src/schemas/telemetry.schema.yaml:141-155`, `src/global/skills/orchestrator.md:278-313`
**Current:** Both fields are `required: true`. The orchestrator completion flow writes `compliance.orchestrator_violation_count` and `execution.budget_total_tokens` but never writes `structural.*`. Every pipeline completion produces a schema-invalid telemetry file.
**Target:** Add write instructions for `structural.constitutional_pass` and `structural.violations` to orchestrator.md Section 7 completion flow.
**Fix:** Add two bullet points to orchestrator.md completion flow specifying when/how to populate structural fields.

### C-04 — `dispatch.md` labels Daedalus as "L0 agent" for quality map injection — should be L2

**Files:** `src/global/skills/dispatch.md:330`
**Current:** `"For L0 agents (Daedalus): include full.md content"`. Daedalus has L2 quality-map access per the matrix, agents.md, and the table 12 lines above in the same file. An implementer following this literally would give L0-access agents full content and deny L2 agents correct content.
**Target:** Change line 330 to `"For L2 agents (Daedalus): include full.md content"`.
**Fix:** Single-line text replacement.

---

## High

### H-01 — `status.schema.yaml` `completion.action` enum missing `diff` and `test`

**Files:** `src/schemas/status.schema.yaml:96`, `src/global/skills/orchestrator.md:278-313`, all pipeline final gate YAMLs
**Current:** Enum is `[done, tweak, redo]`. Orchestrator and all final gates also support `diff` and `test`.
**Target:** Extend enum to `[done, tweak, redo, diff, test]`.

### H-02 — `rearchitect` plan gate option has no state recording mapping

**Files:** `src/global/core/pipelines/standard.yaml:126`, `src/global/core/pipelines/full.yaml:132`, `src/global/skills/gates.md:411`, `src/schemas/telemetry.schema.yaml:87`
**Current:** `rearchitect` is a valid plan gate option but `gates.md` State Management only allows `proceed/modify/abort`. Telemetry schema gate result enum is also `[proceed, modify, abort]`.
**Target:** Either add `rearchitect` to the gate decision enum, or define an explicit mapping (e.g., `rearchitect → modify` with annotation).

### H-03 — Reflection post-values (`lightweight`, `background`, `deep`, `epic`) have no dispatch specification

**Files:** All 4 pipeline YAMLs (post sections), `src/global/skills/orchestrator.md`
**Current:** Four distinct reflection values are used but no skill, enum, or dispatch procedure maps them to orchestrator actions. Quick Pipeline says "No Reflector dispatched" but uses value `lightweight` — an orchestrator could incorrectly dispatch a reflector.
**Target:** Define a reflection dispatch table in orchestrator.md mapping each value to a concrete action (or non-action).

### H-04 — Full Pipeline `alternative_selection` gate variant has undefined state recording

**Files:** `src/global/core/pipelines/full.yaml:111`, `src/global/skills/gates.md:408-414`
**Current:** When a user picks "Alternative 2" at the Full architecture gate, there is no defined mapping to the `proceed/modify/abort` gate decision enum.
**Target:** Define in gates.md: "Alternative selection maps to `proceed` with selected alternative noted in `note` field."

### H-05 — Quick Pipeline E6-AGENT uses `escalate` instead of `diagnose_and_escalate`

**Files:** `src/global/core/pipelines/quick.yaml:110`
**Current:** `on_max: escalate`. All other pipelines use `diagnose_and_escalate`. The `errors.md` E6-AGENT procedure requires diagnosis before escalation.
**Target:** Change to `on_max: diagnose_and_escalate` or document why Quick skips diagnosis.

### H-06 — `budget.sh` appends to `budget` block instead of `budget.by_agent`

**Files:** `src/global/lib/budget.sh:230`, `src/schemas/status.schema.yaml:84`
**Current:** `moira_budget_record_agent` appends per-agent entries under top-level `budget:` key. Schema defines structured sub-field `budget.by_agent`.
**Target:** Either fix the append target to `budget.by_agent` (requires `yaml-utils.sh` enhancement for nested append) or restructure schema to match current behavior.

### H-07 — Orchestrator budget thresholds inconsistent across 3 files

**Files:** `src/global/lib/budget.sh:289-293`, `src/global/skills/orchestrator.md:221-226`, `src/global/skills/gates.md:54`
**Current:** `budget.sh` has 3 levels (normal/warning at >40%/critical at >60%). Orchestrator.md has 4 levels (healthy/monitor at 25%/warning at 40%/critical at 60%). Gates.md emoji uses 3 zones (✅ <25%/⚠ 25-60%/🔴 >60%). The Monitor band (25-40%) in orchestrator.md maps to `normal` in shell and ⚠ in gates.md — creating a visual inconsistency.
**Target:** Unify to a single threshold definition. Recommend 3 levels matching schema enum. Update orchestrator.md to drop "Monitor" or add it to schema enum.

### H-08 — `status.schema.yaml` `retries` sub-fields undefined

**Files:** `src/schemas/status.schema.yaml:72-75`, `src/global/skills/errors.md:617-623`, `src/global/lib/budget.sh:439`
**Current:** Schema defines `retries` as opaque `block`. Code and skills use `retries.quality`, `retries.agent_failures`, `retries.budget_splits`, `retries.total`.
**Target:** Define sub-fields in schema: `quality: number`, `agent_failures: number`, `budget_splits: number`, `total: number`, all default 0.

### H-09 — `state.sh` passes step name instead of agent role to `moira_budget_record_agent`

**Files:** `src/global/lib/state.sh:182`, `src/global/lib/budget.sh:195-201`
**Current:** `moira_state_agent_done` passes `"$step_name"` (e.g., `"implementation"`) as the `role` parameter. Budget lookup via `_moira_budget_get_agent_budget "$agent_role"` fails silently (returns 0) because step names don't match budget keys.
**Target:** Pass agent role name (e.g., `"hephaestus"`) instead of step name. Requires `moira_state_agent_done` to accept role as a separate parameter.

### H-10 — `gates.md` reads `retries.total` but no shell code writes it

**Files:** `src/global/skills/gates.md:62`, `src/schemas/status.schema.yaml:72-75`
**Current:** Gates.md health report displays `retries.total` from status.yaml. No shell function increments this field. `budget.sh` writes `retries.budget_splits` only.
**Target:** Either add a shell function to maintain `retries.total` as sum of sub-counters, or have gates.md compute total from individual fields.

### H-11 — Role YAMLs missing `quality_map` access for Metis (L1), Daedalus (L2), Themis (L1)

**Files:** `src/global/core/rules/roles/metis.yaml`, `src/global/core/rules/roles/daedalus.yaml`, `src/global/core/rules/roles/themis.yaml`, `src/global/core/knowledge-access-matrix.yaml`
**Current:** All three role YAMLs omit `quality_map` from their `knowledge_access` block. The matrix and agents.md both specify non-null access levels.
**Target:** Add `quality_map: L1` to metis.yaml, `quality_map: L2` to daedalus.yaml, `quality_map: L1` to themis.yaml.

### H-12 — Apollo NEVER constraint "never select pipeline" missing from role YAML

**Files:** `src/global/core/rules/roles/apollo.yaml:22-25`, `design/architecture/agents.md:44`
**Current:** Design doc explicitly states "Classifier does NOT return pipeline= — pipeline selection is the orchestrator's responsibility." This is not encoded as a NEVER constraint in apollo.yaml. Art 1.2 requires explicit NEVER constraints.
**Target:** Add `"Never select or specify the pipeline type — that is the orchestrator's responsibility"` to apollo.yaml never block.

### H-13 — Constitution Art 1.2 says Apollo "determines pipeline" — agents.md/D-062 say it does NOT

**Files:** `design/CONSTITUTION.md:23`, `design/architecture/agents.md:44`, `design/decisions/log.md` (D-062)
**Current:** Constitution line 23: "Classifier: determines task size and **pipeline**". Design doc and D-062 explicitly say Apollo does NOT select the pipeline.
**Target:** **Requires user action.** Constitution line 23 should be amended to "determines task size and confidence level (input to pipeline selection)" to match D-062. Only the user can modify the Constitution.

### H-14 — `distribution.md` quality file names use old flat scheme

**Files:** `design/architecture/distribution.md:222-225`
**Current:** Lists `correctness.yaml`, `performance.yaml`, `security.yaml`, `standards.yaml`.
**Target:** Should be `q1-completeness.yaml`, `q2-soundness.yaml`, `q3-feasibility.yaml`, `q4-correctness.yaml`, `q5-coverage.yaml`.

### H-15 — `distribution.md` role file names use functional English, not Greek names

**Files:** `design/architecture/distribution.md:209-219`
**Current:** Lists `classifier.yaml`, `explorer.yaml`, etc.
**Target:** Should use D-034 Greek names: `apollo.yaml`, `hermes.yaml`, etc.

### H-16 — `distribution.md` init Step 4 references preset system removed by D-060

**Files:** `design/architecture/distribution.md:299`
**Current:** Step 4 says "from preset + scan results".
**Target:** Should say "from scan results" — presets were removed by D-060.

### H-17 — `testing.md` says "23 checks" but Constitution has 19 invariants

**Files:** `design/subsystems/testing.md:28`, `design/CONSTITUTION.md`, `design/subsystems/self-protection.md:204`
**Current:** testing.md Layer 1: "Constitutional invariants (23 checks)". self-protection.md correctly says 19. Constitution has 19 sub-articles.
**Target:** Change "23 checks" to "19 checks".

### H-18 — Daedalus quality-map access: agents.md/knowledge.md say L2, D-039 says L0

**Files:** `design/architecture/agents.md:176`, `design/subsystems/knowledge.md:25`, `design/decisions/log.md` (D-039)
**Current:** agents.md and knowledge.md both specify L2 quality-map for Daedalus. D-039 explicitly sets `daedalus=L0`. Direct contradiction between the decision log and two design documents.
**Target:** **Requires user decision.** Either update D-039 to match agents.md (L2) or update agents.md and knowledge.md to match D-039 (L0). The implementation (knowledge-access-matrix.yaml) uses L2, suggesting D-039 text is stale.

---

## Medium

### M-01 — Role YAMLs missing `quality_map: null` and `failures: null` for schema completeness

**Files:** `apollo.yaml`, `hermes.yaml`, `hephaestus.yaml`, `aletheia.yaml` (all in `src/global/core/rules/roles/`)
**Current:** These agents have null access for both fields per the matrix, but the YAML files omit the fields entirely.
**Target:** Add `quality_map: null` and `failures: null` to each for schema completeness.

### M-02 — Role YAMLs missing `write_access` block (Mnemosyne, Hermes, Themis)

**Files:** `mnemosyne.yaml`, `hermes.yaml`, `themis.yaml` (all in `src/global/core/rules/roles/`)
**Current:** Matrix defines write access for these agents. Role YAMLs have no `write_access` field.
**Target:** Add `write_access` blocks mirroring the matrix entries.

### M-03 — `dispatch.md` assembly path table omits Mnemosyne and Argus

**Files:** `src/global/skills/dispatch.md:34-39`
**Current:** Table lists 8 agents across pipelines. Mnemosyne (post-task) and Argus (user-invoked) are absent.
**Target:** Add footnote: Mnemosyne uses simplified assembly (background post-task), Argus uses simplified assembly (user-invoked).

### M-04 — `dispatch.md` Prompt Template response format omits `QUALITY:` line

**Files:** `src/global/skills/dispatch.md:74-80`
**Current:** Template says "exact format" with STATUS/SUMMARY/ARTIFACTS/NEXT. QUALITY line is added separately via quality injection but contradicts "exact" phrasing.
**Target:** Add conditional QUALITY line to the template format block.

### M-05 — `dispatch.md` budget lookup chain doesn't include role YAML budget field

**Files:** `src/global/skills/dispatch.md:253-255`
**Current:** Lookup: `budgets.yaml → config.yaml → schema defaults`. Role YAML `budget:` field is not in the chain.
**Target:** Either add role YAML as last fallback or declare role YAML `budget` as the canonical source for schema defaults.

### M-06 — Hermes NEVER constraint for monorepo scope expansion not in `never` block

**Files:** `src/global/core/rules/roles/hermes.yaml:21-25`
**Current:** Monorepo scope reporting is in `capabilities`, not `never` block.
**Target:** Add `"Never silently expand exploration scope — report E2-SCOPE if additional packages are needed"` to never block.

### M-07 — Quick Pipeline final gate includes `test` option not in design doc

**Files:** `src/global/core/pipelines/quick.yaml:77`, `design/architecture/pipelines.md:43-46`
**Current:** YAML includes `test` as final gate option. Design doc Quick flow only shows `done/tweak/redo/diff`.
**Target:** Either remove `test` from Quick final gate YAML or add it to pipelines.md Quick flow.

### M-08 — Phase gate (Full Pipeline) has no `modify` option

**Files:** `src/global/core/pipelines/full.yaml:137-148`, `src/global/skills/gates.md:199-205`
**Current:** Phase gate options: `proceed`, `checkpoint`, `abort`. No way to request phase rework without full abort.
**Target:** Add `modify` option to phase gate (re-dispatch phase agents with feedback).

### M-09 — `moira_state_agent_done` referenced in orchestrator.md with no invocation instruction

**Files:** `src/global/skills/orchestrator.md:246`
**Current:** Referenced as calling `moira_budget_orchestrator_check` internally. No instruction on when/how the orchestrator invokes it.
**Target:** Add explicit instruction: "After each agent returns, call `moira_state_agent_done <task_id> <step_name> <tokens_used>`."

### M-10 — `gates.md` health report context emoji thresholds don't match orchestrator.md warning levels

**Files:** `src/global/skills/gates.md:54`, `src/global/skills/orchestrator.md:221-225`
**Current:** Gates.md: ⚠ at 25%. Orchestrator warning prompt at 40%. User sees ⚠ before any warning is actionable.
**Target:** Align emoji boundaries with orchestrator action thresholds (⚠ at 40%).

### M-11 — `telemetry.schema.yaml` `agents_called[].context_pct` and `.duration_sec` have no documented write path

**Files:** `src/schemas/telemetry.schema.yaml:67-72`, `src/global/skills/orchestrator.md:278-313`
**Current:** Two telemetry sub-fields have no write instruction in completion flow.
**Target:** Add write instructions to orchestrator.md completion flow.

### M-12 — Quality gate agent mapping is prose-only, not machine-readable in pipeline YAMLs

**Files:** `src/global/skills/orchestrator.md:95`
**Current:** Q1-Q5 → agent mapping exists only in orchestrator prose. Pipeline step definitions have no `quality_gate` field.
**Target:** Consider adding `quality_gate: Q4` (etc.) to relevant pipeline step definitions.

### M-13 — `status.schema.yaml` `warnings` and `gates` blocks have no sub-field definitions

**Files:** `src/schemas/status.schema.yaml:68-75,88-92`
**Current:** Both defined as opaque `block` type. Shell code writes structured entries to both.
**Target:** Define array item schemas for both fields.

### M-14 — `telemetry.schema.yaml` uses incompatible enum/object format

**Files:** `src/schemas/telemetry.schema.yaml`, `src/global/lib/yaml-utils.sh` (`moira_yaml_validate`)
**Current:** Uses `type: object` with nested `fields:` and `values:` enum syntax. Validator handles neither.
**Target:** Either restructure telemetry schema to flat format or enhance validator.

### M-15 — `overview.md` duplicate `config/` block in project layer

**Files:** `design/architecture/overview.md:195-204`
**Current:** config/ directory block appears twice (copy-paste error).
**Target:** Remove the duplicate.

### M-16 — `overview.md` lists `project-config.tmpl` — file doesn't exist

**Files:** `design/architecture/overview.md:124`
**Current:** Template listed but config is generated inline by bootstrap.sh heredoc.
**Target:** Remove reference or create the template file.

### M-17 — `overview.md` global/project hooks ambiguity

**Files:** `design/architecture/overview.md:119-121,259-262`
**Current:** Both global and project layers show `hooks/` with same files. Only global hooks are registered in settings.json.
**Target:** Clarify that global hooks are executables; project hooks/ is placeholder.

### M-18 — `distribution.md` lib/ section missing 7 Phase 4-7 files

**Files:** `design/architecture/distribution.md:243-246`
**Current:** Lists only 4 of 11 lib files.
**Target:** Add `bootstrap.sh`, `bench.sh`, `budget.sh`, `knowledge.sh`, `quality.sh`, `rules.sh`, `settings-merge.sh`.

### M-19 — `overview.md` missing `knowledge/libraries/` directory

**Files:** `design/architecture/overview.md:205-230`, `design/subsystems/knowledge.md:203`, `design/subsystems/mcp.md:127-138`
**Current:** knowledge/ section omits `libraries/` subdirectory for cached MCP docs.
**Target:** Add `libraries/` to knowledge/ structure in overview.md.

### M-20 — `commands.md` missing `/moira bench` and `/moira health` commands

**Files:** `design/architecture/commands.md`, `design/subsystems/testing.md:774-783`
**Current:** Bench and health commands fully specified in testing.md but absent from commands.md.
**Target:** Add both command groups to commands.md.

### M-21 — `self-protection.md` constitutional check schemas reference wrong file paths

**Files:** `design/subsystems/self-protection.md:215,231,248,262,270`
**Current:** References `src/agents/*.md` and `src/skills/orchestrator.md` (missing `global/` prefix).
**Target:** Update to `src/global/core/rules/roles/*.yaml` and `src/global/skills/orchestrator.md`.

### M-22 — `self-monitoring.md` guard.sh pseudocode includes Grep/Glob, contradicting D-072

**Files:** `design/subsystems/self-monitoring.md:82-87`, `design/decisions/log.md` (D-072)
**Current:** Pseudocode checks for `Read|Write|Edit|Grep|Glob`. D-072 says only check `Read|Write|Edit`.
**Target:** Remove `Grep|Glob` from the violation pattern.

### M-23 — `self-monitoring.md` warning display example shows 58% triggering Critical (threshold is >60%)

**Files:** `design/subsystems/self-monitoring.md:108`
**Current:** Example shows "Context usage: 58%" with checkpoint recommendation. Critical threshold is >60%.
**Target:** Change example value to 62% or higher.

### M-24 — `knowledge.md` package-map access levels not reflected in agent access matrix

**Files:** `design/subsystems/knowledge.md:64-80`
**Current:** Package map defines per-agent access levels (Classifier L0, Explorer L1, Architect L1) but the matrix has no package-map column.
**Target:** Either add package-map as 7th matrix dimension or clarify it's a sub-dimension of project-model.

---

## Low

### L-01 — Role YAMLs: `daedalus.yaml` missing `failures: null` for schema completeness

**Files:** `src/global/core/rules/roles/daedalus.yaml`
**Fix:** Add `failures: null`.

### L-02 — Budget notation inconsistency (20000 vs 20k) between design docs and YAMLs

**Files:** All role YAMLs vs `design/architecture/agents.md`
**Fix:** Cosmetic. No value mismatch.

### L-03 — `config.schema.yaml` `orchestrator_max_percent` is dead/unused

**Files:** `src/schemas/config.schema.yaml:66-70`
**Fix:** Mark as `# not yet active` or remove.

### L-04 — `config.schema.yaml` `deep_scan_pending` lifecycle ownership undocumented

**Files:** `src/schemas/config.schema.yaml:184-187`
**Fix:** Add description: "cleared by orchestrator at first pipeline run".

### L-05 — Schema location paths use `{id}` vs `{task_id}` inconsistently

**Files:** `manifest.schema.yaml:4`, `status.schema.yaml:4` vs `findings.schema.yaml:4`
**Fix:** Standardize to `{task_id}`.

### L-06 — `quality.sh` glob `*-Q*.yaml` too broad

**Files:** `src/global/lib/quality.sh:123`
**Fix:** Tighten to `*-Q[1-5].yaml`.

### L-07 — `current.schema.yaml` step field has no enum; validation only in shell code

**Files:** `src/schemas/current.schema.yaml:29`, `src/global/lib/state.sh:61-62`
**Fix:** Add step enum to schema matching pipeline definitions.

### L-08 — `dispatch.md` references `response-contract.yaml` file but `rules.sh` hardcodes contract inline

**Files:** `src/global/skills/dispatch.md:47`, `src/global/lib/rules.sh:469-476`
**Fix:** Document that shell assembly uses inline contract, or switch to file read.

### L-09 — `naming.md` assigns "Aletheia" to both Tester agent and Knowledge Base component

**Files:** `design/architecture/naming.md:47,57`
**Fix:** Add footnote acknowledging intentional dual-use, or rename knowledge base component.

### L-10 — `IMPLEMENTATION-ROADMAP.md` hardcodes private project name in success criteria

**Files:** `design/IMPLEMENTATION-ROADMAP.md:281`
**Fix:** Generalize to "on a real project".

### L-11 — `multi-developer.md` duplicate config/ section (same as M-15 pattern)

**Files:** `design/subsystems/multi-developer.md:20`
**Fix:** Remove duplicate.

### L-12 — `distribution.md` /moira init step numbering skips Step 5

**Files:** `design/architecture/distribution.md:284-345`
**Fix:** Renumber or add missing Step 5 (scaffold creation).

---

## Fix Dependency Graph

```
C-01 (budget.sh enum)        → standalone
C-02 (escape-hatch format)   → standalone
C-03 (telemetry write path)  → standalone
C-04 (dispatch L0/L2 label)  → standalone

H-01 (completion.action enum) → standalone
H-02 (rearchitect mapping)   → depends on H-01 (both touch gate decision enums)
H-06 (budget append target)  → depends on yaml-utils.sh enhancement OR schema restructure
H-07 (budget thresholds)     → depends on M-10 (emoji alignment)
H-08 (retries sub-fields)    → depends on H-10 (retries.total write path)
H-09 (state.sh role param)   → standalone
H-11 (role YAML quality_map) → standalone
H-12 (Apollo NEVER)          → depends on H-13 (Constitution amendment — user decision)
H-13 (Constitution Art 1.2)  → requires user decision
H-18 (Daedalus L0 vs L2)    → requires user decision

M-01 (null fields)           → after H-11
M-14 (telemetry schema fmt)  → after C-03
```

## Parallel Fix Groups

**Group A — Standalone critical fixes (no dependencies)**
- C-01: `budget.sh` enum fix
- C-02: `escape-hatch.md` command format
- C-03: `telemetry.schema.yaml` write instructions in orchestrator.md
- C-04: `dispatch.md` L0→L2 label

**Group B — Schema fixes (independent of each other)**
- H-01: `status.schema.yaml` completion.action enum
- H-08: `status.schema.yaml` retries sub-fields
- M-13: `status.schema.yaml` warnings/gates sub-fields
- L-05: Schema location path standardization
- L-07: `current.schema.yaml` step enum

**Group C — Pipeline YAML / gate fixes**
- H-02: `rearchitect` gate mapping (after H-01)
- H-03: Reflection dispatch table
- H-04: Alternative selection state recording
- H-05: Quick E6-AGENT `diagnose_and_escalate`
- M-07: Quick final gate `test` option
- M-08: Phase gate `modify` option

**Group D — Role YAML fixes**
- H-11: Add `quality_map` to metis/daedalus/themis
- H-12: Apollo NEVER constraint (after H-13 user decision)
- M-01: Add null fields to remaining role YAMLs
- M-02: Add write_access blocks
- M-06: Hermes scope NEVER constraint
- L-01: Daedalus `failures: null`

**Group E — Shell code fixes**
- H-06: `budget.sh` append target
- H-09: `state.sh` role parameter
- H-10: `retries.total` write function (after H-08)
- L-06: `quality.sh` glob tightening

**Group F — Skill/doc fixes (independent of each other)**
- H-07 + M-10: Budget threshold unification
- M-03-M-06, M-09, M-11-M-12: dispatch.md and orchestrator.md updates
- M-14: Telemetry schema format alignment

**Group G — Design document updates (all independent)**
- H-14-H-16: distribution.md updates
- H-17: testing.md check count
- M-15-M-24: overview.md, commands.md, self-protection.md, self-monitoring.md, knowledge.md
- L-02-L-04, L-08-L-12: Low-severity doc fixes

**Group U — User decisions required (block downstream fixes)**
- H-13: Constitution Art 1.2 amendment (Apollo pipeline wording)
- H-18: Daedalus quality-map access level (D-039 vs agents.md)

## Suggested Fix Order

1. **Group U** — Get user decisions first (H-13, H-18)
2. **Group A** — Critical fixes (all standalone, parallel)
3. **Group B** — Schema fixes (parallel)
4. **Group D** — Role YAML fixes (parallel, some depend on Group U)
5. **Group E** — Shell code fixes (some depend on Group B)
6. **Group C** — Pipeline/gate fixes (some depend on Group B)
7. **Group F** — Skill/doc updates (parallel)
8. **Group G** — Design document updates (parallel)
