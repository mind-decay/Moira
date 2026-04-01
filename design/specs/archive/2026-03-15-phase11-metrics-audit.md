# Phase 11: Metrics, Audit & Cross-Reference Manifest

## Goal

Implement the metrics collection and dashboard system, the 5-domain audit system with tiered depth and batch recommendation approval, and the cross-reference manifest for consistency enforcement. After Phase 11: `/moira metrics` displays a full performance dashboard with trends, drill-down, comparison, and export; `/moira audit` runs independent health verification across all 5 domains (rules, knowledge, agents, config, cross-consistency) with tiered depth (light/standard/deep); audit findings surface actionable recommendations with risk-classified batch approval; the xref manifest maps data dependencies between files so agents can consult it before committing; Tier 1 tests validate manifest entries against actual file content.

**Why now:** The full pipeline is operational (Phases 1-9), reflection captures post-task observations (Phase 10), and per-task telemetry is written at pipeline completion. Telemetry data exists but has no aggregation or visualization. The Auditor role (Argus) is defined but has no dispatch mechanism or instruction templates. The system audit skill (`/system-audit`) exists for Moira's own design docs, but the project-facing audit system (`/moira audit`) does not. D-077 mandates the xref manifest to prevent the 58-finding consistency drift observed in system audits.

## Risk Classification

**YELLOW (overall)** — New shell libraries, new schemas, new templates, new command implementations. No pipeline gate changes. No agent role boundary changes. Needs regression check + impact analysis.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: Metrics Library | YELLOW | New shell library with cross-file aggregation logic |
| D2: Metrics Schema | GREEN | New schema file, additive |
| D3: Metrics Command | YELLOW | Replaces placeholder command with full implementation |
| D4: Audit Library | YELLOW | New shell library with finding parsing and report generation |
| D5: Audit Templates | GREEN | New template files, additive |
| D6: Audit Schema | GREEN | New schema file, additive |
| D7: Audit Command | YELLOW | Replaces placeholder command with full implementation |
| D8: Xref Manifest | ORANGE | New cross-cutting infrastructure; requires updating `overview.md` file tree |
| D9: Tier 1 Tests | GREEN | New test files, additive |

## Design Sources

| Deliverable | Primary Source | Supporting Sources |
|-------------|---------------|-------------------|
| D1-D3: Metrics | `subsystems/metrics.md` | `subsystems/testing.md` (Live Telemetry), `architecture/commands.md` (/moira metrics) |
| D4-D7: Audit | `subsystems/audit.md` | `architecture/agents.md` (Argus), `architecture/commands.md` (/moira audit) |
| D8-D9: Xref | D-077 | Post-phase-10 system audit findings |

## Deliverables

### D1: Metrics Library (`src/global/lib/metrics.sh`)

**What:** Shell library for metrics collection, monthly aggregation, dashboard generation, drill-down, comparison, and export.

**Functions:**

- `moira_metrics_collect_task <task_id> [state_dir]` — Extract metrics from a completed task's `telemetry.yaml` and `status.yaml`. Called at pipeline completion (after telemetry write). Appends per-task record to current month's aggregate file.

- `moira_metrics_aggregate_monthly [state_dir]` — Recalculate monthly aggregate from per-task records. Called by `collect_task` incrementally (update running totals) and on-demand for full recalculation. Produces `state/metrics/monthly-{YYYY-MM}.yaml` matching the schema in `metrics.md`.

- `moira_metrics_dashboard [state_dir]` — Generate the main dashboard display (last 30 days). Reads current and previous month's aggregate. Calculates trend indicators (up/down/stable) by comparing current vs previous period. Returns formatted text matching `metrics.md` dashboard spec.

- `moira_metrics_drilldown <section> [state_dir]` — Generate drill-down view for a specific section (tasks/quality/accuracy/efficiency/knowledge/evolution). Reads per-task records from current month. Returns formatted detail view.

- `moira_metrics_compare [state_dir]` — Generate side-by-side comparison with previous period. Reads current and previous month's aggregates. Returns formatted comparison table.

- `moira_metrics_export [state_dir]` — Generate markdown export of full dashboard + drill-down. Returns complete report suitable for sharing.

**Integration point:** `moira_metrics_collect_task` is called by the orchestrator skill in Section 7 completion flow (`done` action), after `moira_budget_write_telemetry` and before reflection dispatch. This is a single function call — minimal context cost. It also calls `moira_audit_check_trigger` to set an audit-pending flag if due (see D4).

