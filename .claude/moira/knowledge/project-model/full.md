<!-- moira:freshness refresh 2026-03-23 -->
<!-- moira:knowledge project-model L2 -->

---
layout_pattern: single-app
source_root: src
entry_points:
  - src/install.sh
test_pattern: separate
test_roots:
  - src/tests
test_naming: "test-*.sh"
do_not_modify:
  - .ariadne/
  - .git/
  - design/CONSTITUTION.md
modify_with_caution:
  - CLAUDE.md
  - .gitignore
  - .githooks/
dir_commands: src/commands/moira/
dir_schemas: src/schemas/
dir_lib: src/global/lib/
dir_skills: src/global/skills/
dir_hooks: src/global/hooks/
dir_pipelines: src/global/core/pipelines/
dir_roles: src/global/core/rules/roles/
dir_quality_rules: src/global/core/rules/quality/
dir_templates: src/global/templates/
dir_tests_tier1: src/tests/tier1/
dir_design_arch: design/architecture/
dir_design_subsystems: design/subsystems/
dir_knowledge: .claude/moira/knowledge/
dir_state: .claude/moira/state/
---

# Moira Project Structure Scan

## Project Root

```
/Users/minddecay/Documents/Projects/Moira/
  .ariadne/          # Dependency graph data (JSON)
  .claude/           # Claude Code configuration and Moira runtime state
  .git/              # Git repository
  .githooks/         # Git hooks (commit-msg, pre-commit)
  .gitignore         # Git ignore rules
  AGENTS.md          # Agent definitions for Claude Code
  CLAUDE.md          # Claude Code project instructions
  README.md          # Project readme
  .mcp.json          # MCP server configuration (ariadne)
  design/            # Design documents (source of truth) — ~88 files
  src/               # Implementation source — ~225 files
```

## Source Layout (`src/`)

```
src/
  .version                    # Version file (contents: version string)
  .version                    # Version file (contents: version string)
  install.sh                  # Main installer script (18KB, executable)
  remote-install.sh           # Remote/curl-based installer (1.3KB)
  commands/
    moira/                    # Slash commands (14 markdown files)
      audit.md, bench.md, bypass.md, graph.md, health.md, help.md,
      init.md, knowledge.md, metrics.md, refresh.md, resume.md,
      status.md, task.md, upgrade.md
  global/
    core/
      knowledge-access-matrix.yaml
      response-contract.yaml
      xref-manifest.yaml
      pipelines/              # Pipeline definitions (5 YAML files)
        analytical.yaml, decomposition.yaml, full.yaml, quick.yaml, standard.yaml
      rules/
        base.yaml
        quality/              # Quality rule definitions (9 YAML files: q1-q5, qa1-qa4)
          q1-completeness.yaml .. q5-coverage.yaml, qa1-audit.yaml .. qa4-audit.yaml
        roles/                # Agent role definitions (11 YAML files)
          aletheia.yaml, apollo.yaml, argus.yaml, athena.yaml,
          calliope.yaml, daedalus.yaml, hephaestus.yaml, hermes.yaml,
          metis.yaml, mnemosyne.yaml, themis.yaml
    hooks/                    # Runtime hooks (2 shell scripts)
      budget-track.sh, guard.sh
    lib/                      # Shell library functions (22 shell scripts)
      audit.sh, bench.sh, bootstrap.sh, budget.sh, checkpoint.sh,
      completion.sh, epic.sh, graph.sh, judge.sh, knowledge.sh, mcp.sh,
      metrics.sh, quality.sh, reflection.sh, retry.sh, rules.sh,
      scaffold.sh, settings-merge.sh, state.sh, task-id.sh, upgrade.sh,
      yaml-utils.sh
    skills/                   # Skill definitions (6 markdown files)
      completion.md, dispatch.md, errors.md, gates.md, orchestrator.md,
      reflection.md
    statusline/
      context-status.sh
    templates/                # Templates for scaffolding
      budgets.yaml.tmpl
      project-claude-md.tmpl
      audit/                  # Audit templates
      judge/                  # Judge templates
      knowledge/              # Knowledge tier templates (7 subdirs)
        conventions/, decisions/, failures/, libraries/,
        patterns/, project-model/, quality-map/
      reflection/             # Reflection templates
      scanners/               # Scanner templates
        deep/
  schemas/                    # YAML schema definitions (12 files)
    audit.schema.yaml, budgets.schema.yaml, config.schema.yaml,
    current.schema.yaml, findings.schema.yaml, locks.schema.yaml,
    manifest.schema.yaml, mcp-registry.schema.yaml, metrics.schema.yaml,
    queue.schema.yaml, status.schema.yaml, telemetry.schema.yaml
  tests/
    bench/                    # Benchmark/tier2-3 test configs (2 YAML files)
      tier2-config.yaml, tier3-config.yaml
    tier1/                    # Tier 1 tests (26 shell scripts)
      run-all.sh              # Test runner
      test-helpers.sh         # Shared test helpers
      test-*.sh               # Individual test files (24 test scripts)
```

## Design Layout (`design/`)

