# Moira System Audit Report

**Date:** 2026-03-17
**Scope:** Full system — agent architecture, pipelines & gates, schemas & state, design document cross-references
**Prior reports consulted:** `design/reports/2026-03-17-task-testing.md`, archived reports in `design/reports/archive/`

## Summary

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 10 |
| Medium | 22 |
| Low | 16 |
| **Total** | **49** |

**Overall health:** The system is structurally sound — constitutional compliance is strong, agent definitions are consistent, and pipeline determinism holds. The primary gaps are: (1) shell library functions missing for several schema fields the orchestrator needs to write, (2) pipeline YAML `reads_from` declarations incomplete in several steps, (3) stale cross-references in design docs, and (4) one Critical missing error handler.

---

## Critical

### F-001 | Quick Pipeline Missing E10-DIVERGE Handler
**Source:** Agent 2 (P-001)
**File:** `src/global/core/pipelines/quick.yaml` (error_handlers block, lines 86–135)
**Current:** No `E10-DIVERGE` handler defined. Present in all other 3 pipelines.
**Target:** Add handler for completeness and forward compatibility. Quick Pipeline has no Analyst, so the classic conflict cannot arise, but the error taxonomy is system-wide.
**Fix:** Add `E10-DIVERGE` block to `quick.yaml` error_handlers:
```yaml
E10-DIVERGE:
  action: escalate_to_user
  display: diverge_gate
  note: "Not applicable in Quick Pipeline (no Analyst) — present for completeness"
```

---

## High

### F-002 | `checkpoint.sh` Validates Artifacts at Wrong Path
**Source:** Agent 3 (S-021)
**File:** `src/global/lib/checkpoint.sh` line 214
**Current:** `moira_checkpoint_validate` checks `${task_dir}/artifacts/${hist_step}.md`. The `artifacts/` subdirectory does not exist — task artifacts are stored directly in `state/tasks/{task-id}/`.
**Target:** Path should be `${task_dir}/${hist_step}.md`.
**Fix:** Change line 214 from `"${task_dir}/artifacts/${hist_step}.md"` to `"${task_dir}/${hist_step}.md"`.

### F-003 | `budget.sh` Appends to Wrong YAML Key
**Source:** Agent 3 (S-004)
**File:** `src/global/lib/budget.sh` line 247
**Current:** `moira_budget_record_agent` calls `moira_yaml_block_append "$status_file" "by_agent" "$budget_entry"` — uses top-level `by_agent` but schema defines `budget.by_agent` (nested). Comment at lines 235–240 acknowledges this as a workaround.
**Target:** Either extend `moira_yaml_block_append` to support dot-path keys, or restructure `status.yaml` initialization.
**Fix:** Extend `moira_yaml_block_append` in `yaml-utils.sh` to accept 2-level dot-path parent keys, then update `budget.sh` line 247 to use `"budget.by_agent"`.

### F-004 | `budget.sh` Gate Count Heuristic Unreliable
**Source:** Agent 3 (S-006)
**File:** `src/global/lib/budget.sh` lines 289–295
**Current:** `moira_budget_orchestrator_check` uses `grep -c "awaiting_gate\|gate_pending"` on `current.yaml`. This matches strings even in null values (`gate_pending: null`), giving wrong counts.
**Target:** Use only `status.yaml` gate entries, default to 0.
**Fix:** Replace lines 288–295 with:
```bash
local gate_count=0
if [[ -n "$task_id" && -f "${state_dir}/tasks/${task_id}/status.yaml" ]]; then
  gate_count=$(grep -c "^  - gate:" "${state_dir}/tasks/${task_id}/status.yaml" 2>/dev/null) || true
fi
```

