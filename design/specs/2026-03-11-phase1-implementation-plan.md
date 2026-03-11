# Phase 1: Foundation — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Moira directory structure exists, state can be read/written/resumed, install.sh works.

**Architecture:** Pure bash + YAML. No runtime dependencies beyond bash 4+, git, grep, sed, awk. Schema-first approach — schemas define contracts, all state management validates against them.

**Spec:** `design/specs/2026-03-11-phase1-foundation-design.md`

**Key design docs to read before implementation:**
- `design/CONSTITUTION.md` — inviolable invariants
- `design/architecture/overview.md` — file structure (lines 79-222)
- `design/decisions/2026-03-11-blocker-resolution-design.md` — YAML schemas (sections 2.1-2.5)

---

## Chunk 0: Design Document Updates (D-018 prerequisite)

Before any implementation, update design docs per spec Section 8.

### Task 0.1: Update architecture docs with lib/ directory

**Files:**
- Modify: `design/architecture/overview.md` — add `lib/` to global layer file tree (after `templates/`)
- Modify: `design/architecture/distribution.md` — add `lib/` to global layer file tree

Add these entries to the global layer tree:
```
│   └── lib/
│       ├── state.sh
│       ├── scaffold.sh
│       ├── task-id.sh
│       └── yaml-utils.sh
```

- [ ] Update overview.md global layer tree
- [ ] Update distribution.md global layer tree
- [ ] Commit: `moira(design): add lib/ directory to global layer architecture`

### Task 0.2: Fix roadmap and blocker-resolution

**Files:**
- Modify: `design/IMPLEMENTATION-ROADMAP.md` — Phase 1 deliverables: remove "merges hooks into settings.json"
- Modify: `design/decisions/2026-03-11-blocker-resolution-design.md` — fix config.yaml comment path from `config/config.yaml` to `config.yaml`

- [ ] Fix roadmap Phase 1 deliverables
- [ ] Fix blocker-resolution config.yaml path comment
- [ ] Commit: `moira(design): fix roadmap hooks scope and config.yaml path`

### Task 0.3: Fix commands.md naming

**Files:**
- Modify: `design/architecture/commands.md` — rename `/moira continue` to `/moira resume` (heading + description)

- [ ] Rename continue → resume in commands.md
- [ ] Commit: `moira(design): rename /moira continue to /moira resume`

---

## Chunk 1: Version File and YAML Schemas

### Task 1.1: Create .version and project scaffolding

**Files:**
- Create: `src/.version` — contains `0.1.0`
- Ensure dirs exist: `src/global/lib/`, `src/global/core/rules/roles/`, `src/global/core/rules/quality/`, `src/global/skills/`, `src/global/hooks/`, `src/global/templates/stack-presets/`, `src/schemas/`, `src/tests/tier1/`, `src/commands/moira/`

- [ ] Create .version with "0.1.0"
- [ ] Create all directories (empty placeholder dirs get .gitkeep)
- [ ] Commit: `moira(foundation): create src directory scaffold and .version`

### Task 1.2: Write config.schema.yaml

**File:** `src/schemas/config.schema.yaml`

**Source:** blocker-resolution section 2.1. All fields from the config.yaml example become schema fields.

Schema must define:
- `_meta`: name=config, file=config.yaml, location=.claude/moira/, git=committed
- All top-level sections: version, project (name/root/stack), classification, pipelines (4 types with max_retries + gates), budgets (orchestrator_max_percent, agent_max_load_percent, per_agent with all 10 agents), quality, knowledge, audit, mcp, hooks
- Types: string, number, boolean, array (for gates lists)
- Enums: stack presets, pipeline types, quality mode (conform/evolve), review severity, warning levels
- Defaults for all fields (so moira_yaml_init can generate a valid config)

- [ ] Write config.schema.yaml with all fields from blocker-resolution 2.1
- [ ] Commit: `moira(foundation): add config.yaml schema definition`

