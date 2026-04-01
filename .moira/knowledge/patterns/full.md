<!-- moira:freshness init 2026-04-01 -->
<!-- moira:knowledge patterns L2 -->

---
api_style: REST
---

## Component Pattern

Not detected. This is not a frontend project. Moira is a meta-orchestration framework for Claude Code composed of shell scripts, YAML configuration, and markdown skill/command definitions. There are no UI components.

## API Pattern

Not detected in the traditional sense. There is no HTTP API. The system's interface is a set of Claude Code slash commands defined as markdown files in `src/commands/moira/` (e.g., `task.md`, `status.md`, `help.md`). These commands are parsed by Claude Code's skill system, not by a traditional API server. Each command file uses YAML frontmatter to declare metadata (`name`, `description`, `argument-hint`, `allowed-tools`) followed by markdown instructions that define the command's behavior.

Evidence:
- `src/commands/moira/task.md` (lines 1-12): YAML frontmatter with `allowed-tools: [Agent, Read, Write, TaskCreate, TaskUpdate, TaskList]`
- `src/commands/moira/status.md`, `src/commands/moira/help.md`, etc. follow the same frontmatter + markdown body pattern

## Data Access Pattern

There is no database. All state is managed through YAML files on the local filesystem under `.moira/state/`. A custom pure-bash YAML parser (`src/global/lib/yaml-utils.sh`) provides read/write/validate operations with dot-path access up to 3 levels deep. No jq or Python dependency — bash + awk + sed + grep only, compatible with bash 3.2+ (macOS default).

Key functions:
- `moira_yaml_get <file> <dot.path.key>` — read a value by dot-path
- `moira_yaml_set <file> <dot.path.key> <value>` — write/update a value
- `moira_yaml_validate <file> <schema_name>` — validate against schema
- `moira_yaml_init <schema_name> <target_path>` — generate from schema defaults
- `moira_yaml_block_append <file> <parent_key> <yaml_text>` — append block under parent

Evidence:
- `src/global/lib/yaml-utils.sh` (667 lines): full implementation
- `src/global/lib/state.sh` (line 13): sources `yaml-utils.sh`
- `src/global/lib/budget.sh` (line 14): sources `yaml-utils.sh`

Schema files in `src/schemas/` define the structure of each YAML state file using a custom schema format with `_meta`, `fields` (with `type`, `required`, `default`, `enum` properties). Validation is performed by `moira_yaml_validate()` using awk-based schema parsing.

Evidence:
- `src/schemas/config.schema.yaml`: 209 lines defining all config fields
- `src/schemas/current.schema.yaml`, `src/schemas/status.schema.yaml`, etc.

## State Management

State is managed through a layered file system:

1. **Current state**: `.moira/state/current.yaml` — active pipeline state (task_id, pipeline, step, step_status, context_budget, history)
2. **Per-task state**: `.moira/state/tasks/{task_id}/` — contains `manifest.yaml`, `status.yaml`, `input.md`, `classification.md`, `exploration.md`, `architecture.md`, `plan.md`, `implementation.md`, `review.md`, `telemetry.yaml`, `findings/`
3. **Configuration**: `.moira/config.yaml` and `.moira/config/budgets.yaml`

State transitions are managed by `src/global/lib/state.sh` which provides:
- `moira_state_current()` — read current pipeline state
- `moira_state_transition()` — update step/status with validation against pipeline step ordering
- `moira_state_gate()` — record gate decisions
- `moira_state_agent_done()` — record agent execution in history
- `moira_state_increment_retry()` — increment retry counters
- `moira_state_set_status()` — set task status with enum validation

Evidence:
- `src/global/lib/state.sh` (356 lines): all state operations
- `src/global/lib/state.sh` (lines 61-66): step name validation against hardcoded list
- `src/global/lib/state.sh` (lines 88-129): pipeline-aware transition validation reading from pipeline YAML

## Common Abstractions

### 1. Hook Pattern (Claude Code hooks — shell scripts)

All hooks follow a consistent structure:
1. Read JSON input from stdin (`input=$(cat 2>/dev/null) || exit 0`)
2. Parse JSON fields using jq with grep/sed fallback
3. Locate Moira state directory by walking up from CWD (`find_state_dir()`)
4. Check guard activation (`.guard-active` marker file)
5. Read config to check if the hook is enabled
6. Perform hook-specific logic
7. Output JSON to stdout for Claude Code hook protocol (e.g., `{"hookSpecificOutput":{...}}`)
8. Exit 0 unconditionally (hooks MUST NOT fail)

