<!-- moira:freshness refresh 2026-03-23 -->
<!-- moira:knowledge conventions L2 -->

---
naming_files: kebab-case
naming_functions: snake_case
naming_constants: _UPPER_SNAKE_CASE
indent: 2 spaces
---

# Convention Scan Report

Project: Moira (`/Users/minddecay/Documents/Projects/Moira`)
Scanned: 2026-03-22
Files examined: 24

## Language Composition

The project is primarily:
- **Shell scripts** (bash): all executable logic (`src/global/lib/*.sh`, `src/global/hooks/*.sh`, `src/tests/tier1/*.sh`, `src/install.sh`)
- **YAML**: configuration, schemas, pipeline definitions, agent role definitions (`src/global/core/`, `src/schemas/`)
- **Markdown**: commands/skills (Claude Code slash commands), templates, design documents (`src/commands/`, `src/global/skills/`, `src/global/templates/`)

No JavaScript, TypeScript, Python, or other application-language source files exist in the project.

## Naming Conventions

### File Naming: kebab-case
All files use kebab-case consistently across the entire project.

- Shell libs: `yaml-utils.sh`, `task-id.sh`, `settings-merge.sh`, `budget-track.sh` (`src/global/lib/`)
- Test files: `test-file-structure.sh`, `test-budget-system.sh`, `run-all.sh` (`src/tests/tier1/`)
- YAML configs: `knowledge-access-matrix.yaml`, `response-contract.yaml`, `xref-manifest.yaml` (`src/global/core/`)
- YAML schemas: `config.schema.yaml`, `mcp-registry.schema.yaml`, `telemetry.schema.yaml` (`src/schemas/`)
- Agent roles: `aletheia.yaml`, `hephaestus.yaml` (single-word kebab, `src/global/core/rules/roles/`)
- Quality rules: `q1-completeness.yaml`, `q2-soundness.yaml` (`src/global/core/rules/quality/`)
- Commands: `init.md`, `health.md`, `knowledge.md` (single-word kebab, `src/commands/moira/`)
- Skills: `dispatch.md`, `gates.md`, `orchestrator.md` (`src/global/skills/`)
- Scanner templates: `convention-scan.md`, `tech-scan.md`, `pattern-scan.md` (`src/global/templates/scanners/`)
- Knowledge templates: directory names are kebab-case (`project-model/`, `quality-map/`), files within are tier names (`full.md`, `summary.md`, `index.md`)
- Bench test cases: `quick-bugfix-legacy-001.yaml`, `std-feature-greenfield-001.yaml` (`src/tests/bench/cases/`)

### Function Naming: snake_case with `moira_` prefix
All shell functions use snake_case. Public functions are prefixed with `moira_`, private/internal functions with `_moira_`.

Public functions:
- `moira_state_current()` — `src/global/lib/state.sh:18`
- `moira_state_transition()` — `src/global/lib/state.sh:49`
- `moira_yaml_get()` — `src/global/lib/yaml-utils.sh:31`
- `moira_task_id()` — `src/global/lib/task-id.sh:14`
- `moira_quality_parse_verdict()` — `src/global/lib/quality.sh:20`
- `moira_quality_validate_findings()` — `src/global/lib/quality.sh:51`
- `moira_metrics_collect_task()` — `src/global/lib/metrics.sh:22`
- `moira_reflection_task_history()` — `src/global/lib/reflection.sh:20`
- `moira_bootstrap_generate_config` — `src/global/lib/bootstrap.sh` (referenced in test at `test-bootstrap.sh:47`)

Private functions:
- `_moira_budget_get_agent_budget()` — `src/global/lib/budget.sh:39`
- `_moira_budget_get_max_load()` — `src/global/lib/budget.sh:73`
- `_moira_parse_frontmatter()` — `src/global/lib/bootstrap.sh:31`
- `_moira_parse_frontmatter_list()` — `src/global/lib/bootstrap.sh:64`
- `_moira_schema_dir()` — `src/global/lib/yaml-utils.sh:14`

