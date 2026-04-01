# Moira System Audit Report

**Date:** 2026-03-16
**Scope:** Full system — agent architecture, pipelines & gates, schemas & state, design document cross-references
**Previous audit:** `reports/archive/2026-03-16-system-audit.md` (50 findings)

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 6 |
| Medium | 14 |
| Low | 9 |
| **Total** | **30** |

**Overall health:** Good. No runtime-breaking critical bugs. The system's enums, budgets, state paths (D-061), and Constitutional NEVER constraints are all consistent across implementation. The main issues are: one phantom decision reference (D-098), schema/skill signature mismatches that could cause silent failures, and ongoing documentation drift where agents.md lags behind role YAMLs.

**Prior audit status:** Many findings from the 2026-03-16 audit have been resolved (C-01, C-02, H-01, H-03, H-04, H-08, M-01, M-06, M-07, M-08, M-15, M-20, M-21). Several remain open and are re-reported below.

---

## Critical

### F-001 | D-098 referenced but does not exist in Decision Log

- **Files:**
  - `design/architecture/overview.md` line 87 — references `D-098`
  - `design/decisions/log.md` — ends at D-096
- **Current state:** overview.md references `D-098` for `.version-snapshot/` ("Upgrade three-way comparison baseline (D-098)"). D-097 and D-098 do not exist in the Decision Log.
- **Target state:** D-098 must be added to the decision log, or the reference corrected.
- **Fix:** Add D-098 entry to `design/decisions/log.md` documenting the version snapshot decision for the upgrade three-way comparison baseline.
- **Dependencies:** None.

---

## High

### F-002 | `bootstrap.sh` writes `freshness_days` instead of `freshness_confidence_threshold`

- **Files:**
  - `src/global/lib/bootstrap.sh` line 190 — writes `freshness_days: 30`
  - `src/schemas/config.schema.yaml` line 122 — defines `freshness_confidence_threshold`
- **Current state:** bootstrap.sh writes `knowledge.freshness_days: 30`. The schema defines `knowledge.freshness_confidence_threshold` (default 30, percentage). Different field name, different semantics (days vs percentage).
- **Target state:** bootstrap.sh writes `knowledge.freshness_confidence_threshold: 30`.
- **Fix:** Change `freshness_days: 30` to `freshness_confidence_threshold: 30` in bootstrap.sh line 190.
- **Dependencies:** None.

### F-003 | E5-QUALITY retry count ambiguity between `errors.md` and `retry.sh`

- **Files:**
  - `src/global/skills/errors.md` lines 270, 287, 310
  - `src/global/lib/retry.sh` line 36 — `_MOIRA_RETRY_HARD_LIMIT_E5=2`
- **Current state:** errors.md says "After 3 failures → escalate" and displays "QUALITY GATE FAILED (3 attempts)". retry.sh hard limit is 2 (retries). The text "3 attempts" in errors.md is ambiguous — 3 total attempts (1 original + 2 retries) matches the hard limit, but errors.md describes "Attempt 1" and "Attempt 2" then says "After 3 failures", implying 3 retry attempts.
- **Target state:** Unambiguous text: "After 2 retries (3 total attempts) → escalate". Display: "QUALITY GATE FAILED (2 retries exhausted)".
- **Fix:** Clarify errors.md lines 270, 287, 310 to explicitly state "2 retries" or "3 total attempts (1 original + 2 retries)".
- **Dependencies:** None.

### F-004 | `git.pre_task_head` field used in code but missing from `status.schema.yaml`

- **Files:**
  - `src/global/skills/orchestrator.md` line 425
  - `src/global/lib/checkpoint.sh` line 87
  - `src/schemas/status.schema.yaml` — field absent
- **Current state:** orchestrator.md and checkpoint.sh reference `status.yaml git.pre_task_head` for diff computation. The field does not exist in the schema.
- **Target state:** `status.schema.yaml` defines `git.pre_task_head` (type: string, required: false, default: null).
- **Fix:** Add `git.pre_task_head` field to `status.schema.yaml`.
- **Dependencies:** None.

### F-005 | D-093a referenced but does not exist as a sub-decision

