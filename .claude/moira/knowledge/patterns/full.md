<!-- moira:freshness refresh 2026-03-23 -->
<!-- moira:knowledge patterns L2 -->

---
api_style: YAML-defined pipeline orchestration
api_handler_structure: Shell function libraries with YAML state files
api_validation: YAML schema validation via pure-bash awk parser
error_handling: Enumerated error codes (E1-E11) with per-type recovery handlers
---

# Pattern Scan Report

## Component Pattern

Not detected. This project has no frontend UI components. Moira is a meta-orchestration framework for Claude Code, consisting of YAML configuration, shell libraries, and markdown prompt/skill definitions.

## API Pattern

Not detected in the traditional REST/GraphQL sense. The system uses a pipeline-based orchestration pattern where:

- **Pipeline definitions** (YAML) define step sequences, agent dispatch modes, gate points, and error handlers
- **Agent dispatch** is performed by the orchestrator skill via Claude Code's Agent tool, not HTTP endpoints
- **Commands** are Claude Code slash commands defined as markdown files with YAML frontmatter specifying `allowed-tools`

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/pipelines/standard.yaml` — pipeline step definition with `steps[]`, `gates[]`, `error_handlers`
- `/Users/minddecay/Documents/Projects/Moira/src/commands/moira/init.md` — command as markdown with YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools`)

## Data Access Pattern

All state is managed through YAML files read/written by a custom pure-bash YAML parser (`yaml-utils.sh`). There is no database, no ORM, no SQL.

### Recurring YAML state access pattern

Every shell library follows a consistent pattern:

1. Source `yaml-utils.sh` from the same directory
2. Read values via `moira_yaml_get <file> <dot.path.key>` (supports 1-3 level dot-path keys)
3. Write values via `moira_yaml_set <file> <dot.path.key> <value>`
4. Append block entries via `moira_yaml_block_append <file> <parent_key> <yaml_text>`
5. Validate files via `moira_yaml_validate <file> <schema_name>`
6. Initialize files from schema via `moira_yaml_init <schema_name> <target_path>`

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/yaml-utils.sh` — all 6 functions listed above
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/state.sh` — uses `moira_yaml_get`, `moira_yaml_set`, `moira_yaml_block_append`
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/budget.sh` — uses `moira_yaml_get`, `moira_yaml_set`, `moira_yaml_block_append`
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/quality.sh` — uses `moira_yaml_get`, `moira_yaml_set`

### Schema-driven file generation

YAML schema files in `src/schemas/` define fields with `type`, `required`, `enum`, and `default` properties. The `moira_yaml_init` function generates conformant YAML files from these schemas.

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/schemas/current.schema.yaml` — defines `current.yaml` structure
- `/Users/minddecay/Documents/Projects/Moira/src/schemas/config.schema.yaml` — defines `config.yaml` structure

## State Management

Not a frontend application. State is managed through:

1. **Live pipeline state**: `.claude/moira/state/current.yaml` — tracks active task, pipeline step, gate status, context budget
2. **Per-task records**: `.claude/moira/state/tasks/{task_id}/status.yaml` — gates, retries, budget, completion
3. **Project config**: `.claude/moira/config.yaml` — project settings, quality mode, budget overrides

State transitions are validated against enums (e.g., valid steps, valid statuses) before writes.

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/state.sh` — `moira_state_transition()` validates `new_step` against a fixed list, validates `new_status` against enum, then writes

## Common Abstractions

### 1. Shell library sourcing pattern

Every shell library follows the same bootstrap pattern:
```
set -euo pipefail
_MOIRA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_MOIRA_LIB_DIR}/yaml-utils.sh"
```

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/state.sh` (lines 8-13)
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/budget.sh` (lines 9-14)
- `/Users/minddecay/Documents/Projects/Moira/src/global/lib/quality.sh` (lines 9-14)

### 2. Agent role definition pattern (YAML)

Every agent role file follows an identical YAML structure:
```yaml
_meta:
  name: <name>
  role: <role>
  purpose: <description>
  budget: <number>
identity: |
  <multi-line identity prompt>
capabilities:
  - <list of capabilities>
never:
  - <list of prohibitions>
knowledge_access:
  project_model: <level|null>
  conventions: <level|null>
  decisions: <level|null>
  patterns: <level|null>
  quality_map: <level|null>
  failures: <level|null>
  libraries: <level|null>
  graph: <level|null>
quality_checklist: <checklist_name|null>
response_format: |
  STATUS: success|failure|blocked|budget_exceeded
  SUMMARY: ...
  ARTIFACTS: ...
  NEXT: ...
```

10 agent role files observed, all conforming to this structure.

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/rules/roles/hermes.yaml`
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/rules/roles/athena.yaml`
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/rules/roles/daedalus.yaml`

### 3. Quality checklist pattern (YAML)

Quality checklists follow a consistent structure:
```yaml
_meta:
  name: <name>
  gate: <Q1-Q5>
  description: <description>
  agent: <agent_name>
  pipeline_step: <step>
items:
  - id: <ID>
    check: <description>
    required: true|false
on_missing: <action>
```

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/rules/quality/q1-completeness.yaml`

### 4. Agent response contract

All agents return the same 4-line format:
```
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <factual sentence>
ARTIFACTS: [<file paths>]
NEXT: <next step>
```

