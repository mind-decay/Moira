# Test Coverage Assessment — 2026-03-24

## Delta Since 2026-03-22

### New Source Files (not present in prior assessment)

| File | Test Coverage | Notes |
|---|---|---|
| `src/global/lib/completion.sh` | No test coverage detected | Post-gate finalization library; sources yaml-utils, budget, quality, knowledge, metrics, checkpoint |
| `src/global/lib/log-rotation.sh` | No test coverage detected | Log rotation with 5000-line threshold (D-143) |
| `src/global/lib/bootstrap.sh` | `test-bootstrap.sh` | Already tracked in prior assessment |
| `src/global/lib/rules.sh` | `test-rules-assembly.sh` | Already tracked in prior assessment |
| `src/global/hooks/pre-commit.sh` | No test coverage detected | Constitutional invariant verification hook (Art 6.3, D-142); fail-closed on verification failures, fail-open on internal errors |
| `src/global/skills/completion.md` | `test-orchestrator-enforcement.sh` | Structural (Phase 3 heading, pipeline_type analytical check) |
| `src/global/core/pipelines/analytical.yaml` | `test-analytical-pipeline.sh` | Structural (9 steps, 4 gates, 6 subtypes, organize_map, depth_checkpoint branching) |
| `src/global/core/rules/roles/calliope.yaml` | `test-analytical-pipeline.sh`, `test-agent-definitions.sh` | Structural (role, budget, identity, capabilities, never, knowledge_access, NEVER constraints >= 7) |
| `src/global/core/rules/quality/qa1-scope-completeness.yaml` | `test-analytical-pipeline.sh` | Structural (_meta, items, on_missing, agent, pipeline_step) |
| `src/global/core/rules/quality/qa2-evidence-quality.yaml` | `test-analytical-pipeline.sh` | Structural (same as qa1) |
| `src/global/core/rules/quality/qa3-actionability.yaml` | `test-analytical-pipeline.sh` | Structural (same as qa1) |
| `src/global/core/rules/quality/qa4-analytical-rigor.yaml` | `test-analytical-pipeline.sh` | Structural (same as qa1) |

### New Test Files (not present in prior assessment)

| Test File | Covers | Test Type |
|---|---|---|
| `test-analytical-pipeline.sh` | analytical.yaml, calliope.yaml, qa1-qa4, state.sh step IDs, budget.sh scribe default, apollo.yaml mode field, knowledge-access-matrix calliope entry, xref-manifest analytical entries, agent analytical_mode sections, graph.sh analytical baseline | Structural |
| `test-orchestrator-enforcement.sh` | apollo.yaml (valid_values enums), orchestrator.md (classification validation, step enforcement, post-pipeline terminal state), completion.md (Phase 3 analytical), current.schema.yaml (completed_steps) | Structural |

### Updated File Counts

| Category | Prior Count | Current Count | Change |
|---|---|---|---|
| Shell libraries (lib/) | 21 | 23 | +2 (completion.sh, log-rotation.sh) |
| Hooks | 2 | 3 | +1 (pre-commit.sh) |
| Pipeline definitions | 4 | 5 | +1 (analytical.yaml) |
| Agent roles | 10 | 11 | +1 (calliope.yaml) |
| Quality checklists | 5 | 9 | +4 (qa1-qa4) |
| Schemas | 12 | 12 | 0 |
| Skills | 5 | 6 | +1 (completion.md) |
| Commands | 14 | 14 | 0 |
| Install script | 1 | 1 | 0 |
| Remote install | 1 | 1 | 0 |
| Statusline | 1 | 1 | 0 |
| Tier 1 test files | 24 | 26 | +2 (test-analytical-pipeline.sh, test-orchestrator-enforcement.sh) |

### Updated Coverage Summary