Test helper functions (no prefix, short names):
- `pass()`, `fail()`, `assert_dir_exists()`, `assert_file_exists()`, `assert_file_contains()`, `assert_equals()`, `assert_not_empty()`, `assert_exit_code()`, `test_summary()` — `src/tests/tier1/test-helpers.sh:9-78`

Non-library functions (local scope, no prefix):
- `find_state_dir()` — `src/global/hooks/guard.sh:32`
- `check_prerequisites()` — `src/install.sh:20`
- `install_global()` — `src/install.sh:50`
- `format_tokens()` — `src/global/statusline/context-status.sh:26`

### Constants: _UPPER_SNAKE_CASE with `_MOIRA_` prefix
Module-level constants use underscore-prefixed UPPER_SNAKE_CASE with `_MOIRA_` namespace prefix.

- `_MOIRA_BUDGET_DEFAULTS_classifier=20000` — `src/global/lib/budget.sh:18`
- `_MOIRA_BUDGET_DEFAULT_MAX_LOAD=70` — `src/global/lib/budget.sh:29`
- `_MOIRA_BUDGET_ORCHESTRATOR_CAPACITY=1000000` — `src/global/lib/budget.sh:30`
- `_MOIRA_BUDGET_ORCH_BASE_OVERHEAD=15000` — `src/global/lib/budget.sh:33`
- `_MOIRA_BUDGET_ORCH_PER_STEP=500` — `src/global/lib/budget.sh:34`
- `_MOIRA_BUDGET_ORCH_PER_GATE=2000` — `src/global/lib/budget.sh:35`
- `_MOIRA_GRAPH_DEFAULT_GRAPH_DIR=".ariadne/graph"` — `src/global/lib/graph.sh:14`
- `_MOIRA_METRICS_TREND_THRESHOLD=5` — `src/global/lib/metrics.sh:16`
- `_MOIRA_KNOWLEDGE_TYPES="project-model conventions decisions patterns failures quality-map libraries"` — `src/global/lib/knowledge.sh:17`

Exception: test files use bare UPPER_SNAKE_CASE without prefix:
- `PASSES=0`, `FAILURES=0`, `TEST_NAME=""` — `src/tests/tier1/test-helpers.sh:5-7`
- `TOTAL_PASSES=0`, `TOTAL_FAILURES=0`, `TOTAL_FILES=0` — `src/tests/tier1/run-all.sh:9-11`
- `SCRIPT_DIR`, `MOIRA_HOME`, `COMMANDS_DIR` — used across all test files (e.g., `test-file-structure.sh:7-11`)

### YAML Key Naming: snake_case
All YAML configuration and schema keys use snake_case.

- `task_id`, `step_status`, `pipeline` — `src/global/lib/state.sh:28-38`
- `agent_budgets`, `max_load_percent`, `per_agent` — `src/global/lib/budget.sh:46-78`
- `critical_count`, `warning_count` — `src/global/lib/quality.sh:29-34`
- `_meta`, `applies_to`, `knowledge_access`, `write_access`, `always_check`, `quality_checklist` — `src/global/core/rules/roles/hermes.yaml`
- `classification.default_pipeline`, `classification.size_hints_override` — `src/schemas/config.schema.yaml:29-36`
- `writes_to`, `reads_from`, `trigger_alt` — `src/global/core/pipelines/standard.yaml`

### Component Naming: Not applicable
No UI components exist in this project. The named entities are agents (Greek names: Hermes, Apollo, Athena, Metis, Daedalus, Hephaestus, Themis, Aletheia, Mnemosyne, Argus) and pipeline types (quick, standard, full, decomposition).

### Type Naming: Not applicable
No typed language (TypeScript, Java, etc.) source files exist.

## Import Style

Shell sourcing pattern is consistent across all library files:

1. Compute own directory into a module-scoped variable
2. Use shellcheck source directive
3. Source dependency by absolute path from same directory

Pattern (`src/global/lib/state.sh:10-13`):
```bash
_MOIRA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_LIB_DIR}/yaml-utils.sh"
```