**Data flow:**
```
telemetry.yaml + status.yaml → collect_task → monthly-{YYYY-MM}.yaml
monthly-{YYYY-MM}.yaml → dashboard/drilldown/compare/export → formatted text
```

**Trend calculation:** Compare same metric between current and previous period. Trend indicators per `metrics.md`: ↑ improving, ↓ declining, → stable. Threshold for trend direction is implementation-defined (D-093).

### D2: Metrics Schema (`src/schemas/metrics.schema.yaml`)

**What:** YAML schema for `monthly-{YYYY-MM}.yaml` files. Validates the structure defined in `subsystems/metrics.md`.

**Fields** (from metrics.md):
- `period` (string, required, format: "YYYY-MM")
- `tasks` block: `total`, `by_size` (small/medium/large/epic), `bypassed`, `aborted`
- `quality` block: `first_pass_accepted`, `tweaks`, `redos`, `retry_loops_total`, `reviewer_criticals`
- `accuracy` block: `classification_correct`, `architecture_first_try`, `plan_first_try`
- `efficiency` block: `avg_orchestrator_context_pct`, `avg_implementer_context_pct`, `checkpoints_needed`, `mcp_calls`, `mcp_useful`, `mcp_cache_hits`
- `knowledge` block: `patterns_total`, `patterns_added`, `decisions_total`, `decisions_added`, `quality_map_coverage_pct`, `freshness_pct`, `stale_entries`
- `evolution` block: `improvements_proposed`, `applied`, `deferred`, `rejected`, `regressions`

**Per-task records** (appended by collect_task, used for drill-down):
- `task_records` array: per-task snapshots with `task_id`, `pipeline`, `size`, `first_pass`, `tweaked`, `redone`, `retries`, `orchestrator_pct`, `reviewer_criticals`, `by_agent` (per-agent budget percentages)

### D3: Metrics Command (`src/commands/moira/metrics.md`)

**What:** Replace the placeholder with full implementation.

**Subcommands** (from `commands.md`):
- `/moira metrics` — calls `moira_metrics_dashboard`, displays result
- `/moira metrics details <section>` — calls `moira_metrics_drilldown`, displays result
- `/moira metrics compare` — calls `moira_metrics_compare`, displays result
- `/moira metrics export` — calls `moira_metrics_export`, displays result

**Allowed tools:** `Read` only (metrics is read-only — reads state files, outputs text). The command reads library functions and invokes them conceptually by presenting their output format. Since commands are markdown skill files executed by Claude, the command instructs Claude to read the monthly YAML files and format them per the dashboard spec.

**Note on command implementation:** Moira commands are markdown skill files. The orchestrator (Claude) reads state files and formats output. Shell functions serve as the canonical logic reference, but the command skill may read YAML directly and format output inline rather than invoking shell. Both approaches produce identical output.

### D4: Audit Library (`src/global/lib/audit.sh`)

**What:** Shell library providing finding parsing, report generation, recommendation formatting, and audit trigger detection. Does NOT dispatch agents — shell cannot invoke the Agent tool. Agent dispatch is performed by the `audit.md` command skill (Claude).

**Functions:**

- `moira_audit_check_trigger [state_dir]` — Check if automatic audit is due. Reads completed task count from metrics, returns "light" (every 10th task), "standard" (every 20th task), or "none". Writes `audit_pending: {depth}` to `state/audit-pending.yaml` if due. The orchestrator checks this flag at the START of the next pipeline (in Section 2, pre-pipeline setup), similar to the deep scan check, and offers to run the audit before starting the new task.

- `moira_audit_select_templates <domain|"all"> <depth>` — Given domain and depth, return the list of template file paths to use. Used by the `audit.md` command skill to know which templates to load for Agent dispatch.

- `moira_audit_parse_findings <audit_file>` — Parse structured findings from Auditor agent output. Extract finding count, risk levels, domain breakdown. Returns structured summary matching `audit.md` output format.

- `moira_audit_generate_report <date> [state_dir]` — Generate the full audit report. Combines per-domain findings into unified report. Writes to `state/audits/{date}-audit.md`.

- `moira_audit_format_recommendations <audit_file>` — Extract recommendations grouped by risk level (low/medium/high). Format for batch approval presentation per `audit.md` spec.