### F-005 | Final Gate `after_step` Ambiguous Across All Pipelines
**Source:** Agent 2 (P-005)
**Files:** All 4 pipeline YAMLs — `quick.yaml` line 68, `standard.yaml` line 134, `full.yaml` line 154, `decomposition.yaml` line 137
**Current:** `final_gate` says `after_step: review/testing/integration` but a `completion` step exists after these in `steps[]`. The relationship between the `completion` step and `final_gate` is undefined — could cause the gate to fire twice or be orphaned.
**Target:** Unambiguous linkage: `final_gate after_step: completion` in all pipelines.
**Fix:** Change `after_step` in all 4 `final_gate` definitions to `completion`.

### F-006 | Reflection Step Not Explicit in Completion Flow (F-001 from Prior Report, Unfixed)
**Source:** Agent 2 (P-006)
**File:** `src/global/skills/orchestrator.md` line 406
**Current:** Reflection dispatch is buried in an 18-item unordered list under the `done` action in Section 7. Prior task-testing report (F-001) documented this as causing skipped reflection during real execution.
**Target:** Make reflection an explicit numbered step in the completion flow.
**Fix:** Restructure Section 7 `done` action to use numbered steps, with "Step N: Reflection Dispatch" as a clearly labeled action.

### F-007 | SYSTEM-DESIGN.md Phase 12 Specs Listed as Active (Archived on Disk)
**Source:** Agent 4 (DD-001)
**File:** `design/SYSTEM-DESIGN.md` lines 45–46
**Current:** Active specs section lists Phase 12 spec and plan, but files were moved to `design/specs/archive/` per commit `cd30f2d`.
**Target:** Move entries to Archived specs section with corrected paths.
**Fix:** Move Phase 12 entries from Active to Archived in SYSTEM-DESIGN.md, update links to `specs/archive/` paths.

### F-008 | SYSTEM-DESIGN.md Formal Methods Specs — Status Ambiguous
**Source:** Agent 4 (DD-002)
**File:** `design/SYSTEM-DESIGN.md` lines 47–48
**Current:** Two formal-methods specs remain in `design/specs/` and listed as active. Phase 12 specs were archived in the same commit, so the status of formal-methods work is unclear.
**Target:** Unambiguous status — either archive (if complete) or add status note (if ongoing).
**Fix:** Verify completion status with user. Archive or annotate accordingly.

### F-009 | Quick Pipeline Completion Step Missing `implementation.md` in `reads_from`
**Source:** Agent 2 (P-002)
**File:** `src/global/core/pipelines/quick.yaml` lines 47–52
**Current:** Completion step reads only `review.md`. Missing `implementation.md` in the dependency contract.
**Target:** Add `implementation.md` to `reads_from` for artifact lineage traceability (Art 3.1).
**Fix:** Expand `reads_from` to include both `review.md` and `implementation.md`.

### F-010 | `pipelines.md` Classification Table Missing Small+Low-Confidence Row
**Source:** Agent 2 (P-003)
**File:** `design/architecture/pipelines.md` lines 15–18
**Current:** Table shows 4 rows (Small→Quick, Medium→Standard, Large→Full, Epic→Decomposition). The confidence downgrade rule (Small+low→Standard) is only in prose, not in the table. Constitution Art 2.1 and orchestrator Section 3 both include it.
**Target:** Add a 5th row: `Small (low confidence) → Standard`.
**Fix:** Add row to classification table in pipelines.md.

### F-011 | Standard Pipeline Reviewer Missing `architecture.md` in `reads_from`
**Source:** Agent 2 (P-004)
**File:** `src/global/core/pipelines/standard.yaml` lines 65–72
**Current:** Reviewer (Themis) reads only `implementation.md` and `plan.md`. Cannot verify implementation conforms to architecture without reading `architecture.md`.
**Target:** Add `architecture.md` to reviewer's `reads_from`.
**Fix:** Add `"tasks/{task_id}/architecture.md"` to the reads_from list.

---

## Medium