Same pattern in `budget.sh:12-14`, `quality.sh:12-14`, `metrics.sh:11-13`, `reflection.sh:12-14`, `bootstrap.sh:20-24`.

Test files source helpers relative to `SCRIPT_DIR` (`src/tests/tier1/test-file-structure.sh:7-8`):
```bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
```

Hooks intentionally avoid sourcing libraries for speed (`src/global/hooks/guard.sh:5`): `"MUST be fast -- no library sourcing, minimal forks."`

## Export Style

Not applicable. Shell scripts do not use export patterns in the module sense. Functions are defined in sourced files and become available in the sourcing shell's scope. No barrel re-exports or default exports exist.

## Error Handling

### Shell strict mode
Every shell file begins with `set -euo pipefail` (`src/global/lib/state.sh:8`, `budget.sh:9`, `yaml-utils.sh:11`, `task-id.sh:8`, `quality.sh:9`, `metrics.sh:8`, `reflection.sh:9`, `bootstrap.sh:11`, `install.sh:7`, all test files).

Exception: hooks explicitly omit strict mode and use `|| exit 0` to ensure they never fail (`guard.sh:4-5`: `"MUST NOT fail -- any error exits 0 silently."`; `budget-track.sh:4-5`: same).

### Error output to stderr
Functions consistently write errors to stderr and return non-zero:
- `echo "Error: no active pipeline (current.yaml not found)" >&2; return 1` — `state.sh:56-57`
- `echo "Error: findings file not found: $findings_path" >&2; return 1` — `quality.sh:24-25`
- `echo "Error: unknown pipeline step '$new_step'" >&2; return 1` — `state.sh:71-72`
- `echo "Warning: status file not found: $status_file" >&2; return 0` — `metrics.sh:31-32` (warning returns 0, error returns 1)

### Fallback/default pattern with `|| true`
Functions use `|| true` to prevent `set -e` from killing the script on expected failures:
- `task_id=$(moira_yaml_get "$current_file" "task_id" 2>/dev/null) || true` — `state.sh:28`
- `budget=$(moira_yaml_get "$config_path/budgets.yaml" "agent_budgets.${role}" 2>/dev/null) || true` — `budget.sh:46`
- `size=$(moira_yaml_get "$status_file" "size" 2>/dev/null) || true; size=${size:-medium}` — `metrics.sh:37-38`

### Hooks: fail-safe with `|| exit 0`
- `input=$(cat 2>/dev/null) || exit 0` — `guard.sh:8`, `budget-track.sh:8`
- `echo "..." >> "$state_dir/tool-usage.log" 2>/dev/null || true` — `guard.sh:61`

### Input validation
Functions validate inputs before proceeding:
- Step name validation against known list: `state.sh:61-72`
- Status validation against known list: `state.sh:75-80`
- File existence checks: `quality.sh:23-26`, `quality.sh:55-58`

### Conditional tool availability
Hooks check for jq availability and fall back to grep/sed:
- `if command -v jq &>/dev/null; then ... else ...` — `guard.sh:12-25`, `budget-track.sh:11-23`

## Logging

Not detected. No logging library or framework is used. Output mechanisms are:
- `echo` to stdout for normal output (function results, status messages)
- `echo ... >&2` for errors and warnings
- Direct file appends for audit trails: `echo "$timestamp $tool_name $file_path" >> "$state_dir/tool-usage.log"` — `guard.sh:61`
- Test output via `pass()`/`fail()` helpers: `echo "  [PASS] $1"` — `test-helpers.sh:10`

## Code Organization

### File header pattern
Every shell file starts with a standardized header:
1. Shebang: `#!/usr/bin/env bash`
2. Comment with filename, em-dash, one-line description
3. Additional detail lines (optional)
4. Blank line
5. `set -euo pipefail`