**Dispatch model:** The `audit.md` command skill (D7) uses the Agent tool to dispatch Argus with domain-specific instruction templates. Shell function `moira_audit_select_templates` provides template paths. For full audit, all 5 domain dispatches can run in parallel (no dependencies between domains). Cross-consistency domain may depend on other domain results for deep audit — in that case, it runs after the other 4 complete.

**Recommendation application:** Argus is READ-ONLY (Art 1.2) — it never modifies files. When the user approves a recommendation, the `audit.md` command skill dispatches Hephaestus (implementer) with the specific recommendation context (target file, change description, evidence). This reuses the existing implementer agent for file modifications, maintaining separation of concerns. Low-risk recommendations (freshness markers, scan paths) target moira config files, not project code — these are within the audit command's `Write` scope (moira state/config only, not project source).

**Tiered depth** (from `audit.md`):

| Depth | Trigger | Agent Count | Scope |
|-------|---------|-------------|-------|
| Light | Every 10 tasks (automatic) | 1 | Surface consistency checks |
| Standard | Every 20 tasks or manual | 1-2 | Full 5-domain audit |
| Deep | Upgrade, quarterly, manual | 3-4 | Deep with codebase verification |

**Automatic triggers:** `moira_audit_check_trigger` is called by `moira_metrics_collect_task` at pipeline completion. It writes an `audit_pending` flag to state. The orchestrator reads this flag at the start of the next pipeline (Section 2, pre-pipeline setup) and offers to run the audit before the new task. This avoids bloating the completing pipeline's context and gives the user a natural decision point (D-093).

### D5: Audit Templates (`src/global/templates/audit/`)

**What:** Instruction templates for Argus per domain and depth level.

**Files:**
- `rules-light.md` — Surface rules consistency check
- `rules-standard.md` — Full rules audit per `audit.md` §1
- `rules-deep.md` — Deep rules audit with codebase cross-reference
- `knowledge-light.md` — Knowledge freshness spot check
- `knowledge-standard.md` — Full knowledge audit per `audit.md` §2
- `knowledge-deep.md` — Deep with source code cross-validation: dispatches Hermes (explorer) to verify 3-5 sampled knowledge claims against current source code (per `audit.md` §2). Argus instructs orchestrator to dispatch Explorer; Argus remains read-only.
- `agents-standard.md` — Agent performance audit per `audit.md` §3, including classifier accuracy (gate override rate from `status.yaml classification.overridden`)
- `agents-deep.md` — Deep agent performance with per-task drill-down
- `config-standard.md` — Config audit per `audit.md` §4
- `config-deep.md` — Deep config audit with MCP efficiency analysis
- `consistency-standard.md` — Cross-consistency audit per `audit.md` §5
- `consistency-deep.md` — Deep cross-consistency with xref manifest verification

**Template structure:** Each template contains:
1. Domain-specific audit instructions
2. Files to read (knowledge access per argus.yaml — L2 for all types)
3. Finding format (structured YAML within markdown)
4. Risk classification guidance
5. Recommendation format

**Light templates:** Only rules-light and knowledge-light exist. Light audits for other domains are omitted because surface checks for agents, config, and consistency require reading multiple files — not meaningfully lighter than standard.

### D6: Audit Schema (`src/schemas/audit.schema.yaml`)

**What:** YAML schema for structured audit findings embedded in audit reports.

**Fields:**
- `_meta` block: `date`, `depth` (light/standard/deep), `domains` audited, `moira_version`
- `findings` array: per-finding records
  - `id` (string, e.g. "R-01", "K-03")
  - `domain` (enum: rules/knowledge/agents/config/consistency)
  - `risk` (enum: low/medium/high)
  - `description` (string)
  - `evidence` (string)
  - `recommendation` (string)
  - `target_file` (string, optional — file to modify if recommendation applied)
- `summary` block: `total`, `by_risk` (low/medium/high counts), `by_domain` counts

### D7: Audit Command (`src/commands/moira/audit.md`)

**What:** Replace the placeholder with full implementation.

**Subcommands** (from `commands.md`):
- `/moira audit` — full audit (all 5 domains, standard depth)
- `/moira audit <domain>` — specific domain audit (standard depth; domains: rules, knowledge, agents, config, consistency)

Depth is auto-selected based on trigger (light for periodic passive, standard for manual, deep for upgrade/quarterly). Manual deep audit: `/moira audit` + user selects "deep" when offered depth choice. This avoids adding flags not defined in `commands.md`.