Evidence:
- `src/global/hooks/guard.sh` (117 lines): PostToolUse violation detection
- `src/global/hooks/budget-track.sh` (88 lines): PostToolUse token tracking
- `src/global/hooks/agent-inject.sh` (121 lines): SubagentStart context injection
- `src/global/hooks/pipeline-dispatch.sh` (336 lines): PreToolUse dispatch validation

The `find_state_dir()` function is duplicated across all hooks (not shared via library) — each hook contains its own identical copy. This is intentional: hooks must be fast with no library sourcing and minimal forks.

### 2. Library Module Pattern (shell libraries)

All library files follow a consistent structure:
1. Shebang + header comment describing purpose and responsibility boundary
2. `set -euo pipefail`
3. Resolve own directory for sourcing dependencies: `_MOIRA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"`
4. Source dependencies from the same directory (e.g., `source "${_MOIRA_LIB_DIR}/yaml-utils.sh"`)
5. Functions prefixed with `moira_` namespace (e.g., `moira_state_transition`, `moira_budget_estimate_tokens`)
6. Internal helper functions prefixed with `_moira_` (e.g., `_moira_budget_get_agent_budget`)

Evidence:
- `src/global/lib/state.sh` (lines 1-13): header, set, sourcing pattern
- `src/global/lib/budget.sh` (lines 1-14): identical pattern
- `src/global/lib/quality.sh` (lines 1-14): identical pattern
- `src/global/lib/yaml-utils.sh` (lines 1-10): base library (no dependency sourcing)

### 3. Agent Role Definition Pattern (YAML)

All agent roles follow a consistent YAML schema:
- `_meta`: name, role, purpose, budget
- `identity`: multiline string defining agent persona
- `quality_stance`: agent's quality focus
- `capabilities`: list of what the agent can do
- `never`: list of absolute prohibitions
- `knowledge_access`: per-knowledge-type access levels (L0/L1/L2/null)
- `write_access`: what knowledge the agent can write to
- `analysis_paralysis_guard`: threshold for consecutive read-only operations
- `quality_checklist`: assigned quality gate (or null)
- `response_format`: expected response structure

Evidence:
- `src/global/core/rules/roles/hermes.yaml` (95 lines): explorer role
- Other role files: `apollo.yaml`, `athena.yaml`, `metis.yaml`, `daedalus.yaml`, `hephaestus.yaml`, `themis.yaml`, `aletheia.yaml`, `mnemosyne.yaml`, `argus.yaml`, `calliope.yaml`

### 4. Pipeline Definition Pattern (YAML)

All pipelines follow a consistent YAML schema:
- `_meta`: name, description, trigger conditions
- `steps`: ordered list with `id`, `agent`, `role`, `mode`, `writes_to`, `reads_from`
- `gates`: list with `id`, `after_step`, `required`, `options` (each with `id` and `description`)
- `error_handlers`: keyed by error code (E1-E11) with `action`, `max_attempts`, `on_max`, `display`
- `post`: post-pipeline actions (reflection, budget_report)

Evidence:
- `src/global/core/pipelines/standard.yaml` (222 lines)
- Other pipelines: `quick.yaml`, `full.yaml`, `decomposition.yaml`, `analytical.yaml`

### 5. Quality Checklist Pattern (YAML)

All quality gates follow a consistent YAML schema:
- `_meta`: name, gate ID, description, assigned agent, pipeline_step
- `items`: list of checklist items with `id`, `check` (description), `required` (boolean)
- `on_missing`: action when items are missing

Evidence:
- `src/global/core/rules/quality/q1-completeness.yaml`
- Other quality files: `q2-soundness.yaml`, `q3-feasibility.yaml`, `q3b-plan-check.yaml`, `q4-correctness.yaml`, `q5-coverage.yaml`

### 6. Schema Definition Pattern (YAML)

All schemas follow a consistent meta-schema:
- `_meta`: name, file, location, git (committed/ignored), description
- `fields`: keyed by dot-path name, each with `type`, `required`, `default`, `enum`, `description`
- Supported types: `string`, `number`, `boolean`, `enum`, `array`, `block`

