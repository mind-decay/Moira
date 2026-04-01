# Phase 5 Implementation Plan

Spec: `design/specs/2026-03-12-phase5-bootstrap-engine.md`

## Chunk Overview

| Chunk | Deliverables | Dependencies | Files |
|-------|-------------|--------------|-------|
| 1. Scanner Instruction Templates | D1 | None | 4 new |
| 2. Stack Presets | D2 | None | 6 new |
| 3. Bootstrap Library | D3, D5 | Chunks 1, 2 | 2 new |
| 4. Init Command | D4 | Chunk 3 | 1 modified |
| 5. Deep Scan Trigger + Install | D6, D7, D8 | Chunks 1-4 | 2 modified |
| 6. Tests | D9, D10 | Chunks 1-5 | 3 new/modified |

---

## Chunk 1: Scanner Instruction Templates

Creates the 4 Layer 4 instruction templates that Explorer (Hermes) receives during bootstrap scanning. These define WHAT each scanner reports and HOW it formats output.

### Task 1.1: Create tech scanner template

**File:** `src/global/templates/scanners/tech-scan.md` (NEW)

**Source:** Spec D1 (Tech Scanner), blocker resolution Blocker 5

**Key points:**
- Header: identifies this as a scanner template for Hermes (explorer) during bootstrap
- Objective section: enumerate all categories — languages/versions, frameworks/libraries, build tools, test frameworks, linting/formatting, database/ORM, deployment, package managers
- Scan strategy section: ordered list of files to read
  1. Root config files: `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`
  2. Tool configs: `tsconfig.json`, `.eslintrc*`, `.prettierrc*`, `jest.config*`, `vitest.config*`, `vite.config*`, `next.config*`, `nuxt.config*`, `webpack.config*`
  3. CI/CD files: `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `Dockerfile`, `docker-compose*`
  4. Env example (NEVER `.env`): `.env.example`, `.env.sample`
  5. Lock files (existence check only): `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `poetry.lock`, `go.sum`
- Output format section: structured markdown per spec D1 with sections for Language & Runtime, Framework, Build & Tooling, Testing, Linting & Formatting, Database & ORM, CI/CD, Deployment
- Output path: `.moira/state/init/tech-scan.md`
- Constraints section: FACTS ONLY, no opinions, "Not detected" for missing categories, 140k token budget
- Include Explorer NEVER constraints inline: "Never propose solutions", "Never express opinions", "Never make recommendations"

### Task 1.2: Create structure scanner template

**File:** `src/global/templates/scanners/structure-scan.md` (NEW)

**Source:** Spec D1 (Structure Scanner)

**Key points:**
- Objective: map directory layout, entry points, source/generated/vendored separation, config locations, test organization
- Scan strategy:
  1. List top-level dirs and files (depth 1)
  2. For each source dir: list depth 2
  3. Identify entry points: `src/index.*`, `src/main.*`, `src/app.*`, `main.*`, `cmd/`
  4. Identify generated dirs: `dist/`, `build/`, `.next/`, `__pycache__/`, `node_modules/`
  5. Identify vendored: `vendor/`, `third_party/`
  6. Identify test roots
  7. Count files per top-level dir (approximate)
- Output format: per spec D1 — Project Root, Source Layout, Directory Roles table, Generated, Vendored, Configuration, Test Organization
- Output path: `.moira/state/init/structure-scan.md`
- Same constraints as tech scanner

### Task 1.3: Create convention scanner template

**File:** `src/global/templates/scanners/convention-scan.md` (NEW)

**Source:** Spec D1 (Convention Scanner)

**Key points:**
- Objective: detect naming, import style, export style, error handling, logging, code organization from actual code samples
- Scan strategy:
  1. Read linter/formatter configs for explicit rules
  2. Sample 3-5 files per category (components, API, services, utilities, types, tests)
  3. For each file: note naming, imports, exports, error handling
  4. Look for shared patterns across samples
  5. NEVER read more than 30 files total
- Output format: per spec D1 — tables for Naming Conventions, Import Style, Export Style, Error Handling, Logging, Code Organization — each with Evidence columns
- Output path: `.moira/state/init/convention-scan.md`
- Constraints: evidence-based (every claim needs `file:line` evidence), no opinions

### Task 1.4: Create pattern scanner template

**File:** `src/global/templates/scanners/pattern-scan.md` (NEW)

**Source:** Spec D1 (Pattern Scanner)

**Key points:**
- Objective: identify recurring code patterns, component structures, API patterns, data access, state management, abstractions
- Scan strategy:
  1. Read 3-5 representative files per architectural layer (UI, API, data access, services, middleware)
  2. For each layer: identify RECURRING structure (not one-offs)
  3. Note abstractions: base classes, HOCs, hooks, decorators, middleware chains
  4. Look for project-specific patterns
  5. NEVER read more than 25 files total
- Output format: per spec D1 — Component Pattern, API Pattern, Data Access Pattern, State Management, Common Abstractions table, Recurring Structures table — each with Example path
- Output path: `.moira/state/init/pattern-scan.md`
- Constraints: same as other scanners

