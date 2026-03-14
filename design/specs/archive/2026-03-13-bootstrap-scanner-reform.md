# Bootstrap Scanner Reform — Remove Presets, Standardize Scanner Output

## Goal

Fix systemic issues in `/moira:init` bootstrap flow: remove stack presets that produce false defaults for unknown stacks, and standardize scanner output format to eliminate fragile bash markdown parsing. Scanners remain unchanged in count — only their output format, minor responsibility extension (structure scanner gains directory conventions), and the config generation pipeline change.

## Motivation

Field testing on a SvelteKit project exposed 11 bugs (see `design/reports/2026-03-13-init-bootstrap-bugs.md`). Root cause analysis shows two systemic problems:

1. **Stack presets actively harm unknown stacks.** SvelteKit matched `react-vite` preset (BUG-2), injecting React-specific defaults (`data_fetching: React Query / SWR`, `error_handling: Error boundaries + try-catch`) that pollute config (BUG-3, BUG-6). Adding a SvelteKit preset fixes one stack but the problem recurs for every unsupported stack (Remix, Nuxt, Astro, Hono, Elixir, Rust, Terraform, etc.). Presets don't scale.

2. **Bash grep/sed parsing of free-form markdown is fragile.** `bootstrap.sh` uses `_extract_scan_value`, `_extract_table_value`, and `_condense_to_summary` to regex-parse LLM-generated markdown. This breaks on: backtick-wrapped values (BUG-5), "Not detected (reason...)" strings (BUG-4), nested lists (BUG-7), missing table headers (BUG-9), ignored sections (BUG-8).

## Risk Classification

**ORANGE** — Changes config generation pipeline, scanner output format, removes stack presets. Requires design doc updates first.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/reports/2026-03-13-init-bootstrap-bugs.md` | Full bug report with 11 issues — primary motivation |
| `design/specs/2026-03-12-phase5-bootstrap-engine.md` | Current scanner format spec (D1), preset system (D2), config generator (D3) |
| `design/architecture/distribution.md` | `/moira init` flow (lines 276-393), file structure with `stack-presets/` |
| `design/architecture/overview.md` | Global layer file tree with `templates/stack-presets/` |
| `design/architecture/rules.md` | Layer 3 project rules structure — `conventions.yaml` includes `structure:` section (lines 114-122) |
| `design/IMPLEMENTATION-GUIDE.md` | Bootstrap scanning strategy (lines 146-157) |
| `design/subsystems/knowledge.md` | L0/L1/L2 population from scanner output |
| `design/decisions/log.md` | D-032 (scanners = Explorer invocations), D-043 (knowledge templates) |
| `src/schemas/config.schema.yaml` | `project.stack` enum (line 24): `[nextjs, react-vite, express, fastapi, go-api, vue, python, rust, java, generic]` — includes 4 values without corresponding presets |

## What Changes

### Scanners: 4 agents, new output format, structure scanner gains directory conventions

Each scanner writes a **frontmatter block** (machine-readable fields for config generation) followed by **free-form markdown** (human-readable documentation for knowledge base).

```
Before:  Scanner → free-form .md → bash grep/sed → YAML config
After:   Scanner → frontmatter + .md → bash read-until-'---' → YAML config
```

The frontmatter contains ONLY the fields needed for config generation. Everything else stays as free-form markdown for knowledge.

#### Tech Scanner frontmatter

```yaml
---
language: TypeScript
language_version: "5.3"
framework: SvelteKit
framework_version: "2.0"
framework_type: web
runtime: Node.js
package_manager: pnpm
build_tool: vite
styling: Tailwind CSS
orm: Prisma
testing: Vitest
ci: GitHub Actions
deployment: Vercel
---
```

After `---`: free-form markdown with full details, evidence, paths (becomes knowledge L2).

#### Structure Scanner frontmatter

Structure scanner gains **directory convention fields** (`dir_*`) — file placement patterns detected from recurring directory structures. This data was previously in presets only (see `rules.md:114-122` `conventions.yaml` `structure:` section). The structure scanner already maps directories to roles; detecting file placement patterns is a natural extension.

```yaml
---
layout_pattern: single-app
source_root: src
entry_points:
  - src/app.html
  - src/hooks.server.ts
