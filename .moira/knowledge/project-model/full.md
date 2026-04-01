<!-- moira:freshness init 2026-04-01 -->
<!-- moira:knowledge project-model L2 -->

---
layout_pattern: single-app
source_root: src
entry_points:
  - src/install.sh
  - src/cli/moira
test_pattern: separate
test_roots:
  - src/tests
test_naming: "test-*.sh"
do_not_modify:
  - .ariadne/
  - .git/
  - node_modules/
modify_with_caution:
  - CLAUDE.md
  - .claude/settings.json
  - .claude/settings.local.json
  - .mcp.json
  - src/install.sh
dir_components: src/global/
dir_pages: src/commands/
---

## Project Root

```
.ariadne/          — Ariadne graph engine cache (gitignored, generated)
.claude/           — Claude Code configuration and Moira runtime
.git/              — Git repository
.githooks/         — Git hooks (commit-msg, pre-commit)
.gitignore         — Git ignore rules
.mcp.json          — MCP server configuration (Ariadne)
.vscode/           — VS Code settings (gitignored)
AGENTS.md          — Agent definitions reference (Claude Code convention)
CLAUDE.md          — Project instructions for Claude Code
README.md          — Project documentation
design/            — Design documents (source of truth)
src/               — Implementation source
```

## Source Layout

```
src/
  .version             — Version file (currently 0.3.0)
  install.sh           — Main installer script (entry point)
  remote-install.sh    — Remote installation script
  cli/
    moira              — CLI entry point (shell script, 38k)
  commands/
    moira/             — Slash command definitions (markdown)
      audit.md, bench.md, bypass.md, graph.md, health.md,
      help.md, init.md, knowledge.md, metrics.md, refresh.md,
      resume.md, status.md, task.md, upgrade.md
  global/
    core/
      pipelines/       — Pipeline definitions (YAML): analytical, decomposition, full, quick, standard
      rules/
        base.yaml      — Base rules
        quality/       — Quality checklist rules (q1-q5, qa1-qa4)
        roles/         — Agent role definitions (YAML): aletheia, apollo, argus, athena, calliope, daedalus, hephaestus, hermes, metis, mnemosyne, themis
      knowledge-access-matrix.yaml
      response-contract.yaml
      xref-manifest.yaml
    hooks/             — Runtime hooks (shell scripts, 17 files)
    lib/               — Shared shell libraries (26 files)
    skills/            — Orchestrator skill definitions (markdown, 6 files)
    statusline/        — Status line display (context-status.sh)
    templates/
      audit/           — Audit templates (deep/standard/light variants)
      judge/           — Judge prompt template
      knowledge/       — Knowledge base templates (7 domains, 3 tiers each)
      reflection/      — Reflection templates (background, deep, epic, lightweight)
      scanners/        — Scanner templates (convention, mcp, pattern, structure, tech + deep/)
  schemas/             — YAML schema definitions (13 files)
  tests/
    bench/             — Tier 2/3 benchmark tests
      calibration/     — Calibration fixtures (good/mediocre/poor implementation)
      cases/           — Test cases (YAML, 9 files)
      fixtures/        — Project fixtures (greenfield/legacy/mature webapps)
      rubrics/         — Scoring rubrics (bugfix, feature, refactor)
      tier2-config.yaml
      tier3-config.yaml
    tier1/             — Tier 1 shell tests (37 test files + run-all.sh + test-helpers.sh)
```

## Directory Roles

| Directory | Role |
|-----------|------|
| `src/cli/moira` | Main CLI entry point; shell script dispatching commands |
| `src/commands/moira/` | Claude Code slash command definitions (markdown prompt files) |
| `src/global/core/rules/roles/` | Agent role definitions (one YAML per agent) |
| `src/global/core/pipelines/` | Pipeline state machine definitions (YAML) |
| `src/global/core/rules/quality/` | Quality gate checklist items (YAML) |
| `src/global/hooks/` | Claude Code hooks for pipeline enforcement (shell scripts) |
| `src/global/lib/` | Shared shell library functions used by hooks, CLI, and tests |
| `src/global/skills/` | Orchestrator skills (dispatch, gates, reflection, etc.) |
| `src/global/templates/` | Prompt templates for scanners, audits, reflection, knowledge |
| `src/schemas/` | YAML schema definitions for config, state, metrics, etc. |
| `src/tests/` | All tests (tier1 shell tests, tier2/3 benchmarks) |
| `design/` | Design documents, architecture specs, decision log, reports |
| `design/architecture/` | Architecture documents (agents, pipelines, rules, etc.) |
| `design/decisions/` | Architectural decision log |
| `design/subsystems/` | Subsystem design documents |
| `design/specs/` | Phase implementation specs and plans |
| `design/reports/` | Audit and review reports |
| `design/guides/` | Developer guides |
| `.claude/` | Claude Code configuration, settings, installed Moira runtime |
| `.claude/commands/` | Claude Code custom commands (system-audit, review-*, fix-audit) |
| `.githooks/` | Git hooks (pre-commit, commit-msg) |