- **Files:**
  - `design/guides/metrics-guide.md` line 212 — references `D-093a`
  - `design/decisions/log.md` — has D-093 but no D-093a
- **Current state:** Metrics guide references "D-093a" for the 5-point trend threshold. No such sub-decision exists.
- **Target state:** Either create D-093a as a sub-entry of D-093, or change the reference to D-093.
- **Fix:** Check if D-093 covers the trend threshold. If so, change "D-093a" to "D-093". If not, add D-093a.
- **Dependencies:** None.

### F-006 | Metrics guide uses wrong Greek name "Dike" for Auditor (should be "Argus")

- **Files:**
  - `design/guides/metrics-guide.md` line 362
  - `design/architecture/naming.md` line 47 — canonical name is "Argus"
- **Current state:** Budget table says `Auditor (Dike)`.
- **Target state:** `Auditor (Argus)`.
- **Fix:** Change "Dike" to "Argus" on line 362.
- **Dependencies:** None.

### F-007 | `distribution.md` commands listing missing 3 command files

- **Files:**
  - `design/architecture/distribution.md` lines 286-296
  - `src/commands/moira/` — has 13 files, distribution.md lists 10
- **Current state:** Missing: `bench.md`, `health.md`, `upgrade.md`.
- **Target state:** All 13 command files listed.
- **Fix:** Add the 3 missing entries to distribution.md commands listing.
- **Dependencies:** None.

---

## Medium

### F-008 | agents.md missing NEVER constraints documented in role YAMLs (5 agents, 14 constraints)

- **Files:**
  - `design/architecture/agents.md` — Rules sections for Apollo, Hermes, Athena, Metis, Daedalus
  - `src/global/core/rules/roles/apollo.yaml` line 25
  - `src/global/core/rules/roles/hermes.yaml` lines 22-27
  - `src/global/core/rules/roles/athena.yaml` lines 19-23
  - `src/global/core/rules/roles/metis.yaml` lines 22-27
  - `src/global/core/rules/roles/daedalus.yaml` lines 44-47
- **Current state:** Role YAMLs are correctly stricter than agents.md. agents.md is incomplete as the canonical design reference:
  - **Apollo** (1 missing): pipeline-selection prohibition (only informal "Note:", not a formal Rule)
  - **Hermes** (3 missing): no architectural suggestions, no file modifications, no scope expansion
  - **Athena** (3 missing): no specific technologies, no code/pseudocode, no assuming requirements
  - **Metis** (3 missing): no implementation code, no task decomposition, no requirements decisions
  - **Daedalus** (2 missing): no choosing between alternatives, no implementation code
- **Target state:** All 14 NEVER constraints added to agents.md as formal Rules.
- **Fix:** Add missing bullets to each agent's Rules section in agents.md.
- **Dependencies:** None. Prior ref: M-02 from 2026-03-16 audit.

### F-009 | `moira_quality_aggregate_task` signature mismatch (task_id vs task_dir)

- **Files:**
  - `src/global/skills/orchestrator.md` line 378 — calls with `<task_id>`
  - `src/global/lib/quality.sh` line 107 — expects `<task_dir>`
- **Current state:** Orchestrator skill passes task ID; function expects directory path.
- **Target state:** Orchestrator references `moira_quality_aggregate_task <task_dir>`.
- **Fix:** Update orchestrator.md line 378 to use task directory path.
- **Dependencies:** None.

### F-010 | `checkpoint.sh` reads `description` from `current.yaml` but field not in schema

- **Files:**
  - `src/global/lib/checkpoint.sh` line 295
  - `src/schemas/current.schema.yaml` — no `description` field
- **Current state:** checkpoint.sh reads `description` from current.yaml; falls back to status.yaml.
- **Target state:** Remove the current.yaml read (use only status.yaml which has the field), or add field to current.schema.yaml.
- **Fix:** Preferred: remove lines 295-296 from checkpoint.sh. Alternative: add `description` to current.schema.yaml.
- **Dependencies:** None.

### F-011 | `moira_knowledge_update_quality_map` invocations omit required parameters