| Category | Total Files | Functionally Tested | Structurally Only | Untested |
|---|---|---|---|---|
| Shell libraries (lib/) | 23 | 7 (yaml-utils, knowledge, rules, bootstrap, graph, scaffold, task-id) | 14 | 2 (retry.sh, completion.sh) |
| Hooks | 3 | 0 (basic exit-code only for 2) | 2 | 1 (pre-commit.sh) |
| Pipeline definitions | 5 | 0 (structural but thorough) | 5 | 0 |
| Agent roles | 11 | 0 | 11 | 0 |
| Quality checklists | 9 | 0 | 9 | 0 |
| Schemas | 12 | 6 (via yaml-utils round-trips) | 6 | 0 |
| Skills | 6 | 0 | 6 | 0 |
| Commands | 14 | 0 | 14 | 0 |
| Install script | 1 | 1 | 0 | 0 |
| Remote install | 1 | 0 | 0 | 1 |
| Statusline | 1 | 0 | 0 | 1 |
| **Totals** | **86** | **14** | **67** | **5** |

### New Untested Files (no test references detected)

- `src/global/lib/completion.sh` — no test file sources, invokes, or references this library
- `src/global/lib/log-rotation.sh` — no test file sources, invokes, or references this library
- `src/global/hooks/pre-commit.sh` — no test file references this hook

### New Structurally-Only Tested Files

- `src/global/core/pipelines/analytical.yaml` — tested by `test-analytical-pipeline.sh` (structural: steps, gates, agent_map, organize_map)
- `src/global/core/rules/roles/calliope.yaml` — tested by `test-analytical-pipeline.sh` and `test-agent-definitions.sh` (structural: sections, NEVER constraints)
- `src/global/core/rules/quality/qa1-qa4` (4 files) — tested by `test-analytical-pipeline.sh` (structural: _meta, items, on_missing, agent, pipeline_step)
- `src/global/skills/completion.md` — tested by `test-orchestrator-enforcement.sh` (structural: Phase 3 heading, pipeline_type check)

### Cross-Reference: test-analytical-pipeline.sh Scope

This test file validates cross-cutting concerns across multiple source files for the analytical pipeline feature:
- `state.sh`: all 17 step IDs in valid_steps (including 5 new analytical steps: gather, scope, depth_checkpoint, organize, synthesis)
- `budget.sh`: scribe default of 80000
- `apollo.yaml`: mode= field and analytical_signals section
- `knowledge-access-matrix.yaml`: calliope entry present
- `xref-manifest.yaml`: scribe budget, gather step, calliope agent, scope_gate, depth_checkpoint_gate
- `graph.sh`: moira_graph_analytical_baseline function and ariadne binary check
- 4 agents (athena, metis, argus, themis): analytical_mode section present
- calliope.yaml: correctly lacks analytical_mode section

### Cross-Reference: test-orchestrator-enforcement.sh Scope

This test file validates orchestrator enforcement fixes across:
- `apollo.yaml`: valid_values block with size/mode/confidence/subtype enums
- `orchestrator.md`: classification validation (Step 1b), step completion tracking, step enforcement, post-pipeline terminal state
- `completion.md`: Phase 3 analytical findings, pipeline_type check
- `current.schema.yaml`: analytical.completed_steps array type

---

# Test Coverage Assessment — 2026-03-22

## 1. Test Infrastructure

### Test Runner
- **Entry point:** `src/tests/tier1/run-all.sh`
- **Pattern:** Discovers and runs all `test-*.sh` files in `src/tests/tier1/`, skipping `test-helpers.sh`
- **Aggregation:** Parses `N/N passed, N failed` output from each test file; aggregates totals
- **Exit code:** Returns 1 if any failures, 0 otherwise

### Test Helpers
- **File:** `src/tests/tier1/test-helpers.sh` (sourced, not executed)
- **Assertions available:** `assert_dir_exists`, `assert_file_exists`, `assert_file_contains`, `assert_equals`, `assert_not_empty`, `assert_exit_code`
- **Reporting:** `pass()` / `fail()` functions; `test_summary()` emits per-file counts

### Test Tiers
- **Tier 1 (structural):** 24 test files in `src/tests/tier1/` — pure bash, 0 Claude tokens, deterministic
- **Tier 2 (behavioral):** Config at `src/tests/bench/tier2-config.yaml` — bench fixture-based, uses rubrics
- **Tier 3 (end-to-end):** Config at `src/tests/bench/tier3-config.yaml` — bench cases for checkpoint/resume, epic decomposition, redo, tweak

