# Phase 1: Foundation — File Structure & State Management

**Date:** 2026-03-11
**Status:** Complete
**Phase:** 1 of 12
**Goal:** Moira directory structure exists, state can be read/written/resumed, install.sh works.

---

## Approach

Schema-First (Approach A). YAML schemas are the single source of truth. All state management functions build around them. Validation is built-in from day one. Per D-029.

---

## 1. Source Structure

```
src/
├── global/                              # → ~/.claude/moira/
│   ├── core/
│   │   └── rules/
│   │       ├── roles/                   # placeholder dirs (Phase 2)
│   │       └── quality/                 # placeholder dirs (Phase 2)
│   ├── skills/                          # orchestrator.md (Phase 3)
│   ├── hooks/                           # guard.sh, budget-track.sh (Phase 8)
│   ├── templates/
│   │   └── scanners/                    # scanner templates (Phase 5) — stack-presets/ removed per D-060
│   └── lib/
│       ├── state.sh                     # state management utilities
│       ├── scaffold.sh                  # directory scaffold generator
│       ├── task-id.sh                   # task ID generation
│       └── yaml-utils.sh               # YAML read/write/validate (pure bash)
│
├── commands/moira/                      # → ~/.claude/commands/moira/
│   ├── init.md                          # stub (Phase 5)
│   ├── task.md                          # stub (Phase 3)
│   ├── status.md                        # stub (Phase 3)
│   ├── resume.md                        # stub (Phase 12)
│   ├── knowledge.md                     # stub (Phase 4)
│   ├── metrics.md                       # stub (Phase 11)
│   ├── audit.md                         # stub (Phase 11)
│   ├── bypass.md                        # stub (Phase 3)
│   ├── refresh.md                       # stub (Phase 5)
│   └── help.md                          # functional in Phase 1
│
├── schemas/                             # YAML schema definitions (dev/test only)
│   ├── config.schema.yaml
│   ├── current.schema.yaml
│   ├── status.schema.yaml
│   ├── manifest.schema.yaml
│   ├── queue.schema.yaml
│   └── locks.schema.yaml
│
├── tests/
│   └── tier1/
│       ├── run-all.sh                   # entry point
│       ├── test-file-structure.sh
│       ├── test-yaml-schemas.sh
│       └── test-install.sh
│
├── install.sh
└── .version                             # "0.1.0"
```

### Key Decisions

- **`src/global/lib/`**: Bash utilities for state management. No runtime dependencies beyond bash + git (D-020).
- **`src/schemas/`**: Separate directory. Not copied to Global Layer — used in dev/test only. Runtime validation is embedded in `state.sh`.
- **Command stubs**: Full correct frontmatter (name, description, allowed-tools), minimal body. install.sh works immediately; Phase 2-5 fill commands with real logic.
- **No jq dependency in core**: `yaml-utils.sh` uses pure bash parsing for simple YAML. jq is acceptable in hooks only (Phase 8).

---

## 2. YAML Schemas

All schemas follow blocker-resolution D-029 sections 2.1–2.5 exactly.

### Schema Format

Self-describing YAML (not JSON Schema — minimalism per D-020):

```yaml
_meta:
  name: <schema_name>
  file: <filename.yaml>
  location: <path relative to .moira/>
  git: committed|gitignored
  description: <purpose>

fields:
  <dot.path.key>:
    type: string|number|boolean|array|enum
    required: true|false
    enum: [values]          # for enum type
    pattern: '<regex>'      # for string validation
    default: <value>        # default when initializing
```

### Six Schemas

| Schema | File | Location | Git | Source |
|--------|------|----------|-----|--------|
| config | config.yaml | .moira/ (project root) | committed | blocker-resolution 2.1 (note: blocker-resolution comment says config/config.yaml — that is an error; overview.md and distribution.md both place it at project root) |
| current | current.yaml | .moira/state/ | gitignored | blocker-resolution 2.2 |
| status | status.yaml | .moira/state/tasks/{id}/ | gitignored | blocker-resolution 2.3 |
| manifest | manifest.yaml | .moira/state/tasks/{id}/ | gitignored | blocker-resolution 2.4 |
| queue | queue.yaml | .moira/state/ | gitignored | blocker-resolution 2.5 |
| locks | locks.yaml | .moira/config/ | committed | Defect 6 (D-033) |

All field definitions taken 1:1 from blocker-resolution.

---

## 3. State Management API

`src/global/lib/` contains four bash libraries:

### yaml-utils.sh

```bash
# Read value from YAML by dot-path
moira_yaml_get <file> <key>
# Example: moira_yaml_get "config.yaml" "project.stack" → "nextjs"

# Write value to YAML
moira_yaml_set <file> <key> <value>
# Example: moira_yaml_set "current.yaml" "step" "review"

# Validate YAML file against schema
moira_yaml_validate <file> <schema_name>
# Exit 0 (ok) or exit 1 + stderr with errors

# Initialize YAML from schema defaults
moira_yaml_init <schema_name> <target_path>
```

**YAML parsing boundaries:**

