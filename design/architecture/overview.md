# Architecture Overview

## Three-Layer Architecture

```
┌─────────────────────────────────────────────────┐
│              GLOBAL LAYER (~/.claude/)           │
│  Orchestrator core, agent templates, bootstrap   │
│  engine, reflection engine, pipeline definitions │
└──────────────────────┬──────────────────────────┘
                       │ generates
┌──────────────────────▼──────────────────────────┐
│           PROJECT LAYER (.claude/moira/)          │
│  Project-specific agents, rules, conventions,    │
│  knowledge base, state machine                   │
└──────────────────────┬──────────────────────────┘
                       │ executes via
┌──────────────────────▼──────────────────────────┐
│              EXECUTION LAYER (agents)            │
│  Classifier, Explorer, Analyst, Architect,       │
│  Planner, Implementer, Reviewer, Tester,         │
│  Reflector, Auditor                              │
└─────────────────────────────────────────────────┘
```

## Global Layer

Installed once. Project-independent. Contains:

- **Orchestrator skill** — the brain of the system, pipeline executor
- **Pipeline definitions** — deterministic execution routes per task size
- **Core agent templates** — base prompts for each agent role
- **Bootstrap engine** — project analysis and configuration generator
- **Reflection engine templates** — post-task and periodic analysis
- **Quality criteria** — universal code quality standards (SOLID, KISS, DRY, security, performance)
- **Audit engine** — system self-verification

## Project Layer

Generated per project via `/moira init`. Project-specific:

- **Adapted agents** — agent templates customized for project stack/conventions
- **Project rules** — stack, conventions, patterns, boundaries
- **Knowledge base** — project model, decisions, patterns, failures, quality map
- **MCP registry** — configured MCP tools with usage guidelines
- **Task state** — current/queued tasks, execution manifests, locks
- **Metrics** — per-task and aggregated performance data

## Execution Layer

Agents that do the actual work. Each agent:

1. Receives assembled instructions (Layer 1-4 rules + task-specific context)
2. Reads only authorized files (scoped by instructions)
3. Writes detailed results to state files
4. Returns ONLY a status summary to orchestrator

## Data Flow

```
User → /moira <task>
  │
  Orchestrator reads: pipeline definition + task state
  Orchestrator spawns: Classifier agent
  │
  Classifier reads: project-model summary, task description
  Classifier writes: .claude/moira/state/tasks/{id}/classification.md
  Classifier returns: "STATUS: success | SUMMARY: medium task | NEXT: explore+analyze"
  │
  Orchestrator reads: classifier summary (not full file)
  Orchestrator presents: classification to user → GATE
  │
  ... pipeline continues ...
  │
  Orchestrator context stays minimal (summaries only)
  All detailed work happens in agent contexts (isolated)
```

## File Structure

### Global Layer (`~/.claude/`)