### F-012 | Aletheia YAML Missing "Never Fix Bugs" in `never` Block
**Source:** Agent 1 (A-001)
**File:** `src/global/core/rules/roles/aletheia.yaml` lines 19–23
**Current:** agents.md rule "If test fails due to implementation bug → reports, doesn't fix" is in identity prose but absent from `never` block. Art 1.2 test requires explicit NEVER constraints.
**Fix:** Add `"Never fix implementation bugs found through testing — report them instead"` to `never` block.

### F-013 | Argus No Machine-Readable `write_access: false`
**Source:** Agent 1 (A-002)
**Files:** `src/global/core/rules/roles/argus.yaml`, `src/global/core/knowledge-access-matrix.yaml` line 29
**Current:** Read-only status documented only as a YAML comment. No machine-readable entry.
**Fix:** Add `write_access` block with all fields `false` to `argus.yaml`.

### F-014 | `dispatch.md` Assembly Path Table Misleading for Mnemosyne/Argus
**Source:** Agent 1 (A-003)
**File:** `src/global/skills/dispatch.md` lines 40–41
**Current:** Table structure implies Mnemosyne/Argus use pre-assembled instruction files, which is false — they use dedicated dispatch paths.
**Fix:** Move to a separate "Special Dispatch Cases" section below the table.

### F-015 | `status.yaml` `status` Field Has No Writer in Shell Libraries
**Source:** Agent 3 (S-001)
**Files:** `src/schemas/status.schema.yaml` lines 33–36; `src/global/lib/state.sh`
**Current:** Schema defines `status` enum but no shell function writes it. `reflection.sh` reads it.
**Fix:** Add `moira_state_set_status` to `state.sh`.

### F-016 | `status.yaml` `completion.*` Fields Have No Shell Writer
**Source:** Agent 3 (S-002)
**Files:** `src/schemas/status.schema.yaml` lines 127–144; `src/global/lib/state.sh`
**Current:** Orchestrator.md references direct YAML writes for `completion.action`, `completion.tweak_count`, etc. No shell function wraps these. No enum validation on write.
**Fix:** Add `moira_state_record_completion` to `state.sh` with enum validation.

### F-017 | `config.schema.yaml` `budgets.orchestrator_max_percent` Name Is Misleading
**Source:** Agent 2 (P-009), Agent 3 (S-007) — deduplicated
**File:** `src/schemas/config.schema.yaml` lines 58–64
**Current:** Field name says "max_percent" but default is 25% (the healthy/monitor boundary). Actual critical threshold is 60%.
**Fix:** Rename to `budgets.orchestrator_monitor_threshold` or clarify description.

### F-018 | `full.yaml` Architecture Gate `variant: alternative_selection` Undocumented
**Source:** Agent 2 (P-007)
**File:** `src/global/core/pipelines/full.yaml` lines 109–122
**Current:** `variant` key is not defined in any schema or orchestrator skill. Behavior relies on implicit convention.
**Fix:** Document the `variant` key in the gate definition schema or orchestrator skill, and add a `proceed` option placeholder.

### F-019 | `per_task_gate` Missing-Modify Rationale Not in `gates.md`
**Source:** Agent 2 (P-008)
**File:** `src/global/skills/gates.md` Per-Task Gate section
**Current:** YAML has a comment explaining why no `modify` option, but gates.md doesn't document this design rationale.
**Fix:** Add note to gates.md: "No `modify` option — sub-task rework handled within sub-pipeline's own final gate."

### F-020 | E9-SEMANTIC `max_attempts: 2` Conflicts with E5-QUALITY `max_attempts: 3`
**Source:** Agent 2 (P-010)
**Files:** `src/global/core/pipelines/standard.yaml` lines 193–196; `full.yaml` lines 213–216
**Current:** E9 shares E5's retry counter per errors.md, but E9 has `max_attempts: 2` while E5 has `max_attempts: 3`. Behavior is undefined when limits differ on a shared counter.
**Fix:** Align E9 `max_attempts` to match E5 (`3`) in Standard/Full/Decomposition, or remove E9's `max_attempts` and rely on E5's cap.