### Bench Infrastructure
- **Fixtures:** 3 project fixtures in `src/tests/bench/fixtures/` (greenfield-webapp, legacy-webapp, mature-webapp), each with `.moira-fixture.yaml`
- **Cases:** 9 YAML test cases in `src/tests/bench/cases/` (5 Tier 2, 4 Tier 3)
- **Rubrics:** 3 rubric files in `src/tests/bench/rubrics/` (bugfix, feature-implementation, refactor)
- **Calibration:** 3 calibration examples in `src/tests/bench/calibration/` (good, mediocre, poor implementations), each with `expected.yaml` and `test-results.md`

### Coverage Configuration
- No coverage tool configuration observed (no `.nycrc`, `jest.config`, `lcov`, `bashcov`, or equivalent)
- No coverage thresholds defined
- No CI integration files observed for test execution

## 2. Test File Mapping — Source to Test

### Shell Libraries (`src/global/lib/*.sh`) — 21 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `lib/yaml-utils.sh` | `test-yaml-schemas.sh` | Functional (init, validate, get, set round-trips) |
| `lib/state.sh` | `test-install.sh`, `test-xref-manifest.sh`, `test-checkpoint-resume.sh` | Structural (existence, syntax) + cross-ref spot-checks |
| `lib/scaffold.sh` | `test-install.sh`, `test-upgrade.sh`, `test-reflection-system.sh` | Functional (scaffold_project idempotency, directory creation) |
| `lib/task-id.sh` | `test-install.sh` | Functional (sequential ID generation) |
| `lib/knowledge.sh` | `test-knowledge-system.sh` | Functional (read/write/freshness/archive/consistency, agent access enforcement) |
| `lib/rules.sh` | `test-rules-assembly.sh` | Functional (layer loading, conflict detection, project rules mapping, instruction assembly, knowledge access enforcement) |
| `lib/bootstrap.sh` | `test-bootstrap.sh` | Functional (CLAUDE.md injection, gitignore, frontmatter parsing, gen_* functions, full pipeline, summary condensation, scanner contract validation) |
| `lib/budget.sh` | `test-budget-system.sh` | Structural (9 functions exist) + integration checks |
| `lib/quality.sh` | `test-quality-system.sh` | Structural (4 functions exist, syntax) |
| `lib/mcp.sh` | `test-mcp-system.sh` | Structural (8 functions exist, syntax) |
| `lib/reflection.sh` | `test-reflection-system.sh` | Structural (9 functions exist, syntax) |
| `lib/judge.sh` | `test-reflection-system.sh` | Structural (4 functions exist, syntax) |
| `lib/bench.sh` | `test-quality-system.sh`, `test-reflection-system.sh` | Structural (syntax, sources judge.sh) |
| `lib/metrics.sh` | `test-metrics-audit.sh` | Structural (6 functions exist, syntax, sources yaml-utils) |
| `lib/audit.sh` | `test-metrics-audit.sh` | Structural (5 functions exist, syntax, sources yaml-utils) |
| `lib/checkpoint.sh` | `test-checkpoint-resume.sh` | Structural (4 functions exist, syntax) |
| `lib/epic.sh` | `test-epic.sh` | Structural (5 functions exist, syntax) |
| `lib/upgrade.sh` | `test-upgrade.sh` | Structural (4 functions exist, syntax) |
| `lib/settings-merge.sh` | `test-hooks-system.sh` | Structural (2 functions exist, syntax) |
| `lib/graph.sh` | `test-graph-integration.sh`, `test-graph-e2e.sh` | Functional (summary with mock data, read_view L0/L1, access matrix) + E2E (build, summary, views, queries — requires ariadne binary) |
| `lib/retry.sh` | `test-file-structure.sh` | Structural (existence, syntax only) |

### Hooks (`src/global/hooks/`) — 2 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `hooks/guard.sh` | `test-hooks-system.sh` | Structural (syntax, key strings present) + basic functional (exits 0 with empty input) |
| `hooks/budget-track.sh` | `test-hooks-system.sh` | Structural (syntax, key strings present) + basic functional (exits 0 with empty input) |

