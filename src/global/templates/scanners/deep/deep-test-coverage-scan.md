# Deep Scanner: Test Coverage Assessment
# Agent: Hermes (explorer)
# Phase: Background deep scan (triggered on first task after bootstrap)

## Objective

Perform a comprehensive test coverage assessment. Map which source files have test coverage and identify gaps:

1. **Test file mapping** — which test files cover which source files
2. **Untested files** — source files with no corresponding test coverage
3. **Test quality observations** — brittle tests, missing assertions, test anti-patterns
4. **Test infrastructure** — fixtures, factories, mocks, test utilities
5. **Coverage configuration** — coverage thresholds, excluded paths, report formats

## Pre-Context (Ariadne Data)

Review centrality and hotspots to prioritize test coverage for high-impact files.

Pre-context data available at `.moira/state/init/ariadne-context.md`. Read that file FIRST for structural context.

If the pre-context file does not exist or is a placeholder, proceed with full manual scanning as before.

## Scan Strategy

Read up to 50 files. Map source files to their test counterparts.

1. **Test configuration** (read fully):
   - `jest.config*`, `vitest.config*`, `pytest.ini`, `conftest.py`, `.nycrc`, `karma.conf*`
   - Coverage configuration and thresholds

2. **Test directory structure** (enumerate):
   - List all test files (patterns: `*.test.*`, `*.spec.*`, `__tests__/*`, `test/*`, `tests/*`)
   - Map each test file to its likely source file

3. **Source-to-test mapping** (compare):
   - For each source directory, check if corresponding test files exist
   - Track unmapped source files

4. **Test file sampling** (read 15-20 test files):
   - Check for assertion density (tests with few/no assertions)
   - Check for test isolation (shared mutable state, order dependencies)
   - Check for mock usage patterns (over-mocking, testing implementation details)
   - Check for test naming conventions

5. **Test utilities** (read):
   - Shared fixtures, factories, helpers, test setup files

## Output Format

Write findings as structured markdown:

```markdown
<!-- moira:deep-scan test-coverage {date} -->

## Deep Scan: Test Coverage

### Source-to-Test Mapping
| Source File | Test File | Status |
|------------|-----------|--------|
| {source path} | {test path} | {covered/missing} |

### Untested Files
- {file path}: {brief description of what it does}

### Test Quality Observations
- **{pattern name}**: {description}
  - Location: {file:line}
  - Impact: {why this matters}

### Test Infrastructure
- Fixtures: {location and description}
- Factories: {location and description}
- Mocks: {location and description}
- Test utilities: {location and description}

### Coverage Configuration
- Tool: {jest/istanbul/coverage.py/...}
- Thresholds: {configured thresholds or "none"}
- Excluded: {excluded paths}
```

## Output Path

Enhance existing file: `.moira/knowledge/testing/full.md`

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
