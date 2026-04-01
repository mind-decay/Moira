# Phase 11: Implementation Plan

**Spec:** `design/specs/2026-03-15-phase11-metrics-audit.md`
**Date:** 2026-03-16

## Chunk Overview

```
Chunk 1: Schemas + Design Doc Updates (no dependencies)
Chunk 2: Metrics Library (depends on Chunk 1 schema)
Chunk 3: Audit Library (depends on Chunk 1 schema)
Chunk 4: Audit Templates (depends on Chunk 3 for template selection contract)
Chunk 5: Xref Manifest + Xref Tests (no dependency on Chunks 2-4)
Chunk 6: Commands (depends on Chunks 2, 3, 4)
Chunk 7: Orchestrator Integration + Scaffold + Install (depends on Chunks 2, 3, 6)
Chunk 8: Tier 1 Tests + Regression (depends on all previous chunks)
```

---

## Chunk 1: Schemas + Design Doc Updates

**Goal:** Create metrics and audit schemas, update `overview.md` file tree.

### Task 1.1: Metrics Schema
- **File:** `src/schemas/metrics.schema.yaml`
- **Source:** `subsystems/metrics.md` (Metric Storage section), spec D2
- **Key points:**
  - `_meta` block: `name: metrics`, `file: monthly-{YYYY-MM}.yaml`, `location: .moira/state/metrics/`, `git: gitignored`
  - 7 top-level blocks: `period`, `tasks`, `quality`, `accuracy`, `efficiency`, `knowledge`, `evolution`
  - `task_records` array for per-task drill-down data
  - Match field names exactly from `metrics.md` YAML example (lines 44-77)
  - `evolution` block fields: `improvements_proposed`, `applied`, `deferred`, `rejected`, `regressions` (all type: number, default: 0)
  - Follow existing schema format from `telemetry.schema.yaml` and `status.schema.yaml`
- **Commit:** `moira(metrics): add monthly metrics YAML schema`

### Task 1.2: Audit Schema
- **File:** `src/schemas/audit.schema.yaml`
- **Source:** `subsystems/audit.md` (Audit Output section), spec D6
- **Key points:**
  - `_meta` block: `name: audit`, `file: {date}-audit.yaml`, `location: .moira/state/audits/`, `git: gitignored`
  - `meta` fields: `date` (string), `depth` (enum: light/standard/deep), `domains` (array of enum: rules/knowledge/agents/config/consistency), `moira_version` (string)
  - `findings` array with item_fields: `id` (string), `domain` (enum), `risk` (enum: low/medium/high), `description` (string), `evidence` (string), `recommendation` (string), `target_file` (string, required: false)
  - `summary` fields: `total`, `by_risk.low`, `by_risk.medium`, `by_risk.high`, `by_domain.rules`, `by_domain.knowledge`, `by_domain.agents`, `by_domain.config`, `by_domain.consistency`
  - Note: audit REPORTS remain `.md` format for readability. This schema validates the STRUCTURED findings block within the report. Reports contain both human-readable narrative and a YAML findings block that can be parsed by `audit.sh`.
- **Commit:** `moira(audit): add audit findings YAML schema`

### Task 1.3: Update `overview.md` File Tree
- **File:** `design/architecture/overview.md`
- **Source:** Spec "Files Modified" table
- **Key points:**
  - Global layer `core/` section: add `xref-manifest.yaml` after `pipelines/` directory
  - Global layer `templates/` section: add `audit/` directory with comment (12 domain-depth templates)
  - Global layer `lib/` section: add `metrics.sh` and `audit.sh`
  - Global layer `schemas/` section: add `metrics.schema.yaml` and `audit.schema.yaml`
  - Verify no other sections need updating
- **Commit:** `moira(design): update overview.md file tree for phase 11`

---

## Chunk 2: Metrics Library

**Goal:** Implement `metrics.sh` with all 6 functions.

