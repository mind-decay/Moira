# Phase 5: Bootstrap Engine (/moira:init)

## Goal

`/moira:init` fully works — scans any project, generates project-specific config and rules, populates the knowledge base, integrates with `.claude/CLAUDE.md`, and offers micro-onboarding. This is the first phase where Moira becomes usable by engineers.

Phase 5 connects everything built in Phases 1-4: the scaffold (Phase 1), agent definitions (Phase 2), pipeline engine (Phase 3), and rules/knowledge system (Phase 4) into a single coherent initialization flow.

## Risk Classification

**ORANGE** — New command implementation, project rules generation, CLAUDE.md integration, stack presets. Needs design doc update first for any deviations.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | Art 1.1 (orchestrator purity — init dispatches agents, doesn't scan itself), Art 2.3 (no implicit decisions — all scan results shown to user), Art 4.2 (user authority — user reviews config before accepting), Art 5.1 (evidence-based knowledge) |
| `design/architecture/distribution.md` | `/moira init` flow (lines 276-393), `.claude/` compatibility rules, what gets committed |
| `design/architecture/onboarding.md` | Micro-onboarding flow (3 minutes, interactive, skippable) |
| `design/architecture/overview.md` | Project layer file structure, data flow |
| `design/architecture/agents.md` | Explorer role, Agent Response Contract, Spawning Strategy |
| `design/architecture/rules.md` | Layer 3 project rules structure (stack.yaml, conventions.yaml, patterns.yaml, boundaries.yaml) |
| `design/architecture/commands.md` | `/moira init` command spec, progressive disclosure |
| `design/subsystems/knowledge.md` | Bootstrapping hybrid approach (Phase 0 quick scan + Phase 1 deep scan), L0/L1/L2 population |
| `design/IMPLEMENTATION-GUIDE.md` | Bootstrap scanning strategy (config files first, sample don't scan all, preliminary quality map) |
| `design/decisions/log.md` | D-007 (hybrid bootstrapping), D-020 (file-copy distribution), D-022 (config via git, state via gitignore), D-030 (native commands), D-032 (scanners = Explorer invocations with L4 instructions), D-043 (knowledge templates as installed files) |
| `design/decisions/2026-03-11-blocker-resolution-design.md` | Blocker 5: scanner instructions, dispatch strategy, budget |

## Prerequisites (from Phase 1-4)

- **Phase 1:** `scaffold.sh` (creates project directory structure), `yaml-utils.sh`, `state.sh`, `task-id.sh`, `install.sh`, all YAML schemas
- **Phase 2:** All 10 agent role definitions (especially `hermes.yaml` — Explorer), `base.yaml`, `response-contract.yaml`, `knowledge-access-matrix.yaml`
- **Phase 3:** Orchestrator skill, dispatch module, pipeline definitions, gate system, error handling
- **Phase 4:** `knowledge.sh` (read/write/freshness), `rules.sh` (assembly), knowledge templates (17 files), dispatch instruction file support

## Deliverables

### D1: Scanner Instruction Templates (`src/global/templates/scanners/`)

Four Layer 4 instruction templates for Explorer (Hermes) invocations during bootstrap. Each template defines WHAT facts the Explorer should collect and WHERE to write them. Per D-032, these are NOT new agents — they are task-specific instructions for the Explorer.

**Files:**
- `tech-scan.md` — Technical stack discovery
- `structure-scan.md` — Project structure mapping
- `convention-scan.md` — Coding convention detection
- `pattern-scan.md` — Recurring pattern identification

Each template follows this structure:

```markdown
# Scanner: {name}
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective
{what facts to collect — specific, enumerated}

## Scan Strategy
{what files to read, in what order, with explicit limits}

## Output Format
{exact structure of the artifact file}

## Output Path
{where to write: .claude/moira/knowledge/{type}/full.md}

## Constraints
- Report ONLY observed facts with file path evidence
- NO opinions, NO recommendations, NO proposals
- If a category has no data, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
```

#### Tech Scanner (`tech-scan.md`)

Objective: Identify languages, frameworks, build tools, test frameworks, linting/formatting config, database/ORM, deployment config, package managers.

Scan strategy:
1. Read root config files: `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`
2. Read tool configs: `tsconfig.json`, `.eslintrc*`, `.prettierrc*`, `jest.config*`, `vitest.config*`, `.babelrc*`, `webpack.config*`, `vite.config*`, `next.config*`, `nuxt.config*`
3. Read CI/CD: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `Dockerfile`, `docker-compose*`
4. Read env: `.env.example`, `.env.sample` (NEVER `.env` — may contain secrets)
5. Read lock files (existence only, not content): `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Pipfile.lock`, `poetry.lock`, `go.sum`

Output format:
```markdown
## Language & Runtime
- Primary: {language} {version}
- Secondary: {if any}

## Framework
- Name: {framework} {version}
- Type: {web/api/cli/library/monorepo}

## Build & Tooling
- Package manager: {npm/yarn/pnpm/pip/cargo/go}
- Build tool: {vite/webpack/turbopack/esbuild/tsc/none}
- Bundler config: {path or "default"}

## Testing
- Framework: {jest/vitest/pytest/go test/...}
- Config: {path}
- Test directory pattern: {co-located/__tests__/test/...}

## Linting & Formatting
- Linter: {eslint/pylint/golangci-lint/...} with config at {path}
- Formatter: {prettier/black/gofmt/...} with config at {path}
- Type checking: {typescript/mypy/none}

## Database & ORM
- Database: {postgres/mysql/sqlite/mongodb/none}
- ORM/Query: {prisma/drizzle/sqlalchemy/gorm/none}
- Migration tool: {prisma migrate/alembic/goose/none}

## CI/CD
- Platform: {github actions/gitlab ci/jenkins/none}
- Config: {path}

## Deployment
- Container: {docker/none}
- Platform: {vercel/aws/gcp/self-hosted/unknown}
```

#### Structure Scanner (`structure-scan.md`)

Objective: Map directory layout, entry points, source vs generated vs vendored separation, config locations, test organization.

Scan strategy:
1. List top-level directories and files (depth 1)
2. For each source directory: list depth 2
3. Identify entry points: `src/index.*`, `src/main.*`, `src/app.*`, `main.*`, `cmd/`
4. Identify generated directories: `dist/`, `build/`, `.next/`, `__pycache__/`, `node_modules/`
5. Identify vendored: `vendor/`, `third_party/`
6. Identify test roots
7. Count files per top-level directory (rough sizing)

Output format:
```markdown
## Project Root
{annotated top-level directory listing}

## Source Layout
- Pattern: {monorepo/single-app/library/multi-package}
- Source root: {src/app/lib/...}
- Entry points: {list with paths}

## Directory Roles
| Directory | Role | Files (approx) |
|-----------|------|----------------|
| src/ | application source | ~150 |
| tests/ | test files | ~40 |
| ... | ... | ... |

## Generated (do not modify)
{list of directories}

## Vendored (do not modify)
{list of directories}

## Configuration
{list of config files at root with purpose}

## Test Organization
- Pattern: {co-located/separate/both}
- Test root(s): {paths}
- Naming: {*.test.ts/*.spec.ts/*_test.go/test_*.py}
```

#### Convention Scanner (`convention-scan.md`)

Objective: Detect naming patterns, import style, export patterns, error handling, logging, code organization from actual code samples.

Scan strategy:
1. Read linter/formatter configs for explicit rules
2. Sample 3-5 files from EACH of these categories (if they exist):
   - Components/views (UI files)
   - API routes/handlers
   - Services/business logic
   - Utilities/helpers
   - Type definitions
   - Test files
3. For each file: note naming, imports, exports, error handling pattern
4. Look for shared patterns across samples
5. NEVER read more than 30 files total

Output format:
```markdown
## Naming Conventions
| What | Convention | Evidence |
|------|-----------|----------|
| Files | {kebab-case/camelCase/PascalCase} | src/components/user-profile.tsx, ... |
| Functions | {camelCase/snake_case} | getUserById in src/services/user.ts:12 |
| Components | {PascalCase} | UserProfile in src/components/user-profile.tsx:5 |
| Constants | {UPPER_SNAKE/camelCase} | MAX_RETRIES in src/config/constants.ts:3 |
| Types/Interfaces | {PascalCase} | User in src/types/user.ts:1 |
| Test files | {*.test.ts/*.spec.ts} | src/services/__tests__/user.test.ts |

## Import Style
- Module imports: {named/default/mixed}
- Path aliases: {@ = src, ~ = root, none}
- Import order: {framework → external → internal → relative}
- Evidence: {file:line examples}

## Export Style
- Default exports: {used/not used}
- Re-export barrels: {index.ts files present/absent}
- Evidence: {file:line examples}

## Error Handling
- Pattern: {try-catch/error boundary/result type/middleware}
- Custom errors: {yes — path, no}
- Evidence: {file:line examples}

## Logging
- Library: {console/winston/pino/slog/none}
- Pattern: {structured/unstructured}
- Evidence: {file:line examples}

## Code Organization
- Function length: {typical range}
- File length: {typical range}
- Comments: {frequent/rare/JSDoc/none}
- Evidence: {representative files}
```

#### Pattern Scanner (`pattern-scan.md`)

Objective: Identify recurring code patterns, component structures, API patterns, data access patterns, state management, common abstractions.

Scan strategy:
1. Read 3-5 representative files per architectural layer:
   - UI components (if frontend)
   - API handlers/controllers
   - Data access / repository layer
   - Business logic / services
   - Middleware / interceptors
2. For each layer: identify the RECURRING structure (not unique one-offs)
3. Note abstractions: base classes, HOCs, hooks, decorators, middleware chains
4. Look for project-specific patterns (custom hooks, utility wrappers, etc.)
5. NEVER read more than 25 files total

Output format:
```markdown
## Component Pattern (if frontend)
- Structure: {functional/class/mixed}
- State: {hooks/stores/context/redux}
- Styling: {CSS modules/Tailwind/styled-components/...}
- Example: {path — representative file}

## API Pattern
- Style: {REST/GraphQL/RPC/tRPC}
- Handler structure: {controller→service→repo / route handler / serverless function}
- Request validation: {zod/joi/class-validator/manual/none}
- Response format: {envelope pattern/raw/standard}
- Example: {path — representative file}

## Data Access Pattern
- Pattern: {repository/active record/direct ORM/raw SQL}
- Transaction handling: {middleware/manual/none}
- Example: {path — representative file}

## State Management (if frontend)
- Client state: {zustand/redux/context/jotai/...}
- Server state: {react-query/swr/rtk-query/manual}
- Example: {path — representative file}

## Common Abstractions
| Abstraction | Location | Purpose |
|-------------|----------|---------|
| {e.g., useQuery hook} | {path} | {what it wraps} |
| ... | ... | ... |

## Recurring Structures
| Pattern | Frequency | Example |
|---------|-----------|---------|
| {e.g., "every service has constructor injection"} | {all/most/some} | {path:line} |
| ... | ... | ... |
```

### D2: Stack Presets (`src/global/templates/stack-presets/`)

Preset YAML files that provide default Layer 3 project rules for common stacks. The tech scanner identifies the stack, the init command finds the closest preset, then augments it with scanner findings.

Presets are starting points, not rigid templates (per IMPLEMENTATION-GUIDE.md). They will be overridden by actual scan results wherever the scan provides evidence.

**Files:**
- `generic.yaml` — Fallback for unknown/undetected stacks
- `nextjs.yaml` — Next.js (App Router or Pages)
- `react-vite.yaml` — React + Vite (SPA)
- `express.yaml` — Express.js API
- `fastapi.yaml` — Python FastAPI
- `go-api.yaml` — Go API

Each preset contains a skeleton `stack`, `conventions`, `patterns`, and `boundaries` section:

```yaml
_meta:
  name: {preset name}
  stack_id: {nextjs|react-vite|express|fastapi|go-api|generic}
  match_signals:  # how tech scanner identifies this preset
    - {signal: "next in package.json dependencies", weight: 10}
    - {signal: "next.config.* exists", weight: 5}

stack:
  language: {TypeScript|Python|Go|...}
  framework: {Next.js|React|Express|FastAPI|Go stdlib|...}
  runtime: {Node.js|Python|Go|...}
  styling: {Tailwind CSS|CSS Modules|none|...}
  orm: {Prisma|SQLAlchemy|GORM|none|...}
  testing: {Jest|Vitest|pytest|go test|...}
  ci: {GitHub Actions|...}

conventions:
  naming:
    files: {kebab-case|snake_case|...}
    components: {PascalCase|...}
    functions: {camelCase|snake_case|...}
    constants: {UPPER_SNAKE_CASE|...}
    types: {PascalCase|...}
  formatting:
    indent: {2 spaces|4 spaces|tabs}
    quotes: {single|double}
    semicolons: {true|false}
    max_line_length: {80|100|120}
  structure: {}  # populated by scan

patterns:
  data_fetching: {default pattern for this stack}
  validation: {default pattern}
  error_handling: {default pattern}
  # populated further by scan

boundaries:
  do_not_modify: []  # populated by scan
  modify_with_caution: []  # populated by scan
```

Additional presets (nestjs, django, vue-nuxt, rust) are listed in the design but deferred to future work. The 6 above cover the most common cases + the generic fallback.

### D3: Config Generator (`src/global/lib/bootstrap.sh`)

Shell library for bootstrap operations: preset matching, config generation, knowledge population, and CLAUDE.md integration.

**Functions:**

#### `moira_bootstrap_match_preset <tech_scan_path> <presets_dir>`
Match tech scan results to the closest stack preset.

- Reads tech scan artifact (markdown output from tech scanner)
- Extracts key signals: framework name, language, build tool
- Scores each preset using `_meta.match_signals` weights
- Returns: preset filename (e.g., `nextjs.yaml`) or `generic.yaml` if no match scores > 5
- Matching is keyword-based: check if scan text contains each signal string

#### `moira_bootstrap_generate_config <project_root> <preset_path> <tech_scan_path>`
Generate `config.yaml` from preset + scan results.

- Reads preset YAML
- Reads tech scan for project name (from package.json, go.mod, etc.) and stack details
- Fills `config.yaml` schema fields:
  - `version`: "1.0"
  - `project.name`: extracted from scan or dirname
  - `project.root`: `$project_root`
  - `project.stack`: preset's `stack_id`
  - Remaining fields: schema defaults from `config.schema.yaml`
- Writes to `.claude/moira/config.yaml`

#### `moira_bootstrap_generate_project_rules <project_root> <preset_path> <scan_results_dir>`
Generate Layer 3 project rules from preset + all scanner results.

- Reads preset for defaults
- Reads all 4 scan artifacts for evidence-based overrides
- Generates 4 files in `.claude/moira/project/rules/`:
  - `stack.yaml` — from tech scan + preset `stack` section
  - `conventions.yaml` — from convention scan + preset `conventions` section (scan wins on conflict)
  - `patterns.yaml` — from pattern scan + preset `patterns` section
  - `boundaries.yaml` — from structure scan (generated dirs → `do_not_modify`, config files → `modify_with_caution`)

#### `moira_bootstrap_populate_knowledge <project_root> <scan_results_dir>`
Populate knowledge templates with scan results.

- Reads all 4 scan artifacts
- Writes knowledge files at all 3 levels:
  - `project-model/full.md` — from structure scan (full output)
  - `project-model/summary.md` — condensed: project type, main dirs, entry points
  - `project-model/index.md` — section list only
  - `conventions/full.md` — from convention scan (full output)
  - `conventions/summary.md` — condensed: key naming/formatting/structure rules
  - `conventions/index.md` — category list only
  - `patterns/full.md` — from pattern scan (full output)
  - `patterns/summary.md` — condensed: main patterns per layer
  - `patterns/index.md` — pattern names only
  - `quality-map/full.md` — preliminary, from pattern scan observations
  - `quality-map/summary.md` — preliminary assessment
- Adds freshness markers to each file: `<!-- moira:freshness init {date} -->`
- Marks quality-map as preliminary: `<!-- moira:preliminary — deep scan required -->`
- Leaves `decisions/`, `failures/` as templates (no data yet — these grow organically)

#### `moira_bootstrap_inject_claude_md <project_root> <moira_home>`
Integrate Moira section into project's `.claude/CLAUDE.md`.

- If `.claude/CLAUDE.md` exists:
  - Check for existing `<!-- moira:start -->` / `<!-- moira:end -->` markers
  - If markers exist: replace content between them (idempotent re-init)
  - If no markers: append Moira section at end of file
- If `.claude/CLAUDE.md` does not exist:
  - Create `.claude/` directory if needed
  - Create `CLAUDE.md` with Moira section only
- NEVER modify content outside moira markers
- NEVER delete existing content

Moira section content (from template):
```markdown
<!-- moira:start -->
## Moira Orchestration System

This project uses Moira for task orchestration. When working on tasks:

### For Task Execution
Use `/moira:task <description>` for all non-trivial changes. Moira will classify the task,
assemble the right agents, and guide you through approvals.

### Quick Reference
- `/moira:task <description>` — execute a task
- `/moira:status` — current state
- `/moira:resume` — continue interrupted work
- `/moira:knowledge` — view project knowledge
- `/moira:help` — detailed help

### Orchestrator Rules (Inviolable)
When executing as Moira orchestrator (via /moira:task):
- NEVER read, write, or modify project source files directly
- NEVER run bash commands on project files
- ALL project interaction happens through dispatched agents
- Read ONLY `.claude/moira/` state and config files
<!-- moira:end -->
```

#### `moira_bootstrap_setup_gitignore <project_root>`
Ensure Moira's gitignore entries are present.

- Check `.gitignore` for existing moira entries
- If not present, append:
  ```
  # Moira orchestration state (per-developer)
  .claude/moira/state/tasks/
  .claude/moira/state/bypass-log.yaml
  .claude/moira/state/current.yaml
  .claude/moira/state/init/
  ```
- Idempotent — check before appending
- Note: `state/init/` contains temporary scanner output from bootstrap, should not be committed

### D4: Init Command Implementation (`src/commands/moira/init.md`)

Replace the Phase 5 stub with the full `/moira:init` command. This is the main orchestration logic for bootstrap.

**Command frontmatter:**
```yaml
---
name: moira:init
description: Set up Moira for the current project
argument-hint: "[--force]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---
```

Note: `init.md` is one of the few commands that needs `Bash` (for running scaffold.sh, checking prerequisites, etc.) and `Write` (for creating config files). This is different from `task.md` which is the orchestrator and has restricted tools.

**Init flow (10 steps from distribution.md):**

#### Step 1: Check Global Layer
- Read `~/.claude/moira/.version`
- If not found: display error "Moira not installed. Run: curl ... | bash" and stop
- Store version for compatibility check

#### Step 2: Check Existing Init
- Check if `.claude/moira/config.yaml` exists
- If exists AND no `--force` flag: display "Already initialized. Use /moira:refresh to update, or /moira:init --force to reinitialize."
- If exists AND `--force`: continue (reinit mode — preserves knowledge)
- If not exists: continue (fresh init)

#### Step 3: Create Project Scaffold
- Run `moira_scaffold_project $PROJECT_ROOT` (from scaffold.sh)
- This creates all directories and copies knowledge templates

#### Step 4: Dispatch 4 Scanner Agents (Parallel)
- Read scanner instruction templates from `~/.claude/moira/templates/scanners/`
- Dispatch 4 Explorer (Hermes) agents in PARALLEL using Agent tool with `run_in_background: true`
- Each agent:
  - Gets the Explorer role identity + NEVER constraints (from hermes.yaml)
  - Gets base inviolable rules (from base.yaml)
  - Gets scanner-specific L4 instructions (from template)
  - Gets response contract
  - Writes detailed results to `.claude/moira/state/init/{scan_type}.md`
  - Returns status summary only

Wait for all 4 to complete.

Scan result storage: `.claude/moira/state/init/` (temporary, can be cleaned after init completes)

#### Step 5: Match Stack Preset
- Call `moira_bootstrap_match_preset` with tech scan results
- Log matched preset

#### Step 6: Generate Project Config and Rules
- Call `moira_bootstrap_generate_config`
- Call `moira_bootstrap_generate_project_rules`

#### Step 7: Populate Knowledge Base
- Call `moira_bootstrap_populate_knowledge`

#### Step 8: Integrate CLAUDE.md
- Call `moira_bootstrap_inject_claude_md`

#### Step 9: Setup Gitignore
- Call `moira_bootstrap_setup_gitignore`

#### Step 10: User Review Gate
Present results to user:

```
═══════════════════════════════════════════
  MOIRA — Project Setup Complete
═══════════════════════════════════════════
  Detected:
  ├─ Stack: {framework} {version}, {language}, {styling}
  ├─ Testing: {test framework}
  ├─ Structure: {layout pattern}
  └─ CI: {ci platform}

  Generated:
  ├─ Config: .claude/moira/config.yaml
  ├─ Rules: .claude/moira/project/rules/ (4 files)
  ├─ Knowledge: .claude/moira/knowledge/ (populated)
  └─ CLAUDE.md: updated with Moira section

  ▸ review  — inspect generated files
  ▸ accept  — start using Moira
  ▸ adjust  — correct something
═══════════════════════════════════════════
```

- `review`: show key generated files (config.yaml, stack.yaml summary)
- `accept`: proceed to onboarding (if first time) or done
- `adjust`: accept user corrections, update config/rules accordingly

This is an approval gate (Art 4.2 — user authority). Init does NOT complete until user explicitly accepts.

#### Step 11: Onboarding (conditional)
- Check if this is first-time Moira use (no previous init in any project)
- If first time: offer micro-onboarding per `onboarding.md`
- If not: skip

#### `--force` Mode
When `--force` is passed:
- Steps 1-3: Same, but scaffold is re-run (idempotent — doesn't destroy existing)
- Step 4: Full rescan (all 4 scanners run again)
- Steps 5-7: Config and rules are regenerated, knowledge is UPDATED (not destroyed):
  - Scanner-sourced knowledge (project-model, conventions, patterns): overwritten with new scan
  - Organically grown knowledge (decisions, failures): PRESERVED
  - Quality-map: regenerated as preliminary
- Steps 8-9: Re-inject CLAUDE.md (replaces between markers), re-check gitignore
- Steps 10-11: Same review gate

### D5: CLAUDE.md Template (`src/global/templates/project-claude-md.tmpl`)

The template file for the Moira section injected into `.claude/CLAUDE.md`. Stored in global templates, read by `bootstrap.sh`.

Content matches the Moira section shown in D3 `moira_bootstrap_inject_claude_md`.

### D6: Deep Scan Trigger

The init command sets a flag in `config.yaml` indicating that a deep scan should run during the first task:

```yaml
bootstrap:
  quick_scan_completed: true
  quick_scan_at: "2026-03-12T10:00:00Z"
  deep_scan_completed: false
  deep_scan_pending: true
```

The deep scan itself is NOT implemented in Phase 5 — it requires the pipeline engine to be active (Phase 3 is done) and would dispatch additional Explorer agents during the first task execution. The trigger mechanism is:

1. During `/moira:task` execution (in orchestrator.md), before classification step:
   - Check `config.yaml` for `bootstrap.deep_scan_pending: true`
   - If true: dispatch deep scan Explorer agents in background (`run_in_background: true`)
   - Set `bootstrap.deep_scan_pending: false` immediately (so it only runs once)
   - Deep scan updates knowledge files when complete (non-blocking)

Phase 5 implements: the flag in config.yaml + the trigger check in orchestrator.md.
Phase 5 does NOT implement: the deep scan agent instructions (those are similar to but more comprehensive than quick scan — deferred to Phase 6+ when quality gates exist to validate deep scan output).

### D7: Updated `install.sh`

Add Phase 5 artifacts to installation:

**New copy operations:**
- `global/templates/scanners/` → `$MOIRA_HOME/templates/scanners/`
- `global/templates/stack-presets/` → `$MOIRA_HOME/templates/stack-presets/`
- `global/templates/project-claude-md.tmpl` → `$MOIRA_HOME/templates/project-claude-md.tmpl`
- `global/lib/bootstrap.sh` → `$MOIRA_HOME/lib/bootstrap.sh`

**New verification checks:**
- `bootstrap.sh` exists and has valid syntax
- Scanner templates directory exists with 4 `.md` files
- Stack presets directory has at least `generic.yaml`
- `project-claude-md.tmpl` exists

### D8: Updated Orchestrator (Deep Scan Trigger)

Add deep scan trigger to `src/global/skills/orchestrator.md`.

**Change:** At the start of every pipeline execution (before classification step), add:

```
## Bootstrap Deep Scan Check

Before starting the pipeline, check if a deep scan is pending:
1. Read `config.yaml` field `bootstrap.deep_scan_pending`
2. If `true`:
   - Log: "Deep scan triggered (background)"
   - Set `bootstrap.deep_scan_pending` to `false` in config.yaml
   - Dispatch deep scan agents in background (non-blocking)
   - Continue with pipeline — do NOT wait for deep scan
3. If `false` or field not present: skip
```

This is a minimal addition — the deep scan agents themselves are a future deliverable.

### D9: Tier 1 Test Additions (`src/tests/tier1/`)

#### New test file: `test-bootstrap.sh`

Tests for bootstrap engine:

**Scanner template tests:**
- All 4 scanner templates exist (`tech-scan.md`, `structure-scan.md`, `convention-scan.md`, `pattern-scan.md`)
- Each template contains: Objective, Scan Strategy, Output Format, Output Path, Constraints sections
- Each template contains Explorer NEVER constraints (no opinions, no recommendations)
- Each template specifies an output path under `.claude/moira/`

**Stack preset tests:**
- `generic.yaml` exists (required fallback)
- At least 5 additional presets exist
- Each preset has `_meta.name`, `_meta.stack_id`, `_meta.match_signals`
- Each preset has `stack`, `conventions`, `patterns`, `boundaries` sections
- All `stack_id` values are unique
- All `stack_id` values are valid enum values from config.schema.yaml (`project.stack` field)

**Bootstrap library tests:**
- `bootstrap.sh` exists and has valid bash syntax
- Functions exist: `moira_bootstrap_match_preset`, `moira_bootstrap_generate_config`, `moira_bootstrap_generate_project_rules`, `moira_bootstrap_populate_knowledge`, `moira_bootstrap_inject_claude_md`, `moira_bootstrap_setup_gitignore`

**Init command tests:**
- `init.md` has valid frontmatter with `name: moira:init`
- `init.md` has `allowed-tools` including: Agent, Read, Write, Bash
- `init.md` is not a stub (contains more than 20 lines of content)

**CLAUDE.md template tests:**
- Template file exists
- Contains `<!-- moira:start -->` and `<!-- moira:end -->` markers
- Contains orchestrator inviolable rules section
- Contains quick reference commands

#### Extended existing tests:
- `test-file-structure.sh`: add checks for scanner templates, stack presets, bootstrap.sh, CLAUDE.md template
- `test-install.sh`: add verification for Phase 5 artifacts (scanner templates, presets, bootstrap lib, CLAUDE.md template)

### D10: Updated `run-all.sh`

Add `test-bootstrap.sh` to the test runner.

## Non-Deliverables (explicitly deferred)

- **Deep scan agent instructions** (Phase 6+): The trigger is in place, but the actual deep scan agents (which produce comprehensive architecture maps, dependency analysis, test coverage assessment, security surface scan) require quality gates (Phase 6) to validate their output.
- **Hooks configuration injection** (Phase 8): `distribution.md` Step 8 mentions injecting hooks into `.claude/settings.json`. Phase 8 builds the hooks themselves; Phase 5 creates the hooks/ directory but doesn't populate `settings.json`.
- **AGENTS.md generation** (deferred): `distribution.md` Step 7 mentions generating project-adapted AGENTS.md. This requires the full quality gate system to validate adapted agent definitions. Deferred until Phase 6+.
- **Version pinning** (Phase 12): `config.yaml` can include `moira.version` for pinning. Not enforced until upgrade command exists.
- **MCP registry generation** (Phase 9): `config/mcp-registry.yaml` stays empty until MCP integration.
- **Budgets customization** (Phase 7): `config/budgets.yaml` uses schema defaults. Phase 7 builds the full budget system.
- **Team adoption flow** (Phase 12): Second developer joining an existing Moira project needs different init behavior (detect existing config). Phase 5 implements the basic "already initialized" check but not the full team flow.
- **Onboarding live example execution** (deferred): The onboarding flow (Step 3 in `onboarding.md`) involves executing a real task through the Quick Pipeline with annotations. This requires the full pipeline to work end-to-end with real project context, which is beyond Phase 5 scope. Phase 5 implements Steps 1-2 (concept + commands) and offers to try a task manually.

## Architectural Decisions

### AD-1: Scanner Results in Temporary Init Directory

Scanner outputs are written to `.claude/moira/state/init/` rather than directly to knowledge files. This allows:
1. All 4 scans to complete before any config/knowledge generation
2. The config generator to cross-reference all scan results
3. The temporary directory to be cleaned after init
4. Re-scan on `--force` without touching knowledge until all scans complete

### AD-2: Preset Matching by Signal Weights

Rather than complex detection logic, each preset declares match signals with weights. The tech scanner's output text is searched for each signal string. Highest-scoring preset wins. If no preset scores above threshold (5), `generic.yaml` is used.

This is simple, extensible (add signals to preset YAML), and deterministic. New presets can be added without modifying bootstrap logic.

### AD-3: Scan Overrides Preset on Conflict

When scan results conflict with preset defaults, scan results always win. Example: preset says `indent: 2 spaces` but `.prettierrc` says `tabWidth: 4` — the scan-detected value (4 spaces) is used.

Rationale: presets are generic defaults; scans observe the actual project. Evidence beats assumption (Art 2.3).

### AD-4: Knowledge Preservation on --force Reinit

`--force` reinitializes config and scanner-sourced knowledge but preserves organic knowledge (decisions, failures). Rationale: decisions and failures are accumulated over multiple tasks and represent unique project history. Rescanning cannot reproduce this data. Config and conventions can be re-detected.

### AD-5: Init Step Order Differs from distribution.md

The spec reorders `distribution.md`'s init flow: scaffold creation (Step 3) comes before scanning (Step 4), whereas `distribution.md` starts with scanning (its Step 3). Rationale: scanners write output to `.claude/moira/state/init/` — the directory must exist before agents write to it. Scaffold also copies knowledge templates that `--force` reinit needs to check against. Steps 7 (AGENTS.md) and 8 (Hooks) from `distribution.md` are deferred (see Non-Deliverables).

### AD-6: AGENTS.md Generation Deferred

`distribution.md` Step 7 defines AGENTS.md generation with project-adapted agent definitions. This is deferred because: (1) adapted agents need quality gates (Phase 6) to validate the adaptations, (2) the global agent definitions from Phase 2 work correctly without project adaptation, (3) the value of project-adapted AGENTS.md is marginal until the system has run enough tasks to understand what adaptations matter. This should be recorded as D-044 in the decision log.

### AD-7: Init Command Has Broader Tools Than Task Command

`init.md` has `allowed-tools: [Agent, Read, Write, Bash]` — it can use Bash and Write directly. This is acceptable because:
1. Init is NOT the orchestrator — it's a one-time setup command
2. Init needs Bash to run scaffold.sh and check prerequisites
3. Init needs Write to create config.yaml, project rules, etc.
4. Init does NOT read project source code — scanners (agents) do that
5. Art 1.1 applies to the orchestrator during pipeline execution, not to the setup command

### AD-9: Config Schema Updates for Phase 5

`config.schema.yaml` required two updates before Phase 5 implementation:
1. **Stack enum expansion:** Added `react-vite`, `express`, `fastapi`, `go-api` to `project.stack` enum to match preset `stack_id` values. Removed `react` (ambiguous without build tool context).
2. **Bootstrap fields:** Added `bootstrap.quick_scan_completed`, `bootstrap.quick_scan_at`, `bootstrap.deep_scan_completed`, `bootstrap.deep_scan_pending` per D-029 (schemas upfront) and D-045.

### AD-10: Additional Gitignore Entry

Added `.claude/moira/state/current.yaml` to gitignore entries (beyond what `distribution.md` lists). `current.yaml` is per-developer pipeline state and should not be committed. Also added `.claude/moira/state/init/` for temporary scanner output.

### AD-8: Simplified Onboarding in Phase 5

Full onboarding (per `onboarding.md`) includes a live example task execution. Phase 5 implements a simplified version:
- Step 1 (Core Concept): displayed as-is
- Step 2 (Commands): displayed as-is
- Step 3 (Live Example): replaced with "Try `/moira:task` with a small task when ready" — no automated execution

Full onboarding with live example execution is a quality-of-life improvement for later phases when the system is battle-tested.

## Success Criteria

1. **`/moira:init` works on a real project:** Running init on target project creates complete project layer
2. **Scanners produce useful output:** All 4 scanners return structured facts with file path evidence
3. **Preset matching works:** Tech scan correctly identifies the project's stack and selects matching preset
4. **Config is valid:** Generated `config.yaml` passes schema validation
5. **Project rules are evidence-based:** `stack.yaml`, `conventions.yaml`, `patterns.yaml`, `boundaries.yaml` contain data from actual scans, not just preset defaults
6. **Knowledge is populated:** All 3 levels of project-model, conventions, and patterns contain scanner-derived content
7. **CLAUDE.md integration is idempotent:** Running init twice doesn't duplicate the Moira section
8. **Gitignore is correct:** State directories are gitignored, config/knowledge/rules are committed
9. **--force preserves decisions/failures:** Reinit doesn't destroy organic knowledge
10. **User reviews before accepting:** Gate at Step 10 requires explicit user action
11. **Deep scan trigger is in place:** Config flag + orchestrator check ready for future deep scan
12. **Tier 1 tests pass:** All structural verification tests pass (existing + new Phase 5 tests)
13. **Constitutional compliance:** All invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Init dispatches Explorer agents for scanning, does not read project code itself
[✓] 1.2 — Explorer role constraints preserved in all scanner invocations (NEVER propose, NEVER recommend)
[✓] 1.3 — Bootstrap logic (bootstrap.sh), scanner templates, presets are separate components

ARTICLE 2: Determinism
[✓] 2.1 — N/A (no pipeline selection in init)
[✓] 2.2 — User review gate present (Step 10) — required before init completes
[✓] 2.3 — Scanner results shown to user, no implicit decisions (user can adjust)

ARTICLE 3: Transparency
[✓] 3.1 — Scanner results written to state files, visible via /moira:init review
[✓] 3.2 — N/A (no budget tracking during init — this is a setup command)
[✓] 3.3 — Scan failures reported to user, not silently ignored

ARTICLE 4: Safety
[✓] 4.1 — Scanners inherit anti-fabrication rules from base.yaml
[✓] 4.2 — User approves generated config at review gate
[✓] 4.3 — Init is reversible (delete .claude/moira/, restore CLAUDE.md from git)
[✓] 4.4 — N/A (no bypass in init)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — All knowledge entries sourced from scanner evidence (file paths, actual content)
[✓] 5.2 — N/A (no rule changes during init)
[✓] 5.3 — N/A (no existing knowledge to conflict with at first init)

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation
[✓] 6.3 — Tier 1 tests validate init artifacts
```