**Implementation:** The command reads audit templates via `moira_audit_select_templates`, dispatches Argus agent(s) via Agent tool with domain-specific templates, collects results via `moira_audit_parse_findings`, presents summary per `audit.md` output format, and offers recommendation approval flow.

**Allowed tools:** `Agent`, `Read`, `Write` (dispatch Argus, read results, write audit report and apply low-risk moira config changes). Write scope is `.moira/` only — never project source files. For recommendations requiring project file changes, the command dispatches Hephaestus (implementer) via Agent tool.

**Recommendation approval flow** (from `audit.md`):
1. Show summary with finding counts by risk
2. Low-risk: batch "apply-all" or "review one-by-one". Apply = direct Write to moira config files (freshness markers, scan paths, budget thresholds)
3. Medium-risk: individual approval with context (apply/skip/modify). Apply = dispatch Hephaestus with recommendation context for rule/convention file updates
4. High-risk: detailed review with full evidence (apply/defer/reject). Apply = dispatch Hephaestus with full recommendation context

**Art 5.2 interaction:** Audit recommendations for rule changes are PROPOSALS. When a rule-change recommendation is approved, the change is applied but also recorded as an observation in the reflection system's pattern-keys registry. This ensures that single-observation rule changes are still visible to Mnemosyne for trend tracking. The 3-confirmation threshold (Art 5.2) applies to AUTOMATIC rule evolution via reflection — user-approved audit recommendations are explicit user decisions (Art 4.2) and do not require the threshold, but are still tracked for pattern analysis.

### D8: Cross-Reference Manifest (`src/global/core/xref-manifest.yaml`)

**What:** Machine-readable dependency map between files for consistency enforcement (D-077).

**Structure:**
```yaml
# Cross-Reference Manifest — Data Dependencies Between Files
# Source: D-077
# Purpose: Agents consult this before committing to find all affected files.
# Tier 1 tests validate entries against actual file content.

entries:
  - id: xref-001
    description: "Agent budget defaults"
    canonical_source: "src/schemas/budgets.schema.yaml"
    dependents:
      - file: "src/global/lib/budget.sh"
        field: "_MOIRA_BUDGET_DEFAULTS_*"
        sync_type: "value_must_match"
      - file: "src/global/core/rules/roles/*.yaml"
        field: "_meta.budget"
        sync_type: "value_must_match"
    values_tracked: "per-agent token budget numbers"

  - id: xref-002
    description: "Pipeline step names"
    canonical_source: "src/global/core/pipelines/*.yaml"
    dependents:
      - file: "src/global/lib/state.sh"
        field: "valid_steps"
        sync_type: "enum_must_match"
      - file: "src/schemas/current.schema.yaml"
        field: "step enum"
        sync_type: "enum_must_match"
    values_tracked: "pipeline step name strings"

  - id: xref-003
    description: "Agent role names (Greek)"
    canonical_source: "design/architecture/agents.md"
    dependents:
      - file: "src/global/core/rules/roles/*.yaml"
        field: "filenames"
        sync_type: "names_must_match"
      - file: "src/global/core/knowledge-access-matrix.yaml"
        field: "agent keys"
        sync_type: "names_must_match"
      - file: "src/schemas/telemetry.schema.yaml"
        field: "role enum values"
        sync_type: "enum_must_match"
    values_tracked: "agent Greek names and role mappings"

  # ... additional entries discovered during implementation
  # by auditing actual cross-file dependencies
```

**Scope:** The manifest starts with known high-frequency drift sources (budget values, enum lists, agent names, pipeline steps, knowledge access levels). Additional entries are added as audits discover new drift patterns. The manifest is NOT exhaustive on day 1 — it grows organically.

**Agent integration — scope reduction from roadmap:** The roadmap lists "Agent pre-commit xref check — agents consult manifest before committing to find affected files." Phase 11 delivers the manifest and Tier 1 validation, but defers mechanical enforcement to Phase 12 (which updates the orchestrator skill for checkpoint/resume and can incorporate xref checks at the same time). For Phase 11: agent pre-commit consultation is documented as a convention in CLAUDE.md's moira section, not enforced mechanically. This is a deliberate scope reduction (D-093) — the manifest must exist and be validated before enforcement can be built on top of it.

**Location:** `src/global/core/xref-manifest.yaml` — lives with other core infrastructure. Installed to `~/.claude/moira/core/xref-manifest.yaml`.