## Generated (do not modify)

| Path | Purpose |
|------|---------|
| `.ariadne/` | Ariadne dependency graph cache; regenerated by `ariadne` CLI |
| `.moira/state/` | Moira runtime state; gitignored, generated per session |
| `.git/` | Git internals |

## Vendored (do not modify)

No vendored third-party code detected. The project contains no `vendor/`, `third_party/`, or `node_modules/` directories.

## Configuration

| File | Purpose |
|------|---------|
| `.mcp.json` | MCP server configuration; registers Ariadne graph server |
| `.gitignore` | Excludes `.ariadne/`, `.moira/state/`, `.vscode/`, `node_modules/`, `tmp/`, `.DS_Store` |
| `.claude/settings.json` | Claude Code project settings (hooks, permissions) |
| `.claude/settings.local.json` | Local Claude Code settings overrides |
| `.claude/CLAUDE.md` | Project instructions for orchestrator boundary enforcement |
| `CLAUDE.md` | Root project instructions for Claude Code |
| `AGENTS.md` | Agent definitions reference |
| `src/.version` | Version identifier: `0.3.0` |
| `.vscode/settings.json` | VS Code editor settings |
| `.githooks/pre-commit` | Git pre-commit hook |
| `.githooks/commit-msg` | Git commit message hook |

## Test Organization

- **Pattern**: Separate test directory (`src/tests/`), not co-located with source
- **Tier 1** (`src/tests/tier1/`): 37 shell-based test scripts; naming pattern `test-*.sh`; runner `run-all.sh`
- **Tier 2** (`src/tests/bench/`): Benchmark test cases in YAML with project fixtures; config at `tier2-config.yaml`
- **Tier 3** (`src/tests/bench/`): Complex scenario tests in YAML; config at `tier3-config.yaml`
- **Calibration** (`src/tests/bench/calibration/`): Three calibration fixtures (good/mediocre/poor) with expected outputs for benchmark scoring validation
- **Fixtures** (`src/tests/bench/fixtures/`): Three mock webapp projects (greenfield, legacy, mature) used as test targets
- **Rubrics** (`src/tests/bench/rubrics/`): Scoring rubrics for bugfix, feature-implementation, refactor test types
- **Helper**: `src/tests/tier1/test-helpers.sh` provides shared test utilities

### Not found

- No unit test framework detected (no Jest, pytest, Go test, etc.); all tests are shell scripts
- No CI/CD configuration files detected (no `.github/workflows/`, no `.gitlab-ci.yml`, no `Makefile`)
- No `package.json` or dependency manifest at root level (only in test fixtures)
- No `Dockerfile` or container configuration

## Structural Bottlenecks

| File | Centrality Score |
|------|-----------------|
| .claude/CLAUDE.md | 0.0 |
| .claude/commands/fix-audit.md | 0.0 |
| .claude/commands/review-architecture.md | 0.0 |
| .claude/commands/review-plan.md | 0.0 |
| .claude/commands/review-spec.md | 0.0 |
| .claude/commands/system-audit.md | 0.0 |
| .moira/config.yaml | 0.0 |
| .moira/config/budgets.yaml | 0.0 |
| .moira/knowledge/conventions/full.md | 0.0 |
| .moira/knowledge/conventions/index.md | 0.0 |
| .moira/knowledge/conventions/summary.md | 0.0 |
| .moira/knowledge/decisions/full.md | 0.0 |
| .moira/knowledge/decisions/index.md | 0.0 |
| .moira/knowledge/decisions/summary.md | 0.0 |
| .moira/knowledge/failures/full.md | 0.0 |

## Architectural Layers

| Layer | Files |
|-------|-------|
| 00000 | .claude/CLAUDE.md, .claude/commands/fix-audit.md, .claude/commands/review-architecture.md, .claude/commands/review-pl... |
| 00001 | src/tests/bench/fixtures/greenfield-webapp/src/index.ts, src/tests/bench/fixtures/legacy-webapp/src/app.js, src/tests... |
| 00002 | src/tests/bench/fixtures/mature-webapp/src/routes/products.ts, src/tests/bench/fixtures/mature-webapp/src/routes/user... |
| 00003 | src/tests/bench/fixtures/mature-webapp/src/index.ts |

## Cluster Metrics

| Cluster | Instability | Abstractness | Distance | Zone |
|---------|-------------|-------------|----------|------|
| .claude | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| commands | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| design | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| global | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| root | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| schemas | 0.0 | 0.0 | 1.0 | ZoneOfPain |
| tests | 0.0 | 0.0339 | 0.9661 | ZoneOfPain |

## Architectural Boundaries

(no boundary data available)

## Graph Summary

- Nodes: 299
- Edges: 57
- Clusters: 7
- Cycles: 0
- Smells: 6
- Monolith score: 0
- Temporal: available