**Commit message:** `moira(knowledge): add bootstrap scanner instruction templates`

---

## Chunk 2: Stack Presets

Creates the 6 stack preset YAML files that provide default Layer 3 project rules for common stacks.

### Task 2.1: Create generic preset

**File:** `src/global/templates/stack-presets/generic.yaml` (NEW)

**Source:** Spec D2, `design/architecture/rules.md` (Layer 3 structure)

**Key points:**
- This is the FALLBACK preset — used when no specific stack is detected
- `_meta.stack_id`: `generic`
- `_meta.match_signals`: empty (this preset is selected when nothing else matches)
- `stack`: minimal — `language: unknown`, `framework: unknown`, everything else `unknown` or `none`
- `conventions`: safe defaults — `naming.files: kebab-case`, `formatting.indent: 2 spaces`, `formatting.quotes: double`
- `patterns`: empty — all fields `unknown` or `none`
- `boundaries.do_not_modify`: common generated dirs (`node_modules/`, `dist/`, `build/`, `vendor/`, `.git/`)
- `boundaries.modify_with_caution`: empty (no project-specific knowledge)

### Task 2.2: Create Next.js preset

**File:** `src/global/templates/stack-presets/nextjs.yaml` (NEW)

**Source:** Spec D2, `design/architecture/rules.md` (conventions.yaml example is Next.js-based)

**Key points:**
- `_meta.stack_id`: `nextjs`
- `_meta.match_signals`:
  - `{signal: "next", context: "package.json dependencies", weight: 10}`
  - `{signal: "next.config", context: "file exists", weight: 5}`
  - `{signal: "@next/", context: "package.json dependencies", weight: 3}`
- `stack`: TypeScript, Next.js, Node.js, Tailwind CSS (common), no default ORM, Jest or Vitest
- `conventions`: per `rules.md` example — `files: kebab-case`, `components: PascalCase`, `functions: camelCase`, `indent: 2 spaces`, `quotes: single`, `semicolons: true`
- `conventions.structure`: App Router pattern (`src/app/{route}/page.tsx`, `src/components/`, `src/lib/`)
- `patterns`: `data_fetching: "Server Components + Server Actions"`, `validation: "Zod schemas"`, `error_handling: "error.tsx error boundaries"`
- `boundaries.do_not_modify`: `node_modules/`, `.next/`, `public/` (static assets), `prisma/migrations/` (if Prisma detected)
- `boundaries.modify_with_caution`: `next.config.*`, `middleware.ts`, `prisma/schema.prisma`

### Task 2.3: Create React+Vite preset

**File:** `src/global/templates/stack-presets/react-vite.yaml` (NEW)

**Key points:**
- `_meta.stack_id`: `react-vite`
- `_meta.match_signals`:
  - `{signal: "react", context: "package.json dependencies", weight: 5}`
  - `{signal: "vite", context: "package.json devDependencies", weight: 8}`
  - `{signal: "vite.config", context: "file exists", weight: 5}`
- `stack`: TypeScript, React, Node.js, Vite bundler, Vitest (common with Vite)
- `conventions`: same naming as Next.js, SPA-oriented structure (`src/components/`, `src/pages/`, `src/hooks/`, `src/stores/`)
- `patterns`: `data_fetching: "React Query / SWR"`, `client_state: "Zustand / Redux"`, `routing: "React Router"`
- `boundaries.do_not_modify`: `node_modules/`, `dist/`

### Task 2.4: Create Express preset

**File:** `src/global/templates/stack-presets/express.yaml` (NEW)

**Key points:**
- `_meta.stack_id`: `express`
- `_meta.match_signals`:
  - `{signal: "express", context: "package.json dependencies", weight: 10}`
- `stack`: TypeScript or JavaScript, Express, Node.js, no default styling, various testing (Jest, Mocha)
- `conventions`: `files: kebab-case`, `functions: camelCase`, API-oriented structure (`src/routes/`, `src/controllers/`, `src/services/`, `src/middleware/`, `src/models/`)
- `patterns`: `api_style: "REST"`, `error_handling: "Express error middleware"`, `validation: "express-validator / Joi / Zod"`
- `boundaries.do_not_modify`: `node_modules/`, `dist/`
- `boundaries.modify_with_caution`: `src/middleware/` (affects all routes)

### Task 2.5: Create FastAPI preset

**File:** `src/global/templates/stack-presets/fastapi.yaml` (NEW)

**Key points:**
- `_meta.stack_id`: `fastapi`
- `_meta.match_signals`:
  - `{signal: "fastapi", context: "pyproject.toml or requirements.txt", weight: 10}`
  - `{signal: "uvicorn", context: "pyproject.toml or requirements.txt", weight: 5}`