```
design/
  CONSTITUTION.md             # Inviolable invariants (NEVER modify)
  SYSTEM-DESIGN.md            # Index of all design documents
  IMPLEMENTATION-GUIDE.md     # Implementation guide
  IMPLEMENTATION-ROADMAP.md   # Phase-based implementation roadmap
  architecture/               # Architecture design docs (12 files)
    agents.md, analytical-pipeline.md, commands.md, distribution.md,
    escape-hatch.md, naming.md, onboarding.md, overview.md,
    pipelines.md, rules.md, tweak-redo.md
  decisions/
    log.md                    # Architectural decision log
  guides/
    metrics-guide.md
  reports/                    # Audit and review reports
    2026-03-19-architecture-review.md
    2026-03-19-first-task-session.md
    archive/                  # Archived reports (~5+ files)
  specs/                      # Phase implementation specs
    post-v1-backlog.md
    archive/                  # Archived specs (~5+ files)
  subsystems/                 # Subsystem design docs (12 files)
    audit.md, checkpoint-resume.md, context-budget.md,
    fault-tolerance.md, knowledge.md, mcp.md, metrics.md,
    multi-developer.md, project-graph.md, quality.md,
    self-monitoring.md, self-protection.md, testing.md
```

## `.claude/` Layout (Runtime Configuration)

```
.claude/
  commands/                   # Claude Code slash commands (installed)
    fix-audit.md, review-architecture.md, review-plan.md,
    review-spec.md, system-audit.md
  moira/                      # Moira runtime directory
    config/
      budgets.yaml            # Budget configuration
    core/
      rules/
        quality/              # (empty — populated at runtime)
        roles/                # (empty — populated at runtime)
    hooks/                    # (empty — populated at runtime)
    knowledge/                # Knowledge base (10 categories)
      architecture/           # full.md
      conventions/            # full.md, index.md, summary.md
      decisions/              # full.md, index.md, summary.md, archive/
      dependencies/           # full.md
      failures/               # full.md, index.md, summary.md
      libraries/              # index.md, summary.md
      patterns/               # full.md, index.md, summary.md, archive/
      project-model/          # full.md, index.md, summary.md
      quality-map/            # full.md, summary.md
      security/               # full.md
      testing/                # full.md
    project/
      rules/                  # (empty — project-specific rules)
    state/
      audits/                 # (empty — runtime)
      init/                   # (this scan output goes here)
      metrics/                # (empty — runtime)
      reflection/             # (empty — runtime)
      tasks/                  # (empty — runtime)
```

## Entry Points

- `src/install.sh` — main installer script (18KB, executable). Installs Moira into a target project by scaffolding `.claude/moira/` directory structure, copying rules, hooks, templates, and commands.
- `src/remote-install.sh` — curl-based remote installer (1.3KB).

No `src/index.*`, `src/main.*`, `src/app.*`, `main.*`, or `cmd/` entry points detected. The project is shell-script-based with no compiled application entry point.

## Generated Directories

Not detected. No `dist/`, `build/`, `.next/`, `__pycache__/`, or `node_modules/` directories exist.

The `.claude/moira/state/` directory contains runtime-generated state that is gitignored (tasks, locks, current state, queue, budget log).

## Vendored Directories

Not detected. No `vendor/` or `third_party/` directories exist.

## Configuration Files

| File | Purpose |
|------|---------|
| `.gitignore` | Ignores OS files, IDE files, node_modules, Moira runtime state, worktrees, tmp files |
| `CLAUDE.md` | Claude Code project instructions — development rules, prohibitions, change risk classification, commit conventions |
| `AGENTS.md` | Agent definitions for Claude Code subagent dispatch |
| `.githooks/pre-commit` | Pre-commit hook (3.5KB) |
| `.githooks/commit-msg` | Commit message validation hook (1.6KB) |

## Test Organization

- **Test root:** `src/tests/`
- **Pattern:** Separate test directory (not co-located with source)
- **Naming convention:** `test-*.sh` (shell scripts)
- **Test runner:** `src/tests/tier1/run-all.sh`
- **Test helpers:** `src/tests/tier1/test-helpers.sh`
- **Tier structure:**
  - `tier1/` — 24 individual test scripts (shell-based, fast, structural)
  - `bench/` — tier2 and tier3 config files (YAML configs for higher-tier testing)
- **Test count:** 24 test scripts in tier1

## Technology Stack

- **Primary language:** Shell (bash) — all lib, hooks, tests, and installer
- **Configuration format:** YAML (schemas, rules, pipelines, budgets)
- **Agent/command definitions:** Markdown
- **No package manager** detected (no package.json, Cargo.toml, go.mod, requirements.txt, etc.)
- **No build system** detected (no Makefile, Taskfile, justfile, etc.)

## `.ariadne/` Directory

Contains pre-computed dependency graph data:
- `graph/clusters.json` (1.4KB)
- `graph/graph.json` (7.5KB)
- `graph/raw_imports.json` (4.4KB)
- `graph/stats.json` (3.0KB)

This appears to be generated analysis data and should not be manually modified.