### F-021 | Decomposition Planner `reads_from` Missing `classification.md`
**Source:** Agent 2 (P-011)
**File:** `src/global/core/pipelines/decomposition.yaml` lines 43–51
**Current:** Daedalus reads only `epic-architecture.md` and `epic-requirements.md`. Missing `classification.md` with epic scope/confidence context.
**Fix:** Add `"tasks/{task_id}/classification.md"` to reads_from.

### F-022 | `pipelines.md` Cites `D-094a` — Wrong Decision Reference
**Source:** Agent 4 (DD-005)
**File:** `design/architecture/pipelines.md` line 299
**Current:** `| Orchestrator context >60% | Mandatory checkpoint (D-094a) |` — D-094(a) is about pipeline graph verification. The mandatory checkpoint is from D-064.
**Fix:** Change `(D-094a)` to `(D-064)`.

### F-023 | `pipelines.md` References `orchestrator.md Section 6` (Implementation, Not Design)
**Source:** Agent 4 (DD-003)
**File:** `design/architecture/pipelines.md` line 301
**Current:** Design doc cross-references implementation file for budget thresholds.
**Fix:** Replace with reference to `design/subsystems/context-budget.md`.

### F-024 | `self-monitoring.md` References `orchestrator.md Section 2` (Implementation, Not Design)
**Source:** Agent 4 (DD-004)
**File:** `design/subsystems/self-monitoring.md` line 100
**Fix:** Replace external reference with inline description of agent-violation logging behavior.

### F-025 | `self-monitoring.md` Critical Threshold Action Text Abbreviated
**Source:** Agent 4 (DD-006)
**File:** `design/subsystems/self-monitoring.md` line 115
**Current:** Says "Recommend checkpoint" — missing "+ new session" from `context-budget.md`.
**Fix:** Update to "Recommend checkpoint + new session".

### F-026 | SYSTEM-DESIGN.md Missing F-001/F-002 Fix Specs
**Source:** Agent 4 (DD-008)
**File:** `design/SYSTEM-DESIGN.md` lines 44–49
**Current:** Two new specs (`2026-03-17-fix-f001-f002.md` and plan) exist on disk but not in the index.
**Fix:** Add both to Active specs section.

### F-027 | `telemetry.yaml` `agents_called[].status` Has No Write Instruction
**Source:** Agent 3 (S-010)
**Files:** `src/schemas/telemetry.schema.yaml` lines 58–60; `src/global/skills/orchestrator.md` Section 7
**Current:** Schema defines the field, but orchestrator write instructions don't mention populating it.
**Fix:** Add to orchestrator.md Section 7: record `status` from agent's returned STATUS value.

### F-028 | `moira_audit_check_trigger` Ignores Config Thresholds
**Source:** Agent 3 (S-017)
**Files:** `src/global/lib/audit.sh` lines 42–58; `src/schemas/config.schema.yaml` lines 134–141
**Current:** Hardcodes 10/20 task thresholds. Config defines `audit.light_every_n_tasks` and `audit.standard_every_n_tasks` but they're never read.
**Fix:** Read config values with fallback to hardcoded defaults.

### F-029 | `moira_state_agent_done` Omits `role` from History Entry
**Source:** Agent 3 (S-018)
**File:** `src/global/lib/state.sh` lines 162–167
**Current:** History entry includes step, status, duration, tokens, result — but not `role`. Role is needed by telemetry.
**Fix:** Add `role: ${role}` to history entry string.

### F-030 | `metrics.sh` `tasks.bypassed` Always 0 — No Incrementor
**Source:** Agent 3 (S-012)
**Files:** `src/global/lib/metrics.sh` lines 120–123; `src/schemas/metrics.schema.yaml` lines 42–46
**Current:** Field initialized to 0 and never incremented regardless of actual bypass usage.
**Fix:** Add bypass detection based on `current.yaml bypass.active`, or mark field as NOT YET IMPLEMENTED.

