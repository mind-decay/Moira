<!-- moira:freshness init 2026-04-01 -->
<!-- moira:knowledge conventions L2 -->

---
naming_files: kebab-case
naming_functions: snake_case
naming_constants: UPPER_SNAKE_CASE
indent: 2 spaces
quotes: double
semicolons: false
---

## Naming Conventions

### File Naming: kebab-case

All shell library files use kebab-case consistently:

- `src/global/lib/yaml-utils.sh` (yaml-utils.sh:1)
- `src/global/lib/budget.sh` (budget.sh:1)
- `src/global/lib/task-init.sh` (task-init.sh:1)
- `src/global/lib/log-rotation.sh` (log-rotation.sh:1)
- `src/global/lib/markdown-utils.sh` (markdown-utils.sh:1)
- `src/global/lib/preflight-assemble.sh` (preflight-assemble.sh:1)
- `src/global/hooks/budget-track.sh` (budget-track.sh:1)
- `src/global/hooks/agent-inject.sh` (agent-inject.sh:1)
- `src/global/hooks/pipeline-dispatch.sh` (pipeline-dispatch.sh:1)
- `src/global/hooks/guard-prevent.sh` (guard-prevent.sh:1)

Test files also use kebab-case: `test-rules-assembly.sh`, `test-budget-system.sh`, `test-pipeline-graph.sh`.

YAML config files use kebab-case: `knowledge-access-matrix.yaml`, `response-contract.yaml`, `q2-soundness.yaml`.

Role definition files use single-word lowercase: `hermes.yaml`, `hephaestus.yaml`, `themis.yaml` (src/global/core/rules/roles/).

### Function Naming: snake_case with moira_ prefix

All public library functions use `moira_` prefix + `snake_case`:

- `moira_state_current()` (state.sh:18)
- `moira_state_transition()` (state.sh:49)
- `moira_yaml_get()` (yaml-utils.sh:53)
- `moira_budget_estimate_tokens()` (budget.sh:93)
- `moira_budget_check_overflow()` (budget.sh:180)
- `moira_rules_load_layer()` (rules.sh:19)
- `moira_rules_detect_conflicts()` (rules.sh:133)
- `moira_rules_assemble_instruction()` (rules.sh:296)
- `moira_graph_build()` (graph.sh:47)
- `moira_graph_check_binary()` (graph.sh:33)
- `moira_md_extract_section()` (markdown-utils.sh:26)
- `moira_checkpoint_create()` (checkpoint.sh:20)
- `moira_metrics_collect_task()` (metrics.sh:22)
- `moira_rotate_logs()` (log-rotation.sh:8)
- `moira_preflight_assemble_apollo()` (preflight-assemble.sh:25)
- `moira_task_init()` (task-init.sh:22)

Private/internal functions use `_moira_` prefix:

- `_moira_budget_get_agent_budget()` (budget.sh:41)
- `_moira_budget_get_max_load()` (budget.sh:75)
- `_moira_yaml_split_key()` (yaml-utils.sh:29)
- `_moira_schema_dir()` (yaml-utils.sh:14)

Non-library helper functions in hooks use bare snake_case without prefix:

- `find_state_dir()` (guard.sh:42, budget-track.sh:28, agent-inject.sh:17, pipeline-dispatch.sh:39)
- `check_prerequisites()` (install.sh:20)
- `install_global()` (install.sh:49)

Test helper functions use bare snake_case:

- `pass()` (test-helpers.sh:9)
- `fail()` (test-helpers.sh:13)
- `assert_dir_exists()` (test-helpers.sh:19)
- `assert_file_exists()` (test-helpers.sh:25)
- `assert_file_contains()` (test-helpers.sh:31)
- `assert_equals()` (test-helpers.sh:43)
- `assert_not_empty()` (test-helpers.sh:50)
- `assert_exit_code()` (test-helpers.sh:58)
- `test_summary()` (test-helpers.sh:70)

### Constants: UPPER_SNAKE_CASE with _MOIRA_ prefix

Module-level constants use `_MOIRA_` prefix + UPPER_SNAKE_CASE:

- `_MOIRA_BUDGET_DEFAULTS_classifier=20000` (budget.sh:18)
- `_MOIRA_BUDGET_DEFAULT_MAX_LOAD=70` (budget.sh:30)
- `_MOIRA_BUDGET_ORCHESTRATOR_CAPACITY=1000000` (budget.sh:31)
- `_MOIRA_BUDGET_ORCH_BASE_OVERHEAD=15000` (budget.sh:34)
- `_MOIRA_BUDGET_ORCH_PER_STEP=500` (budget.sh:35)
- `_MOIRA_GRAPH_DEFAULT_GRAPH_DIR=".ariadne/graph"` (graph.sh:14)
- `_MOIRA_GRAPH_DEFAULT_VIEWS_DIR=".ariadne/views"` (graph.sh:15)
- `_MOIRA_GRAPH_PID_FILE=".ariadne/graph/.serve.pid"` (graph.sh:16)
- `_MOIRA_METRICS_TREND_THRESHOLD=5` (metrics.sh:16)