### D9: Tier 1 Tests

**What:** Structural verification tests for metrics, audit, and xref systems.

**Files:**

- `src/tests/tier1/test-metrics-audit.sh` — Tests:
  - Monthly metrics schema exists and is valid
  - Audit schema exists and is valid
  - Audit templates exist for all depth/domain combinations listed in D5
  - Metrics command is not a placeholder
  - Audit command is not a placeholder
  - metrics.sh library exists and defines expected functions
  - audit.sh library exists and defines expected functions

- `src/tests/tier1/test-xref-manifest.sh` — Tests:
  - xref-manifest.yaml exists and has entries
  - Each manifest entry has required fields (id, description, canonical_source, dependents)
  - Canonical source files exist
  - Dependent files exist
  - For `value_must_match` entries: spot-check that values in canonical source match dependents
  - For `enum_must_match` entries: verify enum values are consistent across files

## Dependencies on Previous Phases

| Dependency | Phase | Status | What's Used |
|-----------|-------|--------|-------------|
| Per-task telemetry | 3 | Done | `telemetry.yaml` written at pipeline completion |
| Status tracking | 3 | Done | `status.yaml` with gates, retries, budget |
| Budget reporting | 7 | Done | `budget.sh` functions, budget data in status.yaml |
| State management | 1 | Done | `state.sh`, `yaml-utils.sh` |
| Argus role definition | 2 | Done | `argus.yaml` agent role |
| Reflection data | 10 | Done | `reflection.md` per task, pattern-keys.yaml |
| Knowledge access matrix | 2 | Done | Argus has L2 access to all knowledge types |

## Files Created

| File | Type | Description |
|------|------|-------------|
| `src/global/lib/metrics.sh` | Shell library | Metrics collection, aggregation, dashboard |
| `src/global/lib/audit.sh` | Shell library | Audit dispatch, finding parsing, recommendations |
| `src/schemas/metrics.schema.yaml` | Schema | Monthly metrics YAML schema |
| `src/schemas/audit.schema.yaml` | Schema | Audit findings schema |
| `src/global/templates/audit/*.md` | Templates | 12 audit instruction templates |
| `src/global/core/xref-manifest.yaml` | Config | Cross-reference dependency manifest |
| `src/tests/tier1/test-metrics-audit.sh` | Test | Tier 1 structural tests for metrics/audit |
| `src/tests/tier1/test-xref-manifest.sh` | Test | Tier 1 xref validation tests |

## Files Modified

| File | Change | Reason |
|------|--------|--------|
| `src/commands/moira/metrics.md` | Replace placeholder with full implementation | D3 |
| `src/commands/moira/audit.md` | Replace placeholder with full implementation | D7 |
| `src/install.sh` | Add new files to install manifest + verify loop | New libs, templates, schemas, xref manifest |
| `src/tests/tier1/run-all.sh` | Add new test files to test runner | New test scripts |
| `src/global/skills/orchestrator.md` | Add `moira_metrics_collect_task` call to Section 7 completion flow (`done` action, after telemetry write); add audit-pending flag check to Section 2 pre-pipeline setup | D1 integration point, D4 automatic triggers |
| `src/global/lib/scaffold.sh` | Add `mkdir -p templates/audit` to `moira_scaffold_global()` | D5 new template directory |
| `design/architecture/overview.md` | Add `templates/audit/`, `core/xref-manifest.yaml`, `lib/metrics.sh`, `lib/audit.sh`, `metrics.schema.yaml`, `audit.schema.yaml` to file tree | New files must appear in canonical structure reference |
| `src/global/skills/dispatch.md` | Update Argus dispatch notes: template-based dispatch as alternative path for audit command (not simplified assembly) | D5/D7 template-based audit dispatch |
| `src/tests/tier1/test-file-structure.sh` | Add Phase 11 artifact checks (metrics.sh, audit.sh, templates/audit/, xref-manifest.yaml, schemas) | Canonical structural verifier must cover Phase 11 |
| `src/tests/tier1/test-install.sh` | Add Phase 11 installation verification | Install test must verify Phase 11 artifacts |
| `src/global/skills/errors.md` | Update Phase 11 forward references (lines 410, 417, 457) to reference actual audit commands | Forward references now implemented |

## Success Criteria