```
~/.claude/
├── moira/                             # Core system (installed once)
│   ├── .version
│   ├── core/
│   │   ├── rules/
│   │   │   ├── base.yaml              # Layer 1: inviolable + overridable rules
│   │   │   ├── roles/                 # Layer 2: per-agent role rules (D-034 Greek names)
│   │   │   │   ├── apollo.yaml        # Classifier
│   │   │   │   ├── hermes.yaml        # Explorer
│   │   │   │   ├── athena.yaml        # Analyst
│   │   │   │   ├── metis.yaml         # Architect
│   │   │   │   ├── daedalus.yaml      # Planner
│   │   │   │   ├── hephaestus.yaml    # Implementer
│   │   │   │   ├── themis.yaml        # Reviewer
│   │   │   │   ├── aletheia.yaml      # Tester
│   │   │   │   ├── mnemosyne.yaml     # Reflector
│   │   │   │   └── argus.yaml         # Auditor
│   │   │   └── quality/
│   │   │       ├── q1-completeness.yaml
│   │   │       ├── q2-soundness.yaml
│   │   │       ├── q3-feasibility.yaml
│   │   │       ├── q4-correctness.yaml
│   │   │       └── q5-coverage.yaml
│   │   ├── response-contract.yaml
│   │   ├── knowledge-access-matrix.yaml
│   │   ├── pipelines/                 # Pipeline definitions (D-035)
│   │   │   ├── quick.yaml
│   │   │   ├── standard.yaml
│   │   │   ├── full.yaml
│   │   │   └── decomposition.yaml
│   │   └── xref-manifest.yaml         # Cross-reference dependency map (D-077)
│   ├── skills/
│   │   ├── orchestrator.md            # Main orchestrator skill
│   │   ├── gates.md                   # Gate presentation templates
│   │   ├── dispatch.md                # Agent dispatch instructions
│   │   ├── errors.md                  # Error handling procedures
│   │   └── reflection.md             # Reflection engine skill
│   ├── statusline/
│   │   └── context-status.sh          # Claude Code status line (context tracking)
│   ├── hooks/
│   │   ├── guard.sh                   # PostToolUse violation detection (D-031)
│   │   └── budget-track.sh            # Context budget logging
│   ├── templates/
│   │   ├── project-claude-md.tmpl
│   │   ├── budgets.yaml.tmpl
│   │   ├── scanners/                  # Scanner instruction templates
│   │   │   └── deep/                  # Deep scan templates
│   │   ├── reflection/                # Reflection templates (background, deep, lightweight, epic)
│   │   ├── judge/                     # LLM-judge rubric templates (feature, bugfix, refactor)
│   │   └── audit/                     # Audit instruction templates (12 domain-depth templates)
│   ├── schemas/                       # YAML schema definitions
│   │   ├── budgets.schema.yaml
│   │   ├── config.schema.yaml
│   │   ├── current.schema.yaml
│   │   ├── findings.schema.yaml
│   │   ├── locks.schema.yaml
│   │   ├── manifest.schema.yaml
│   │   ├── queue.schema.yaml
│   │   ├── status.schema.yaml
│   │   ├── telemetry.schema.yaml
│   │   ├── mcp-registry.schema.yaml
│   │   ├── metrics.schema.yaml
│   │   └── audit.schema.yaml
│   └── lib/
│       ├── bootstrap.sh
│       ├── bench.sh
│       ├── budget.sh
│       ├── knowledge.sh
│       ├── quality.sh
│       ├── rules.sh
│       ├── scaffold.sh
│       ├── settings-merge.sh
│       ├── state.sh
│       ├── task-id.sh
│       ├── yaml-utils.sh
│       ├── mcp.sh
│       ├── reflection.sh
│       ├── judge.sh
│       ├── metrics.sh
│       ├── audit.sh
│       ├── bench.sh
│       └── retry.sh
│
├── commands/moira/                    # User-facing slash commands (D-030)
│   ├── init.md                        # /moira:init
│   ├── task.md                        # /moira — main entry point
│   ├── status.md                      # /moira:status
│   ├── bypass.md                      # /moira:bypass
│   ├── resume.md                      # /moira:resume
│   └── ...
│
└── settings.json                      # Hooks + statusline registration (merge)
```

### Project Layer (`.claude/moira/`)