- **Files:**
  - `src/global/skills/orchestrator.md` lines 68, 381
  - `src/global/lib/knowledge.sh` line 650 — requires `<task_dir> <quality_map_dir>`
- **Current state:** Orchestrator says "call with task findings" without specifying both args.
- **Target state:** Full calling convention: `moira_knowledge_update_quality_map <task_dir> <quality_map_dir>`.
- **Fix:** Update orchestrator.md references to specify both arguments.
- **Dependencies:** None.

### F-012 | E9-SEMANTIC max_attempts semantics undefined when sharing E5-QUALITY retry counters

- **Files:**
  - `src/global/core/pipelines/quick.yaml` line 128 (`max_attempts: 1`)
  - `src/global/core/pipelines/standard.yaml` line 193 (`max_attempts: 2`)
  - `src/global/core/pipelines/full.yaml` line 213 (`max_attempts: 2`)
  - `src/global/core/pipelines/decomposition.yaml` line 196 (`max_attempts: 2`)
  - `src/global/skills/errors.md` lines 501-507
- **Current state:** E9-SEMANTIC's notes say it uses "E5-QUALITY retry path" with "same retry counters". But E9 has its own `max_attempts` field differing from E5's. The relationship is undefined.
- **Target state:** Either remove `max_attempts` from E9 entries (add note: "Uses E5-QUALITY retry budget"), or document that E9 has a separate cap within E5's budget.
- **Fix:** Add clarifying note to all four pipeline YAMLs and errors.md.
- **Dependencies:** None.

### F-013 | Orchestrator Section 6 budget thresholds differ from pipelines.md error table

- **Files:**
  - `src/global/skills/orchestrator.md` lines 291-295 — 4-tier: <25% healthy, 25-40% monitor, 40-60% warning, >60% critical (mandatory checkpoint)
  - `design/architecture/pipelines.md` lines 297-298 — >40% warning, >60% "recommend checkpoint"
- **Current state:** pipelines.md says "recommend" at 60%; orchestrator.md says "mandatory". pipelines.md omits the 25% "Monitor" tier.
- **Target state:** pipelines.md matches orchestrator.md or defers to it entirely.
- **Fix:** Update pipelines.md lines 297-298 to match the 4-tier model, or replace with "See orchestrator.md Section 6".
- **Dependencies:** None.

### F-014 | pipelines.md Quick Pipeline `test` gate option lacks ad-hoc dispatch note

- **Files:**
  - `design/architecture/pipelines.md` lines 43-47
  - `src/global/core/pipelines/quick.yaml` lines 78-81
- **Current state:** pipelines.md lists `test` as a Quick Pipeline final gate option without noting it dispatches Aletheia ad-hoc (not a pipeline step). quick.yaml documents this correctly.
- **Target state:** pipelines.md notes the ad-hoc nature.
- **Fix:** Add parenthetical: `test -- run additional tests (dispatches Aletheia ad-hoc, not a pipeline step)`.
- **Dependencies:** None.

### F-015 | overview.md data flow shows `.moira/` instead of `.moira/`

- **Files:**
  - `design/architecture/overview.md` line 67
- **Current state:** Data flow diagram shows `.moira/state/tasks/{id}/classification.md`.
- **Target state:** `.moira/state/tasks/{id}/classification.md` per D-061.
- **Fix:** Update the path. Prior ref: M-13 from 2026-03-16 audit.
- **Dependencies:** None.

### F-016 | Contradicting freshness models across design docs, config, and errors.md

- **Files:**
  - `design/subsystems/knowledge.md` — exponential decay model
  - `src/schemas/config.schema.yaml` — `freshness_days` (time-based)
  - `src/global/skills/errors.md` — ">20 tasks" (count-based)
  - `src/global/lib/knowledge.sh` — exponential decay (correct)
- **Current state:** Three different freshness models coexist: exponential decay (design + implementation), time-based (config), count-based (errors.md).
- **Target state:** Single model: exponential decay per knowledge.md.
- **Fix:** Update config and errors.md to reference confidence-based thresholds. Related to F-002.
- **Dependencies:** F-002 should be done first.

### F-017 | knowledge.md access matrix missing write access information