### Task 1.3: Write current.schema.yaml

**File:** `src/schemas/current.schema.yaml`

**Source:** blocker-resolution section 2.2.

Schema must define:
- `_meta`: name=current, file=current.yaml, location=.claude/moira/state/, git=gitignored
- Scalar fields: task_id, pipeline, started_at, developer, step, step_status, step_started_at, gate_pending, gate_options
- Block fields (marked type=block): history, context_budget, bypass
- Enums: step_status (pending/in_progress/awaiting_gate/completed/failed), pipeline types, warning_level (normal/warning/critical)
- Defaults: task_id=null, step=null, step_status=pending, bypass.active=false

- [ ] Write current.schema.yaml
- [ ] Commit: `moira(foundation): add current.yaml schema definition`

### Task 1.4: Write status.schema.yaml

**File:** `src/schemas/status.schema.yaml`

**Source:** blocker-resolution section 2.3.

Schema must define:
- `_meta`: name=status, file=status.yaml, location=.claude/moira/state/tasks/{id}/, git=gitignored
- Scalar fields: task_id, description, size, confidence, pipeline, developer, status, created_at, completed_at
- Nested scalars: classification.* (classifier_size, classifier_confidence, user_hint, overridden, reasoning)
- Block fields: artifacts, gates, retries, budget (with by_agent sub-map), completion
- Enums: size (small/medium/large/epic), confidence (high/low), status (pending/in_progress/completed/failed/aborted), completion.action (done/tweak/redo)

- [ ] Write status.schema.yaml
- [ ] Commit: `moira(foundation): add status.yaml schema definition`

### Task 1.5: Write manifest.schema.yaml

**File:** `src/schemas/manifest.schema.yaml`

**Source:** blocker-resolution section 2.4.

Schema must define:
- `_meta`: name=manifest, file=manifest.yaml, location=.claude/moira/state/tasks/{id}/, git=gitignored
- Scalar fields: task_id, pipeline, developer
- Nested scalars: checkpoint.step, checkpoint.batch, checkpoint.created_at, checkpoint.reason
- Block fields: resume_context (multiline string), decisions_made, files_modified, files_expected, dependencies, validation
- Enums: checkpoint.reason (context_limit/user_pause/error/session_end)

- [ ] Write manifest.schema.yaml
- [ ] Commit: `moira(foundation): add manifest.yaml schema definition`

### Task 1.6: Write queue.schema.yaml

**File:** `src/schemas/queue.schema.yaml`

**Source:** blocker-resolution section 2.5.

Schema must define:
- `_meta`: name=queue, file=queue.yaml, location=.claude/moira/state/, git=gitignored
- Scalar fields: epic_id, description, created_at, developer
- Block fields: tasks (array of objects with task_id/title/status/pipeline/depends_on/completed_at), progress (total/completed/in_progress/pending/failed)
- Enums: task status within tasks[] array

- [ ] Write queue.schema.yaml
- [ ] Commit: `moira(foundation): add queue.yaml schema definition`

### Task 1.7: Write locks.schema.yaml

**File:** `src/schemas/locks.schema.yaml`

**Source:** Defect 6 resolution (D-033). No example in blocker-resolution — design from D-033 description.

Schema must define:
- `_meta`: name=locks, file=locks.yaml, location=.claude/moira/config/, git=committed
- Block field: locks (array of objects with file_path, locked_by, locked_at, expires_at, task_id)
- expires_at field enables TTL-based stale lock detection

- [ ] Write locks.schema.yaml
- [ ] Commit: `moira(foundation): add locks.yaml schema definition`

---

## Chunk 2: Bash Libraries

### Task 2.1: Implement yaml-utils.sh

**File:** `src/global/lib/yaml-utils.sh`

This is the foundation — all other libraries depend on it.

**Functions to implement:**