1. `/moira metrics` displays a formatted dashboard with all 7 sections (Tasks, Quality, Accuracy, Efficiency, Knowledge, Evolution, Trends) and trend indicators
2. `/moira metrics details <section>` shows per-task drill-down for any section
3. `/moira metrics compare` shows side-by-side with previous period
4. `/moira metrics export` generates complete markdown report
5. `/moira audit` dispatches Argus for all 5 domains and produces unified report
6. `/moira audit <domain>` audits a single domain
7. Audit findings are classified by risk (low/medium/high) with actionable recommendations
8. Recommendation approval flow supports batch (low), individual (medium), and detailed (high) modes
9. Tiered depth (light/standard/deep) produces appropriately scoped audits
10. xref-manifest.yaml exists with entries covering known high-frequency drift sources
11. Tier 1 tests validate manifest entries against actual file content
12. All existing Tier 1 tests continue to pass (regression check)

## Deferred from Design Sources

The following items from design documents are explicitly NOT in Phase 11 scope:

1. **Passive audit checks** (audit.md §Passive): on task start (check locks/state), on explore (flag contradictions), on review (flag convention drift). These produce inline warnings during pipeline execution. Deferred because they require modifying pipeline step logic in orchestrator.md — better suited for Phase 12 when the orchestrator skill gets checkpoint/resume updates.

2. **Agent pre-commit xref enforcement** (roadmap line 225): mechanical enforcement deferred to Phase 12 (see D8 scope reduction note). Phase 11 delivers manifest + validation.

## New Decision Log Entries Required

This spec introduces the following architectural choices that need D-xxx entries:

- **D-093: Phase 11 Architectural Choices** — covers: (a) trend threshold for metric direction is implementation-defined, not design-specified; (b) automatic audit triggers use flag-based deferred execution (write flag at pipeline completion, check at next pipeline start); (c) only rules-light and knowledge-light templates exist — agents/config/consistency light audits omitted as not meaningfully lighter than standard; (d) audit finding ID format uses domain prefix + sequence number (R-01, K-03, etc.); (e) audit schema `_meta` block structure; (f) per-task record fields for drill-down; (g) agent pre-commit xref check deferred from mechanical enforcement to CLAUDE.md convention for Phase 11, with mechanical enforcement targeted for Phase 12.

## Constitutional Compliance

```
ARTICLE 1: Separation of Concerns
Art 1.1 OK  Metrics command uses Read only. Audit command uses Agent+Read+Write
            where Write scope is .moira/ only (never project source files).
            Recommendation application dispatches Hephaestus (implementer) for
            file modifications requiring project file changes.
Art 1.2 OK  Argus NEVER constraints unchanged: read-only, no modifications.
            Argus produces findings; Hephaestus applies approved changes.
            No new agent roles introduced.
Art 1.3 OK  Metrics and audit are separate subsystems, not merged.

ARTICLE 2: Determinism
Art 2.1 OK  No pipeline selection changes
Art 2.2 OK  No gate changes
Art 2.3 OK  Audit findings are evidence-based, not assumed

ARTICLE 3: Transparency
Art 3.1 OK  All audit reports written to state/audits/
            All metrics written to state/metrics/
Art 3.2 OK  Budget report unchanged
Art 3.3 OK  Audit errors reported to user (not silent)

ARTICLE 4: Safety
Art 4.1 OK  Audit findings cite evidence (file paths, metric values)
Art 4.2 OK  Recommendations require user approval before application.
            Batch "apply-all" for low-risk is user-initiated (user chooses
            to batch). No automatic changes without user action.
Art 4.3 OK  Recommendation application is reversible (git-backed)
Art 4.4 OK  No escape hatch interaction

ARTICLE 5: Knowledge Integrity
Art 5.1 OK  Audit findings reference evidence (task IDs, file paths)
Art 5.2 OK  Art 5.2 threshold applies to AUTOMATIC rule evolution via
            reflection (3+ observations). User-approved audit recommendations
            are explicit user decisions (Art 4.2 takes precedence) but are
            still recorded as observations in pattern-keys for trend tracking.
Art 5.3 OK  N/A — Argus is read-only for knowledge. Recommendation application
            goes through Hephaestus with user approval.

ARTICLE 6: Self-Protection
Art 6.1 OK  No code path modifies CONSTITUTION.md
Art 6.2 OK  This spec written before implementation
Art 6.3 OK  Xref manifest + Tier 1 tests strengthen invariant verification
```