### Task 2.1: `metrics.sh` — Core Functions
- **File:** `src/global/lib/metrics.sh`
- **Source:** `subsystems/metrics.md`, spec D1
- **Key points:**
  - Source `yaml-utils.sh` from same directory (follow `budget.sh` pattern)
  - `moira_metrics_collect_task <task_id> [state_dir]`:
    - Read `telemetry.yaml` fields: `pipeline.type`, `pipeline.classification_correct`, `execution.retries_total`, `execution.budget_total_tokens`, `quality.first_pass_accepted`, `quality.final_result`, `quality.reviewer_findings.critical`, `compliance.orchestrator_violation_count`
    - Read `status.yaml` fields: `size`, `classification.overridden`, `budget.actual_tokens`, `completion.action`, `completion.tweak_count`, `completion.redo_count`
    - Append to `task_records` in `state/metrics/monthly-{YYYY-MM}.yaml`
    - Increment running totals in the monthly file (tasks.total, by_size, quality counts, etc.)
    - Call `moira_audit_check_trigger` at the end (source `audit.sh` with existence guard and `|| true`, same pattern as other cross-lib sourcing)
  - `moira_metrics_aggregate_monthly [state_dir]`:
    - Full recalculation from `task_records` array
    - Compute averages (orchestrator_pct, implementer_pct) from per-task records
    - Used for consistency check / monthly rollover
  - `moira_metrics_dashboard [state_dir]`:
    - Read current month file + previous month file
    - Format 7 sections: Tasks, Quality, Accuracy, Efficiency, Knowledge, Evolution, Trends
    - Compute trend indicators by comparing current vs previous period values
    - Trend direction: implementation-defined threshold per D-093
    - Output format: match `metrics.md` dashboard display section
  - `moira_metrics_drilldown <section> [state_dir]`:
    - Valid sections: tasks, quality, accuracy, efficiency, knowledge, evolution
    - Read `task_records` from current month
    - Format per-task detail lines per `metrics.md` drill-down section
    - Include per-agent budget distribution from `by_agent` field
  - `moira_metrics_compare [state_dir]`:
    - Read current + previous month aggregates
    - Side-by-side output with delta columns
  - `moira_metrics_export [state_dir]`:
    - Combine dashboard + all drill-down sections into markdown
    - Date-stamped header
- **Commit:** `moira(metrics): implement metrics collection and dashboard library`

---

## Chunk 3: Audit Library

**Goal:** Implement `audit.sh` with finding parsing, report generation, trigger detection.

### Task 3.1: `audit.sh` — All Functions
- **File:** `src/global/lib/audit.sh`
- **Source:** `subsystems/audit.md`, spec D4
- **Key points:**
  - Source `yaml-utils.sh` from same directory
  - `moira_audit_check_trigger [state_dir]`:
    - Read task count from current month's `monthly-{YYYY-MM}.yaml` `tasks.total`
    - If total % 20 == 0: write `audit_pending: standard` to `state/audit-pending.yaml`
    - Else if total % 10 == 0: write `audit_pending: light` to `state/audit-pending.yaml`
    - Else: echo "none", no file write
    - Edge case: if file doesn't exist (first task), task count is 0, no trigger
  - `moira_audit_select_templates <domain|"all"> <depth>`:
    - Template dir: `~/.claude/moira/templates/audit/`
    - Map domain+depth → file path(s)
    - For "all": return all template paths for the given depth
    - Light depth only has rules-light.md and knowledge-light.md (D-093c)
    - Return newline-separated list of template file paths
  - `moira_audit_parse_findings <audit_file>`:
    - Extract YAML findings block from audit report markdown
    - Count findings by risk level and domain
    - Output structured summary: total, by_risk.{low,medium,high}, by_domain.{rules,knowledge,agents,config,consistency}
  - `moira_audit_generate_report <date> [state_dir]`:
    - Combine per-domain finding files into unified report
    - Write to `state/audits/{date}-audit.md`
    - Include both narrative and structured YAML findings block
  - `moira_audit_format_recommendations <audit_file>`:
    - Extract recommendations, group by risk level
    - Format for display: low-risk batch header, medium-risk individual, high-risk detailed
    - Output matches `audit.md` recommendation approval section format
- **Commit:** `moira(audit): implement audit library with finding parsing and triggers`

---

## Chunk 4: Audit Templates

**Goal:** Create 12 audit instruction templates for Argus.