Dot-path access (`moira_yaml_get`/`moira_yaml_set`) supports:
- Scalars at any depth up to 3 levels: `project.stack`, `budgets.per_agent.classifier`
- Simple arrays read as comma-separated string: `pipelines.quick.gates` → "classification,final"

Whole-block operations (read/write as raw text) for:
- Arrays of objects: `history[]` in current.yaml, `gates[]` in status.yaml, `tasks[]` in queue.yaml
- Multi-line strings: `resume_context` in manifest.yaml

Not supported by dot-path (use block operations):
- Nested array element access: `history[0].status`
- Object-in-array field access: `tasks[2].depends_on`

Covered by grep/sed/awk without a full YAML parser. Test cases must cover the deepest supported dot-paths (`budgets.per_agent.classifier`, `pipelines.standard.gates`) to validate boundary.

### state.sh

Higher-level state operations built on yaml-utils:

```bash
# Get current pipeline state
moira_state_current

# Update pipeline step
moira_state_transition <new_step> <new_status>

# Record gate decision
moira_state_gate <gate_name> <decision> [note]

# Record agent execution in history
moira_state_agent_done <step_name> <status> <duration_sec> <tokens_used> <result_summary>
```

### task-id.sh

```bash
# Generate unique task ID
# Format: task-{YYYY-MM-DD}-{NNN}
# NNN: auto-increment based on existing dirs in state/tasks/ for current date
# Note: blocker-resolution examples use short form (task-042) — those are
# illustrative, not normative. Date-based format provides sortability and
# cross-day uniqueness. Schema examples will be updated.
moira_task_id
```

### scaffold.sh

```bash
# Create global layer directory structure
# Called by install.sh
moira_scaffold_global <target_dir>

# Create project layer directory structure
# Fully implemented in Phase 1, called by /moira:init in Phase 5
# Creates the complete directory tree from overview.md (lines 131-222):
#   .moira/{config.yaml, core/, project/rules/, config/, knowledge/, state/, hooks/}
# Does NOT populate files (that's Phase 5 bootstrap logic)
moira_scaffold_project <project_root>
```

Both functions are idempotent — re-run does not destroy existing files (Art 4.3).

---

## 4. install.sh

Follows `design/architecture/distribution.md` with Phase 1 adjustments.

### Steps

1. **check_prerequisites** — claude CLI + git + bash
2. **install_global** — copy `src/global/` → `~/.claude/moira/`
3. **install_lib** — copy lib/ utilities
4. **install_commands** — copy `src/commands/moira/` → `~/.claude/commands/moira/`
5. **verify** — Phase 1-specific checks (see below)

### Phase 1 Differences from distribution.md

- **No fetch_source**: works from local clone only. curl install mechanism added later with GitHub repo.
- **No merge_hooks**: hooks are Phase 8. Creates hook directories but does not touch `settings.json`.
- **Idempotent**: re-run overwrites core files (update), preserves project-layer files. `--force` flag for full overwrite.

### Phase 1 Verification Checks

The verify step checks only files that exist after Phase 1 installation (NOT the distribution.md checks which reference Phase 2-8 files):

1. `~/.claude/moira/.version` exists and contains valid semver
2. `~/.claude/moira/lib/state.sh` exists and is sourceable
3. `~/.claude/moira/lib/yaml-utils.sh` exists and is sourceable
4. `~/.claude/moira/lib/scaffold.sh` exists and is sourceable
5. `~/.claude/moira/lib/task-id.sh` exists and is sourceable
6. `~/.claude/commands/moira/` contains all 10 command stubs
7. Each command stub has valid YAML front matter with `name` and `allowed-tools`

### Command Stubs

10 command files with correct YAML frontmatter:

| File | Command | allowed-tools | Functional in |
|------|---------|--------------|---------------|
| task.md | /moira:task | Agent, Read, Write, TaskCreate/Update/List | Phase 3 |
| init.md | /moira:init | Agent, Read, Write, Bash | Phase 5 |
| status.md | /moira:status | Read | Phase 3 |
| resume.md | /moira:resume | Agent, Read, Write | Phase 12 |
| knowledge.md | /moira:knowledge | Read, Agent | Phase 4 |
| metrics.md | /moira:metrics | Read | Phase 11 |
| audit.md | /moira:audit | Agent, Read | Phase 11 |
| bypass.md | /moira:bypass | Agent, Read, Write | Phase 3 |
| refresh.md | /moira:refresh | Agent, Read, Write | Phase 5 |
| help.md | /moira:help | Read | Phase 1 |

**Constitution compliance:**
- Art 2.2: `allowed-tools` in frontmatter enforces gate structure
- Art 4.2: No auto-proceed logic in stubs
- D-031: First layer of three-layer guard (allowed-tools) established in Phase 1

---

## 5. Tier 1 Structural Verification

Bash scripts, 0 Claude tokens, deterministic.

### Entry Point

`tests/tier1/run-all.sh` — runs all `test-*.sh` files, aggregates results:

```
Moira Tier 1 — Structural Verifier
═══════════════════════════════════
[PASS] File structure: global layer
[PASS] File structure: commands
[PASS] YAML schema: config.yaml defaults valid
...
═══════════════════════════════════
10/10 passed, 0 failed
```