- `stack`: Python, FastAPI, Python runtime, SQLAlchemy (common), pytest
- `conventions`: `files: snake_case`, `functions: snake_case`, `classes: PascalCase`, `constants: UPPER_SNAKE_CASE`, `indent: 4 spaces`, `quotes: double`
- `conventions.structure`: `app/routers/`, `app/models/`, `app/schemas/`, `app/services/`, `app/core/`
- `patterns`: `api_style: "REST with Pydantic models"`, `validation: "Pydantic v2"`, `db_access: "SQLAlchemy with Alembic migrations"`
- `boundaries.do_not_modify`: `__pycache__/`, `.venv/`, `alembic/versions/`

### Task 2.6: Create Go API preset

**File:** `src/global/templates/stack-presets/go-api.yaml` (NEW)

**Key points:**
- `_meta.stack_id`: `go-api`
- `_meta.match_signals`:
  - `{signal: "go.mod", context: "file exists", weight: 10}`
  - `{signal: "net/http", context: "import in .go files", weight: 3}`
  - `{signal: "gin-gonic", context: "go.mod dependencies", weight: 5}`
  - `{signal: "chi", context: "go.mod dependencies", weight: 5}`
- `stack`: Go, stdlib or Gin/Chi, Go runtime, GORM (common), go test
- `conventions`: `files: snake_case`, `functions: PascalCase (exported) / camelCase (unexported)`, `types: PascalCase`, `constants: PascalCase or UPPER_SNAKE_CASE`, `indent: tabs`, `formatting: gofmt enforced`
- `conventions.structure`: `cmd/`, `internal/`, `pkg/`, `api/`, `config/`
- `patterns`: `api_style: "REST"`, `error_handling: "error return values"`, `db_access: "Repository pattern with GORM or sqlx"`
- `boundaries.do_not_modify`: `vendor/` (if present)

**Commit message:** `moira(knowledge): add stack preset templates for 6 common stacks`

---

## Chunk 3: Bootstrap Library

Creates `bootstrap.sh` — the core library for preset matching, config generation, knowledge population, and CLAUDE.md integration. Also creates the CLAUDE.md template. Depends on Chunks 1 and 2 (references scanner output format and preset structure).

### Task 3.1: Create CLAUDE.md template

**File:** `src/global/templates/project-claude-md.tmpl` (NEW)

**Source:** Spec D5, `design/architecture/distribution.md` (CLAUDE.md integration)

**Key points:**
- Plain markdown file with `<!-- moira:start -->` and `<!-- moira:end -->` markers
- Content between markers per spec D3 `moira_bootstrap_inject_claude_md`:
  - Section header: `## Moira Orchestration System`
  - Brief description of what Moira does
  - Quick reference: 5 key commands
  - Orchestrator inviolable rules (NEVER read/write project files, ALL interaction through agents)
- This is a static template — no variable substitution needed
- Stored in global templates, read by `bootstrap.sh` at init time

### Task 3.2: Create `src/global/lib/bootstrap.sh` — preset matching

**File:** `src/global/lib/bootstrap.sh` (NEW)

**Source:** Spec D3

**Key points:**
- Source `yaml-utils.sh` from same directory
- `set -euo pipefail`, bash 3.2+ compatible
- File header: responsibilities — bootstrap operations for `/moira:init`

**Function to implement:**

`moira_bootstrap_match_preset()`:
- Args: `tech_scan_path`, `presets_dir`
- Read tech scan artifact (markdown file from tech scanner)
- Convert to lowercase for matching
- For each `.yaml` file in `presets_dir`:
  - Read `_meta.match_signals` entries
  - For each signal: check if signal string (lowercase) appears in tech scan text
  - Sum weights for matched signals
- Return the preset filename with highest score
- If no preset scores > 5: return `generic.yaml`
- If tie: return first match (alphabetical)

Signal matching is intentionally simple: `grep -qi` of signal string in scan text. This is deterministic and extensible (add signals to preset YAML to improve matching).

### Task 3.3: Create `src/global/lib/bootstrap.sh` — config + rules generation

**File:** `src/global/lib/bootstrap.sh` (APPEND to Task 3.2)

**Source:** Spec D3, `src/schemas/config.schema.yaml`

**Functions to implement:**

`moira_bootstrap_generate_config()`:
- Args: `project_root`, `preset_path`, `tech_scan_path`
- Read preset YAML for `stack_id`
- Extract project name: try `package.json` name field, else `go.mod` module name, else `basename $project_root`
- Write `config.yaml` to `$project_root/.moira/config.yaml`:
  ```yaml
  version: "1.0"
  project:
    name: "{extracted name}"
    root: "{project_root}"
    stack: "{stack_id from preset}"
  # All other fields use schema defaults from config.schema.yaml
  # Users can customize via /moira:init adjust or manual edit
  classification:
    default_pipeline: standard
    size_hints_override: false
  pipelines:
    quick: {max_retries: 1, gates: [classification, final]}
    standard: {max_retries: 2, gates: [classification, architecture, plan, final]}
    full: {max_retries: 2, gates: [classification, architecture, plan, per-phase, final]}
    decomposition: {max_retries: 2, gates: [classification, decomposition, per-task, final]}
  budgets:
    orchestrator_max_percent: 25
    agent_max_load_percent: 70
    per_agent: {classifier: 20000, explorer: 140000, analyst: 80000, architect: 100000, planner: 70000, implementer: 120000, reviewer: 100000, tester: 90000, reflector: 80000, auditor: 140000}
  quality: {mode: conform, evolution_threshold: 3, review_severity_minimum: medium}
  knowledge: {freshness_days: 30, archival_max_entries: 100}
  audit: {light_every_n_tasks: 10, standard_every_n_tasks: 20, auto_batch_apply_risk: low}
  mcp: {enabled: false, registry_path: config/mcp-registry.yaml}
  hooks: {guard_enabled: true, budget_tracking_enabled: true}
  bootstrap:
    quick_scan_completed: true
    quick_scan_at: "{current UTC timestamp}"
    deep_scan_completed: false
    deep_scan_pending: true
  ```
