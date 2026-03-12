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

## Output Format

Write your findings as structured markdown using EXACTLY this format:

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
- If a category has no data, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
- Use approximate file counts — do NOT count every file individually