Evidence:
- `src/schemas/config.schema.yaml` (209 lines)
- Other schemas: `current.schema.yaml`, `status.schema.yaml`, `budgets.schema.yaml`, `manifest.schema.yaml`, `metrics.schema.yaml`, `telemetry.schema.yaml`, `findings.schema.yaml`, `locks.schema.yaml`, `queue.schema.yaml`, `audit.schema.yaml`, `role.schema.yaml`, `mcp-registry.schema.yaml`

### 7. Cross-Reference Manifest Pattern (YAML)

The `xref-manifest.yaml` defines data dependencies between files:
- Each entry has `id`, `description`, `canonical_source`, `dependents` (list of `file`, `field`, `sync_type`), `values_tracked`
- Sync types: `value_must_match`, `enum_must_match`, `names_must_match`

Evidence:
- `src/global/core/xref-manifest.yaml` (entries xref-001 through xref-005+ covering budget defaults, step names, role names, knowledge access, quality gates)

### 8. Skill Definition Pattern (Markdown)

Skills are markdown files that define orchestrator behaviors:
- Header with references to design documents
- Structured sections with step-by-step instructions
- Embedded prompt templates with `{placeholder}` syntax
- Tables mapping agents, roles, and configurations

Evidence:
- `src/global/skills/dispatch.md` (671 lines): agent dispatch module
- `src/global/skills/orchestrator.md`, `src/global/skills/gates.md`, `src/global/skills/reflection.md`, `src/global/skills/completion.md`, `src/global/skills/errors.md`

## Recurring Structures

### JSON Parsing with jq/grep Fallback

Every hook that reads JSON input implements the same dual-path parsing pattern:
```bash
if command -v jq &>/dev/null; then
  field=$(echo "$input" | jq -r '.field // empty' 2>/dev/null) || field=""
else
  field=$(echo "$input" | grep -o '"field"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"field"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || field=""
fi
```

This pattern appears in: `guard.sh`, `budget-track.sh`, `agent-inject.sh`, `pipeline-dispatch.sh`.

### Find State Directory

Every hook contains an identical `find_state_dir()` function that walks up from `$PWD` looking for `.moira/state/current.yaml`:

```bash
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.moira/state/current.yaml" ]]; then
      echo "$dir/.moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}
```

This pattern appears in: `guard.sh`, `budget-track.sh`, `agent-inject.sh`, `pipeline-dispatch.sh`, `agent-done.sh`, `pipeline-tracker.sh`, `guard-prevent.sh`, and others.

### Config-Gated Hook Execution

Hooks check a specific config flag before executing their main logic:
```bash
config_file="${state_dir%/state}/config.yaml"
if [[ -f "$config_file" ]]; then
  val=$(grep 'config_key' "$config_file" 2>/dev/null | head -1) || true
  if [[ "$val" == *"false"* ]]; then
    exit 0
  fi
fi
```

Evidence: `guard.sh` checks `guard_enabled`, `budget-track.sh` checks `budget_tracking_enabled`.

### Enum Validation Pattern

Functions that accept enumerated values validate against a hardcoded space-separated list:
```bash
local valid_values="val1 val2 val3"
local is_valid=false
for v in $valid_values; do
  if [[ "$input" == "$v" ]]; then
    is_valid=true
    break
  fi
done
if ! $is_valid; then
  echo "Error: invalid value '$input'" >&2
  return 1
fi
```

Evidence:
- `state.sh` (lines 62-72): step name validation
- `state.sh` (lines 75-86): status validation
- `state.sh` (lines 148-150): gate decision validation
- `state.sh` (lines 297-310): task status validation

### Budget Config Lookup Chain

Budget values are resolved through a 4-level fallback chain: `budgets.yaml` -> `config.yaml` -> role definition YAML -> hardcoded defaults.

Evidence: `budget.sh` `_moira_budget_get_agent_budget()` (lines 41-71)

### Responsibility Separation Comments

Every library file begins with a comment block that explicitly states what it is responsible for AND what it is NOT responsible for:
```bash
# Responsibilities: budget logic ONLY
# Does NOT handle state transitions (that's state.sh)
# Does NOT read project files (Art 1.1)
```

Evidence:
- `state.sh` (line 6): "Responsibilities: state transitions and recording ONLY / Does NOT handle pipeline logic"
- `budget.sh` (line 7-8): "Responsibilities: budget logic ONLY / Does NOT handle state transitions"
- `quality.sh` (line 7): "Responsibilities: quality findings processing and mode management ONLY"
- `yaml-utils.sh` (line 9): "Responsibilities: YAML parsing ONLY"