- Use heredoc for YAML generation (not yaml-utils — config is one-time write, not incremental)

`moira_bootstrap_generate_project_rules()`:
- Args: `project_root`, `preset_path`, `scan_results_dir`
- Read preset YAML for default `stack`, `conventions`, `patterns`, `boundaries` sections
- Read scan results to override defaults where evidence exists:
  - `tech-scan.md` → overrides `stack` section values
  - `convention-scan.md` → overrides `conventions` section values
  - `structure-scan.md` → adds to `boundaries` (generated dirs → do_not_modify)
  - `pattern-scan.md` → overrides `patterns` section values
- For each file, scan override means: if scan result provides a value for a field, use it instead of preset default
- Scan parsing: extract values from the structured markdown output (e.g., `Primary: TypeScript 5.3` → `language: TypeScript`, `version: "5.3"`)
- Write 4 files to `$project_root/.moira/project/rules/`:
  - `stack.yaml` — tech stack facts
  - `conventions.yaml` — coding conventions
  - `patterns.yaml` — recurring code patterns
  - `boundaries.yaml` — modification restrictions

Implementation note: scan result parsing is inherently fuzzy (markdown → YAML). The approach:
1. For each output section in scan markdown, extract the value after the last colon or pipe delimiter
2. Map to the corresponding YAML key
3. If extraction fails for a field, fall back to preset default
4. This is acceptable because: (a) user reviews at Step 10 gate, (b) scan results are written by our own templates with predictable format

### Task 3.4: Create `src/global/lib/bootstrap.sh` — knowledge population

**File:** `src/global/lib/bootstrap.sh` (APPEND to Task 3.3)

**Source:** Spec D3, `design/subsystems/knowledge.md` (Bootstrapping)

**Function to implement:**

`moira_bootstrap_populate_knowledge()`:
- Args: `project_root`, `scan_results_dir`
- For each knowledge type that gets scanner data:

**project-model** (from structure-scan.md):
- L2 (full.md): copy structure scan output with freshness marker
- L1 (summary.md): extract key sections — Source Layout pattern, entry points, directory count
- L0 (index.md): extract section headers only (Domain, Architecture, etc.) with one-liner per section

**conventions** (from convention-scan.md):
- L2 (full.md): copy convention scan output with freshness marker
- L1 (summary.md): extract key conventions — one line per Naming/Import/Export/Error/Logging category
- L0 (index.md): list of convention categories

**patterns** (from pattern-scan.md):
- L2 (full.md): copy pattern scan output with freshness marker
- L1 (summary.md): extract pattern names with one-liner descriptions
- L0 (index.md): pattern name list only

**quality-map** (from pattern-scan.md — preliminary):
- L2 (full.md): extract "Recurring Structures" and "Common Abstractions" sections, format as preliminary quality assessment
- L1 (summary.md): list of identified abstractions with frequency (all/most/some)
- Add marker: `<!-- moira:preliminary — deep scan required -->`

**decisions** — leave as template (no data yet)
**failures** — leave as template (no data yet)

For each write:
- Add freshness marker: `<!-- moira:freshness init {YYYY-MM-DD} -->`
- Preserve knowledge header tag from template: `<!-- moira:knowledge {type} {level} -->`
- Use `moira_knowledge_write` from `knowledge.sh` for proper freshness tracking

Level condensation approach: L2 gets full scan output; L1 is produced by extracting first line/value from each section of L2; L0 is produced by extracting section headers only from L2. This is implemented in shell using `grep`/`sed`/`awk` — we do NOT dispatch agents for level condensation during init (that would blow the bootstrap budget).

### Task 3.5: Create `src/global/lib/bootstrap.sh` — CLAUDE.md + gitignore

**File:** `src/global/lib/bootstrap.sh` (APPEND to Task 3.4)

**Source:** Spec D3, `design/architecture/distribution.md` (`.claude/` compatibility)

**Functions to implement:**

`moira_bootstrap_inject_claude_md()`:
- Args: `project_root`, `moira_home`
- Read template from `$moira_home/templates/project-claude-md.tmpl`
- Target file: `$project_root/.claude/CLAUDE.md`
- Logic:
  1. If target file exists:
     a. Check for `<!-- moira:start -->` marker
     b. If marker found: replace everything between `<!-- moira:start -->` and `<!-- moira:end -->` (inclusive) with template content
     c. If no marker: append newline + template content at end of file
  2. If target file does not exist:
     a. Create `.claude/` directory if needed: `mkdir -p "$project_root/.claude"`
     b. Write template content as entire file