Exception: Some constants mix UPPER_SNAKE with lowercase suffixes (role names):
`_MOIRA_BUDGET_DEFAULTS_classifier`, `_MOIRA_BUDGET_DEFAULTS_explorer` (budget.sh:18-28). These are used as dynamic variable names via `eval` referencing role names.

Environment variable constants use UPPER_SNAKE_CASE without underscore prefix:

- `MOIRA_HOME` (install.sh:10, cli/moira:13)
- `MOIRA_VERSION` (install.sh:11)
- `MOIRA_LIB` (cli/moira:14)
- `MOIRA_PROJECT_STATE` (cli/moira:15)
- `MOIRA_CONFIG` (cli/moira:16)
- `MOIRA_SCHEMA_DIR` (yaml-utils.sh:15)

Script-local directory variables use UPPER_SNAKE_CASE:

- `SCRIPT_DIR` (run-all.sh:8, test-rules-assembly.sh:7, test-budget-system.sh:7)
- `TEMP_DIR` (test-rules-assembly.sh:13)

Color variables use UPPER_SNAKE_CASE:

- `BOLD`, `DIM`, `RESET`, `GREEN`, `YELLOW`, `RED`, `CYAN` (cli/moira:21-28)

### YAML Key Naming: snake_case

YAML configuration and schema files use snake_case for keys:

- `task_id`, `step_status`, `pipeline` (state operations, state.sh:28-38)
- `agent_budgets`, `max_load_percent`, `orchestrator_capacity` (budget config)
- `mcp_estimates` (budget template)
- `per_agent` (config.schema.yaml:60)
- `classification.default_pipeline`, `classification.size_hints_override` (config.schema.yaml:28-34)
- `rotation_threshold_lines`, `archive_dir` (log-rotation.sh:18-25)
- `_meta`, `applies_to`, `quality_stance` (base.yaml:1-5, hermes.yaml:1-13)
- `quality_checklist`, `writes_to`, `reads_from` (standard.yaml:21-28)

### YAML Role Definition Naming: snake_case for keys, lowercase for names

- `_meta.name: hermes`, `_meta.role: explorer` (hermes.yaml:1-3)
- `_meta.name: base`, `_meta.layer: 1` (base.yaml:1-3)
- `exploration_strategy`, `gap_analysis` (hermes.yaml:17-37)

## Import Style

### Shell Source Pattern

Libraries source dependencies from the same directory using a directory resolution pattern:

```
_MOIRA_<MODULE>_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
source "${_MOIRA_<MODULE>_LIB_DIR}/yaml-utils.sh"
```

Evidence:
- `_MOIRA_LIB_DIR` in state.sh:11
- `_MOIRA_BUDGET_LIB_DIR` in budget.sh:12
- `_MOIRA_RULES_LIB_DIR` in rules.sh:11
- `_MOIRA_METRICS_LIB_DIR` in metrics.sh:11
- `_MOIRA_REFLECTION_LIB_DIR` in reflection.sh:12
- `_MOIRA_TASK_INIT_LIB_DIR` in task-init.sh:11
- `_MOIRA_BOOTSTRAP_LIB_DIR` in bootstrap.sh:20
- `_MOIRA_COMPLETION_LIB_DIR` in completion.sh:10
- `_MOIRA_AUDIT_LIB_DIR` in audit.sh:12
- `_MOIRA_KNOWLEDGE_LIB_DIR` in knowledge.sh:11
- `_MOIRA_PREFLIGHT_ASSEMBLE_LIB_DIR` in preflight-assemble.sh:12

All lib files use `# shellcheck source=<filename>` annotations before source statements (state.sh:12, budget.sh:13, rules.sh:13, checkpoint.sh:13).

### Import Ordering

Observed ordering (consistent across files):
1. Shebang line
2. File description comment block
3. `set -euo pipefail`
4. Directory resolution variable
5. shellcheck source annotations + source statements
6. Constants
7. Function definitions

Evidence: state.sh:1-14, budget.sh:1-37, rules.sh:1-16, yaml-utils.sh:1-12, metrics.sh:1-16.

### Hooks: Lightweight, No Library Sourcing

Hooks explicitly avoid sourcing libraries for performance. They use inline jq or grep/sed fallbacks:

- guard.sh:4 comment: "MUST be fast -- no library sourcing, minimal forks."
- budget-track.sh:4 comment: "MUST be fast -- no library sourcing, minimal forks."
- agent-inject.sh:12 comment: "MUST be fast -- minimal forks."
- pipeline-dispatch.sh:20 comment: "MUST NOT fail -- exits 0 silently on any error."

Hooks parse JSON using a dual-path pattern:
```
if command -v jq &>/dev/null; then
  tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
else
  tool_name=$(echo "$input" | grep -o '...' | head -1 | sed '...' 2>/dev/null) || tool_name=""
fi
```
Evidence: guard.sh:12-24, budget-track.sh:10-22, pipeline-dispatch.sh:24-33.

## Export Style

No explicit export mechanism. Shell libraries define functions that become available after sourcing. There are no barrel re-exports.

Libraries expose public functions via `moira_<module>_<action>()` naming. Private functions use `_moira_<module>_<action>()` prefix convention (underscore-prefixed).

Evidence:
- Public: `moira_yaml_get`, `moira_state_current`, `moira_budget_estimate_tokens`
- Private: `_moira_budget_get_agent_budget`, `_moira_yaml_split_key`, `_moira_schema_dir`

## Error Handling

### Pattern 1: stderr + return code

All library functions write errors to stderr and return non-zero:

```
echo "Error: no active pipeline (current.yaml not found)" >&2
return 1
```

Evidence:
- state.sh:57-58 ("Error: no active pipeline")
- state.sh:70-71 ("Error: unknown pipeline step")
- yaml-utils.sh:58 (return 1 for missing file)
- rules.sh:27-28 ("Error: base rules not found")
- graph.sh:53-54 ("Error: moira_graph_build requires <project_root>")
- graph.sh:57-58 ("Error: ariadne binary not found in PATH")
- checkpoint.sh:32-33 ("Error: task directory not found")
- checkpoint.sh:40-42 ("Error: invalid checkpoint reason")
- preflight-assemble.sh:41-43 ("Warning: apollo.yaml not found")

Error messages use "Error:" prefix for fatal errors and "Warning:" prefix for non-fatal issues.

164 occurrences of `>&2` across 23 library files.

### Pattern 2: Silent failure in hooks

Hooks MUST NOT fail. Every external command is wrapped with `|| exit 0` or `|| true`:

```
input=$(cat 2>/dev/null) || exit 0
tool_name=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
```

Evidence:
- guard.sh:8: `input=$(cat 2>/dev/null) || exit 0`
- guard.sh:13: `|| tool_name=""`
- budget-track.sh:8: `input=$(cat 2>/dev/null) || exit 0`
- agent-inject.sh:14: `input=$(cat 2>/dev/null) || exit 0`

### Pattern 3: set -euo pipefail

Every shell file begins with `set -euo pipefail` after the shebang and comment block:

Evidence: state.sh:8, budget.sh:9, yaml-utils.sh:11, rules.sh:8, guard.sh (absent -- hooks intentionally omit strict mode), checkpoint.sh:9, metrics.sh:8, graph.sh:10, install.sh:6, task-init.sh:9, test-helpers.sh (absent -- sourced, not executed), test-rules-assembly.sh:4, test-budget-system.sh:4.

Hooks deliberately omit `set -euo pipefail` because they must never fail.

### Pattern 4: Validation via case statements

Input validation uses case statements for enum-like values:

```
case "$reason" in
  context_limit|user_pause|error|session_end) ;;
  *) echo "Error: invalid checkpoint reason..." >&2; return 1 ;;
esac
```

Evidence: checkpoint.sh:37-43, state.sh:61-72 (valid_steps loop), state.sh:76-80 (valid_statuses loop).

## Logging

No logging library is used. The project uses two logging mechanisms:

### 1. Structured log files (append-only)

Hooks append structured lines to log files:

- `violations.log`: guard.sh:80+ writes timestamped violation records
- `tool-usage.log`: guard.sh:80+ writes timestamped tool usage records
- `budget-tool-usage.log`: budget-track.sh:68 writes `"$timestamp $tool_name ${file_path:--} ${file_size:-0}"`

Format is space-delimited: `timestamp tool_name file_path size`

Evidence: budget-track.sh:68.

### 2. stderr for human-readable messages

Libraries use bare `echo` to stderr for errors/warnings. No structured logging format, no log levels beyond Error/Warning prefix:

- `echo "Error: ..." >&2` (fatal, returns non-zero)
- `echo "Warning: ..." >&2` (non-fatal, continues)
- `echo "[OK] ..." ` (stdout, success messages in install.sh:46)
- `echo "[ERROR] ..."` (stdout, in install.sh:23-25)