Example (`src/global/lib/budget.sh:1-9`):
```
#!/usr/bin/env bash
# budget.sh — Context budget management for Moira
# Estimation, tracking, reporting, and overflow handling.
#
# Responsibilities: budget logic ONLY
# Does NOT handle state transitions (that's state.sh)
# Does NOT read project files (Art 1.1) — only .claude/moira/ state/config

set -euo pipefail
```

### Responsibility declarations
Library headers explicitly declare what the file IS responsible for and what it is NOT, referencing other modules:
- `state.sh:5-6`: "Responsibilities: state transitions and recording ONLY / Does NOT handle pipeline logic (that's the orchestrator skill)"
- `budget.sh:5-7`: "Responsibilities: budget logic ONLY / Does NOT handle state transitions (that's state.sh) / Does NOT read project files (Art 1.1)"
- `quality.sh:5-6`: "Responsibilities: quality findings processing and mode management ONLY / Does NOT handle pipeline routing (that's the orchestrator skill)"
- `reflection.sh:5-7`: "Responsibilities: reflection data access ONLY / Does NOT handle reflection dispatch (that's the reflection skill) / Does NOT run Mnemosyne (that's the orchestrator via Agent tool)"

### Function documentation
Functions are preceded by a comment block using box-drawing characters:
```
# ── moira_state_current [state_dir] ───────────────────────────────────
# Read current pipeline state. Outputs key fields.
```
Pattern: `# ── function_name <required_args> [optional_args] ─────...`
Observed in: `state.sh:15-17`, `state.sh:46-48`, `budget.sh:37-38`, `budget.sh:71-72`, `yaml-utils.sh:26-29`, `quality.sh:16-19`, `quality.sh:47-50`, `metrics.sh:18-21`, `task-id.sh:10-13`, `reflection.sh:16-19`

### Section dividers in test files
Test files use double-line box-drawing for section headers:
```
# ═══════════════════════════════════════════════════════════════════════
# Scanner template tests
# ═══════════════════════════════════════════════════════════════════════
```
Observed in: `test-bootstrap.sh:13-15`

### Comment style in YAML
YAML files use `#` comments. Design-reference comments cite decision IDs:
- `# Orchestrator estimation constants (D-058)` — `budget.sh:32`
- `# Trend threshold: minimum absolute difference to register as up/down (D-093a)` — `metrics.sh:15`
- `# Reserved -- not yet read by orchestrator. Target activation: Phase 12+.` — `config.schema.yaml:26`

### File lengths (shell libraries)
Range: 51 lines (`task-id.sh`) to 1041 lines (`rules.sh`).
Median: ~362 lines. Most files fall in the 200-600 line range.
Outliers above 700: `metrics.sh` (722), `bench.sh` (782), `knowledge.sh` (801), `bootstrap.sh` (926), `rules.sh` (1041).

### File lengths (test files)
Range: 49 lines (`test-epic.sh`) to 589 lines (`test-bootstrap.sh`).
Median: ~139 lines.

### YAML structure conventions
YAML config/schema files use a `_meta:` block at the top with `name:`, `description:`, and additional metadata fields:
- `base.yaml:1-5`: `_meta: name, layer, description, applies_to`
- `hermes.yaml:1-5`: `_meta: name, role, purpose, budget`
- `config.schema.yaml:2-7`: `_meta: name, file, location, git, description`

Pipeline YAML files use a header comment citing the source design document:
- `standard.yaml:1-3`: `# Standard Pipeline Definition / # Source: design/architecture/pipelines.md`

### Markdown skill/command files
Use YAML frontmatter between `---` delimiters for metadata, then markdown body:
- `init.md:1-10`: frontmatter with `name`, `description`, `argument-hint`, `allowed-tools`
- Skills use `---` section dividers and `##` headers for sections

### Indent style
Shell: 2-space indentation observed consistently across all files (`state.sh`, `budget.sh`, `yaml-utils.sh`, `quality.sh`, `metrics.sh`, `bootstrap.sh`, `guard.sh`, `install.sh`, all test files).
YAML: 2-space indentation (`base.yaml`, `hermes.yaml`, `config.schema.yaml`, `standard.yaml`).