- Implementation: use `sed` for marker replacement, `cat >>` for append
- CRITICAL: never modify content outside moira markers. If existing CLAUDE.md has content above/below markers, preserve it exactly.

`moira_bootstrap_setup_gitignore()`:
- Args: `project_root`
- Target: `$project_root/.gitignore`
- Entries to add (per `distribution.md`):
  ```
  # Moira orchestration state (per-developer)
  .moira/state/tasks/
  .moira/state/bypass-log.yaml
  .moira/state/current.yaml
  .moira/state/init/
  ```
- Check if each entry already exists (grep). Only append missing entries.
- If `.gitignore` doesn't exist: create it with these entries.
- Idempotent — multiple runs don't duplicate entries.

**Commit message:** `moira(bootstrap): implement bootstrap library with preset matching, config generation, and CLAUDE.md integration`

---

## Chunk 4: Init Command

Replaces the Phase 5 stub in `init.md` with the full `/moira:init` implementation. This is the main user-facing deliverable — the command that ties everything together.

### Task 4.1: Implement `/moira:init` command

**File:** `src/commands/moira/init.md` (MODIFY — replace stub)

**Source:** Spec D4, `design/architecture/distribution.md` (Steps 1-10), `design/architecture/onboarding.md`

**Key points:**

The init command is a markdown skill file that Claude reads and follows. It is NOT a shell script. It contains instructions for Claude on how to orchestrate the init process using the allowed tools (Agent, Read, Write, Bash).

**Frontmatter** (keep existing):
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

**Command body structure:**

```markdown
# Moira — Project Initialization

## Overview
This command sets up Moira for the current project. It scans the project,
generates configuration and rules, populates the knowledge base, and
integrates with .claude/CLAUDE.md.

## Step 1: Check Global Layer
Read `~/.claude/moira/.version`.
- If file exists: store version, continue.
- If not: display error and stop:
  ```
  Moira is not installed globally.
  Run: curl -fsSL https://<org>/moira/main/install.sh | bash
  ```

## Step 2: Check Existing Init
Read `.moira/config.yaml`.
- If exists AND $ARGUMENTS does not contain "--force":
  Display: "Moira already initialized for this project."
  Suggest: "/moira:refresh to update, /moira:init --force to reinitialize"
  Stop.
- If exists AND "--force" in arguments: continue (reinit mode)
- If not exists: continue (fresh init)

## Step 3: Create Project Scaffold
Run via Bash:
```bash
source ~/.claude/moira/lib/scaffold.sh
moira_scaffold_project "{project_root}"
```
This creates all directories and copies knowledge templates.

## Step 4: Dispatch Scanner Agents
Source scanner templates and dispatch 4 Explorer agents in PARALLEL.

Read each scanner template from `~/.claude/moira/templates/scanners/`.

For each scanner, construct prompt:
1. Read `~/.claude/moira/core/rules/roles/hermes.yaml` for identity + NEVER constraints
2. Read `~/.claude/moira/core/rules/base.yaml` for inviolable rules
3. Read the scanner template for task-specific instructions
4. Combine into agent prompt

Dispatch ALL 4 agents simultaneously using 4 Agent tool calls in a single message:

- Agent 1: "Hermes (explorer) — tech scan"
  - prompt: {assembled prompt with tech-scan.md instructions}
  - subagent_type: general-purpose

- Agent 2: "Hermes (explorer) — structure scan"
  - prompt: {assembled prompt with structure-scan.md instructions}
  - subagent_type: general-purpose

- Agent 3: "Hermes (explorer) — convention scan"
  - prompt: {assembled prompt with convention-scan.md instructions}
  - subagent_type: general-purpose

- Agent 4: "Hermes (explorer) — pattern scan"
  - prompt: {assembled prompt with pattern-scan.md instructions}
  - subagent_type: general-purpose

Wait for all 4 to complete. Check STATUS from each:
- If any STATUS: failure or blocked → report which scanner failed and why, offer to retry or skip
- If all STATUS: success → proceed

### Scanner Failure Handling
If a scanner fails:
- Display which scanner failed and the error summary
- Offer: retry / skip (use preset defaults for that category) / abort
- If skipped: that category will use preset defaults only (no evidence-based data)

## Step 5: Match Stack Preset
Run via Bash:
```bash
source ~/.claude/moira/lib/bootstrap.sh
moira_bootstrap_match_preset ".moira/state/init/tech-scan.md" "$HOME/.claude/moira/templates/stack-presets"
```
Display: "Matched stack preset: {result}"

## Step 6: Generate Config and Rules
Run via Bash:
```bash
source ~/.claude/moira/lib/bootstrap.sh
moira_bootstrap_generate_config "{project_root}" "$HOME/.claude/moira/templates/stack-presets/{preset}" ".moira/state/init/tech-scan.md"
moira_bootstrap_generate_project_rules "{project_root}" "$HOME/.claude/moira/templates/stack-presets/{preset}" ".moira/state/init"
```

## Step 7: Populate Knowledge
Run via Bash:
```bash
source ~/.claude/moira/lib/bootstrap.sh
moira_bootstrap_populate_knowledge "{project_root}" ".moira/state/init"
```

## Step 8: Integrate CLAUDE.md
Run via Bash:
```bash
source ~/.claude/moira/lib/bootstrap.sh
moira_bootstrap_inject_claude_md "{project_root}" "$HOME/.claude/moira"
```

## Step 9: Setup Gitignore
Run via Bash:
```bash
source ~/.claude/moira/lib/bootstrap.sh
moira_bootstrap_setup_gitignore "{project_root}"
```

## Step 10: User Review Gate (REQUIRED — Art 4.2)
Present results to user. This is an APPROVAL GATE — do NOT proceed without explicit user action.

Display:
```
═══════════════════════════════════════════
  MOIRA — Project Setup Complete
