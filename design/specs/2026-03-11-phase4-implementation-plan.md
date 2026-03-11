# Phase 4 Implementation Plan

Spec: `design/specs/2026-03-11-phase4-rules-knowledge.md`

## Chunk Overview

| Chunk | Deliverables | Dependencies | Files |
|-------|-------------|--------------|-------|
| 1. Knowledge Shell Library | D1 | Phase 1 (yaml-utils.sh) | 1 new |
| 2. Knowledge Templates | D5, D7 | None | 17 new |
| 3. Rules Assembly Library | D2 | Chunk 1 | 1 new |
| 4. Scaffold + Install | D6, D8 | Chunks 1-3 | 2 modified |
| 5. Dispatch + Daedalus | D3, D4 | Chunk 3 | 2 modified |
| 6. E8 Stub Upgrade | D9 | Chunk 1 | 1 modified |
| 7. Tests | D10 | Chunks 1-6 | 4 new/modified |

---

## Chunk 1: Knowledge Shell Library

Creates `knowledge.sh` — the foundation for all knowledge operations. All subsequent chunks depend on this.

### Task 1.1: Create `src/global/lib/knowledge.sh` — core read functions

**File:** `src/global/lib/knowledge.sh` (NEW)

**Source:** `design/subsystems/knowledge.md` (L0/L1/L2 levels, agent access matrix), spec D1

**Key points:**
- Source `yaml-utils.sh` from same directory (same pattern as `state.sh` line 11)
- `set -euo pipefail` header, bash 3.2+ compatible
- File header comment block explaining responsibilities (pattern: `state.sh` lines 1-6)

**Functions to implement:**

`moira_knowledge_read()`:
- Args: `knowledge_dir`, `knowledge_type`, `level`
- Valid types: `project-model`, `conventions`, `decisions`, `patterns`, `failures`, `quality-map`
- Level mapping: L0→`index.md`, L1→`summary.md`, L2→`full.md`
- Quality-map + L0 → return error (no L0 for quality-map, spec AD-6)
- File doesn't exist → return empty string, exit 0
- `cat` the file to stdout