Agents with quality gates add a `QUALITY:` line.

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/response-contract.yaml`
- Response format duplicated identically in `hermes.yaml`, `athena.yaml`, `daedalus.yaml`

### 5. Pipeline definition pattern (YAML)

Pipeline YAML files follow a consistent structure:
```yaml
_meta:
  name: <name>
  description: <description>
  trigger: { size: <enum>, confidence: <enum> }
steps:
  - id: <step_id>
    agent: <agent_name|null>
    role: <role>
    mode: foreground|background|parallel
    writes_to: <path_template>
    reads_from: <path_template|list>
gates:
  - id: <gate_id>
    after_step: <step_id>
    required: true|false
    options:
      - id: <option_id>
        description: <text>
error_handlers:
  <error_code>:
    action: <action>
    ...
post:
  reflection: <mode>
  budget_report: true|false
```

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/core/pipelines/standard.yaml`
- 4 pipeline files total: `quick.yaml`, `standard.yaml`, `full.yaml`, `decomposition.yaml`

### 6. Schema definition pattern (YAML)

```yaml
_meta:
  name: <name>
  file: <filename>
  location: <path>
  git: <gitignored|committed>
  description: <text>
fields:
  <dot.path.key>:
    type: <string|number|enum|boolean|block|array>
    required: <true|false>
    enum: [<values>]  # if type is enum
    default: <value>
```

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/schemas/current.schema.yaml`
- `/Users/minddecay/Documents/Projects/Moira/src/schemas/config.schema.yaml`
- 12 schema files total in `src/schemas/`

## Recurring Structures

### 1. Enum validation pattern in shell functions

Multiple functions validate inputs against a whitespace-separated list of valid values using the same loop pattern:

```bash
local valid_values="value1 value2 value3"
local is_valid=false
for v in $valid_values; do
  if [[ "$new_value" == "$v" ]]; then
    is_valid=true
    break
  fi
done
if ! $is_valid; then
  echo "Error: invalid value '$new_value'" >&2
  return 1
fi
```

Observed in 4 separate functions:
- `moira_state_transition` — validates step names and step statuses (two loops)
- `moira_state_gate` — validates gate decisions via `case` statement (variant)
- `moira_state_set_status` — validates task statuses
- `moira_state_record_completion` — validates completion actions

Evidence: `/Users/minddecay/Documents/Projects/Moira/src/global/lib/state.sh` (lines 61-86, 148-152, 298-306, 331-342)

### 2. Guard/safety-first file existence checks

Every function that operates on state files begins with a file existence check, returning error or warning:

```bash
if [[ ! -f "$target_file" ]]; then
  echo "Error: ..." >&2
  return 1  # or return 0 for non-critical warnings
fi
```

This pattern appears in every function in `state.sh`, `budget.sh`, `quality.sh`, and `yaml-utils.sh`.

### 3. Default value fallback chain

Budget resolution follows a multi-source fallback chain: `budgets.yaml` -> `config.yaml` -> role definition YAML -> hardcoded defaults. The same pattern (try source 1, fall back to source 2, ..., use hardcoded default) appears in:
- `_moira_budget_get_agent_budget()` — 4-level fallback
- `_moira_budget_get_max_load()` — 3-level fallback
- `_moira_schema_dir()` — 3-level fallback (env var, MOIRA_HOME, script-relative)

Evidence: `/Users/minddecay/Documents/Projects/Moira/src/global/lib/budget.sh` (lines 38-69, 72-86)

### 4. Two-path architecture: global (read-only) vs project (read-write)

The entire system separates configuration into:
- `~/.claude/moira/` — global installation (core rules, pipelines, templates, skills). Read-only at runtime.
- `.claude/moira/` — project-local (state, config, knowledge). Read-write at runtime.

This is enforced structurally (guard.sh hook) and by convention in every shell lib and skill.

Evidence:
- `/Users/minddecay/Documents/Projects/Moira/src/global/skills/orchestrator.md` (Section 1, Path Resolution)
- `/Users/minddecay/Documents/Projects/Moira/src/global/hooks/guard.sh` — validates write paths

### 5. Markdown-as-code pattern

Orchestration logic, agent dispatch rules, command definitions, and skill behaviors are all defined as markdown files. These are not documentation — they are executable prompts interpreted by Claude Code.

Three categories observed:
- **Commands** (`src/commands/moira/*.md`): 14 files with YAML frontmatter specifying `allowed-tools`
- **Skills** (`src/global/skills/*.md`): 5 files defining orchestrator behaviors
- **Templates** (`src/global/templates/**/*.md`): 50+ files defining agent prompt templates for scanners, reflections, audits, and knowledge structures

### 6. Test pattern: bash structural verification

Tests run as pure bash scripts (zero Claude tokens), checking file existence, YAML structure, and cross-reference consistency:

```bash
# Pattern: run test files, aggregate pass/fail counts
for test_file in "$SCRIPT_DIR"/test-*.sh; do
  output=$(bash "$test_file" 2>&1)
  # Extract N/M passed, K failed from output
done
```

Evidence: `/Users/minddecay/Documents/Projects/Moira/src/tests/tier1/run-all.sh`

### 7. PostToolUse hook pattern

The guard hook follows a specific contract: read JSON from stdin, parse tool_name and file_path (jq with grep fallback), check against path rules, output `hookSpecificOutput` JSON for context injection on violations.

Evidence: `/Users/minddecay/Documents/Projects/Moira/src/global/hooks/guard.sh`