```
.claude/moira/
├── config.yaml                    # Project configuration
├── core/
│   └── rules/
│       ├── base.yaml              # Layer 1: project-adapted copy (base from global, customizable by init)
│       ├── roles/                 # Layer 2: per-agent role rules (D-034 Greek names)
│       │   ├── apollo.yaml        # Classifier
│       │   ├── hermes.yaml        # Explorer
│       │   ├── athena.yaml        # Analyst
│       │   ├── metis.yaml         # Architect
│       │   ├── daedalus.yaml      # Planner
│       │   ├── hephaestus.yaml    # Implementer
│       │   ├── themis.yaml        # Reviewer
│       │   ├── aletheia.yaml      # Tester
│       │   ├── mnemosyne.yaml     # Reflector
│       │   └── argus.yaml         # Auditor
│       └── quality/
│           ├── q1-completeness.yaml
│           ├── q2-soundness.yaml
│           ├── q3-feasibility.yaml
│           ├── q4-correctness.yaml
│           └── q5-coverage.yaml
│
├── project/
│   └── rules/
│       ├── stack.yaml             # Layer 3: detected stack (from bootstrap)
│       ├── conventions.yaml       # Layer 3: coding conventions
│       ├── patterns.yaml          # Layer 3: project patterns
│       └── boundaries.yaml        # Layer 3: off-limits areas

├── config/
│   ├── mcp-registry.yaml         # MCP tools registry
│   ├── budgets.yaml              # Context budget allocations
│   └── locks.yaml                # File reservation locks (committed for cross-developer visibility, D-033)
│
├── knowledge/
│   ├── project-model/
│   │   ├── index.md              # L0: section list
│   │   ├── summary.md            # L1: key facts
│   │   └── full.md               # L2: complete model
│   ├── conventions/
│   │   ├── index.md
│   │   ├── summary.md
│   │   └── full.md
│   ├── decisions/
│   │   ├── index.md
│   │   ├── summary.md
│   │   ├── full.md
│   │   └── archive/              # Rotated old decisions
│   ├── patterns/
│   │   ├── index.md
│   │   ├── summary.md
│   │   └── full.md
│   ├── failures/
│   │   ├── index.md
│   │   ├── summary.md
│   │   └── full.md
│   ├── quality-map/              # No L0 index — quality-map has no index level
│   │   ├── summary.md
│   │   └── full.md
│   └── libraries/                # Cached MCP documentation for project dependencies
│
├── state/
│   ├── current.yaml              # Current task state machine
│   ├── queue.yaml                # Task queue (for epics)
│   ├── bypass-log.yaml           # Escape hatch usage log
│   ├── budget-accuracy.yaml      # Budget estimation accuracy tracking
│   ├── retry-stats.yaml          # Retry outcome statistics
│   ├── audit-pending.yaml        # Pending audit trigger flag
│   ├── tasks/
│   │   └── {task-id}/
│   │       ├── input.md          # Original task description
│   │       ├── manifest.yaml     # Execution manifest (for resume)
│   │       ├── classification.md
│   │       ├── exploration.md
│   │       ├── requirements.md
│   │       ├── architecture.md
│   │       ├── plan.md
│   │       ├── review.md
│   │       ├── tests.md
│   │       ├── reflection.md
│   │       ├── status.yaml
│   │       ├── telemetry.yaml
│   │       ├── findings/         # Quality gate findings
│   │       └── instructions/     # Assembled agent instructions
│   │           ├── explorer.md
│   │           ├── implementer-A.md
│   │           └── ...
│   ├── reflection/
│   │   ├── pattern-keys.yaml         # Pattern key registry (D-089, gitignored)
│   │   ├── deep-reflection-counter.yaml  # Counter for periodic deep reflection (D-092)
│   │   └── proposals.yaml            # Pending rule change proposals
│   ├── violations.log
│   ├── tool-usage.log
│   ├── budget-tool-usage.log
│   ├── init/
│   ├── metrics/
│   │   └── monthly-{YYYY-MM}.yaml
│   └── audits/
│       ├── {date}-audit.md
│       ├── {date}-audit.yaml
│       └── {date}-{domain}.yaml
│
└── hooks/                        # Hook executables live at global layer; registered via settings.json
```

## Orchestrator Boundaries

### DOES:
- Dispatch agents (parallel or sequential per pipeline)
- Read state files and agent summaries
- Present gates to user
- Track pipeline progress
- Handle errors (retry, escalate, abort)

### DOES NOT (enforced by `allowed-tools` + PostToolUse hook, D-031):
- Read project source files (prevented by `allowed-tools` exclusion)
- Write/edit project source files (prevented by `allowed-tools` exclusion)
- Run bash commands (prevented by `allowed-tools` exclusion)
- Use Grep/Glob on project files (prevented by `allowed-tools` exclusion)
- Make architectural decisions
- Rationalize bypassing pipeline steps