═══════════════════════════════════════════
  Detected:
  ├─ Stack: {from config.yaml project.stack}
  ├─ Testing: {from stack.yaml testing field}
  ├─ Structure: {from structure scan — source layout pattern}
  └─ CI: {from tech scan — CI platform}

  Generated:
  ├─ Config: .moira/config.yaml
  ├─ Rules: .moira/project/rules/ (4 files)
  ├─ Knowledge: .moira/knowledge/ (3 types populated)
  └─ CLAUDE.md: updated with Moira section

  ▸ review  — inspect generated files
  ▸ accept  — start using Moira
  ▸ adjust  — correct something
═══════════════════════════════════════════
```

Wait for user response.

### On "review":
Read and display key files:
- `.moira/config.yaml` (full)
- `.moira/project/rules/stack.yaml` (full)
- `.moira/project/rules/conventions.yaml` (summary)
Then re-present the gate (review/accept/adjust).

### On "accept":
Display: "Moira is ready. Use /moira:task <description> to start."
Proceed to Step 11 (onboarding check).

### On "adjust":
Ask user what needs correction. Apply changes to the relevant files.
Then re-present the gate.

## Step 11: Micro-Onboarding (conditional)
Check: has user used Moira before? (Look for completed tasks in any project's metrics — or simply check if this is a fresh global install with version file created recently.)

If appears to be first time:
```
═══════════════════════════════════════════
  MOIRA — First time setup
═══════════════════════════════════════════

  ▸ start — 3-minute walkthrough of how Moira works
  ▸ skip  — I'll figure it out (tip: /moira:help)
═══════════════════════════════════════════
```

### On "start":
Display Step 1 (Core Concept) from onboarding.md:
```
═══════════════════════════════════════════
  HOW MOIRA WORKS
═══════════════════════════════════════════

  You describe a task → Moira orchestrates agents:

  You ──→ Classify ──→ Analyze ──→ Plan ──→ Build ──→ Review
             │           │          │         │         │
          "how big?"  "what's    "how?"   "write    "check
                       needed?"            code"    quality"

  You approve at key checkpoints (▸ prompts).
  You never need to manage agents directly.

  ▸ next
═══════════════════════════════════════════
```

Display Step 2 (Commands):
```
═══════════════════════════════════════════
  COMMANDS — just 5 to remember
═══════════════════════════════════════════

  /moira:task <task>     — do a task
  /moira:resume          — resume interrupted work
  /moira:status          — where am I?
  /moira:knowledge       — what does the system know?
  /moira:metrics         — how well is it working?

  Everything else happens through prompts.

  ▸ done — you're all set!
═══════════════════════════════════════════
```

(Step 3 — live example — deferred per spec AD-6. Instead:)
Display: "Try /moira:task with a small task when ready."

### On "skip":
Display: "Quick reference: /moira:task <task>, /moira:status, /moira:help"
Done.

## --force Mode Differences
When --force is passed:
- Step 3: scaffold is re-run (idempotent)
- Step 4: all 4 scanners run again
- Step 7: knowledge update preserves decisions/ and failures/ content:
  - project-model, conventions, patterns: overwritten with new scan data
  - quality-map: regenerated as preliminary
  - decisions: PRESERVED (organic growth)
  - failures: PRESERVED (organic growth)
- Steps 8-9: CLAUDE.md re-injected (replaces between markers), gitignore rechecked
```

**Commit message:** `moira(bootstrap): implement /moira:init command with full bootstrap flow`

---

## Chunk 5: Deep Scan Trigger + Install Updates

Adds the deep scan trigger mechanism to the orchestrator and updates install.sh for Phase 5 artifacts.

### Task 5.1: Update orchestrator with deep scan trigger

**File:** `src/global/skills/orchestrator.md` (MODIFY)

**Source:** Spec D6, D8

**Changes:**
Find the section where pipeline execution begins (after reading task input, before classification step). Add:

```markdown
## Bootstrap Deep Scan Check

Before starting the pipeline, check if a deep scan is pending:

1. Read `.moira/config.yaml` field `bootstrap.deep_scan_pending`
2. If `true`:
   - Display: "ℹ Background deep scan triggered — knowledge base will update automatically."
   - Update `config.yaml`: set `bootstrap.deep_scan_pending` to `false`
   - NOTE: The actual deep scan agent dispatch is not yet implemented (Phase 6+).
     When implemented, this will dispatch Explorer agents in background for:
     - Full architecture mapping
     - Dependency analysis
     - Test coverage assessment
     - Security surface scan
   - Continue with pipeline — do NOT wait
3. If `false` or field not present: continue silently
```

This is a minimal stub that sets the flag correctly. The actual deep scan dispatch will be added in a future phase when quality gates can validate the output.

### Task 5.2: Update `src/install.sh`

**File:** `src/install.sh` (MODIFY)

**Source:** Spec D7

**Changes in `install_global()`:**
After the existing knowledge templates copy block, add:

```bash
# Copy scanner templates (Phase 5)
if [[ -d "$SCRIPT_DIR/global/templates/scanners" ]]; then
  mkdir -p "$MOIRA_HOME/templates/scanners"
  cp -f "$SCRIPT_DIR/global/templates/scanners/"*.md "$MOIRA_HOME/templates/scanners/"
fi

# Copy CLAUDE.md template (Phase 5)
if [[ -f "$SCRIPT_DIR/global/templates/project-claude-md.tmpl" ]]; then
  cp -f "$SCRIPT_DIR/global/templates/project-claude-md.tmpl" "$MOIRA_HOME/templates/"
fi
```

Note: stack-presets copy already exists in install.sh (lines 83-85). Do NOT add a duplicate block.

**Changes in `verify()`:**
Add after existing knowledge template check:

```bash
# Check: bootstrap.sh exists and has valid syntax (Phase 5)
((checks_total++))
if [[ -f "$MOIRA_HOME/lib/bootstrap.sh" ]] && bash -n "$MOIRA_HOME/lib/bootstrap.sh" 2>/dev/null; then
  ((checks_passed++))
else
  errors+="  lib/bootstrap.sh not found or has syntax errors\n"
fi

# Check: scanner templates exist (Phase 5)
((checks_total++))
local scanner_count
scanner_count=$(find "$MOIRA_HOME/templates/scanners" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$scanner_count" -ge 4 ]]; then
  ((checks_passed++))
else
  errors+="  scanner templates: expected >=4, found ${scanner_count}\n"
fi

# Check: stack presets exist with generic fallback (Phase 5)
((checks_total++))
if [[ -f "$MOIRA_HOME/templates/stack-presets/generic.yaml" ]]; then
  ((checks_passed++))
else
  errors+="  generic.yaml stack preset not found\n"
fi

# Check: CLAUDE.md template exists (Phase 5)
((checks_total++))
if [[ -f "$MOIRA_HOME/templates/project-claude-md.tmpl" ]]; then
  ((checks_passed++))
else
  errors+="  project-claude-md.tmpl not found\n"
fi
```

Also update the `for lib_file in ...` loop to include `bootstrap.sh`:
```bash
for lib_file in state.sh yaml-utils.sh scaffold.sh task-id.sh knowledge.sh rules.sh bootstrap.sh; do
```

Note: `bootstrap.sh` itself does NOT need an explicit copy block in `install_global()` — the existing line `cp -f "$SCRIPT_DIR/global/lib/"*.sh "$MOIRA_HOME/lib/"` already copies ALL `.sh` files from `global/lib/`, so `bootstrap.sh` is included automatically. Only the verification and template copies are new.

### Task 5.3: Update scaffold for init state directory

**File:** `src/global/lib/scaffold.sh` (MODIFY)

**Source:** Spec AD-1 (scanner results in temporary init directory)

**Changes to `moira_scaffold_project()`:**
Add after existing state directories (after `mkdir -p "$base"/state/audits`):

```bash
# Init scan results directory (temporary, used during /moira:init)
mkdir -p "$base"/state/init
```

Note: `moira_scaffold_global()` already creates `templates/scanners/` (added during review fixes).

**Commit message:** `moira(bootstrap): add deep scan trigger and update install for Phase 5`

---

## Chunk 6: Tests

Creates new test files and extends existing ones for Phase 5 verification.

### Task 6.1: Create `src/tests/tier1/test-bootstrap.sh`

**File:** `src/tests/tier1/test-bootstrap.sh` (NEW)

**Source:** Spec D9

**Pattern:** Follow existing test files — source test-helpers.sh, use `assert_*` helpers, call `test_summary` at end.

**Tests to implement:**

**1. Scanner template tests:**
- All 4 templates exist in `$MOIRA_HOME/templates/scanners/`
- Each template contains "## Objective" section
- Each template contains "## Scan Strategy" section
- Each template contains "## Output Format" section
- Each template contains "## Output Path" section
- Each template contains "## Constraints" section
- Each template contains Explorer NEVER constraints (grep for "Never propose" or "NO opinions")
- Each template specifies output path under `.moira/`

