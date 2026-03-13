# Scanner: Project Structure Mapping
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective

Map the project's directory layout and organization:

1. **Top-level structure** — all directories and files at root
2. **Source directory layout** — depth 2 for each source directory
3. **Entry points** — main application entry files
4. **Generated directories** — build output, caches (should not be modified)
5. **Vendored directories** — third-party code checked into repo
6. **Configuration files** — config files at root with their purpose
7. **Test organization** — test root, naming pattern, co-located vs separate

## Scan Strategy

1. List top-level directories and files (depth 1)
2. For each source directory: list depth 2
3. Identify entry points: `src/index.*`, `src/main.*`, `src/app.*`, `main.*`, `cmd/`
4. Identify generated directories: `dist/`, `build/`, `.next/`, `__pycache__/`, `node_modules/`
5. Identify vendored directories: `vendor/`, `third_party/`
6. Identify test roots
7. Count files per top-level directory (rough sizing)
8. After mapping directory roles, identify recurring file placement patterns. If 3+ files of the same type exist in a directory, record as `dir_{role}: {path}/` in frontmatter

## Output Format

Start output with a YAML frontmatter block between `---` delimiters. Fields you cannot determine — omit entirely.

After the second `---`, write the detailed markdown report.

### Frontmatter Contract

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

**Scalar fields:** `layout_pattern`, `source_root`, `test_pattern`, `test_naming`.

**List fields** (use `  - ` items): `entry_points`, `test_roots`, `do_not_modify`, `modify_with_caution`.

**Directory convention fields** (`dir_*`): file placement patterns detected from recurring directory structures. If 3+ files of the same type exist in a directory, record as `dir_{role}: {path}/`. Standard keys: `dir_components`, `dir_pages`, `dir_api`, `dir_services`, `dir_types`, `dir_utils`. Additional keys are allowed (e.g., `dir_hooks`, `dir_stores`, `dir_middleware`). Omit any `dir_*` field you cannot determine.

All values are plain strings. Omit any field you cannot determine.

### Markdown Body

After the frontmatter, write the detailed report using this format:

```markdown
## Project Root
{annotated top-level directory listing with brief description per entry}

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
{list of directories that are build output or caches}

## Vendored (do not modify)
{list of directories containing third-party code}

## Configuration
{list of config files at root with purpose}

## Test Organization
- Pattern: {co-located/separate/both}
- Test root(s): {paths}
- Naming: {*.test.ts/*.spec.ts/*_test.go/test_*.py}
```

## Output Path

Write the complete output to: `.claude/moira/state/init/structure-scan.md`

## Constraints

- Report ONLY observed facts with file path evidence
- Never propose solutions
- Never express opinions
- Never make recommendations
- NO opinions, NO recommendations, NO proposals
- Do NOT write `Not detected` or `unknown` in frontmatter — omit the field
- In the markdown body, write "Not detected" for empty categories — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
- Use approximate file counts — do NOT count every file individually