`moira_yaml_get <file> <key>`:
- Parse dot-path key (e.g., `budgets.per_agent.classifier`)
- Navigate YAML indentation to find the value
- For scalar values: return the value (stripped of quotes)
- For simple arrays on one line (`[a, b, c]`): return comma-separated
- For keys not found: return empty string, exit 1
- Must handle: 1-level (`step`), 2-level (`project.stack`), 3-level (`budgets.per_agent.classifier`)

`moira_yaml_set <file> <key> <value>`:
- Find the key line using same dot-path navigation
- Replace the value portion (after `: `)
- If key doesn't exist: append at correct indentation level under parent
- Preserve file formatting (comments, blank lines, other keys)

`moira_yaml_validate <file> <schema_name>`:
- Load schema from `$MOIRA_HOME/schemas/<schema_name>.schema.yaml` (dev) or embedded (runtime)
- For each field marked required=true: check key exists in file
- For enum fields: check value is in allowed list
- For pattern fields: check value matches regex
- Output errors to stderr, exit 0 if valid, exit 1 if not
- Note: schemas dir location — in dev use `$SCRIPT_DIR/../../schemas/`, in installed use `$MOIRA_HOME/schemas/`

`moira_yaml_init <schema_name> <target_path>`:
- Read schema, generate YAML file with all default values
- Required fields without defaults: leave as empty/null with comment `# REQUIRED`
- Respect nesting — indent correctly for dot-path keys
- Result must pass `moira_yaml_validate`