### Task 4.1: Rules Domain Templates (3 files)
- **Files:** `src/global/templates/audit/rules-light.md`, `rules-standard.md`, `rules-deep.md`
- **Source:** `audit.md` §1 Rules Audit
- **Key points:**
  - Light: check core rules integrity + inviolable rules intact. Quick pass, ~1 min.
  - Standard: all 7 checks from audit.md §1 (core integrity, role files, quality criteria, inviolable rules, project rules match reality, layer conflicts, duplicates/contradictions)
  - Deep: standard + codebase cross-reference (verify project rules match actual code patterns)
  - Each template: identity section (you are Argus), instructions, files to read, finding format (YAML block), risk classification guidance
  - Finding format example in template: `findings:\n  - id: R-01\n    domain: rules\n    risk: medium\n    description: "..."\n    evidence: "..."\n    recommendation: "..."\n    target_file: "..."`
- **Commit:** `moira(audit): add rules audit templates (light/standard/deep)`

### Task 4.2: Knowledge Domain Templates (3 files)
- **Files:** `src/global/templates/audit/knowledge-light.md`, `knowledge-standard.md`, `knowledge-deep.md`
- **Source:** `audit.md` §2 Knowledge Audit
- **Key points:**
  - Light: freshness spot check — scan knowledge entries for stale markers
  - Standard: all checks from audit.md §2 (coverage, accuracy, decisions, patterns, quality map, freshness, contradictions, missing areas)
  - Deep: standard + source code cross-validation. Template instructs Argus to REQUEST orchestrator dispatch Hermes (explorer) for 3-5 sampled claims. Argus reports what needs verification; orchestrator dispatches Explorer; Argus receives results and incorporates. Argus itself never reads project source code for this — Explorer does.
  - Finding IDs use K-prefix (K-01, K-02, ...)
- **Commit:** `moira(audit): add knowledge audit templates (light/standard/deep)`

### Task 4.3: Agents Domain Templates (2 files)
- **Files:** `src/global/templates/audit/agents-standard.md`, `agents-deep.md`
- **Source:** `audit.md` §3 Agent Performance Audit
- **Key points:**
  - Standard: analyze per-agent effectiveness from recent task telemetry. Include classifier accuracy (gate override rate from `status.yaml classification.overridden`). Read `state/tasks/*/telemetry.yaml` for agent performance data.
  - Deep: standard + per-task drill-down with specific failure pattern analysis
  - Finding IDs use A-prefix
- **Commit:** `moira(audit): add agents audit templates (standard/deep)`

### Task 4.4: Config Domain Templates (2 files)
- **Files:** `src/global/templates/audit/config-standard.md`, `config-deep.md`
- **Source:** `audit.md` §4 Config Audit
- **Key points:**
  - Standard: MCP registry check, budget config check, hooks check, version check, orphaned state check
  - Deep: standard + MCP efficiency analysis (call frequency, cache opportunities from telemetry)
  - Finding IDs use C-prefix
- **Commit:** `moira(audit): add config audit templates (standard/deep)`

### Task 4.5: Consistency Domain Templates (2 files)
- **Files:** `src/global/templates/audit/consistency-standard.md`, `consistency-deep.md`
- **Source:** `audit.md` §5 Cross-Consistency Audit
- **Key points:**
  - Standard: 5 cross-checks from audit.md (rules↔knowledge, rules↔codebase, knowledge↔codebase, agents↔rules, state↔reality)
  - Deep: standard + xref manifest verification (read `xref-manifest.yaml`, verify entries match actual file content)
  - Finding IDs use X-prefix
- **Commit:** `moira(audit): add consistency audit templates (standard/deep)`

---

## Chunk 5: Xref Manifest + Xref Tests

**Goal:** Create the cross-reference manifest and its Tier 1 validation tests.