No third-party logging library was found. No JSON-structured logging. No log level configuration.

## Code Organization

### File Structure

Shell libraries (`src/global/lib/`) follow a consistent structure:

1. Shebang: `#!/usr/bin/env bash`
2. Module comment: `# <filename> -- <one-line description>`
3. Extended comment block: responsibilities, what it does NOT handle
4. `set -euo pipefail`
5. Directory resolution + dependency sourcing
6. Constants (if any)
7. Function definitions

Evidence: state.sh:1-14, budget.sh:1-37, yaml-utils.sh:1-12, rules.sh:1-16, checkpoint.sh:1-15, metrics.sh:1-16, graph.sh:1-16.

Hooks (`src/global/hooks/`) follow a different structure:

1. Shebang: `#!/usr/bin/env bash`
2. Module comment with design reference
3. No `set -euo pipefail` (intentional)
4. `input=$(cat 2>/dev/null) || exit 0`
5. JSON parsing (jq with grep/sed fallback)
6. Early exits for non-applicable cases
7. Core logic

Evidence: guard.sh:1-8, budget-track.sh:1-8, agent-inject.sh:1-14, pipeline-dispatch.sh:1-21.

### Comment Style

Section headers use a decorative dash pattern:

```
# ── moira_function_name <args> ────────────────────────────────────
```

206 occurrences of `# ── ` across 25 library files.

Per-function comments describe purpose, arguments, and return values in the section header line. No separate doc-comment block format is used.

Inline comments use `#` with a single space. Design decision references use parenthetical format: `(D-058)`, `(D-031)`, `(Art 3.1)`.

Evidence:
- budget.sh:33: `# Orchestrator estimation constants (D-058)`
- guard.sh:2: `# Guard hook -- PostToolUse violation detection and audit logging (Layer 2, D-031)`
- budget-track.sh:3: `# Logs tool activity for post-task budget analysis (Art 3.2).`
- markdown-utils.sh:3: `# D-201: Provides reliable section extraction from markdown artifacts.`

### File Length

Library files vary considerably in length. Based on function count per file:

- rules.sh: 6+ functions (moira_rules_load_layer, moira_rules_detect_conflicts, moira_rules_assemble_instruction, moira_rules_cpm_schedule, moira_rules_cpm_critical_path, moira_rules_lpt_split)
- budget.sh: 9+ functions (estimate_tokens, estimate_batch, estimate_agent, check_overflow, record_agent, orchestrator_check, generate_report, write_telemetry, handle_overflow)
- reflection.sh: 8+ functions
- knowledge.sh: multiple functions (22 `# ── ` section headers)
- bootstrap.sh: multiple functions (20 `# ── ` section headers)

Hooks are typically single-purpose, single-flow files (no function definitions in guard.sh, budget-track.sh).

### Responsibility Comments

Library files include explicit responsibility boundary comments:

- state.sh:5-6: "Responsibilities: state transitions and recording ONLY / Does NOT handle pipeline logic"
- budget.sh:5-7: "Responsibilities: budget logic ONLY / Does NOT handle state transitions / Does NOT read project files"
- yaml-utils.sh:9: "Responsibilities: YAML parsing ONLY / Does NOT handle state logic"
- rules.sh:5-6: "Responsibilities: rule assembly ONLY / Does NOT handle pipeline logic or agent dispatch"
- graph.sh:6-7: "Responsibilities: wrapping ariadne binary commands / Does NOT implement graph algorithms"

### Bash Compatibility

Files consistently note bash 3.2+ compatibility (macOS default):

- yaml-utils.sh:6: "Compatible with bash 3.2+ (macOS default)"
- graph.sh:8: "Bash 3.2+ compatible"
- cli/moira:8: "Bash 3.2+ compatible (macOS default)"
- markdown-utils.sh:4: "POSIX-compatible (no bashisms) -- works in bash and zsh"
- install.sh:35: checks `BASH_VERSINFO[0] -lt 3`

Zsh compatibility is also addressed via `${BASH_SOURCE[0]:-${(%):-%x}}` pattern used in directory resolution (state.sh:11, budget.sh:12, etc.).

### Items Searched For But Not Found

- No `.eslintrc`, `.prettierrc`, `.editorconfig`, or `tsconfig.json` in project root (only in test fixtures)
- No `package.json` in project root (only in test fixtures)
- No TypeScript, JavaScript, Python, or Go source files in the project source
- No component/view files (this is not a UI project)
- No API route handlers
- No type definition files
- No logging library (winston, pino, bunyan, etc.)
- No error boundary pattern
- No result/Either types
- No default exports (not applicable to shell scripts)
- No barrel re-exports (not applicable to shell scripts)