- **Files:**
  - `design/subsystems/knowledge.md` lines 20-31
  - `src/global/core/knowledge-access-matrix.yaml` — has write access data
- **Current state:** knowledge.md matrix shows read access levels but not write access.
- **Target state:** Write access noted via footnote or additional row.
- **Fix:** Add write access footnote to the matrix table.
- **Dependencies:** None.

### F-018 | SYSTEM-DESIGN.md misplaces blocker-resolution-design under Decisions

- **Files:**
  - `design/SYSTEM-DESIGN.md` line 46
- **Current state:** Lists blocker-resolution-design spec under "Decisions" section.
- **Target state:** Move to "Implementation Specs" section.
- **Fix:** Relocate the entry.
- **Dependencies:** None.

### F-019 | Roadmap Phase 12 missing references to D-095 and D-096

- **Files:**
  - `design/IMPLEMENTATION-ROADMAP.md` lines 231-248
- **Current state:** Phase 12 section doesn't mention D-095 (max_attempts semantics) or D-096 (orchestrator state management) which were decided during Phase 12 work.
- **Target state:** Phase 12 references both decisions.
- **Fix:** Add note referencing D-095 and D-096 in Phase 12 section.
- **Dependencies:** None.

### F-020 | SYSTEM-DESIGN.md index missing active spec file listing

- **Files:**
  - `design/SYSTEM-DESIGN.md`
  - `design/specs/` — has 5 active files
- **Current state:** Says "Active implementation specs live in `design/specs/` by convention" but doesn't list them.
- **Target state:** Either list active specs explicitly or add a clear discovery note.
- **Fix:** Add current spec file names under the Implementation Specs section.
- **Dependencies:** None.

### F-021 | Design docs not yet updated for D-095 max_attempts semantics

- **Files:**
  - `design/architecture/pipelines.md` lines 99-101
  - `design/subsystems/fault-tolerance.md` lines 109-139
- **Current state:** fault-tolerance.md still uses ambiguous "MAX RETRY: 2 attempts total" wording. D-095 was created to resolve this but the docs haven't been updated.
- **Target state:** Design docs use D-095's clarified semantics.
- **Fix:** Update fault-tolerance.md and pipelines.md. Prior ref: C-01 from 2026-03-16 audit.
- **Dependencies:** None.

---

## Low

### F-022 | Quality Checkpoint conditional gate not referenced in pipeline YAMLs

- **Files:**
  - `src/global/skills/gates.md` lines 389-430
  - All 4 pipeline YAMLs
- **Current state:** gates.md defines a Quality Checkpoint conditional gate. No pipeline YAML references it. Mechanism works via orchestrator logic, but YAML readers won't know it exists.
- **Target state:** Brief comment in each pipeline YAML near `gates:` section.
- **Fix:** Add comment: `# Conditional: Quality Checkpoint (gates.md) — triggered when quality-gate returns fail_warning`.
- **Dependencies:** None.

### F-023 | Config fields `classification.default_pipeline` and `classification.size_hints_override` unused without annotation

- **Files:**
  - `src/schemas/config.schema.yaml` lines 25-33
- **Current state:** Defined and written by bootstrap but never read. No "Reserved" annotation.
- **Target state:** Add "Reserved" annotation.
- **Fix:** Add comment: `# Reserved -- not yet read by orchestrator. Target activation: Phase 12+.`
- **Dependencies:** None.

### F-024 | Config field `audit.auto_batch_apply_risk` unused without annotation

- **Files:**
  - `src/schemas/config.schema.yaml` lines 139-143
- **Current state:** Defined and written by bootstrap but never read.
- **Target state:** Add "Reserved" annotation.
- **Fix:** Add comment: `# Reserved -- not yet read by audit system.`
- **Dependencies:** None.

### F-025 | Config field `knowledge.archival_max_entries` unused without annotation

- **Files:**
  - `src/schemas/config.schema.yaml` lines 128-130
- **Current state:** Defined and written by bootstrap but never read.
- **Target state:** Add "Reserved" annotation.
- **Fix:** Add comment: `# Reserved -- not yet enforced by knowledge archival system.`
- **Dependencies:** None.