### Task 5.1: Xref Manifest
- **File:** `src/global/core/xref-manifest.yaml`
- **Source:** D-077, spec D8
- **Key points:**
  - Start with known high-frequency drift sources discovered in system audits
  - Entry structure: `id`, `description`, `canonical_source`, `dependents[]` (file, field, sync_type), `values_tracked`
  - Minimum entries to include (verify each against actual files):
    - xref-001: Agent budget defaults (budgets.schema.yaml → budget.sh defaults + role yaml _meta.budget)
    - xref-002: Pipeline step names (pipeline YAMLs → state.sh valid_steps + current.schema.yaml step enum)
    - xref-003: Agent role names (agents.md → role file names + knowledge-access-matrix keys + telemetry role enum)
    - xref-004: Knowledge access levels (knowledge-access-matrix.yaml → role yaml knowledge_access + dispatch.md access notes)
    - xref-005: Quality gate assignments (dispatch.md agent-to-gate mapping → quality checklist files + findings.schema gate enum)
    - xref-006: Pipeline gate names (pipeline YAMLs → constitution Art 2.2 gate list + gates.md templates)
  - After writing, verify every canonical_source and dependent file actually exists
  - For each value_must_match/enum_must_match entry, spot-check one value to confirm the dependency is real
- **Commit:** `moira(metrics): add cross-reference manifest for consistency enforcement`

### Task 5.2: Xref Tier 1 Tests
- **File:** `src/tests/tier1/test-xref-manifest.sh`
- **Source:** Spec D9
- **Key points:**
  - Source test-helpers.sh (follow existing test pattern)
  - Test: manifest file exists at expected path
  - Test: each entry has required fields (id, description, canonical_source, dependents)
  - Test: canonical_source files exist (resolve wildcards)
  - Test: dependent files exist (resolve wildcards)
  - Test: for `value_must_match` entries, extract a value from canonical and verify it appears in dependent
  - Test: for `enum_must_match` entries, extract enum values from canonical and verify they appear in dependent
  - Use grep-based validation (consistent with other Tier 1 tests — no YAML parser needed)
- **Commit:** `moira(metrics): add tier 1 xref manifest validation tests`

---

## Chunk 6: Commands

**Goal:** Replace placeholder commands with full implementations.

### Task 6.1: Metrics Command
- **File:** `src/commands/moira/metrics.md`
- **Source:** `commands.md`, spec D3
- **Key points:**
  - Frontmatter: `name: moira:metrics`, `description: View Moira performance metrics dashboard`, `argument-hint: "[details <section>|compare|export]"`, `allowed-tools: [Read]`
  - Parse argument to determine subcommand: no arg = dashboard, `details <section>` = drilldown, `compare` = comparison, `export` = markdown export
  - Instruct Claude to read `state/metrics/monthly-{YYYY-MM}.yaml` files
  - Format output per metrics.md dashboard display spec
  - Handle missing data gracefully: "No metrics data yet. Complete tasks via /moira to start collecting metrics."
  - Reference `metrics.sh` functions as canonical logic but implement inline (Claude reads YAML directly)
- **Commit:** `moira(metrics): implement /moira metrics command`