### F-031 | `metrics.sh` Accuracy Fields Always 0
**Source:** Agent 3 (S-013)
**Files:** `src/global/lib/metrics.sh` lines 138–141; `src/schemas/metrics.schema.yaml` lines 87–95
**Current:** `accuracy.architecture_first_try` and `accuracy.plan_first_try` initialized but never incremented.
**Fix:** Parse `status.yaml gates[]` to detect first-pass approvals, or mark as NOT YET IMPLEMENTED.

### F-032 | `yaml-utils.sh` Depth-3 Limit Undocumented
**Source:** Agent 3 (S-009)
**File:** `src/global/lib/yaml-utils.sh` lines 26–27
**Current:** Max nesting depth is 3 levels but this constraint is not documented for consumers.
**Fix:** Add header comment: "Maximum supported nesting depth: 3 levels."

### F-033 | `status.yaml` `completed_at` Never Written
**Source:** Agent 3 (S-003, related to S-001/S-002)
**File:** `src/schemas/status.schema.yaml` lines 37–43
**Fix:** Include `completed_at` with ISO timestamp in the `moira_state_record_completion` function (F-016).

---

## Low

### F-034 | Apollo Response Example Shows Only `success` Status
**Source:** Agent 1 (A-004)
**File:** `design/architecture/agents.md` lines 37–43
**Fix:** Add clarifying comment to example showing full status options.

### F-035 | Hermes YAML Adds "Never Express Opinions" Not in `agents.md`
**Source:** Agent 1 (A-005)
**File:** `src/global/core/rules/roles/hermes.yaml` line 22
**Fix:** Add "Does NOT express opinions" to agents.md Hermes rules for doc completeness.

### F-036 | `gates.md` "Standard Variant" Term Ambiguous
**Source:** Agent 2 (P-012)
**File:** `src/global/skills/gates.md` line 129
**Fix:** Rewrite note to clarify it means the "proceed/details/modify/abort option set."

### F-037 | Full/Decomposition Completion `reads_from` Underspecified
**Source:** Agent 2 (P-013)
**Files:** `src/global/core/pipelines/full.yaml` lines 88–95; `decomposition.yaml` lines 74–81
**Fix:** Add comment noting full completion data sourced from status.yaml per orchestrator.md Section 7.

### F-038 | Post-Agent Guard Check Scope Undocumented
**Source:** Agent 2 (P-014)
**File:** `src/global/skills/orchestrator.md` lines 108–123
**Fix:** Add comment documenting why only `implementer` and `explorer` are scoped.

### F-039 | Schema Dot-Notation Convention Undocumented
**Source:** Agent 3 (S-005)
**Fix:** Add comment to schema files explaining dot-notation = YAML nesting.

### F-040 | Duplicate Budget Defaults Across Schemas (No Sync Note)
**Source:** Agent 3 (S-008)
**Files:** `src/schemas/config.schema.yaml` lines 69–108; `src/schemas/budgets.schema.yaml` lines 9–53
**Fix:** Add cross-reference comments to both schema files.

### F-041 | `telemetry.yaml` `moira_version` Required but No Writer
**Source:** Agent 3 (S-011)
**Files:** `src/schemas/telemetry.schema.yaml` lines 25–28
**Fix:** Add instruction to orchestrator.md Section 7 to read from `~/.claude/moira/.version`.

### F-042 | `audit-pending.yaml` Has No Schema
**Source:** Agent 3 (S-014)
**Fix:** Create `src/schemas/audit-pending.schema.yaml`.

### F-043 | `retry-stats.yaml` Has No Schema
**Source:** Agent 3 (S-015)
**Fix:** Create `src/schemas/retry-stats.schema.yaml`.