### Pipeline Definitions (`src/global/core/pipelines/`) — 4 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `pipelines/quick.yaml` | `test-pipeline-engine.sh`, `test-pipeline-graph.sh` | Structural (triggers, gate counts, no auto-proceed, state writes) + graph-theoretic (BFS reachability, gate completeness, no bypass, fork/join, error handlers) |
| `pipelines/standard.yaml` | `test-pipeline-engine.sh`, `test-pipeline-graph.sh` | Same as above |
| `pipelines/full.yaml` | `test-pipeline-engine.sh`, `test-pipeline-graph.sh` | Same as above |
| `pipelines/decomposition.yaml` | `test-pipeline-engine.sh`, `test-pipeline-graph.sh`, `test-epic.sh` | Same as above + repeatable_group check |

### Agent Role Definitions (`src/global/core/rules/roles/`) — 10 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| All 10 role YAMLs (apollo, hermes, athena, metis, daedalus, hephaestus, themis, aletheia, mnemosyne, argus) | `test-agent-definitions.sh` | Structural (required sections, >=3 NEVER constraints, constitutional compliance, knowledge access matrix consistency) |

### Quality Checklists (`src/global/core/rules/quality/`) — 5 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| All 5 quality YAMLs (q1-q5) | `test-agent-definitions.sh` | Structural (existence, agent field, items/sections structure) |

### Core Config Files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `core/rules/base.yaml` | `test-agent-definitions.sh`, `test-rules-assembly.sh` | Structural (inviolable count) + functional (layer loading, conflict detection) |
| `core/knowledge-access-matrix.yaml` | `test-agent-definitions.sh`, `test-graph-integration.sh` | Structural (all 10 agents present, graph column values) + consistency (role file cross-check) |
| `core/response-contract.yaml` | `test-agent-definitions.sh`, `test-budget-system.sh` | Structural (4 status types, budget_exceeded, QUALITY line) |
| `core/xref-manifest.yaml` | `test-xref-manifest.sh` | Structural (entries exist, required fields) + spot-check validation (canonical sources + dependents exist, cross-ref value matching) |

### Schemas (`src/schemas/`) — 12 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `config.schema.yaml` | `test-yaml-schemas.sh`, `test-hooks-system.sh`, `test-quality-system.sh`, `test-mcp-system.sh` | Functional (init/validate round-trip, get/set) + structural (specific fields) |
| `current.schema.yaml` | `test-yaml-schemas.sh`, `test-checkpoint-resume.sh`, `test-xref-manifest.sh` | Functional (init/validate) + structural (checkpointed status, step enum) |
| `status.schema.yaml` | `test-yaml-schemas.sh` | Functional (init/validate round-trip) |
| `manifest.schema.yaml` | `test-yaml-schemas.sh`, `test-checkpoint-resume.sh` | Functional (init/validate) + structural (checkpoint fields) |
| `queue.schema.yaml` | `test-yaml-schemas.sh`, `test-epic.sh` | Functional (init/validate) + structural (epic_id, tasks, progress) |
| `locks.schema.yaml` | `test-yaml-schemas.sh` | Functional (init/validate round-trip) |
| `telemetry.schema.yaml` | `test-yaml-schemas.sh`, `test-pipeline-engine.sh`, `test-reflection-system.sh` | Structural (_meta, fields, mcp_calls) |
| `findings.schema.yaml` | `test-quality-system.sh` | Structural (fields, severity/result enums) |
| `metrics.schema.yaml` | `test-metrics-audit.sh` | Structural (_meta, name) |
| `audit.schema.yaml` | `test-metrics-audit.sh` | Structural (_meta, name) |
| `budgets.schema.yaml` | `test-xref-manifest.sh` | Spot-check (classifier default value cross-ref) |
| `mcp-registry.schema.yaml` | `test-mcp-system.sh` | Structural (servers key) |

### Skill Files (`src/global/skills/`) — 5 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `skills/orchestrator.md` | `test-pipeline-engine.sh`, `test-budget-system.sh`, `test-hooks-system.sh`, `test-passive-audit.sh`, `test-quality-system.sh`, `test-reflection-system.sh`, `test-tweak-redo.sh` | Structural (keyword presence for budget, guard, quality, reflection, passive audit, tweak/redo) |
| `skills/gates.md` | `test-budget-system.sh`, `test-passive-audit.sh`, `test-tweak-redo.sh` | Structural (budget report template, passive audit warning, tweak/redo gates) |
| `skills/dispatch.md` | `test-budget-system.sh`, `test-quality-system.sh`, `test-mcp-system.sh`, `test-reflection-system.sh` | Structural (budget context, quality checklist, MCP, Mnemosyne path) |
| `skills/errors.md` | `test-pipeline-engine.sh`, `test-budget-system.sh`, `test-hooks-system.sh` | Structural (E1-E6 Display sections, E4-BUDGET, E7-DRIFT not stub) |
| `skills/reflection.md` | `test-reflection-system.sh` | Structural (existence) |