### Task 6.2: Audit Command
- **File:** `src/commands/moira/audit.md`
- **Source:** `commands.md`, `audit.md`, spec D7
- **Key points:**
  - Frontmatter: `name: moira:audit`, `description: Run Moira system health audit`, `argument-hint: "[rules|knowledge|agents|config|consistency]"`, `allowed-tools: [Agent, Read, Write]`
  - Parse argument: no arg = full audit (all 5 domains, standard); domain name = single domain audit
  - Depth selection: manual invocation defaults to standard. Offer "deep" option to user before dispatching. If triggered by audit-pending flag: use the pending depth.
  - Dispatch flow:
    1. Read template via `moira_audit_select_templates`
    2. For each domain: dispatch Argus with template content as prompt via Agent tool
    3. For full audit: dispatch all 5 in parallel (or 4+1 for deep cross-consistency)
    4. Collect results, parse findings via `moira_audit_parse_findings`
    5. Generate report via `moira_audit_generate_report`
    6. Display summary per `audit.md` output format
    7. Run recommendation approval flow
  - Recommendation application:
    - Low-risk moira config changes (freshness markers, scan paths, budget thresholds): audit command writes directly via Write tool (`.moira/` scope only)
    - Medium-risk moira rule/convention file updates: audit command writes directly via Write tool (still `.moira/` scope — project-layer rules are moira files, not project source)
    - High-risk changes or changes requiring project source file modifications: dispatch Hephaestus (implementer) with recommendation context (Hephaestus's documented scope is "write code to project files")
    - Record rule-change recommendations as observations in `state/reflection/pattern-keys.yaml` (Art 5.2 tracking)
  - Clear `state/audit-pending.yaml` after audit completes
  - Write scope: `Write` tool limited to `.moira/` paths only. Never write project source files.
- **Commit:** `moira(audit): implement /moira audit command`

---

## Chunk 7: Orchestrator Integration + Scaffold + Install

**Goal:** Wire metrics collection into pipeline completion, add audit-pending check to pipeline start, update scaffold and install.

### Task 7.1: Orchestrator Skill Updates
- **File:** `src/global/skills/orchestrator.md`
- **Source:** Spec D1 integration point, D4 automatic triggers
- **Key points:**
  - Section 7, `done` action: insert after the MCP writes block (ending with "If no MCP calls: omit `mcp_calls` section"), immediately before "Set pipeline status to `completed`". Add:
    - `- Collect metrics: call moira_metrics_collect_task <task_id> to aggregate task data into monthly metrics and check for audit triggers.`
  - Section 2, pre-pipeline setup: after existing checks (deep scan check, etc.), add:
    - Check for `state/audit-pending.yaml`. If exists: read pending depth, display to user: "Audit due ({depth}). Run /moira audit before starting? [yes/skip]". If user says yes: invoke `/moira audit` with appropriate depth. Clear flag after audit or skip.
  - Keep changes minimal — one line in Section 7, one paragraph in Section 2

### Task 7.2: Dispatch Skill Update
- **File:** `src/global/skills/dispatch.md`
- **Source:** Spec Files Modified table
- **Key points:**
  - Update the Argus note in the "Which Agents Use Which Path" section (the sentence: "Argus (auditor) uses simplified assembly (user-invoked via `/moira audit`)")
  - New text: "Argus (auditor) uses template-based dispatch when invoked via `/moira audit`. The audit command reads domain-specific templates from `~/.claude/moira/templates/audit/` and uses them as the agent prompt. Simplified assembly is the fallback if templates are missing."
  - No other changes to dispatch.md

### Task 7.3: Scaffold Update
- **File:** `src/global/lib/scaffold.sh`
- **Source:** Spec Files Modified table
- **Key points:**
  - In `moira_scaffold_global()`: add `mkdir -p "$target_dir"/templates/audit` after the existing `templates/knowledge` line
  - No other changes

### Task 7.4: Install Script Update
- **File:** `src/install.sh`
- **Source:** Spec Files Modified table
- **Key points:**
  - Note: `install_global()` line 58 already uses `cp -f "$SCRIPT_DIR/global/lib/"*.sh` (wildcard) — `metrics.sh` and `audit.sh` are automatically copied. No explicit lib copies needed.
  - Note: `install_schemas()` line 165 already uses `cp -f "$SCRIPT_DIR/schemas/"*.yaml` (wildcard) — new schemas are automatically copied. No explicit schema copies needed.
  - Add to `install_global()` (after existing template copies, following the Phase 4-7 template pattern):
    - Audit templates directory: `if [[ -d "$SCRIPT_DIR/global/templates/audit" ]]; then mkdir -p "$MOIRA_HOME/templates/audit" && cp -f "$SCRIPT_DIR/global/templates/audit/"*.md "$MOIRA_HOME/templates/audit/"; fi`
    - Xref manifest: `if [[ -f "$SCRIPT_DIR/global/core/xref-manifest.yaml" ]]; then cp -f "$SCRIPT_DIR/global/core/xref-manifest.yaml" "$MOIRA_HOME/core/"; fi`
  - Add to verify function's lib check loop: `metrics.sh`, `audit.sh`
  - Add to verify function's schema check loop: `metrics.schema.yaml`, `audit.schema.yaml`
  - Add to verify function: check `templates/audit/` directory exists with expected template count
  - Add to verify function: check `core/xref-manifest.yaml` exists

- **Commit (covers Tasks 7.1-7.4):** `moira(metrics): wire metrics collection into orchestrator and update install`

---

## Chunk 8: Tier 1 Tests + Regression

**Goal:** Create metrics/audit Tier 1 tests, register all new tests, run full Tier 1 suite.

### Task 8.1: Metrics/Audit Tier 1 Tests
- **File:** `src/tests/tier1/test-metrics-audit.sh`
- **Source:** Spec D9
- **Key points:**
  - Source test-helpers.sh
  - Tests:
    - `metrics.schema.yaml` exists and has `_meta.name: metrics`
    - `audit.schema.yaml` exists and has `_meta.name: audit`
    - All 12 audit templates exist (rules-light, rules-standard, rules-deep, knowledge-light, knowledge-standard, knowledge-deep, agents-standard, agents-deep, config-standard, config-deep, consistency-standard, consistency-deep)
    - `metrics.md` command is not a placeholder (does not contain "will be implemented in Phase 11")
    - `audit.md` command is not a placeholder
    - `metrics.sh` exists and defines expected functions (grep for function names)
    - `audit.sh` exists and defines expected functions
    - `metrics.sh` sources `yaml-utils.sh`
    - `audit.sh` sources `yaml-utils.sh`
- **Commit:** `moira(metrics): add tier 1 tests for metrics and audit system`

### Task 8.2: Register Tests in Runner
- **File:** `src/tests/tier1/run-all.sh`
- **Source:** Spec Files Modified table
- **Key points:**
  - Add `test-metrics-audit.sh` to test list
  - Add `test-xref-manifest.sh` to test list
  - Follow existing registration pattern
- **Commit (combined with 8.1):** same commit

### Task 8.3: Update Existing Tier 1 Tests
- **Files:** `src/tests/tier1/test-file-structure.sh`, `src/tests/tier1/test-install.sh`
- **Source:** Existing test patterns from Phases 4-10
- **Key points:**
  - `test-file-structure.sh`: add Phase 11 artifact checks:
    - `lib/metrics.sh` exists and has valid bash syntax
    - `lib/audit.sh` exists and has valid bash syntax
    - `templates/audit/` directory exists with 12 template files
    - `core/xref-manifest.yaml` exists
    - `schemas/metrics.schema.yaml` exists
    - `schemas/audit.schema.yaml` exists
  - `test-install.sh`: add Phase 11 installation checks:
    - `metrics.sh` and `audit.sh` installed and have valid syntax
    - Audit templates directory copied
    - `xref-manifest.yaml` installed
    - New schemas installed
  - Follow existing per-phase check patterns in both files

### Task 8.4: Update `errors.md` Forward References
- **File:** `src/global/skills/errors.md`
- **Source:** Review finding — Phase 11 forward references now implemented
- **Key points:**
  - Line 410: change "Audit recommends rule changes if violations are recurring (Phase 11)" to "Audit recommends rule changes if violations are recurring (via `/moira audit`)"
  - Line 417: change "Audit (Phase 11) tracks frequency trends" to "Audit tracks frequency trends (via `/moira audit`)"
  - Line 457: change "Impact assessment of stale knowledge on task quality (Phase 11)" to "Impact assessment of stale knowledge on task quality (via `/moira audit knowledge`)"
- **Commit (combined with 8.1-8.2):** same commit

### Task 8.5: Run Full Tier 1 Suite
- Run `src/tests/tier1/run-all.sh`
- Verify all existing tests still pass (regression)
- Verify new tests pass
- Fix any failures before proceeding

---

## Dependency Graph

```
Chunk 1 (schemas + docs)
  ├── Chunk 2 (metrics.sh) ─────┐
  ├── Chunk 3 (audit.sh) ───────┤
  │     └── Chunk 4 (templates) ─┤
  └── Chunk 5 (xref + tests)    │
                                 ├── Chunk 6 (commands)
                                 │     └── Chunk 7 (orchestrator + install)
                                 │           └── Chunk 8 (tier 1 tests + regression)
                                 └─────────────────┘
```

Chunks 2, 3, and 5 can run in parallel after Chunk 1.
Chunk 4 depends on Chunk 3 (template selection contract).
Chunk 6 depends on Chunks 2, 3, 4.
Chunk 7 depends on Chunks 2, 3, 6.
Chunk 8 depends on all previous chunks.
