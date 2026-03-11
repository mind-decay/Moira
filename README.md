# Moira

**Meta-orchestration framework for Claude Code.**

Moira transforms Claude from a code executor into a pure orchestrator. Instead of reading files and writing code directly, Claude dispatches specialized agents through deterministic pipelines — producing predictable, high-quality engineering output.

## How It Works

```
You describe a task
        │
   ┌────▼────┐     ┌─────────┐     ┌──────┐     ┌───────┐     ┌────────┐
   │ Classify │ ──▸ │ Analyze │ ──▸ │ Plan │ ──▸ │ Build │ ──▸ │ Review │
   └─────────┘     └─────────┘     └──────┘     └───────┘     └────────┘
        │               │              │             │              │
   "how big?"     "what's needed?"  "how?"     "write code"   "check quality"
        │               │              │             │              │
      [gate]          [gate]        [gate]                       [gate]
   you confirm     you confirm   you confirm                  you confirm
```

You approve at key checkpoints. Agents do the work. Claude orchestrates — never touches code directly.

## Why Moira

| Without Moira | With Moira |
|---------------|------------|
| Claude reads code, fills its context, starts hallucinating | Claude dispatches agents, context stays clean |
| Unpredictable quality — depends on how much context is left | Deterministic pipelines — same task type, same process |
| No separation of concerns — Claude does everything | 9 specialized agents, each with strict boundaries |
| No quality gates — you review at the end | Quality checked at every step (requirements, architecture, code, tests) |
| Knowledge lost between sessions | Knowledge accumulates, system improves over time |
| Works differently every time | Predictable: good input → good output |

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/moira/main/install.sh | bash
```

Requirements: [Claude Code CLI](https://docs.anthropic.com/claude-code), git, bash. Nothing else.

## Quick Start

```bash
# 1. Open your project
cd my-project

# 2. Start Claude Code
claude

# 3. Initialize Moira for this project
> /moira init

# 4. Run a task
> /moira Add pagination to the products API endpoint
```

That's it. Moira scans your project, detects your stack and conventions, generates project-specific configuration, and you're ready.

## Commands

| Command | What it does |
|---------|-------------|
| `/moira init` | Set up Moira for current project |
| `/moira <task>` | Execute a task through the pipeline |
| `/moira continue` | Resume interrupted task |
| `/moira status` | Show current state |
| `/moira knowledge` | View/manage knowledge base |
| `/moira metrics` | Performance dashboard |
| `/moira audit` | System health check |
| `/moira help` | Help and documentation |

## Core Concepts

### Agents

9 specialized agents, each with one job:

| Agent | Role | Does NOT |
|-------|------|----------|
| **Explorer** | Reads code, reports facts | Propose solutions |
| **Analyst** | Formalizes requirements, finds edge cases | Propose technical implementation |
| **Architect** | Makes technical decisions | Write code |
| **Planner** | Creates step-by-step execution plan | Make architectural decisions |
| **Implementer** | Writes code per plan | Decide what to build |
| **Reviewer** | Checks code quality | Fix code |
| **Tester** | Writes and runs tests | Modify application code |
| **Reflector** | Analyzes outcomes, proposes improvements | Change rules directly |
| **Auditor** | Verifies system health | Modify system files |

### Pipelines

Task size determines the pipeline:

| Size | When | Pipeline | Approval gates |
|------|------|----------|----------------|
| **Small** | 1-2 files, simple change | Quick | 2 |
| **Medium** | Multiple files, needs context | Standard | 4 |
| **Large** | New entities, architecture changes | Full | 5+ |
| **Epic** | Multiple related tasks | Decomposition | Many |

### Knowledge System

Moira accumulates project knowledge over time:

- **Project model** — living understanding of your project's architecture
- **Decisions log** — why decisions were made, not just what
- **Patterns** — what works and what doesn't, with evidence
- **Quality map** — assessment of existing code quality
- **Conventions** — detected and confirmed coding standards

Knowledge is committed to your repo — shared with the team.

### Quality Enforcement

Quality is built into every step, not checked at the end:

1. **Requirements completeness** — are all edge cases covered?
2. **Architecture soundness** — SOLID, no circular deps, verified APIs
3. **Plan feasibility** — files exist, budget fits, dependencies ordered
4. **Code correctness** — standards, performance, security, conventions
5. **Test coverage** — happy path, errors, edge cases

### Context Budget Management

Every agent has a context budget. Moira tracks usage and prevents overflow:

```
╔═══════════════════════════════════════╗
║       CONTEXT BUDGET REPORT          ║
║  Explorer      │  48% │ ✅           ║
║  Implementer-1 │  38% │ ✅           ║
║  Reviewer      │  71% │ 🔴           ║
║  Orchestrator  │   9% │ ✅  CLEAN    ║
╚═══════════════════════════════════════╝
```

## Team Usage

### First developer (project setup)

```bash
curl -fsSL https://.../install.sh | bash     # one-time global install
cd project && claude
> /moira init                                  # generates project config
# commit .claude/moira/ to repo
```

### Everyone else

```bash
curl -fsSL https://.../install.sh | bash     # one-time global install
git pull && cd project && claude
> /moira init                                  # detects existing config, ready
```

Project configuration and accumulated knowledge are shared via git. Task state is per-developer (gitignored).

## Architecture

```
~/.claude/moira/              ← Global layer (installed once)
├── core/rules/               ← Universal rules + quality criteria
├── skills/                   ← Orchestrator, init, audit, etc.
├── hooks/                    ← Guard hook, budget tracker
└── templates/                ← Project bootstrapping templates

<project>/.claude/moira/      ← Project layer (generated per project)
├── project/rules/            ← Stack, conventions, patterns
├── knowledge/                ← Project model, decisions, patterns
├── config/                   ← MCP registry, budgets
└── state/                    ← Task execution state (gitignored)
```

Full architecture documentation: [`design/`](design/SYSTEM-DESIGN.md)

## Design Documents

- [System Design](design/SYSTEM-DESIGN.md) — complete index
- [Architecture Overview](design/architecture/overview.md)
- [Agent Architecture](design/architecture/agents.md)
- [Pipeline Architecture](design/architecture/pipelines.md)
- [Rules Architecture](design/architecture/rules.md)
- [Distribution & Installation](design/architecture/distribution.md)
- [Constitution](design/CONSTITUTION.md) — inviolable system invariants
- [Implementation Roadmap](design/IMPLEMENTATION-ROADMAP.md)
- [Decision Log](design/decisions/log.md)

## Principles

1. **Orchestrator never executes** — Claude dispatches agents, never reads/writes project code
2. **File-based communication** — agents write to files, orchestrator reads only summaries
3. **Deterministic pipelines** — same task type = same execution path
4. **Gates before action** — no code passes without engineer approval
5. **Knowledge accumulates** — system learns, but changes require validation
6. **Never guess** — if information is missing, stop and ask

## Status

**System design: complete.** Implementation in progress per [roadmap](design/IMPLEMENTATION-ROADMAP.md).

## License

MIT