**Implementation notes:**
- Use awk for the heavy lifting (indentation-aware parsing)
- Do NOT depend on jq or python
- Handle YAML comments (lines starting with #) — preserve but skip during parsing
- Handle quoted strings, null values, boolean values
- The schemas themselves are YAML — yaml-utils.sh needs to parse them too (bootstrap problem). Solution: keep schema parsing simple — schemas use only flat `fields:` with dot-path keys, no deep nesting

- [ ] Implement moira_yaml_get with 1/2/3 level dot-path support
- [ ] Implement moira_yaml_set with key creation and update
- [ ] Implement moira_yaml_validate against schema files
- [ ] Implement moira_yaml_init from schema defaults
- [ ] Test manually: create a sample YAML, verify get/set/validate work
- [ ] Commit: `moira(foundation): implement yaml-utils.sh YAML parser`

### Task 2.2: Implement scaffold.sh

**File:** `src/global/lib/scaffold.sh`

**Functions to implement:**

`moira_scaffold_global <target_dir>`:
- Creates the global layer directory tree at `<target_dir>`:
  ```
  <target_dir>/
  ├── core/rules/{roles/,quality/}
  ├── skills/
  ├── hooks/
  ├── templates/stack-presets/
  └── lib/
  ```
- Uses `mkdir -p` — idempotent by nature
- Does NOT create files (those are copied by install.sh)

`moira_scaffold_project <project_root>`:
- Creates the project layer directory tree at `<project_root>/.claude/moira/`:
  ```
  .claude/moira/
  ├── core/rules/{roles/,quality/}
  ├── project/rules/
  ├── config/
  ├── knowledge/{project-model/,conventions/,decisions/,decisions/archive/,patterns/,failures/,quality-map/}
  ├── state/{tasks/,metrics/,audits/}
  └── hooks/
  ```
- Source: overview.md project layer tree (lines 131-222)
- Uses `mkdir -p` — idempotent
- Does NOT create files (that's Phase 5 /moira:init)
- Checks `<project_root>` exists before proceeding

- [ ] Implement moira_scaffold_global
- [ ] Implement moira_scaffold_project with full directory tree from overview.md
- [ ] Verify idempotency: run twice, second run should be no-op
- [ ] Commit: `moira(foundation): implement scaffold.sh directory generators`

### Task 2.3: Implement task-id.sh

**File:** `src/global/lib/task-id.sh`

**Function to implement:**

`moira_task_id [state_dir]`:
- Format: `task-YYYY-MM-DD-NNN` where NNN is zero-padded 3-digit counter
- Scans `<state_dir>/tasks/` for existing `task-YYYY-MM-DD-*` directories matching today's date
- Finds highest NNN, increments by 1
- If no tasks today: starts at 001
- `state_dir` defaults to `.claude/moira/state` (current project)
- Outputs the new task ID to stdout

Edge cases:
- state/tasks/ doesn't exist yet → return task-{today}-001
- 999 tasks in one day → error (unlikely but handle gracefully)

- [ ] Implement moira_task_id with auto-increment
- [ ] Test: generate 3 IDs, verify sequential
- [ ] Commit: `moira(foundation): implement task-id.sh ID generator`

### Task 2.4: Implement state.sh

**File:** `src/global/lib/state.sh`

Sources yaml-utils.sh. Provides higher-level state operations.

**Functions to implement:**

`moira_state_current [state_dir]`:
- Reads `state/current.yaml`
- Outputs key fields: task_id, pipeline, step, step_status
- If no current.yaml or task_id is null → outputs "idle"

`moira_state_transition <new_step> <new_status> [state_dir]`:
- Updates `step` and `step_status` in current.yaml via moira_yaml_set
- Updates `step_started_at` to current timestamp
- If step changes (not just status): validates new_step is a known pipeline step

`moira_state_gate <gate_name> <decision> [note] [state_dir]`:
- Appends gate record to status.yaml gates block
- Sets gate_pending=null in current.yaml
- decision must be: proceed, modify, abort

`moira_state_agent_done <step_name> <status> <duration_sec> <tokens_used> <result_summary> [state_dir]`:
- Appends history record to current.yaml history block
- Updates context_budget.total_agent_tokens

Note: block-append operations (history, gates) use file append with proper YAML formatting rather than moira_yaml_set (which handles scalar dot-paths only).

- [ ] Implement moira_state_current
- [ ] Implement moira_state_transition
- [ ] Implement moira_state_gate
- [ ] Implement moira_state_agent_done
- [ ] Commit: `moira(foundation): implement state.sh state management`

---

## Chunk 3: Command Stubs and install.sh

### Task 3.1: Create all 10 command stubs

**Files:** `src/commands/moira/{task,init,status,resume,knowledge,metrics,audit,bypass,refresh,help}.md`

Each stub follows the same pattern:
```yaml
---
name: moira:<command>
description: <from spec table>
allowed-tools:
  - <from spec table>
---

# Moira — <Command Name>

> This command will be implemented in Phase N.

Current Moira version: see ~/.claude/moira/.version
```

**help.md is the exception** — it should be functional:
- Read and display .version
- List all available /moira:* commands with descriptions
- Show link to design docs for more info
- Use only the `Read` tool (as specified in allowed-tools)

Exact allowed-tools per command — from spec Section 4 table.

- [ ] Create task.md stub
- [ ] Create init.md stub
- [ ] Create status.md stub
- [ ] Create resume.md stub
- [ ] Create knowledge.md stub
- [ ] Create metrics.md stub
- [ ] Create audit.md stub
- [ ] Create bypass.md stub
- [ ] Create refresh.md stub
- [ ] Create help.md (functional — shows version + command list)
- [ ] Commit: `moira(foundation): add all command stubs with frontmatter`

### Task 3.2: Implement install.sh

**File:** `src/install.sh`

**Steps (5 functions + main flow):**

`check_prerequisites`:
- Verify `claude` CLI exists (`command -v claude`)
- Verify `git` exists
- Verify bash version >= 4 (`${BASH_VERSION}`)
- On failure: print clear error message with install instructions, exit 1

`install_global`:
- Read version from `$SCRIPT_DIR/.version`
- Call `moira_scaffold_global "$MOIRA_HOME"` (source scaffold.sh from src)
- Copy `$SCRIPT_DIR/global/lib/*` → `$MOIRA_HOME/lib/`
- Copy placeholder dirs (core/rules/roles/, quality/, skills/, hooks/, templates/)
- Write version to `$MOIRA_HOME/.version`

`install_commands`:
- `mkdir -p "$HOME/.claude/commands/moira"`
- Copy `$SCRIPT_DIR/commands/moira/*` → `$HOME/.claude/commands/moira/`

`install_schemas`:
- `mkdir -p "$MOIRA_HOME/schemas"`
- Copy `$SCRIPT_DIR/schemas/*` → `$MOIRA_HOME/schemas/`
- (schemas needed by yaml-utils.sh validate function at runtime)

`verify`:
- Check .version exists and matches expected
- Check all 4 lib files exist and are sourceable (`bash -n`)
- Check all 10 command stubs exist
- Check each stub has `name:` and `allowed-tools:` in frontmatter
- Report: N/N checks passed

**Main flow:**
```bash
MOIRA_HOME="$HOME/.claude/moira"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse --force flag
check_prerequisites
install_global
install_commands
install_schemas
verify

echo "Moira v$(cat "$MOIRA_HOME/.version") installed"
echo "Next: cd <project> && claude && /moira:init"
```

**Idempotency:** `install_global` uses `cp -f` (overwrite). Directories created with `mkdir -p`. Re-run is safe.

**--force flag:** Same as normal install (since we overwrite anyway). Reserved for future use when project-layer preservation matters.

- [ ] Implement check_prerequisites
- [ ] Implement install_global (scaffold + copy)
- [ ] Implement install_commands
- [ ] Implement install_schemas
- [ ] Implement verify with Phase 1-specific checks
- [ ] Implement main flow with banner and output
- [ ] Test: run install.sh, verify directory structure
- [ ] Test: run install.sh again (idempotency)
- [ ] Commit: `moira(foundation): implement install.sh installer`

---

## Chunk 4: Tier 1 Tests

### Task 4.1: Implement test helpers and runner

**File:** `src/tests/tier1/run-all.sh`

Runner logic:
- Find all `test-*.sh` in same directory
- Run each, capture exit code
- Aggregate: N passed, M failed
- Print formatted output with banner
- Exit 0 if all pass, 1 if any fail

Helper functions (shared via source):
```bash
pass() { echo "[PASS] $1"; ((PASSES++)); }
fail() { echo "[FAIL] $1"; ((FAILURES++)); }
assert_dir_exists() { [ -d "$1" ] && pass "$2" || fail "$2: $1 not found"; }
assert_file_exists() { [ -f "$1" ] && pass "$2" || fail "$2: $1 not found"; }
assert_file_contains() { grep -q "$2" "$1" && pass "$3" || fail "$3"; }
```

- [ ] Implement run-all.sh with test discovery and aggregation
- [ ] Implement helper functions (pass/fail/assert_*)
- [ ] Commit: `moira(foundation): add Tier 1 test runner`

### Task 4.2: Implement test-file-structure.sh

**File:** `src/tests/tier1/test-file-structure.sh`

Tests (run against installed Moira at $MOIRA_HOME):
- .version file exists and contains semver pattern (X.Y.Z)
- lib/ directory exists with all 4 .sh files
- Each lib .sh file passes bash syntax check (`bash -n`)
- core/rules/roles/ directory exists
- core/rules/quality/ directory exists
- skills/ directory exists
- hooks/ directory exists
- templates/stack-presets/ directory exists
- All 10 command stubs exist in ~/.claude/commands/moira/
- Each command stub contains `name: moira:` in frontmatter
- Each command stub contains `allowed-tools:` in frontmatter

- [ ] Implement all file structure assertions
- [ ] Run and verify all pass after install
- [ ] Commit: `moira(foundation): add file structure tests`

### Task 4.3: Implement test-yaml-schemas.sh

**File:** `src/tests/tier1/test-yaml-schemas.sh`

Tests (source yaml-utils.sh, run against schemas):
- For each of 6 schemas: moira_yaml_init creates a file that passes moira_yaml_validate
- moira_yaml_get on initialized config.yaml returns correct defaults (test 2-3 fields)
- moira_yaml_get on 3-level dot-path works: `budgets.per_agent.classifier` → `20000`
- moira_yaml_set changes a value, moira_yaml_get reads back the new value
- moira_yaml_validate rejects file with missing required field (remove `version:` from config)
- moira_yaml_validate rejects file with invalid enum (set `quality.mode: invalid`)
- Array field read: `pipelines.quick.gates` returns expected values

- [ ] Implement schema init/validate round-trip tests
- [ ] Implement get/set tests including 3-level dot-path
- [ ] Implement negative validation tests
- [ ] Run and verify
- [ ] Commit: `moira(foundation): add YAML schema validation tests`

### Task 4.4: Implement test-install.sh

**File:** `src/tests/tier1/test-install.sh`

Tests (uses temp $HOME to avoid polluting real home):
- Create temp dir, set HOME to it
- Run install.sh
- Verify: .version, lib files, commands all exist
- Run install.sh again (idempotency): everything still exists, no errors
- Modify a lib file in installed location, run install.sh: file gets overwritten (update)
- Verify scaffold functions: source scaffold.sh, call moira_scaffold_project on temp dir, check directory tree

- [ ] Implement clean install test with temp HOME
- [ ] Implement idempotency test
- [ ] Implement overwrite/update test
- [ ] Implement scaffold_project test
- [ ] Run and verify
- [ ] Commit: `moira(foundation): add install.sh integration tests`

---

## Chunk 5: Final Verification

### Task 5.1: Run full Tier 1 suite

- [ ] Run `src/tests/tier1/run-all.sh`
- [ ] All tests pass
- [ ] Fix any failures

### Task 5.2: Verify success criteria

Walk through spec Section 7 checklist:
- [ ] install.sh runs cleanly
- [ ] ~/.claude/moira/ has correct structure with .version
- [ ] ~/.claude/commands/moira/ has all 10 stubs with valid frontmatter
- [ ] All 6 schemas defined and moira_yaml_validate works
- [ ] moira_yaml_init + moira_yaml_get + moira_yaml_set work
- [ ] moira_task_id generates unique sortable IDs
- [ ] moira_scaffold_global and moira_scaffold_project create correct structures
- [ ] install.sh is idempotent
- [ ] tests/tier1/run-all.sh passes
- [ ] /moira:help shows version and commands

### Task 5.3: Constitutional compliance spot-check

- [ ] Art 1.3: each lib/ file has single responsibility — verify
- [ ] Art 4.2: no auto-proceed in any command stub — grep for auto/proceed
- [ ] Art 4.3: scaffold idempotent — tested
- [ ] Art 6.1: no code path touches CONSTITUTION.md — grep all .sh files
- [ ] Art 6.2: spec written before implementation — confirmed

### Task 5.4: Final commit

- [ ] Commit: `moira(foundation): complete Phase 1 — file structure and state management`

---

## Dependency Graph

```
Chunk 0 (design doc updates)
    ↓
Chunk 1 (schemas)
    ↓
Chunk 2 (bash libraries)
  Task 2.1 yaml-utils.sh ←── foundation, no deps
  Task 2.2 scaffold.sh   ←── no deps (mkdir only)
  Task 2.3 task-id.sh    ←── no deps
  Task 2.4 state.sh      ←── depends on yaml-utils.sh
    ↓
Chunk 3 (commands + install)
  Task 3.1 command stubs  ←── no deps
  Task 3.2 install.sh     ←── depends on scaffold.sh, all libs exist
    ↓
Chunk 4 (tests)           ←── depends on everything above
    ↓
Chunk 5 (verification)    ←── depends on tests passing
```

Tasks within a chunk can be parallelized where no dependency exists (e.g., all 6 schemas in Chunk 1, scaffold.sh + task-id.sh in Chunk 2).