`moira_knowledge_read_for_agent()`:
- Args: `knowledge_dir`, `agent_name`, `matrix_file`
- Matrix file defaults to `$MOIRA_HOME/core/knowledge-access-matrix.yaml` if not specified
- Parse matrix YAML with `moira_yaml_get` — the matrix uses inline format: `matrix.{agent}` returns `{ project_model: L1, conventions: null, ... }`
- Since yaml-utils can't parse inline maps, use `grep` + `sed` to extract values from the matrix line for the agent
- For each of the 6 knowledge dimensions (project_model, conventions, decisions, patterns, quality_map, failures): extract level from matrix, skip if `null`, call `moira_knowledge_read` with mapped type name (`project_model` → `project-model`, `quality_map` → `quality-map`)
- Special case: quality-map has no L0 file (AD-6). If matrix says L0 for quality_map, skip silently (the file doesn't exist, `moira_knowledge_read` returns empty)
- Output format: concatenate with section headers `## Knowledge: {Type Name} ({Level})`
- Return concatenated content to stdout

### Task 1.2: Create `src/global/lib/knowledge.sh` — write + freshness functions

**File:** `src/global/lib/knowledge.sh` (APPEND to Task 1.1)

**Source:** `design/subsystems/knowledge.md` (freshness markers, consistency), spec D1

**Functions to implement:**

`moira_knowledge_write()`:
- Args: `knowledge_dir`, `knowledge_type`, `level`, `content_file`, `task_id`
- Note: content is passed as a file path, not inline (avoids bash quoting issues with multiline markdown)
- Construct freshness tag: `<!-- moira:freshness {task_id} {YYYY-MM-DD} -->`
- Construct target path: `{knowledge_dir}/{type}/{level_file}`
- Write: freshness tag + blank line + content from file
- If target already exists: read existing freshness tag, append it to end as `<!-- moira:freshness:previous {old_task_id} {old_date} -->`
- Use `date -u +%Y-%m-%d` for date (UTC, consistent)

`moira_knowledge_freshness()`:
- Args: `knowledge_dir`, `knowledge_type`, `current_task_number`
- Read the L1 (summary) file for the knowledge type — this is the canonical freshness source
- Extract first `<!-- moira:freshness ... -->` tag using `grep` + `sed`
- Parse task ID — extract numeric portion from task ID (e.g., `klosthos-0042` → `42`)
- Calculate distance: `current_task_number - entry_task_number`
- Return: `fresh` (distance < 10), `aging` (10-20), `stale` (>20), `unknown` (no tag)

`moira_knowledge_stale_entries()`:
- Args: `knowledge_dir`, `current_task_number`
- Iterate over all 6 knowledge types
- For each: call `moira_knowledge_freshness`, if `stale` → add to output
- Output format: one line per stale entry: `{type} last_task={task_id} distance={N}`

### Task 1.3: Create `src/global/lib/knowledge.sh` — archival + consistency functions

**File:** `src/global/lib/knowledge.sh` (APPEND to Task 1.2)

**Source:** `design/subsystems/knowledge.md` (archival rotation, consistency validation), spec D1

**Functions to implement:**

`moira_knowledge_archive_rotate()`:
- Args: `knowledge_dir`, `knowledge_type`, `max_entries` (default: 20)
- Only applies to types with archive dirs: `decisions`, `patterns`
- Read `{type}/full.md`, count entries (delimited by `## ` at start of line, not `### ` or deeper)
- If count <= max_entries → return 0 (nothing to do)
- Calculate how many to move: `count - max_entries`
- Extract oldest entries (from top of file), write to `{type}/archive/batch-{NNN}.md` where NNN = next batch number (scan existing batch files, increment)
- Remove extracted entries from `full.md`
- Note: `summary.md` is NOT automatically updated here — that's the agent's job when writing knowledge. Summary should always reflect the complete picture regardless of archival.

`moira_knowledge_validate_consistency()`:
- Args: `knowledge_dir`, `knowledge_type`, `new_content_file`
- Read existing content at L1 level
- Structural checks (keyword-based heuristics):
  1. Extract key-value pairs from both (lines matching `key: value` or `key = value` or `**key**: value`)
  2. Compare: if same key has different value → `conflict`
  3. If new content has keys not in existing → `extend`
  4. If all keys match or no overlap → `confirm`
- Output: single word `confirm`, `extend`, or `conflict` to stdout
- If `conflict`: also output conflict details to stderr (which keys differ)
- This is intentionally simple — per spec AD-3, full semantic validation is Phase 10/11

**Commit message:** `moira(knowledge): implement knowledge shell library with read/write/freshness/archival`

---

## Chunk 2: Knowledge Templates

Creates the 17 template files that define the structure of each knowledge type at each level. These are installed globally and copied to projects.

### Task 2.1: Create project-model templates

**Files (NEW):**
- `src/global/templates/knowledge/project-model/index.md`
- `src/global/templates/knowledge/project-model/summary.md`
- `src/global/templates/knowledge/project-model/full.md`

**Source:** `design/subsystems/knowledge.md` (Project Model section)

**Key points:**
- Each file starts with `<!-- moira:knowledge {type} {level} -->` header tag
- L0 (index.md): list of sections with `(not yet scanned)` placeholders. Sections from knowledge.md: Domain, Architecture, Data Flow, Critical Paths, Boundaries, Pain Points
- L1 (summary.md): section headers with `(not yet scanned)` under each, plus brief description of what each section contains
- L2 (full.md): full section headers with detailed subsections matching knowledge.md Project Model structure
- Include note: `> This file is auto-populated by /moira:init. Manual edits are preserved.`

### Task 2.2: Create conventions templates

**Files (NEW):**
- `src/global/templates/knowledge/conventions/index.md`
- `src/global/templates/knowledge/conventions/summary.md`
- `src/global/templates/knowledge/conventions/full.md`

**Source:** `design/architecture/rules.md` (Layer 3 project rules — conventions.yaml structure)

**Key points:**
- Conventions cover: naming (files, components, functions, constants, types), formatting (indent, quotes, semicolons, line length), structure (component paths, page paths, API paths, etc.)
- L0: list of convention categories
- L1: key conventions per category (one-liner each)
- L2: full conventions with examples

### Task 2.3: Create decisions templates

**Files (NEW):**
- `src/global/templates/knowledge/decisions/index.md`
- `src/global/templates/knowledge/decisions/summary.md`
- `src/global/templates/knowledge/decisions/full.md`

**Source:** `design/subsystems/knowledge.md` (Decisions Log section)

**Key points:**
- Decisions have the most structured format: CONTEXT, DECISION, ALTERNATIVES REJECTED, REASONING
- L0: count of decisions + list of topic tags
- L1: one-liner per decision (date + topic + choice)
- L2: full decision entries with all 4 sections
- Archive dir already exists from Phase 1 scaffold

### Task 2.4: Create patterns templates

**Files (NEW):**
- `src/global/templates/knowledge/patterns/index.md`
- `src/global/templates/knowledge/patterns/summary.md`
- `src/global/templates/knowledge/patterns/full.md`

**Source:** `design/subsystems/knowledge.md` (Patterns section)

**Key points:**
- Pattern format: WORKS WHEN, FAILS WHEN, EVIDENCE
- L0: list of pattern names
- L1: pattern name + one-line "works when" summary
- L2: full pattern documentation

### Task 2.5: Create failures templates

**Files (NEW):**
- `src/global/templates/knowledge/failures/index.md`
- `src/global/templates/knowledge/failures/summary.md`
- `src/global/templates/knowledge/failures/full.md`

**Source:** `design/subsystems/knowledge.md` (Failures section)

**Key points:**
- Failure format: APPROACH, REJECTED BECAUSE, LESSON, APPLIES TO
- L0: list of failed approaches
- L1: approach + rejected reason (one-liner)
- L2: full failure documentation

### Task 2.6: Create quality-map templates

**Files (NEW):**
- `src/global/templates/knowledge/quality-map/summary.md`
- `src/global/templates/knowledge/quality-map/full.md`

**Source:** `design/subsystems/quality.md` (Quality Map section)

**Key points:**
- NO L0 for quality-map (spec AD-6)
- Three categories: Strong Patterns, Adequate Patterns, Problematic Patterns
- L1 (summary): list of modules with their category (strong/adequate/problematic)
- L2 (full): per-module assessment with evidence, specific issues, recommendations
- Include preliminary marker: `> Status: preliminary (deep scan pending)`

**Commit message:** `moira(knowledge): add knowledge template files for all 6 types`

---

## Chunk 3: Rules Assembly Library

Creates `rules.sh` — rule loading, conflict detection, and instruction file assembly. Depends on Chunk 1 for knowledge reading.

### Task 3.1: Create `src/global/lib/rules.sh` — layer loading + conflict detection

**File:** `src/global/lib/rules.sh` (NEW)

**Source:** `design/architecture/rules.md` (Rule Assembly Process, Conflict Detection), spec D2

**Key points:**
- Source `yaml-utils.sh` and `knowledge.sh` from same directory
- `set -euo pipefail`, bash 3.2+ compatible

**Functions to implement:**

`moira_rules_load_layer()`:
- Args: `layer_number`, `source_path`
- L1: reads `source_path` (base.yaml). Extract `inviolable` list items (grep for `rule:` under `inviolable:`) and `overridable` key-value pairs. Output to stdout in structured format.
- L2: reads `source_path` (role yaml). Extract `identity`, `never` items, `quality_checklist` value. Output structured.
- L3: reads `source_path` (directory). For each .yaml file in dir: extract all key-value pairs. Output structured with source file tagged.
- L4: reads `source_path` (file with task-specific content). Output as-is.

`moira_rules_detect_conflicts()`:
- Args: `base_file`, `project_rules_dir` (2 args — `role_file` omitted because L2 role constraints are behavioral, not key-value overrides, so they cannot structurally conflict with L3)
- Extract L1 overridable keys from base.yaml
- Extract L3 keys from project rules files (stack.yaml, conventions.yaml, etc.)
- For each matching key:
  - If key exists in L1 inviolable → ERROR (exit 1), print: `INVIOLABLE CONFLICT: {key} cannot be overridden by project rules`
  - If key exists in L1 overridable → resolved, print: `CONFLICT: {key} L1={val} L3={val} RESOLUTION: L3 wins`
- Key matching: compare overridable keys from base.yaml against project rules keys.
- L1→L3 key mapping (generic overridable → structured project rules):
  - `naming_convention` → any key under `naming:` in conventions.yaml (naming.files, naming.components, naming.functions, etc.). If ANY L3 naming key exists, the L1 default is overridden.
  - `indent` → `formatting.indent` in conventions.yaml
  - `max_function_length` → `max_function_length` in conventions.yaml or patterns.yaml (direct match)
  - `test_framework` → `testing` in stack.yaml (direct match)
  - `file_output_format` → `file_output_format` in conventions.yaml (direct match, rare override)
- If an L1 overridable key has no corresponding L3 key, no conflict exists (L1 default applies).
- The mapping is intentionally simple — it catches the most common overrides. Edge cases are resolved by the Planner (Daedalus) during instruction assembly, not by the structural checker.

`moira_rules_project_rules_for_agent()`:
- Args: `agent_name`, `project_rules_dir`
- Returns list of relevant project rule files per agent (space-separated paths)
- Mapping (from spec D2):
  - `hephaestus|themis|aletheia` → all: stack.yaml conventions.yaml patterns.yaml boundaries.yaml
  - `metis` → stack.yaml patterns.yaml boundaries.yaml
  - `daedalus` → stack.yaml conventions.yaml
  - `hermes|apollo|athena` → stack.yaml only
  - `mnemosyne|argus` → all
- Only return files that actually exist (don't fail on missing)

### Task 3.2: Create `src/global/lib/rules.sh` — instruction file assembly

**File:** `src/global/lib/rules.sh` (APPEND to Task 3.1)

**Source:** `design/architecture/rules.md` (Rule Assembly Process), spec D2 (`moira_rules_assemble_instruction`)

**Function to implement:**

`moira_rules_assemble_instruction()`:
- Args: `output_path`, `agent_name`, `base_file`, `role_file`, `project_rules_dir`, `knowledge_dir`, `task_context_file`, `matrix_file`
- Steps:
  1. Create output directory: `mkdir -p "$(dirname "$output_path")"`
  2. Extract agent display name and role from role file `_meta` section
  3. Run conflict detection (`moira_rules_detect_conflicts`). If inviolable conflict → exit 1
  4. Write instruction file sections to `output_path` using heredoc/printf:

**Instruction file structure:**
```
# Instructions for {DisplayName} ({role})

## Identity
{from role file identity: field — extract multiline YAML value}

## Rules

### Inviolable (NEVER violate — Constitution enforced)
{for each item in base.yaml inviolable: — extract rule: value, format as "- {rule}"}

### Role Constraints
{for each item in role yaml never: — format as "- {constraint}"}

### Project Rules
{for each relevant project rule file (per moira_rules_project_rules_for_agent):
  read file, format as subsection: ### Stack / ### Conventions / etc.
  include full file content}

## Knowledge
{output of moira_knowledge_read_for_agent}

## Quality Checklist
{read quality_checklist from role yaml, e.g. "q3-feasibility"
 then read the actual checklist file from core/rules/quality/{checklist}.yaml
 format items as markdown checklist}

## Response Contract
STATUS: success|failure|blocked|budget_exceeded
SUMMARY: <1-2 sentences>
ARTIFACTS: [<file paths>]
NEXT: <recommended next step>

Write all detailed output to artifact files. Return ONLY the status summary above.

## Task
{content of task_context_file}

## Output
Write your detailed results to: {output_path directory}/../../{agent_name}.md
```

- Identity extraction: the `identity:` field in role YAML uses `|` multiline syntax. Extract everything from `identity: |` until next top-level key (indent 0). Use awk/sed.
- Quality checklist: some agents don't have one (e.g., hermes has `quality_checklist: null`). If null, omit the section.
- If knowledge_dir doesn't exist or is empty, omit Knowledge section (handles projects not yet initialized).
- If project_rules_dir doesn't exist, omit Project Rules section (handles Quick pipeline / no init).

**Commit message:** `moira(rules): implement rules assembly library with conflict detection`

---

## Chunk 4: Scaffold + Install Updates

Updates existing infrastructure to include Phase 4 artifacts.

### Task 4.1: Update `src/global/lib/scaffold.sh`

**File:** `src/global/lib/scaffold.sh` (MODIFY)

**Source:** spec D6

**Changes:**
- In `moira_scaffold_global()`: add `mkdir -p "$target_dir"/templates/knowledge`
- In `moira_scaffold_project()`: add `mkdir -p "$base"/knowledge/patterns/archive` (currently missing — only `decisions/archive` exists)
- In `moira_scaffold_project()`: add template copy logic — if `$MOIRA_HOME/templates/knowledge/` exists, copy template files to project knowledge dirs. Use a helper function `_moira_copy_templates()` that copies each template to the correct project knowledge subdir. Only copy if target file doesn't exist (preserve existing knowledge on re-scaffold, idempotent per Art 4.3).

### Task 4.2: Update `src/install.sh`

**File:** `src/install.sh` (MODIFY)

**Source:** spec D8

**Changes in `install_global()`:**
- After existing `cp -f` lines for lib/ utilities, the existing `cp -f "$SCRIPT_DIR/global/lib/"*.sh` already copies ALL .sh files — so `knowledge.sh` and `rules.sh` are automatically included. No code change needed for lib copy.
- Add: copy knowledge templates directory
  ```
  # Copy knowledge templates (Phase 4)
  if [[ -d "$SCRIPT_DIR/global/templates/knowledge" ]]; then
    mkdir -p "$MOIRA_HOME/templates/knowledge"
    cp -rf "$SCRIPT_DIR/global/templates/knowledge/"* "$MOIRA_HOME/templates/knowledge/"
  fi
  ```

**Changes in `verify()`:**
- Add check: `knowledge.sh` exists and has no syntax errors (pattern: existing lib check loop on line 136). Extend the `for lib_file in ...` loop to include `knowledge.sh` and `rules.sh`.
- Add check: knowledge templates directory exists with expected count:
  ```
  # Check: knowledge templates exist (Phase 4)
  template_count=$(find "$MOIRA_HOME/templates/knowledge" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$template_count" -ge 17 ]]; then ...
  ```
  Note: 17 = 5 types x 3 levels + quality-map x 2 levels = 15 + 2 = 17

**Commit message:** `moira(foundation): update scaffold and install for Phase 4 artifacts`

---

## Chunk 5: Dispatch + Daedalus Updates

Updates the orchestrator's dispatch module and the Planner role definition for full rule assembly.

### Task 5.1: Update `src/global/skills/dispatch.md`

**File:** `src/global/skills/dispatch.md` (MODIFY)

**Source:** `design/architecture/rules.md` (Rule Assembly Process), spec D3

**Changes:**
- Rename "## Prompt Construction (Phase 3 Simplified)" → "## Prompt Construction"
- Add new subsection before current construction steps:

```markdown
### Pre-assembled Instructions (Primary Path)

When dispatching a post-planning agent (any agent after Daedalus has run), check for a pre-assembled instruction file:

1. Check path: `~/.claude/moira/state/tasks/{task_id}/instructions/{agent_name}.md`
2. If file exists and is non-empty:
   - Read the file contents
   - Use directly as the agent prompt (the file IS the complete prompt)
   - Skip simplified assembly — the file contains all rules, knowledge, and context
3. If file does not exist:
   - Fall back to simplified assembly (below)

Instruction files are written by Daedalus (planner) during the planning step. They contain L1-L4 merged rules, authorized knowledge, quality checklist, task context, and output path.
```

- Rename current steps section: "### Simplified Assembly (Fallback)" with note:
```markdown
Used for:
- Pre-planning agents: Apollo (classifier), Hermes (explorer), Athena (analyst) — always
- Quick pipeline: all agents — no Planner step exists
- Any agent when instruction file is missing (safety fallback)
```

- Add new subsection "### Which Agents Use Which Path":
  Table showing per-pipeline which agents get instruction files vs simplified assembly

- Remove the `(Phase 3 Simplified)` and `Phase 3 uses simplified prompt assembly. Full L1-L4 rule assembly is Phase 4.` notes since Phase 4 is now implemented

### Task 5.2: Update `src/global/core/rules/roles/daedalus.yaml`

**File:** `src/global/core/rules/roles/daedalus.yaml` (MODIFY)

**Source:** `design/architecture/agents.md` (Planner), spec D4

**Changes to `identity`:**
Current:
```yaml
identity: |
  You are Daedalus, the Planner. You decompose architecture decisions into execution steps.
  You create dependency graphs, cluster files into batches, and estimate context budgets.
  You assemble Layer 1-4 rules for each agent invocation.
  You allocate MCP tools per step with justification.
  You do NOT make architectural decisions — only decompose.
  You must pass the Q3 Plan Feasibility Checklist.
```

Add after "You assemble Layer 1-4 rules for each agent invocation.":
```
  For each downstream agent in the plan, you WRITE a complete instruction file to
  state/tasks/{task_id}/instructions/{agent_name}.md containing merged rules, authorized
  knowledge (per knowledge-access-matrix.yaml), quality checklist, and task-specific context.
```

**Add new key `output_structure`** after `response_format`:
```yaml
output_structure: |
  Your plan.md artifact MUST include these sections:
  1. Step-by-step execution plan with files, dependencies, and budget per step
  2. Dependency graph
  3. Conflict report — any L1/L3 rule conflicts detected and their resolutions
  4. Knowledge inclusion manifest — which knowledge type at which level for each agent
  5. Instruction files written — list of instructions/{agent}.md files you created
```

**Commit message:** `moira(pipeline): update dispatch and planner for full rule assembly`

---

## Chunk 6: E8 Stub Upgrade

Partially implements E8 (stale knowledge) error handling now that freshness system exists.

### Task 6.1: Update `src/global/skills/errors.md`

**File:** `src/global/skills/errors.md` (MODIFY)

**Source:** `design/subsystems/fault-tolerance.md` (E8), spec D9

**Changes:**
Find the E8 stub section. Replace the stub content with partial implementation:

```markdown
### E8: Stale Knowledge

**Detection:** At pipeline start (after classification, before dispatching exploration agents), check knowledge freshness:

1. Read the current task number from status files (count of completed tasks)
2. Call freshness check on all knowledge types used by the current pipeline
3. If any entries are `stale` (>20 tasks since last confirmation):

**Display:**
\```
⚠ STALE KNOWLEDGE WARNING
The following knowledge entries have not been confirmed in 20+ tasks:
  - {type}: last confirmed at task {task_id} ({distance} tasks ago)
  ...

Stale knowledge may lead to incorrect agent decisions.

▸ proceed — continue (agents may use outdated information)
▸ refresh — run /moira:refresh to update knowledge base first
\```

**Non-blocking:** This is a WARNING, not a gate. Pipeline continues after display.
The user can choose to refresh or proceed.

**State:** Log stale entries to `status.yaml` under `warnings:` block.

**NOT YET IMPLEMENTED:**
- Automatic knowledge refresh during pipeline (Phase 10)
- Impact assessment of stale knowledge on task quality (Phase 11)
```

Keep the existing stub marker comment if present, noting what remains deferred.

**Commit message:** `moira(pipeline): upgrade E8 stale knowledge stub with freshness detection`

---

## Chunk 7: Tests

Creates new test files and extends existing ones for Phase 4 verification.

### Task 7.1: Create `src/tests/tier1/test-knowledge-system.sh`

**File:** `src/tests/tier1/test-knowledge-system.sh` (NEW)

**Source:** spec D10

**Pattern:** Follow `test-yaml-schemas.sh` structure — source test-helpers, create temp dir, run tests, call test_summary.

**Tests to implement:**

1. **Knowledge directory structure** (run against installed MOIRA_HOME):
   - Templates dir exists: `$MOIRA_HOME/templates/knowledge/`
   - Each of 6 knowledge type subdirs exists in templates
   - Template files exist for all types at all levels (17 files total)
   - quality-map has NO index.md (L0 not applicable)

2. **moira_knowledge_read** (functional tests in temp dir):
   - Set up temp knowledge dir with test content at each level
   - Read L0 → returns index.md content
   - Read L1 → returns summary.md content
   - Read L2 → returns full.md content
   - Read quality-map L0 → returns error/empty
   - Read nonexistent type → returns empty

3. **moira_knowledge_read_for_agent** (functional tests):
   - Set up temp knowledge dir + temp matrix file (with all 6 dimensions)
   - Read for hermes → only project-model L0 content (all other types null)
   - Read for metis → project-model L1 + conventions L0 + decisions L2 + patterns L1 + quality-map L1 (failures null)
   - Read for hephaestus → project-model L0 + conventions L2 + patterns L1 (quality-map, failures, decisions all null)
   - Read for daedalus → project-model L1 + conventions L1 + decisions L0 + patterns L0 (quality-map L0 skipped — no L0 file exists)
   - Read for mnemosyne → all 6 types at L2 (full access including failures and quality-map)
   - Output contains section headers `## Knowledge: {Type} ({Level})`
   - Null access types are NOT included
   - quality-map L0 access produces no output (file doesn't exist, not an error)

4. **Freshness markers** (functional tests):
   - Write knowledge with task ID → file contains freshness tag
   - Parse freshness tag → extracts correct task ID and date
   - Freshness categorization: task distance <10 → `fresh`, 10-20 → `aging`, >20 → `stale`
   - No freshness tag → `unknown`

5. **Archive rotation** (functional tests):
   - Create full.md with 25 entries (## headers)
   - Run rotation with max_entries=20
   - Verify: full.md has 20 entries, archive/batch-001.md has 5 entries
   - Run again with 25 entries → creates batch-002.md

6. **Consistency validation** (functional tests):
   - Same keys, same values → `confirm`
   - New keys not in existing → `extend`
   - Same key, different value → `conflict`

### Task 7.2: Create `src/tests/tier1/test-rules-assembly.sh`

**File:** `src/tests/tier1/test-rules-assembly.sh` (NEW)

**Source:** spec D10

**Pattern:** Same as Task 7.1.

**Tests to implement:**

1. **Layer loading**:
   - L1 loads from base.yaml: output contains inviolable rules (check for INV-001)
   - L2 loads from role yaml: output contains identity, never constraints

2. **Conflict detection**:
   - Create temp project rules with `max_function_length: 100`
   - Run against base.yaml (has `max_function_length: 50`)
   - Output contains CONFLICT with L3 wins resolution
   - Create temp project rules that try to override inviolable (e.g., rule about fabrication)
   - Run → exit code 1

3. **Project rules mapping**:
   - `moira_rules_project_rules_for_agent hephaestus {dir}` → returns 4 files
   - `moira_rules_project_rules_for_agent apollo {dir}` → returns 1 file (stack only)
   - `moira_rules_project_rules_for_agent metis {dir}` → returns 3 files (no conventions)

4. **Instruction assembly** (integration test):
   - Create temp dirs with: base.yaml, one role yaml, project rules, knowledge files, task context file, matrix file
   - Run `moira_rules_assemble_instruction`
   - Verify output file contains all required sections: "## Identity", "## Rules", "### Inviolable", "### Role Constraints", "## Knowledge", "## Response Contract", "## Task", "## Output"
   - Verify inviolable rules are present (grep for fabrication prohibition)
   - Verify knowledge section matches agent's access level

5. **Knowledge access enforcement** (Art 1.2):
   - Assemble for hermes → knowledge section does NOT contain conventions, failures, or quality-map content
   - Assemble for hephaestus → knowledge section contains conventions L2 content, does NOT contain failures or quality-map
   - Assemble for apollo → knowledge section contains only project-model L1
   - Assemble for mnemosyne → knowledge section contains ALL 6 types at L2 (including failures and quality-map)

### Task 7.3: Extend existing tests

**Files (MODIFY):**
- `src/tests/tier1/test-file-structure.sh`
- `src/tests/tier1/test-install.sh` (if separate from install.sh verify)

**Changes to `test-file-structure.sh`:**
- Add: check `lib/knowledge.sh` exists in MOIRA_HOME
- Add: check `lib/rules.sh` exists in MOIRA_HOME
- Add: check templates/knowledge/ dir exists with subdirs
- Add: check templates/knowledge/quality-map/ has NO index.md

**Changes to `test-install.sh`:**
- Add: knowledge.sh and rules.sh syntax validation (bash -n)
- Add: template file count check (≥17)

**Commit message:** `moira(quality): add Tier 1 tests for rules assembly and knowledge system`

---

## Dependency Graph

```
Chunk 1: Knowledge Library ──────┬──────────────── Chunk 3: Rules Library
(no deps)                        │                  (depends on Chunk 1)
                                 │                          │
Chunk 2: Knowledge Templates     │                          │
(no deps)                        │                          │
                                 │                          │
                                 ▼                          ▼
                        Chunk 4: Scaffold+Install    Chunk 5: Dispatch+Daedalus
                        (depends on 1,2,3)           (depends on 3)
                                 │                          │
                                 │                          │
Chunk 6: E8 Upgrade ────────────┐│                          │
(depends on Chunk 1)             ││                          │
                                 ▼▼                         │
                        Chunk 7: Tests ◄────────────────────┘
                        (depends on 1-6)
```

**Parallel opportunities:**
- Chunks 1 and 2 can be implemented in parallel (no shared dependencies)
- Chunk 3 starts after Chunk 1 completes
- Chunks 5 and 6 can be implemented in parallel (both depend on earlier chunks, not each other)
- Chunk 4 can start after Chunks 1-3 complete
- Chunk 7 is always last

**Recommended execution order:**
1. Chunk 1 + Chunk 2 (parallel)
2. Chunk 3
3. Chunk 4 + Chunk 5 + Chunk 6 (parallel)
4. Chunk 7

**Total new files:** 20 (knowledge.sh, rules.sh, 17 templates, 2 test files)
**Total modified files:** 5 (scaffold.sh, install.sh, dispatch.md, daedalus.yaml, errors.md + 2 existing test files extended)
