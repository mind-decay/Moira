# Dependency Analysis — 2026-03-22

## 1. Package Versions (Declared Dependencies)

### Moira Core
- **Version:** `0.1.0` (source: `src/.version`)
- **Language/Runtime:** Bash 3.2+ (pure shell, no package manager)
- **External binary dependencies:**
  - `ariadne` — project graph CLI (optional, graceful degradation if absent). Used by `src/global/lib/graph.sh`.
  - `jq` — JSON processing (optional, used opportunistically). Used by `graph.sh`, `settings-merge.sh`, `budget-track.sh`, `guard.sh`.
  - `git` — required by `src/install.sh`, `src/remote-install.sh`
  - `claude` — Claude CLI, required by `src/install.sh`
  - `bash`, `awk`, `sed`, `grep` — standard POSIX utilities used throughout

### Test Fixture: greenfield-webapp (`src/tests/bench/fixtures/greenfield-webapp/package.json`)
| Package | Version | Type |
|---|---|---|
| express | ^4.18.2 | dependency |
| @types/express | ^4.17.21 | devDependency |
| @types/jest | ^29.5.11 | devDependency |
| jest | ^29.7.0 | devDependency |
| ts-jest | ^29.1.1 | devDependency |
| typescript | ^5.3.3 | devDependency |

### Test Fixture: legacy-webapp (`src/tests/bench/fixtures/legacy-webapp/package.json`)
| Package | Version | Type |
|---|---|---|
| express | ^4.17.1 | dependency |
| body-parser | ^1.19.0 | dependency |
| mongoose | ^6.0.0 | dependency |
| jest | ^27.0.0 | devDependency |

### Test Fixture: mature-webapp (`src/tests/bench/fixtures/mature-webapp/package.json`)
| Package | Version | Type |
|---|---|---|
| @prisma/client | ^5.7.0 | dependency |
| express | ^4.18.2 | dependency |
| zod | ^3.22.4 | dependency |
| @types/express | ^4.17.21 | devDependency |
| @types/jest | ^29.5.11 | devDependency |
| eslint | ^8.56.0 | devDependency |
| jest | ^29.7.0 | devDependency |
| prettier | ^3.2.0 | devDependency |
| prisma | ^5.7.0 | devDependency |
| ts-jest | ^29.1.1 | devDependency |
| ts-node-dev | ^2.0.0 | devDependency |
| typescript | ^5.3.3 | devDependency |

## 2. Outdated Packages

Note: No `node_modules/` or lock files exist — these fixtures are static test data, not installed projects. Version staleness is assessed against semver ranges declared at time of scan.

- **legacy-webapp/express ^4.17.1** — older minor range than greenfield/mature (^4.18.2)
- **legacy-webapp/jest ^27.0.0** — two major versions behind greenfield/mature (^29.7.0)
- **legacy-webapp/body-parser ^1.19.0** — bundled into Express since v4.16.0; the standalone package is functionally redundant for Express 4.17+

## 3. Unused/Undeclared Imports

### Undeclared imports (imported in code, absent from package.json)
- **mature-webapp:** `supertest` is imported in `tests/health.test.ts` line 1 (`import request from 'supertest'`) but is NOT declared in `package.json` (neither dependencies nor devDependencies).
  - Evidence: `src/tests/bench/fixtures/mature-webapp/tests/health.test.ts:1`
- **legacy-webapp:** `supertest` is required in `__tests__/health.test.js` line 1 (`const request = require('supertest')`) but is NOT declared in `package.json`.
  - Evidence: `src/tests/bench/fixtures/legacy-webapp/__tests__/health.test.js:1`

### Shell libraries never sourced by other libraries (entry-point only)
These libraries in `src/global/lib/` are never `source`d by other library files — they are only sourced by tests, install scripts, or invoked directly:
- `graph.sh` — sourced only by test files (`test-graph-integration.sh`, `test-graph-e2e.sh`)
- `scaffold.sh` — sourced only by `install.sh` and `test-install.sh`
- `task-id.sh` — sourced only by `test-install.sh`
- `upgrade.sh` — sourced only by `install.sh`
- `epic.sh` — sourced only by `test-epic.sh` (no library or install sourcing found)
- `checkpoint.sh` — sourced only by `test-checkpoint-resume.sh`
- `retry.sh` — not sourced by any other library (standalone)
- `bench.sh` — not sourced by any other library (standalone)

Note: This does not mean these are unused — they may be sourced at runtime by the orchestrator via Bash dispatch. This list reflects static `source` analysis only.

## 4. Circular Dependencies

### Shell library source graph (static analysis)
No circular dependencies detected. The dependency graph is a DAG:

```
yaml-utils.sh          (leaf — no sources)
settings-merge.sh      (leaf — no sources, explicitly documented)
task-id.sh             (leaf — no sources)
scaffold.sh            (leaf — no sources)
upgrade.sh             (leaf — no sources)
graph.sh               (leaf — no sources)

knowledge.sh           -> yaml-utils.sh
mcp.sh                 -> yaml-utils.sh
budget.sh              -> yaml-utils.sh
state.sh               -> yaml-utils.sh, budget.sh (conditional)
audit.sh               -> yaml-utils.sh
metrics.sh             -> yaml-utils.sh, audit.sh (conditional)
quality.sh             -> yaml-utils.sh
judge.sh               -> yaml-utils.sh
reflection.sh          -> yaml-utils.sh
checkpoint.sh          -> yaml-utils.sh
epic.sh                -> yaml-utils.sh
retry.sh               -> yaml-utils.sh
bench.sh               -> yaml-utils.sh, judge.sh

rules.sh               -> yaml-utils.sh, knowledge.sh
bootstrap.sh           -> yaml-utils.sh, knowledge.sh, mcp.sh, settings-merge.sh (conditional)
```

All edges point toward `yaml-utils.sh` as the universal leaf dependency. No back-edges exist.

### Test fixture imports
No circular imports detected in the three fixture projects. All import chains are acyclic.

## 5. Duplicate Functionality

### Observed overlaps in shell libraries
- **YAML parsing:** Centralized in `yaml-utils.sh`. All 14 libraries that need YAML access source this single file. No duplication observed.
- **jq usage:** Both `settings-merge.sh` and `graph.sh` independently check `command -v jq` and fall back to non-jq paths. This is intentional (each library is self-contained with optional jq enhancement), not duplication.
- **`command -v ariadne` checks:** Repeated in `graph.sh` at lines 34, 56, 81, 104, 119, 147, and in `mcp.sh` at line 224. Each function independently gates on the binary. This is defensive design, not accidental duplication.

### Test fixture overlap
- `express` appears in all three fixture package.json files (expected — they are independent test fixtures simulating different project archetypes).