**2. Stack preset tests:**
- `generic.yaml` exists in `$MOIRA_HOME/templates/stack-presets/`
- At least 5 additional `.yaml` files exist
- Each preset contains `_meta:` section
- Each preset contains `stack:` section
- Each preset contains `conventions:` section
- `generic.yaml` has `stack_id: generic`
- All `stack_id` values across presets are unique (no duplicates)

**3. Bootstrap library tests:**
- `bootstrap.sh` exists in `$MOIRA_HOME/lib/`
- `bootstrap.sh` has valid bash syntax (`bash -n`)
- Functions exist (grep for function declarations):
  - `moira_bootstrap_match_preset`
  - `moira_bootstrap_generate_config`
  - `moira_bootstrap_generate_project_rules`
  - `moira_bootstrap_populate_knowledge`
  - `moira_bootstrap_inject_claude_md`
  - `moira_bootstrap_setup_gitignore`

**4. CLAUDE.md template tests:**
- `project-claude-md.tmpl` exists in `$MOIRA_HOME/templates/`
- Contains `<!-- moira:start -->` marker
- Contains `<!-- moira:end -->` marker
- Contains "Moira Orchestration System" heading
- Contains `/moira:task` command reference
- Contains orchestrator inviolable rules (grep for "NEVER read" or "NEVER write")

**5. Init command tests:**
- `init.md` exists in `$HOME/.claude/commands/moira/`
- Has frontmatter with `name: moira:init`
- Has `allowed-tools:` with Agent, Read, Write, Bash
- Content length > 20 lines (not a stub)
- Contains "Step 1" through "Step 10" (all steps present)
- Contains "User Review Gate" or "APPROVAL GATE"

**6. Functional tests (in temp dir):**
- `moira_bootstrap_inject_claude_md` on empty dir → creates `.claude/CLAUDE.md` with markers
- `moira_bootstrap_inject_claude_md` on existing CLAUDE.md without markers → appends markers
- `moira_bootstrap_inject_claude_md` on existing CLAUDE.md WITH markers → replaces between markers, preserves surrounding content
- `moira_bootstrap_setup_gitignore` on empty dir → creates `.gitignore` with moira entries
- `moira_bootstrap_setup_gitignore` on existing `.gitignore` → appends missing entries
- `moira_bootstrap_setup_gitignore` run twice → no duplicate entries
- `moira_bootstrap_match_preset` with nextjs scan → returns `nextjs.yaml`
- `moira_bootstrap_match_preset` with unknown stack → returns `generic.yaml`

### Task 6.2: Extend existing tests

**Files (MODIFY):**
- `src/tests/tier1/test-file-structure.sh`
- `src/tests/tier1/test-install.sh`

**Changes to `test-file-structure.sh`:**
- Add: check `lib/bootstrap.sh` exists in MOIRA_HOME
- Add: check `templates/scanners/` dir exists with 4 `.md` files
- Add: check `templates/stack-presets/` dir exists with `generic.yaml`
- Add: check `templates/project-claude-md.tmpl` exists

**Changes to `test-install.sh`:**
- Extend lib syntax loop to include `bootstrap.sh`
- Add: scanner template count check (≥ 4)
- Add: stack preset check (generic.yaml exists)
- Add: CLAUDE.md template check

### Task 6.3: Verify `run-all.sh` auto-discovery

**File:** `src/tests/tier1/run-all.sh` (NO CHANGE NEEDED)

**Source:** Spec D10

`run-all.sh` auto-discovers all `test-*.sh` files via glob. Creating `test-bootstrap.sh` in the same directory is sufficient — no modification needed. Verify by running the test suite after Task 6.1.

### Task 6.4: Update decision log

**File:** `design/decisions/log.md` (ALREADY DONE during review)

D-044 (AGENTS.md deferred) and D-045 (bootstrap schema fields) have been recorded. Verify entries are present.

**Commit message:** `moira(quality): add Tier 1 tests for bootstrap engine`

---

## Dependency Graph

```
Chunk 1: Scanner Templates ──────────┐
(no deps)                             │
                                      ├──→ Chunk 3: Bootstrap Library
Chunk 2: Stack Presets ──────────────┘    (depends on 1, 2)
(no deps)                                         │
                                                   ▼
                                          Chunk 4: Init Command
                                          (depends on 3)
                                                   │
                                                   ▼
                                          Chunk 5: Deep Scan + Install
                                          (depends on 1-4)
                                                   │
                                                   ▼
                                          Chunk 6: Tests
                                          (depends on 1-5)
```

**Parallel opportunities:**
- Chunks 1 and 2 can be implemented in parallel (no shared dependencies)
- All subsequent chunks are sequential (each depends on the previous)

**Recommended execution order:**
1. Chunk 1 + Chunk 2 (parallel)
2. Chunk 3
3. Chunk 4
4. Chunk 5
5. Chunk 6

**Total new files:** 13 (4 scanner templates, 6 presets, bootstrap.sh, CLAUDE.md template, 1 test file)
**Total modified files:** 5 (init.md, orchestrator.md, install.sh, scaffold.sh, run-all.sh + 2 existing test files extended)