### F-044 | `budget-accuracy.yaml` Has No Schema
**Source:** Agent 3 (S-016)
**Fix:** Create `src/schemas/budget-accuracy.schema.yaml`.

### F-045 | `violations.log` No Formal Format Specification
**Source:** Agent 3 (S-022)
**Fix:** Add format spec to `design/architecture/overview.md`.

### F-046 | `budget.sh` Telemetry Write Incomplete (Per-Agent Accuracy)
**Source:** Agent 3 (S-024)
**Fix:** Extend `moira_budget_write_telemetry` to write per-agent `budget_accuracy` fields.

### F-047 | `dispatch.md` State Update References Indirect
**Source:** Agent 3 (S-025)
**Fix:** Add direct reference to orchestrator.md Section 4 state management table.

### F-048 | ROADMAP Phase 11 Stale "TBD" for Manifest Schema
**Source:** Agent 4 (DD-012)
**File:** `design/IMPLEMENTATION-ROADMAP.md` line 223
**Fix:** Remove "Design doc for manifest schema TBD in phase spec" text.

### F-049 | D-097 Reserved with No Explanation
**Source:** Agent 4 (DD-013)
**File:** `design/decisions/log.md`
**Fix:** Add brief explanation for the reservation.

---

## Fix Dependency Graph

```
F-003 (yaml_block_append dot-path) ← F-004 uses yaml functions
F-015 (state_set_status) ← F-016 (record_completion) ← F-033 (completed_at)
F-005 (final_gate after_step) — independent of all others
F-006 (reflection numbered step) — independent
F-007 + F-008 + F-026 — all SYSTEM-DESIGN.md edits, do together
F-022 + F-023 — both pipelines.md edits, do together
F-024 + F-025 — both self-monitoring.md edits, do together
F-030 + F-031 — both metrics.sh, can combine
F-042 + F-043 + F-044 — all new schema files, do together
```

## Parallel Fix Groups

**Group A — Shell Library Fixes (sequential: F-003 → F-004, then F-015 → F-016 → F-033)**
- F-003: Extend `yaml-utils.sh` `moira_yaml_block_append` for dot-paths
- F-004: Fix `budget.sh` gate count heuristic
- F-002: Fix `checkpoint.sh` artifact path
- F-015 → F-016 → F-033: Add `state.sh` writer functions (sequential chain)
- F-029: Add `role` to history entry in `state.sh`
- F-032: Document depth-3 limit in `yaml-utils.sh`

**Group B — Pipeline YAML Fixes (independent of Group A)**
- F-001: Add E10-DIVERGE to `quick.yaml`
- F-005: Fix `final_gate after_step` across all 4 pipeline YAMLs
- F-009: Add `implementation.md` to quick completion reads_from
- F-011: Add `architecture.md` to standard reviewer reads_from
- F-020: Align E9/E5 max_attempts
- F-021: Add `classification.md` to decomposition planner reads_from

**Group C — Design Document Fixes (independent of A and B)**
- F-007 + F-008 + F-026: SYSTEM-DESIGN.md index fixes
- F-010: pipelines.md classification table
- F-022 + F-023: pipelines.md decision citation + cross-reference
- F-024 + F-025: self-monitoring.md cross-reference + threshold text
- F-048: ROADMAP stale TBD

**Group D — Skill & Documentation Fixes (independent)**
- F-006: orchestrator.md reflection step restructure
- F-012: aletheia.yaml never block
- F-013: argus.yaml write_access
- F-014: dispatch.md table restructure
- F-017: config schema field rename
- F-018: full.yaml architecture gate variant docs
- F-019: gates.md per_task_gate rationale
- F-027: orchestrator.md telemetry write instructions
- F-028: audit.sh config threshold reading

**Group E — Low-Priority Cleanup (do last)**
- F-030 + F-031: metrics.sh stub implementations
- F-034 through F-049: documentation completeness, schema creation, cosmetic fixes