### Command Files (`src/commands/moira/`) — 14 files

| Source File | Test File(s) | Test Type |
|---|---|---|
| `init.md` | `test-bootstrap.sh` | Structural (name, allowed-tools, not stub, 12 steps, approval gate) |
| `resume.md` | `test-checkpoint-resume.sh` | Structural (not placeholder, allowed-tools) |
| `upgrade.md` | `test-upgrade.sh` | Structural (not placeholder, allowed-tools) |
| `bench.md` | `test-quality-system.sh` | Structural (name, allowed-tools) |
| `metrics.md` | `test-metrics-audit.sh` | Structural (not placeholder) |
| `audit.md` | `test-metrics-audit.sh` | Structural (not placeholder) |
| `graph.md` | `test-graph-integration.sh` | Structural (allowed-tools, 12 subcommands) |
| `health.md` | `test-reflection-system.sh`, `test-graph-integration.sh` | Structural (existence, graph references) |
| `refresh.md` | `test-graph-integration.sh` | Structural (graph update reference) |
| All 14 commands | `test-file-structure.sh`, `test-install.sh` | Structural (existence, frontmatter name/allowed-tools) |

### Install Script

| Source File | Test File(s) | Test Type |
|---|---|---|
| `src/install.sh` | `test-install.sh`, `test-graph-integration.sh` | Functional (clean install in temp HOME, idempotency, overwrite/update, scaffold_project, task-id generation, graph.sh reference) |

### Templates

| Source File | Test File(s) | Test Type |
|---|---|---|
| Scanner templates (5 standard + 4 deep) | `test-bootstrap.sh`, `test-file-structure.sh`, `test-quality-system.sh` | Structural (sections, constraints, output paths) |
| Knowledge templates (19 files) | `test-knowledge-system.sh`, `test-file-structure.sh` | Structural (count, directory structure, evidence guidance) |
| Audit templates (12 files) | `test-metrics-audit.sh`, `test-file-structure.sh` | Structural (count, existence) |
| Reflection templates (4 files) | `test-reflection-system.sh` | Structural (existence) |
| Judge template | `test-reflection-system.sh` | Structural (existence) |
| CLAUDE.md template | `test-bootstrap.sh`, `test-file-structure.sh` | Structural (markers, heading, NEVER rules) |
| Budgets template | `test-budget-system.sh`, `test-file-structure.sh` | Structural (sections, agent roles, MCP estimates) |

## 3. Untested Source Files

### Files With No Dedicated Test Coverage
- `src/remote-install.sh` — no test file references this script
- `src/global/statusline/context-status.sh` — no test file covers statusline functionality

### Files With Only Existence/Syntax Checks (No Functional Tests)
- `lib/retry.sh` — only `test-file-structure.sh` checks existence and bash syntax
- `lib/budget.sh` — `test-budget-system.sh` verifies 9 functions exist but does not invoke them with test data
- `lib/quality.sh` — `test-quality-system.sh` verifies 4 functions exist but does not invoke them
- `lib/mcp.sh` — `test-mcp-system.sh` verifies 8 functions exist but does not invoke them
- `lib/reflection.sh` — `test-reflection-system.sh` verifies 9 functions exist but does not invoke them
- `lib/judge.sh` — `test-reflection-system.sh` verifies 4 functions exist but does not invoke them
- `lib/metrics.sh` — `test-metrics-audit.sh` verifies 6 functions exist but does not invoke them
- `lib/audit.sh` — `test-metrics-audit.sh` verifies 5 functions exist but does not invoke them
- `lib/checkpoint.sh` — `test-checkpoint-resume.sh` verifies 4 functions exist but does not invoke them
- `lib/epic.sh` — `test-epic.sh` verifies 5 functions exist but does not invoke them
- `lib/upgrade.sh` — `test-upgrade.sh` verifies 4 functions exist but does not invoke them
- `lib/settings-merge.sh` — `test-hooks-system.sh` verifies 2 functions exist but does not invoke them
- `lib/bench.sh` — `test-quality-system.sh` checks syntax only