### F-026 | E11-TRUNCATION post_exec max_attempts lower in Quick Pipeline, undocumented

- **Files:**
  - `src/global/core/pipelines/quick.yaml` line 133 (`max_attempts: 1`)
  - Other pipeline YAMLs (`max_attempts: 2`)
  - `src/global/skills/errors.md`
- **Current state:** Quick Pipeline has `max_attempts: 1` for E11-TRUNCATION while others have 2. Not documented as intentional.
- **Target state:** Document the exception or align.
- **Fix:** Add note to errors.md E11-TRUNCATION section, or change quick.yaml to `max_attempts: 2`.
- **Dependencies:** None.

### F-027 | overview.md missing state files in project layer tree

- **Files:**
  - `design/architecture/overview.md` (state/ section)
- **Current state:** Missing: `proposals.yaml`, `budget-accuracy.yaml`, `retry-stats.yaml`, `audit-pending.yaml`, `deep-reflection-counter.yaml`.
- **Target state:** All state files listed.
- **Fix:** Add missing files to overview.md. Prior ref: L-13 from 2026-03-16 audit.
- **Dependencies:** None.

### F-028 | overview.md project layer comment slightly ambiguous about base.yaml

- **Files:**
  - `design/architecture/overview.md` line 189
- **Current state:** Comment reads "Layer 1: project-adapted copy" which is correct but could confuse.
- **Target state:** Optionally clarify: "Layer 1: project-adapted base rules (copied from global, may diverge)".
- **Fix:** Minor wording update.
- **Dependencies:** None.

### F-029 | Reports directory convention undocumented (reports in archive/ subdirectory)

- **Files:**
  - `design/SYSTEM-DESIGN.md` — references `reports/`
  - `design/reports/` — all reports in `archive/` subdirectory
- **Current state:** SYSTEM-DESIGN says "reports/" but reports live in "reports/archive/".
- **Target state:** Document the archive convention.
- **Fix:** Update SYSTEM-DESIGN.md or add a note about the archive subdirectory.
- **Dependencies:** None.

### F-030 | SYSTEM-DESIGN.md guides section singular vs plural

- **Files:**
  - `design/SYSTEM-DESIGN.md` line 49
- **Current state:** Section header "Guides" but only one guide exists.
- **Target state:** Add note "(additional guides will be added as needed)" or leave as-is.
- **Fix:** Optional — no action strictly needed.
- **Dependencies:** None.

---

## Fix Dependency Graph

```
F-002 (bootstrap freshness_days) → F-016 (freshness model alignment)
All other findings are independent.
```

## Parallel Fix Groups

**Group A — Critical + High priority (do first):**
- F-001: Add D-098 to decision log
- F-002: Fix bootstrap.sh freshness field name
- F-003: Clarify errors.md retry count wording
- F-004: Add git.pre_task_head to status.schema.yaml
- F-005: Resolve D-093a reference
- F-006: Fix "Dike" → "Argus" in metrics guide
- F-007: Add 3 missing commands to distribution.md

**Group B — Medium design doc alignment (parallel with Group A):**
- F-008: Add 14 NEVER constraints to agents.md
- F-013: Align pipelines.md budget thresholds with orchestrator.md
- F-014: Add ad-hoc test dispatch note to pipelines.md
- F-015: Fix overview.md .moira/ path to .moira/
- F-017: Add write access to knowledge.md matrix
- F-018: Move blocker-resolution in SYSTEM-DESIGN.md
- F-019: Add D-095/D-096 refs to roadmap
- F-020: List active specs in SYSTEM-DESIGN.md
- F-021: Update design docs for D-095 semantics

**Group C — Medium implementation fixes (parallel with B):**
- F-009: Fix quality_aggregate_task signature in orchestrator.md
- F-010: Fix checkpoint.sh description read
- F-011: Fix knowledge_update_quality_map params in orchestrator.md
- F-012: Clarify E9-SEMANTIC max_attempts semantics

**Group D — After F-002 completes:**
- F-016: Align freshness models across config and errors.md

**Group E — Low priority (last, all parallel):**
- F-022 through F-030: Documentation annotations and minor cleanups
