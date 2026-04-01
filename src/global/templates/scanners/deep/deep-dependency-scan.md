# Deep Scanner: Dependency Analysis
# Agent: Hermes (explorer)
# Phase: Background deep scan (triggered on first task after bootstrap)

## Objective

Perform a comprehensive dependency analysis of this project. Identify:

1. **Package versions** — all declared dependencies with their versions
2. **Outdated packages** — packages with significantly old versions (compare declared versions against common knowledge)
3. **Unused imports** — packages declared in manifest but never imported in source code
4. **Circular dependencies** — import chains that form cycles between modules
5. **Duplicate functionality** — multiple packages serving the same purpose

## Pre-Context (Ariadne Data)

Review cycles, coupling, and centrality data for dependency hotspots.

Pre-context data available at `.claude/moira/state/init/ariadne-context.md`. Read that file FIRST for structural context.

If the pre-context file does not exist or is a placeholder, proceed with full manual scanning as before.

## Scan Strategy

Read up to 50 files. Focus on dependency declarations and import statements.

1. **Package manifests** (read fully):
   - `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `requirements.txt`, `Pipfile`
   - Lock files: check existence and format, but do NOT read entire lock file

2. **Import scanning** (sample representative files):
   - Read 20-30 source files across the project
   - Collect all import/require statements
   - Build a list of actually-used packages

3. **Internal module imports** (trace import chains):
   - Read entry points and follow import chains 3-4 levels deep
   - Look for circular patterns (A imports B, B imports C, C imports A)

4. **Configuration files** that reference dependencies:
   - Build configs, plugin configs, test configs

## Output Format

Write findings as structured markdown:

```markdown
<!-- moira:deep-scan dependencies {date} -->

## Deep Scan: Dependencies

### Package Inventory
| Package | Declared Version | Type | Status |
|---------|-----------------|------|--------|
| {name} | {version} | {prod/dev} | {current/outdated/unknown} |

### Potentially Unused Packages
- {package}: declared in {manifest}, no imports found in scanned source files
  - Note: may be used indirectly (CLI tool, plugin, peer dependency)

### Circular Dependencies
- {module A} → {module B} → {module C} → {module A}
  - Files: {file paths}

### Duplicate Functionality
- {purpose}: {package1} and {package2} both provide {functionality}

### Observations
- {any notable dependency patterns}
```

## Output Path

Enhance existing file: `.claude/moira/knowledge/dependencies/full.md`

Prepend your findings as a new section. Do NOT replace existing content — add to it.

## Constraints

- Report ONLY observed facts with file path evidence
- NEVER propose solutions
- NEVER express opinions
- NEVER make recommendations
- NO opinions, NO recommendations, NO proposals
- If information is not found, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens
- Do NOT read files outside the project directory
- Do NOT execute any commands
- Do NOT modify any project files