### Template/Config Files With Minimal Coverage
- All 12 audit templates in `src/global/templates/audit/` — existence checked only, no content validation
- All 4 reflection templates — existence checked only
- Calibration examples (`src/tests/bench/calibration/`) — existence checked only

## 4. Test Quality Observations

### Functional Test Depth (files with actual behavioral testing)
- `lib/yaml-utils.sh` — init/validate round-trips, get/set paths (1-3 levels), array reads, enum rejection, required field rejection
- `lib/knowledge.sh` — read at L0/L1/L2, agent-scoped reads for 5 agents, freshness scoring with exponential decay, backward compatibility, stale detection, archive rotation with sequential batches, consistency validation (confirm/extend/conflict)
- `lib/rules.sh` — layer loading (L1/L2 content verification), conflict detection (overridable vs inviolable), project rules mapping for 5 agents, full instruction assembly with knowledge enforcement for 5 agents
- `lib/bootstrap.sh` — CLAUDE.md injection (3 scenarios: empty, existing, idempotent), gitignore (3 scenarios), frontmatter parsing (scalar/numeric/missing/body-ignore/list/alias), gen_* exit codes with sparse data, full pipeline, summary condensation, scanner-parser field contract
- `lib/graph.sh` — mock-data summary, real binary E2E (build, summary, views, queries for 7 subcommands, blast-radius, compressed, freshness, build-vs-summary consistency)
- `install.sh` — clean install, idempotency, overwrite, scaffold project, task-id generation

### Structural Test Depth
- Pipeline definitions — thoroughly tested via two complementary approaches: `test-pipeline-engine.sh` (trigger values, gate counts, auto-proceed prohibition, state writes) and `test-pipeline-graph.sh` (BFS reachability, gate completeness, no-bypass proof, fork/join balance, error handler validation)
- Agent definitions — constitutional compliance (NEVER constraints), knowledge access matrix cross-consistency between role files and matrix

### Test Patterns
- All Tier 1 tests follow a consistent pattern: `set -euo pipefail`, source helpers, define paths, run assertions, call `test_summary`
- Functional tests create temp directories with `mktemp -d` and `trap 'rm -rf' EXIT`
- `test-install.sh` overrides HOME to avoid polluting the real home directory
- `test-graph-e2e.sh` gracefully skips if ariadne binary is not in PATH

### Cross-Reference Testing
- `test-xref-manifest.sh` validates that canonical sources and dependent files actually exist on disk
- `test-xref-manifest.sh` performs spot-checks for 3 cross-reference entries (budget defaults, pipeline steps, agent names)
- `test-agent-definitions.sh` cross-checks knowledge_access values between each role file and the access matrix for all 10 agents across 5 dimensions

## 5. Coverage Summary

| Category | Total Files | Functionally Tested | Structurally Only | Untested |
|---|---|---|---|---|
| Shell libraries (lib/) | 21 | 7 (yaml-utils, knowledge, rules, bootstrap, graph, scaffold, task-id) | 13 | 1 (retry.sh) |
| Hooks | 2 | 0 (basic exit-code only) | 2 | 0 |
| Pipeline definitions | 4 | 0 (structural but thorough) | 4 | 0 |
| Agent roles | 10 | 0 | 10 | 0 |
| Quality checklists | 5 | 0 | 5 | 0 |
| Schemas | 12 | 6 (via yaml-utils round-trips) | 6 | 0 |
| Skills | 5 | 0 | 5 | 0 |
| Commands | 14 | 0 | 14 | 0 |
| Install script | 1 | 1 | 0 | 0 |
| Remote install | 1 | 0 | 0 | 1 |
| Statusline | 1 | 0 | 0 | 1 |
| **Totals** | **76** | **14** | **58** | **4** |

### Tier 1 Test File Count: 24
(Excluding `test-helpers.sh` and `run-all.sh`)