test_pattern: co-located
test_roots:
  - src
test_naming: "*.test.ts"
do_not_modify:
  - node_modules/
  - .svelte-kit/
  - src/generated/prisma/
modify_with_caution:
  - svelte.config.js
  - prisma/schema.prisma
dir_components: src/lib/components/
dir_pages: src/routes/
dir_api: src/routes/api/
dir_services: src/lib/server/
dir_types: src/types/
dir_utils: src/lib/utils/
---
```

`dir_*` fields are optional — scanner writes only those it can detect from repeating patterns (3+ files with same role in a directory). If a directory role can't be determined, the field is omitted.

Future: a dedicated Architecture Scanner (D-060) may take over `dir_*` detection with deeper analysis (FSD layers, dependency direction rules, module boundaries).

#### Convention Scanner frontmatter

```yaml
---
naming_files: kebab-case
naming_functions: camelCase
naming_components: PascalCase
naming_constants: UPPER_SNAKE_CASE
naming_types: PascalCase
indent: 2 spaces
quotes: single
semicolons: false
max_line_length: 100
import_style: named
export_style: default
---
```

#### Pattern Scanner frontmatter

```yaml
---
component_structure: functional
component_state: runes
component_styling: Tailwind CSS
api_style: REST
api_handler_structure: SvelteKit form actions + load functions
api_validation: Zod
api_response_format: SvelteKit ActionResult
data_fetching: SvelteKit load functions
error_handling: SvelteKit fail() + throw redirect()
client_state: Svelte stores
server_state: SvelteKit load functions
---
```

### Frontmatter contract

- Fields use `snake_case` keys
- **Scalar values** are plain strings (no quotes needed unless containing special YAML characters like `:`, `{`, `[`)
- **Numeric values** (like `max_line_length: 100`) are valid — the parser treats all values as strings
- **List values** use standard YAML list syntax with `  - ` items on subsequent lines (used by `entry_points`, `test_roots`, `do_not_modify`, `modify_with_caution`)
- If scanner cannot determine a value: **omit the field entirely** (do NOT write `unknown` or `Not detected`)
- The `---` delimiters are mandatory and on their own lines
- Order of fields within frontmatter does not matter
- Frontmatter is the ONLY machine-parsed section — everything after second `---` is free-form

### Stack presets: removed

All specialized preset files (`nextjs.yaml`, `react-vite.yaml`, `express.yaml`, `fastapi.yaml`, `go-api.yaml`) are deleted. `generic.yaml` is also deleted — it's no longer needed because missing fields are handled by omission, not by fallback values.

### Config generation: simplified

`bootstrap.sh` changes:

| Function | Before | After |
|----------|--------|-------|
| `moira_bootstrap_match_preset` | grep tech-scan for signals, weight-score presets | **Deleted** |
| `moira_bootstrap_generate_config` | merge preset + tech-scan | Read tech-scan frontmatter only (signature drops `preset_path` param) |
| `moira_bootstrap_generate_project_rules` | 4 sub-functions merging preset + scan | Read frontmatter from all 4 scans, write YAML directly (signature drops `preset_path` param) |
| `_moira_bootstrap_gen_stack` | preset defaults + scan overrides | Tech-scan frontmatter → `stack.yaml` |
| `_moira_bootstrap_gen_conventions` | preset defaults + table parsing | Convention-scan frontmatter + structure-scan `dir_*` fields → `conventions.yaml` (includes `structure:` section) |
| `_moira_bootstrap_gen_patterns` | preset defaults + partial overrides | Pattern-scan frontmatter → `patterns.yaml` |
| `_moira_bootstrap_gen_boundaries` | preset do_not_modify + structure grep | Structure-scan frontmatter → `boundaries.yaml` |
| `_extract_scan_value` | regex markdown sections | **Deleted** — replaced by frontmatter parser |
| `_extract_table_value` | grep markdown table rows | **Deleted** |
| `_extract_preset_field` | parse preset YAML sections | **Deleted** |
| `_extract_section` | extract markdown section by name | **Deleted** — no longer needed for config generation |

New functions:

#### `_moira_parse_frontmatter <file> <field>`

Reads a **scalar** value from YAML frontmatter. Implementation:
1. Read lines between first `---` and second `---`
2. Find line matching `^<field>: `
3. Return the value portion (everything after `<field>: `)
4. Return empty string if field not found

#### `_moira_parse_frontmatter_list <file> <field>`

Reads a **list** value from YAML frontmatter. Implementation:
1. Read lines between first `---` and second `---`
2. Find line matching `^<field>:`
3. Read subsequent lines matching `^  - ` until a non-list-item line
4. Output each list item (one per line, without `  - ` prefix)
5. Return empty string if field not found

Both functions operate on the frontmatter block only (between `---` delimiters), never touching the markdown body.

### `conventions.yaml` gains `structure:` from structure-scan

Previously the `structure:` section was populated only from presets (and lost for unknown stacks — BUG-8). Now:

1. Structure scanner detects directory conventions via `dir_*` frontmatter fields
2. `_moira_bootstrap_gen_conventions` reads `dir_*` fields from structure-scan frontmatter
3. Writes them as `structure:` section in `conventions.yaml`

Example output:
```yaml
# Conventions — generated by /moira:init

naming:
  files: kebab-case
  functions: camelCase
  components: PascalCase
  constants: UPPER_SNAKE_CASE
  types: PascalCase

formatting:
  indent: 2 spaces
  quotes: single
  semicolons: false
  max_line_length: 100

structure:
  components: src/lib/components/
  pages: src/routes/
  api: src/routes/api/
  services: src/lib/server/
  types: src/types/
  utils: src/lib/utils/
```

If no `dir_*` fields are detected, the `structure:` section is omitted entirely.

### Knowledge population: unchanged for L2, improved for L0/L1

- **L2 (full.md)**: entire scanner output file (frontmatter + markdown) — no change
- **L1 (summary.md)**: `_condense_to_summary` still extracts key lines from markdown body (after frontmatter). Existing bugs (BUG-7, BUG-9) are separate fixes, not blocked by this reform
- **L0 (index.md)**: `_condense_to_index` still extracts `## ` headers — no change

### `project.stack` in config.yaml

Currently an enum in `config.schema.yaml` (line 24): `[nextjs, react-vite, express, fastapi, go-api, vue, python, rust, java, generic]`. This enum already includes 4 values (`vue`, `python`, `rust`, `java`) without corresponding preset files. Changes to:

```yaml
project:
  stack: SvelteKit  # free-form string from tech scanner, not an enum
```

Schema change: `type: enum` → `type: string`. Scanner writes whatever framework it detects. No mapping to preset IDs needed.

### init.md skill: changes

- Step 5 (Match Stack Preset): **deleted** — steps renumber (old 6→5, 7→6, etc.)
- Step 5 (was 6) Generate Config and Rules: no longer passes preset path. Calls:
  - `moira_bootstrap_generate_config "{project_root}" ".claude/moira/state/init/tech-scan.md"`
  - `moira_bootstrap_generate_project_rules "{project_root}" ".claude/moira/state/init"`
- Step 9 (was 10) User Review: displays detected stack from config as before
- All other steps: logic unchanged, numbers shift by -1 after old Step 5

## What Does NOT Change

- **Scanner count**: still 4 (tech, structure, convention, pattern)
- **Scanner dispatch**: still 4 parallel Explorer agents per Step 4 of init
- **Agent role**: still Hermes (Explorer) with Layer 4 instructions (D-032)
- **Knowledge templates**: `src/global/templates/knowledge/` — unchanged
- **Knowledge L0/L1/L2 system**: unchanged
- **CLAUDE.md integration**: unchanged
- **Gitignore setup**: unchanged
- **Deep scan mechanism**: unchanged
- **Onboarding flow**: unchanged
- **Knowledge population functions**: `_condense_to_summary`, `_condense_to_index`, `_write_knowledge_level`, `_write_knowledge_file` — unchanged
- **Quality map generation**: `_moira_bootstrap_gen_quality_map` and helpers — unchanged
- **CLAUDE.md injection**: `moira_bootstrap_inject_claude_md` — unchanged
- **Gitignore setup**: `moira_bootstrap_setup_gitignore` — unchanged

## Bug Resolution Matrix

| Bug | This spec fixes? | How |
|-----|-----------------|-----|
| BUG-1: `BASH_SOURCE` in zsh | **Yes** — separate fix | Add zsh fallback `${(%):-%x}` to `bootstrap.sh:14`, `yaml-utils.sh:20`, `knowledge.sh:11` |
| BUG-2: No SvelteKit preset → React defaults | **Yes** | No presets → no wrong match |
| BUG-3: `data_fetching`/`error_handling` never overridden | **Yes** | All fields from frontmatter, no preset layer |
| BUG-4: "Not detected (reason...)" passes check | **Yes** | Frontmatter: omit field if not detected |
| BUG-5: Backtick dups in boundaries | **Yes** | Frontmatter YAML list, no backticks |
| BUG-6: `dist/`/`index.html` from wrong preset | **Yes** | No presets → no wrong defaults |
| BUG-7: `_condense_to_summary` loses data | **No** — separate fix | Knowledge condensation, not config |
| BUG-8: `structure` section ignored | **Yes** | Directory conventions detected by structure scanner (`dir_*` fields), written to `conventions.yaml` `structure:` section by `_moira_bootstrap_gen_conventions` |
| BUG-9: Table without header row | **No** — separate fix | Knowledge formatting, not config |
| BUG-10: Inconsistent scaffold output | **No** — separate fix | Cosmetic |
| BUG-11: Only 1 scanner launches | **No** — separate fix | Init orchestration, not data format |

**Score: 8 of 11 bugs resolved by this spec.** Remaining 3 are independent fixes (BUG-7, 9 = knowledge formatting; BUG-10 = cosmetic; BUG-11 = init orchestration).

## Files to Create/Modify

### Design docs to update

| File | Change |
|------|--------|
| `design/specs/2026-03-12-phase5-bootstrap-engine.md` | D1: update Output Format sections for all 4 scanners (add frontmatter). D2: mark Stack Presets as removed. D3: update config generator function list |
| `design/architecture/distribution.md` | Lines 242-251: remove `stack-presets/` from file tree. Lines 304-307: remove preset matching step from init flow |
| `design/architecture/overview.md` | Lines 122-125: remove `stack-presets/` from global layer tree |
| `design/architecture/rules.md` | Lines 114-122: note that `conventions.yaml` `structure:` section is now populated from structure scanner `dir_*` fields, not presets |
| `design/IMPLEMENTATION-GUIDE.md` | Lines 148-157: update "stack presets are starting points" paragraph — presets removed, scanners detect everything directly |
| `design/IMPLEMENTATION-ROADMAP.md` | Line 108: update Phase 5 description — remove "stack preset" reference |
| `design/decisions/log.md` | Add D-060: "Remove Stack Presets, Frontmatter Scanner Output, Directory Conventions in Structure Scanner" |
| `design/specs/2026-03-12-phase6-quality-gates.md` | Lines 34, 426, 452: update preset references, update `.moira-fixture.yaml` format (remove `moira_init_preset` field) |
| `design/specs/2026-03-11-phase1-foundation-design.md` | Lines 51, 317, 381: add supersession note — `stack-presets/` removed, `project.stack` is free-form string |
| `design/specs/2026-03-11-phase1-implementation-plan.md` | Lines 67, 83, 233, 466: add supersession note — `stack-presets/` directory and enum removed |
| `design/decisions/2026-03-11-blocker-resolution-design.md` | Line 28: add supersession note — `stack-presets/` removed |

### Source files to modify

| File | Change |
|------|--------|
| `src/global/templates/scanners/tech-scan.md` | Add frontmatter contract to Output Format section |
| `src/global/templates/scanners/structure-scan.md` | Add frontmatter contract (including `dir_*` fields) to Output Format section. Add directory convention detection to Scan Strategy |
| `src/global/templates/scanners/convention-scan.md` | Add frontmatter contract to Output Format section |
| `src/global/templates/scanners/pattern-scan.md` | Add frontmatter contract to Output Format section |
| `src/global/lib/bootstrap.sh` | Major refactor: delete preset functions (`moira_bootstrap_match_preset`, `_extract_scan_value`, `_extract_table_value`, `_extract_preset_field`, `_extract_section`), add `_moira_parse_frontmatter` and `_moira_parse_frontmatter_list`, rewrite all `_gen_*` functions to read frontmatter, `_moira_bootstrap_gen_conventions` gains `structure:` section from structure-scan `dir_*` fields. Function signatures change: `moira_bootstrap_generate_config` drops `preset_path` param, `moira_bootstrap_generate_project_rules` drops `preset_path` param |
| `src/global/lib/scaffold.sh` | Line 27: remove `mkdir -p "$target_dir"/templates/stack-presets` |
| `src/commands/moira/init.md` | Remove Step 5 (preset matching), renumber steps 6-11 → 5-10, update Step 5 (was 6) to not pass preset path |
| `src/install.sh` | Lines 83-85: remove preset file copying (`if ls ... stack-presets ... cp`). Line 307-313: remove preset verification check (`generic.yaml stack preset not found`) |
| `src/schemas/config.schema.yaml` | Line 22-24: `project.stack` change from `type: enum` + `enum: [...]` to `type: string`, keep `default: generic` |
| `src/tests/tier1/test-bootstrap.sh` | Remove preset tests (lines 34-68), remove `moira_bootstrap_match_preset` from function existence check (line 83), remove preset matching functional tests (lines 232-262), add frontmatter parsing tests (see Test Specification below) |
| `src/tests/tier1/test-file-structure.sh` | Lines 42, 96: remove `assert_dir_exists "templates/stack-presets"` and `assert_file_exists "stack-presets/generic.yaml"` |
| `src/tests/tier1/test-install.sh` | Line 72: remove `assert_file_exists "generic.yaml preset exists"` |
| `src/tests/bench/fixtures/greenfield-webapp/.moira-fixture.yaml` | Line 10: remove `moira_init_preset: express` |
| `src/tests/bench/fixtures/mature-webapp/.moira-fixture.yaml` | Line 12: remove `moira_init_preset: express` |
| `src/tests/bench/fixtures/legacy-webapp/.moira-fixture.yaml` | Line 12: remove `moira_init_preset: express` |

### Source files to delete

| File | Reason |
|------|--------|
| `src/global/templates/stack-presets/nextjs.yaml` | Preset system removed |
| `src/global/templates/stack-presets/react-vite.yaml` | Preset system removed |
| `src/global/templates/stack-presets/express.yaml` | Preset system removed |
| `src/global/templates/stack-presets/fastapi.yaml` | Preset system removed |
| `src/global/templates/stack-presets/go-api.yaml` | Preset system removed |
| `src/global/templates/stack-presets/generic.yaml` | Preset system removed |
| `src/global/templates/stack-presets/.gitkeep` | Directory removed |

### Separate bug fixes (included in scope)

| File | Bug | Fix |
|------|-----|-----|
| `src/global/lib/bootstrap.sh` | BUG-1 | Line 14: `BASH_SOURCE[0]` → `${BASH_SOURCE[0]:-${(%):-%x}}` |
| `src/global/lib/yaml-utils.sh` | BUG-1 | Line 20: same zsh fallback (confirmed: uses `BASH_SOURCE[0]`) |
| `src/global/lib/knowledge.sh` | BUG-1 | Line 11: same zsh fallback (confirmed: uses `BASH_SOURCE[0]`) |
| `src/global/lib/scaffold.sh` | BUG-1 | **Not applicable** — does not use `BASH_SOURCE` |
| `src/global/lib/scaffold.sh` | BUG-10 | `_moira_copy_templates`: suppress debug output (redirect or remove `echo` of `type_name`) |

## Test Specification

### Tests to delete

1. **Preset existence tests** (lines 38-68): `generic.yaml` exists, `>=6 presets`, section checks, `stack_id` checks, uniqueness cross-validation
2. **`moira_bootstrap_match_preset` function check** (line 83): remove from function existence list
3. **Preset matching functional tests** (lines 232-262): nextjs match test, unknown stack fallback test

### Tests to add

#### Frontmatter parser function tests

```
# _moira_parse_frontmatter: scalar value extraction
test: create temp file with frontmatter, call _moira_parse_frontmatter for a known field
assert: returns correct value

# _moira_parse_frontmatter: missing field returns empty
test: call _moira_parse_frontmatter for a field not in frontmatter
assert: returns empty string

# _moira_parse_frontmatter: ignores content after second ---
test: create file with same field name in frontmatter AND markdown body
assert: returns frontmatter value, not body value

# _moira_parse_frontmatter_list: list extraction
test: create temp file with frontmatter containing a list field
assert: returns all list items, one per line, without "  - " prefix

# _moira_parse_frontmatter_list: empty list returns empty
test: call _moira_parse_frontmatter_list for a field not in frontmatter
assert: returns empty string
```

#### Scanner template structure tests

```
# Each scanner template has frontmatter contract section
for scanner in tech-scan structure-scan convention-scan pattern-scan:
  assert_file_contains: "## Frontmatter Contract" or frontmatter example with ---

# Structure scanner template mentions dir_* fields
assert_file_contains structure-scan.md: "dir_"
```

#### Bootstrap function existence tests (updated)

```
# Updated function list (moira_bootstrap_match_preset removed):
for func in moira_bootstrap_generate_config moira_bootstrap_generate_project_rules
             moira_bootstrap_populate_knowledge moira_bootstrap_inject_claude_md
             moira_bootstrap_setup_gitignore _moira_parse_frontmatter
             _moira_parse_frontmatter_list:
  assert: function declared in bootstrap.sh

# Deleted functions must NOT exist:
for func in moira_bootstrap_match_preset _extract_scan_value
             _extract_table_value _extract_preset_field:
  assert: function NOT in bootstrap.sh
```

#### Install verification test (updated)

```
# Preset verification removed — replace with:
# Scanner templates exist (already tested above, no preset check needed)
# Remove: generic.yaml stack preset check from install.sh verify()
```

## Success Criteria

1. `/moira:init` on a SvelteKit project produces correct config — no React artifacts
2. `/moira:init` on a Go project produces correct config — only genuinely undetectable fields omitted (no `unknown` from generic preset)
3. `/moira:init` on a Python Django project (no preset existed before) produces correct config
4. `bootstrap.sh` contains zero `grep`/`sed` calls for parsing scanner output (frontmatter parser only)
5. All 4 scanner templates include frontmatter contract in their Output Format section
6. `stack-presets/` directory is removed from source and not created by scaffold/install
7. `config.schema.yaml` `project.stack` accepts free-form string (type: string)
8. `conventions.yaml` includes `structure:` section when structure scanner detects `dir_*` patterns
9. All Tier 1 tests pass
10. BUG-1 (zsh) fixed in `bootstrap.sh`, `yaml-utils.sh`, `knowledge.sh`