### Test Files

**test-file-structure.sh:**
- All expected directories exist in `~/.claude/moira/`
- All command stubs exist in `~/.claude/commands/moira/`
- `.version` contains valid version
- Command stubs contain correct YAML frontmatter (name, allowed-tools)
- No unexpected files outside expected structure

**test-yaml-schemas.sh:**
- `moira_yaml_init` creates valid YAML for each schema
- `moira_yaml_validate` passes on default files
- `moira_yaml_validate` fails on intentionally broken files (missing required field, invalid enum)
- `moira_yaml_get` / `moira_yaml_set` read/write correctly

**test-install.sh:**
- Clean install to temp directory (overriding `$HOME`)
- Verify passes
- Re-install (idempotency) — verify passes, existing files preserved
- `--force` reinstall works

### What Is NOT Tested in Phase 1

- Art 1.1 (orchestrator purity) — no orchestrator skill yet
- Art 1.2 (agent NEVER constraints) — no agent definitions yet
- Art 2.1-2.2 (pipeline determinism, gates) — no pipeline engine yet
- Art 3.1-3.3 (transparency) — no pipeline execution yet

These checks are added incrementally in Phase 2-3 as new `test-*.sh` files in the same `tier1/` directory.

---

## 6. What Phase 1 Does NOT Include

- Agent definitions (Phase 2)
- Orchestrator skill / pipeline engine (Phase 3)
- Rules assembly / knowledge system (Phase 4)
- Bootstrap scanners / /moira:init logic (Phase 5)
- Quality gates (Phase 6)
- Budget tracking (Phase 7)
- Hooks — guard.sh, budget-track.sh (Phase 8)
- Stack presets / templates content (Phase 5)
- settings.json hook registration (Phase 8)

---

## 7. Success Criteria

Phase 1 is complete when:

- [x] `install.sh` runs cleanly on a fresh machine (with Claude Code + git)
- [x] `~/.claude/moira/` has correct directory structure with .version file
- [x] `~/.claude/commands/moira/` has all 10 command stubs with valid frontmatter
- [x] All 6 YAML schemas are defined and `moira_yaml_validate` works for each
- [x] `moira_yaml_init` + `moira_yaml_get` + `moira_yaml_set` work correctly
- [x] `moira_task_id` generates unique, sortable task IDs
- [x] `moira_scaffold_global` and `moira_scaffold_project` create correct structures
- [x] `install.sh` is idempotent (re-run preserves state)
- [x] `tests/tier1/run-all.sh` passes all checks (98/98)
- [x] `/moira:help` shows version and available commands

---

## 8. Design Document Updates Required (D-018)

Before implementation begins, these design docs must be updated:

| Document | Change | Reason |
|----------|--------|--------|
| `architecture/overview.md` | Add `lib/` to global layer file tree | Issue 6: new directory not in architecture docs |
| `architecture/distribution.md` | Add `lib/` to global layer file tree | Issue 6: same |
| `IMPLEMENTATION-ROADMAP.md` | Remove "merges hooks into settings.json" from Phase 1 deliverables | Issue 5: hooks are Phase 8 |
| `decisions/2026-03-11-blocker-resolution-design.md` | Fix config.yaml comment path (config/config.yaml → config.yaml) | Issue 1: location mismatch |
| `architecture/commands.md` | Rename `/moira continue` to `/moira resume` | Issue 2: consistency with file name resume.md |

**Deferred to Phase 2 planning:**
- Issue 4: Quality file naming conflict between overview.md (correctness/performance/security/standards) and blocker-resolution (q1-q5). Must be resolved before Phase 2 begins.

---

## Constitutional Compliance

```
ARTICLE 1: Separation of Concerns
Art 1.1 — N/A (no orchestrator skill yet; allowed-tools in stubs prepared)
Art 1.2 — N/A (no agent definitions yet)
Art 1.3 — OK (each lib/ file has single responsibility)

ARTICLE 2: Determinism
Art 2.1 — N/A (no pipeline selection yet)
Art 2.2 — Prepared (allowed-tools in command frontmatter define gate tools)
Art 2.3 — N/A (no agent rules yet)

ARTICLE 3: Transparency
Art 3.1 — Prepared (state file structure ready)
Art 3.2 — N/A (no budget tracking yet)
Art 3.3 — N/A (no pipeline execution yet)

ARTICLE 4: Safety
Art 4.1 — N/A (no agents yet)
Art 4.2 — OK (no auto-proceed in stubs)
Art 4.3 — OK (scaffold is idempotent, install.sh is re-runnable)
Art 4.4 — Prepared (bypass.md stub has correct allowed-tools)

ARTICLE 5: Knowledge Integrity
Art 5.1-5.3 — N/A (no knowledge system yet)

ARTICLE 6: Self-Protection
Art 6.1 — OK (no code path touches CONSTITUTION.md)
Art 6.2 — OK (this spec written before implementation)
Art 6.3 — Prepared (Tier 1 verifier framework ready)
```
