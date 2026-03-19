<p align="center">
  <strong>M O I R A</strong><br>
  <em>Meta-orchestration framework for Claude Code</em>
</p>

<p align="center">
  10 specialized agents. Deterministic pipelines. You approve at every gate.
</p>

<p align="center">
  <code>curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash</code>
</p>

---

## What is Moira

Moira transforms Claude Code from a general-purpose assistant into a **structured engineering system**. Instead of Claude reading your codebase, making decisions, writing code, and reviewing its own work — all in one context window — Moira coordinates 10 specialized agents through deterministic pipelines with quality gates at every step.

You describe a task. Moira classifies it, selects the appropriate pipeline, and dispatches agents in sequence: exploration, analysis, architecture, planning, implementation, review, testing. Each agent has exactly one responsibility and explicit constraints on what it cannot do. You approve at numbered gates before the pipeline advances.

The result: predictable output, problems caught early, knowledge that accumulates across sessions, and context that never overflows.

```
You describe a task
       │
  ┌────▼────┐     ┌─────────┐     ┌──────┐     ┌───────┐     ┌────────┐
  │ Classify │ ──▸ │ Analyze │ ──▸ │ Plan │ ──▸ │ Build │ ──▸ │ Review │
  └─────────┘     └─────────┘     └──────┘     └───────┘     └────────┘
       │               │              │             │              │
  "how big?"     "what's needed?"  "how?"     "write code"   "check quality"
       │               │              │             │              │
    [gate]          [gate]         [gate]                       [gate]
  you approve    you approve    you approve                  you approve
```

---

## Why this exists

Working with Claude Code on production software exposes a set of recurring problems:

**Context overflow.** Claude reads too much of your codebase, fills its context window, and output quality degrades. You notice hallucinations, forgotten requirements, inconsistent decisions — all symptoms of a single agent trying to hold too much at once.

**Non-determinism.** The same task described twice produces different approaches, different architecture, different bugs. There is no process — just improvisation that happens to work sometimes.

**No separation of concerns.** Claude decides what to build, how to build it, writes the code, and reviews its own work. This is the equivalent of a developer who writes requirements, codes, and signs off on their own PR. Corners get cut because there is no structural accountability.

**Knowledge loss.** Every session starts from zero. Patterns discovered yesterday, decisions made last week, failures from last month — gone. The next session repeats the same mistakes.

Moira addresses each of these structurally, not with better prompting.

---

## Quick start

**Install** (once per machine):
```bash
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
```

**Set up a project:**
```bash
cd your-project && claude

> /moira init
# Moira scans your project: stack, structure, conventions, patterns.
# Generates project-specific rules, knowledge base, and agent configuration.
# You review and approve before anything is saved.
```

**Run a task:**
```bash
> /moira Add pagination to the products API endpoint
# Apollo classifies → Hermes explores → Athena analyzes → Metis architects
# → Daedalus plans → Hephaestus implements → Themis reviews → Aletheia tests
# You approve at every gate.
```

**Requirements:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview), git, bash 3+. Nothing else — Moira is markdown, YAML, and shell scripts. No daemon, no server, no compiled dependencies.

---

## The Pantheon — 10 agents with strict boundaries

Each agent has one job and explicit NEVER constraints that prevent role creep. An Explorer that cannot propose solutions actually explores. An Implementer that cannot make architectural decisions follows the plan. Boundaries create reliability.

| Agent | Role | Responsibility | Never does |
|---|---|---|---|
| **Apollo** | Classifier | Determines task size and pipeline | Read source code, propose solutions |
| **Hermes** | Explorer | Scouts codebase, reports facts only | Propose solutions, modify files |
| **Athena** | Analyst | Formalizes requirements, finds edge cases | Propose technical implementation |
| **Metis** | Architect | Makes technical decisions, chooses patterns | Write code |
| **Daedalus** | Planner | Decomposes into executable steps with dependencies | Make architectural decisions |
| **Hephaestus** | Implementer | Writes code according to plan | Decide what to build, fabricate APIs |
| **Themis** | Reviewer | Judges code against standards and requirements | Fix code, suppress findings |
| **Aletheia** | Tester | Writes and runs tests | Modify application code |
| **Mnemosyne** | Reflector | Analyzes outcomes, proposes rule improvements | Change rules directly |
| **Argus** | Auditor | Independent system health verification | Modify system files |

Agent names come from Greek mythology — each deity's mythological role mirrors the agent's function. Names always appear as **Name (role)** in output so the mapping is clear.

Every agent returns a structured response (status, summary, artifacts, quality findings) and writes full output to state files. The orchestrator only reads one-line summaries, keeping its own context minimal.

---

## Pipelines — deterministic execution

Apollo classifies the task. Classification determines the pipeline. Pipeline determines the process. No judgment calls, no heuristics, no "let me figure out the best approach."

| Classification | Criteria | Pipeline | Gates |
|---|---|---|---|
| **Small** (high confidence) | 1-2 files, local change | Quick | 2 |
| **Small** (low confidence) | Uncertain scope | Standard | 4 |
| **Medium** | 3-10 files, project context needed | Standard | 4 |
| **Large** | Architecture changes, >10 files | Full | 5+ |
| **Epic** | Multiple related tasks | Decomposition | Per-task |

**Quick** — Classify → explore → implement → review. Done in minutes.

**Standard** — The workhorse. Explore + analyze run in parallel, then architect → plan → implement in batches → review → test. Implementers run in parallel when tasks are independent, scheduled via Critical Path Method.

**Full** — Standard pipeline with per-phase gates and checkpoints. Each phase can resume in a new Claude session without losing progress. Integration testing across component boundaries.

**Decomposition** — Breaks an epic into independent tasks. Each task runs through its own pipeline (Quick, Standard, or Full). Dependency ordering ensures tasks execute in the right sequence. Cross-task integration verification at the end.

This is a constitutional invariant: the same classification always triggers the same pipeline. No exceptions.

---

## Quality gates — problems caught before code is written

Five gates are embedded in the pipeline. Each gate has a structured checklist. Critical issues block the pipeline. Gates cannot be skipped, reordered, or made optional by any configuration.

| Gate | Checks | Agent |
|---|---|---|
| **Q1: Completeness** | Happy path, error cases, edge cases, input validation, security, backward compatibility | Athena |
| **Q2: Soundness** | SOLID principles, no circular dependencies, verified API contracts, no God objects, performance | Metis |
| **Q3: Feasibility** | Files exist, dependencies ordered, budget fits, rollback path defined, contract interfaces | Daedalus |
| **Q4: Correctness** | Matches spec, standards compliance, security (injection, XSS, credentials), no fabrication | Themis |
| **Q5: Coverage** | Happy path, error cases, edge cases, integration points, tests actually run and pass | Aletheia |

Gates are presented as numbered prompts where you choose: **proceed**, **details** (see full reasoning), **modify** (provide feedback), or **abort**.

```
═══════════════════════════════════════
 GATE: Architecture Approval
═══════════════════════════════════════

 Adapter pattern for OAuth2 integration.
 Provider-specific logic behind a common interface.

 • 3 new files, 2 modified
 • Strategy pattern rejected — over-engineering for 2 providers
 • No breaking changes to existing auth flow

 ▸ proceed  ▸ details  ▸ modify  ▸ abort
═══════════════════════════════════════
```

Critical findings trigger automatic retry (up to 3 attempts with feedback), then escalation to you. Nothing is silent or hidden.

---

## Knowledge system — the project gets smarter over time

Every task Moira executes feeds back into a knowledge base that lives in your repository. Knowledge is evidence-based — sourced from actual task execution, not speculation. Rule changes require 3+ confirming observations before they take effect.

| Type | What it captures |
|---|---|
| **Project model** | Architecture, components, data flow, entry points, boundaries |
| **Conventions** | Naming, imports, file organization, error handling patterns |
| **Decisions** | What was chosen, what was rejected, and why |
| **Patterns** | What works and what doesn't — with evidence from real tasks |
| **Failures** | Root causes, prevention strategies, lessons learned |
| **Quality map** | Per-area code quality assessment (strong / adequate / problematic) |

### Three access levels

Agents don't all see the same knowledge. Access is scoped to prevent bias and control context usage:

- **L0 (Index)** — list of topics only. Explorer gets L0 so it stays unbiased by prior conclusions.
- **L1 (Summary)** — key facts for decisions. Most agents work at this level.
- **L2 (Full detail)** — complete information with examples. Architect gets L2 for decisions, Implementer gets L2 for conventions.

### Knowledge freshness

Knowledge entries have confidence scores that decay over time using an exponential model. Entries verified recently are trusted; old entries are flagged for re-verification. This prevents stale knowledge from driving decisions.

### Bootstrapping

When you run `/moira init`, four parallel scanners analyze your project in 2-3 minutes: technology stack, project structure, coding conventions, and established patterns. This gives Moira a working knowledge base from day one. Subsequent tasks refine and expand it organically.

---

## Context budget — overflow is structurally impossible

Context overflow is the most common failure mode in AI-assisted coding. Moira prevents it at the architecture level:

**Isolated agent contexts.** Each agent runs in its own context window. An Explorer reading 80k tokens of source code does not affect the Architect's reasoning capacity.

**Orchestrator on a diet.** The orchestrator reads one-line summaries from agents, never full output. It typically stays under 25% of its context capacity.

**Pre-execution estimation.** Before a task runs, the Planner estimates token usage per step. If any step would exceed an agent's budget, it is automatically split into smaller units.

**Adaptive safety margin.** Based on telemetry from previous tasks, the system calculates how much margin to reserve. Minimum 20% is always kept, with the actual margin adapting to observed estimation accuracy.

**Auto-checkpoint at 60%.** If the orchestrator's context reaches 60%, work is automatically saved. You can resume in a new Claude session with `/moira resume` — no progress lost, no quality degradation.

```
⚡ context: 23k/1M ▓▓░░░░░░░░ 2%
```

Per-agent budget allocations range from 20k tokens (Classifier) to 140k tokens (Explorer, Auditor), tuned to each role's needs.

---

## The Constitution — six inviolable articles

These are not guidelines. They are structural invariants enforced at every level of the system. No agent, configuration, or automated process can violate them. Only you can amend the Constitution.

| Article | Protects | Key invariant |
|---|---|---|
| **1. Separation** | Role boundaries | Orchestrator never touches code. Each agent has one role with NEVER constraints. |
| **2. Determinism** | Predictability | Same classification → same pipeline. Gates cannot be skipped or reordered. |
| **3. Transparency** | Traceability | Every decision written to state files. Budget visible. Errors reported with full context. |
| **4. Safety** | Correctness | No fabricated APIs or schemas. User has final authority. Everything is git-reversible. |
| **5. Knowledge** | Integrity | Evidence-based only. Rule changes require 3+ confirmations. New knowledge validated against existing. |
| **6. Self-protection** | System integrity | Constitution is immutable by agents. Design documents are source of truth. Invariants verified before changes. |

Enforcement operates on three tiers:
- **Structural** — platform-level (`allowed-tools` restrictions). Impossible to violate.
- **Validated** — orchestrator checks agent responses against expected format and constraints. Parse failures trigger retry.
- **Behavioral** — prompt-based rules (NEVER constraints). Can occasionally be violated — detected by Reviewer (per-task), Reflector (systemic patterns), and Auditor (periodic checks).

---

## Self-improvement — the system learns from itself

After each task completes, Mnemosyne (Reflector) analyzes the execution: what worked, what didn't, what patterns are emerging. If the same issue appears across 3+ tasks, a rule change proposal is generated — but never applied automatically. You review and approve.

Argus (Auditor) runs independently via `/moira audit`, checking five domains: rules consistency, knowledge integrity, agent configuration, system config, and cross-reference validity. Findings are classified by risk (low/medium/high) with specific fix recommendations.

This creates a feedback loop: tasks produce knowledge, knowledge improves agents, better agents produce better tasks. But all changes go through you.

---

## Teams

```bash
# First developer
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
cd project && claude
> /moira init                              # scan project, generate config
git add .claude/moira/ && git commit       # share config + knowledge

# Everyone else
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
git pull && cd project && claude
> /moira init                              # detects existing config, ready
```

Project configuration and knowledge travel with the repo (committed). Task state is per-developer (gitignored). New team members inherit all accumulated project knowledge — conventions, decisions, patterns, quality assessments — on their first session.

---

## Architecture

```
┌───────────────────────────────────────────────────┐
│          GLOBAL LAYER  (~/.claude/moira/)          │
│                                                   │
│  Orchestrator logic, pipeline definitions,        │
│  agent templates, quality criteria, hooks,         │
│  20 shell libraries, 12 YAML schemas.             │
│  Installed once. Shared across all projects.      │
└────────────────────────┬──────────────────────────┘
                         │  /moira init generates
┌────────────────────────▼──────────────────────────┐
│         PROJECT LAYER  (.claude/moira/)            │
│                                                   │
│  Project-adapted rules (stack, conventions,       │
│  patterns, boundaries), knowledge base (6 types   │
│  × 3 levels), MCP registry, context budgets.      │
│  Committed to repo. Shared with team.             │
└────────────────────────┬──────────────────────────┘
                         │  dispatches
┌────────────────────────▼──────────────────────────┐
│         EXECUTION LAYER  (agents)                  │
│                                                   │
│  Each agent receives assembled instructions       │
│  (4 rule layers + scoped knowledge + task          │
│  context), works in its own context window,       │
│  writes output to state files, returns a          │
│  one-line summary to the orchestrator.            │
└───────────────────────────────────────────────────┘
```

### What it's made of

No compiled code. No runtime dependencies. No daemon, server, or package manager.

| Type | Purpose |
|---|---|
| Markdown (`.md`) | Agent prompts, skills, orchestrator logic, knowledge |
| YAML (`.yaml`) | Rules, configs, schemas, pipeline definitions, metrics |
| Shell (`.sh`) | Hooks, libraries, installation, state management |

Moira runs entirely within Claude Code's native infrastructure: custom commands, skills, hooks, and subagents. Installation copies files to `~/.claude/moira/` and `~/.claude/commands/moira/`.

### Four-layer rule system

Agent instructions are assembled from four layers, merged at dispatch time:

1. **Base rules** — universal constraints (inviolable + overridable)
2. **Role rules** — per-agent NEVER constraints and responsibilities
3. **Project rules** — detected stack, conventions, patterns, boundaries
4. **Task rules** — specific context for the current task

Higher layers override lower ones (except inviolable rules from Layer 1, which cannot be overridden).

---

## Commands

| Command | What it does |
|---|---|
| `/moira init` | Scan project, generate config and knowledge base |
| `/moira <task>` | Execute task through the appropriate pipeline |
| `/moira resume` | Resume interrupted task from last checkpoint |
| `/moira status` | Current task, pipeline progress, system health |
| `/moira knowledge` | Browse and manage accumulated knowledge |
| `/moira metrics` | Performance dashboard and trends |
| `/moira audit` | System health check across 5 domains |
| `/moira bench` | Run behavioral test suite |
| `/moira refresh` | Re-scan project, update knowledge |
| `/moira upgrade` | Upgrade Moira to a newer version |
| `/moira graph` | Query project structure graph (requires [Ariadne](https://github.com/mind-decay/ariadne)) |
| `/moira bypass: <task>` | Skip the pipeline — logged, requires explicit confirmation |
| `/moira help` | Documentation and command reference |

After task completion:
- **done** — accept changes
- **tweak** — targeted modification
- **redo** — rollback and re-enter at architecture, plan, or implementation
- **diff** — show full git diff
- **test** — run additional tests

---

## Testing

| Tier | Method | Cost | When |
|---|---|---|---|
| **Structural** | Shell scripts + grep. Deterministic checks on YAML schemas, file structure, NEVER constraints, gate presence. | 0 tokens | Every change |
| **Behavioral** | Full Moira runs on fixture projects (greenfield, mature, legacy). LLM-as-judge scoring with calibrated rubrics. | High | Prompt or rule changes |
| **Full bench** | All tests + statistical confidence bands across multiple runs. | Very high | Pipeline, gate, or role changes |

Live telemetry tracks per-task metrics passively — token usage, durations, gate pass rates, quality scores. Numbers only, never content.

---

## Project graph (optional)

If [Ariadne](https://github.com/mind-decay/ariadne) is installed, Moira gains architectural intelligence: dependency graphs, blast radius analysis, cycle detection, coupling metrics, cluster identification, and code smell detection. Agents use this data for smarter exploration and more informed architectural decisions.

Ariadne is optional. Moira works fully without it — graph features gracefully degrade when the binary is not present.

---

## Design documents

The system is designed before it is built. All implementation conforms to design documents, not the other way around.

| Document | Contents |
|---|---|
| [System Design](design/SYSTEM-DESIGN.md) | Index of all design documents |
| [Constitution](design/CONSTITUTION.md) | Six inviolable articles |
| [Architecture Overview](design/architecture/overview.md) | Layers, data flow, file structure |
| [Agents](design/architecture/agents.md) | Types, contracts, boundaries, knowledge access |
| [Pipelines](design/architecture/pipelines.md) | Execution flows, batching, CPM scheduling |
| [Knowledge](design/architecture/knowledge.md) | Types, access levels, freshness, bootstrapping |
| [Quality](design/architecture/quality.md) | Gates, checklists, severity, code evolution |
| [Budget](design/architecture/budget.md) | Context management, estimation, adaptive margins |
| [Rules](design/architecture/rules.md) | Four-layer rule system |
| [Decision Log](design/decisions/log.md) | 100+ architectural decisions with reasoning |
| [Roadmap](design/IMPLEMENTATION-ROADMAP.md) | Implementation phases |

---

## Status

Phases 1-12 complete. Phase 13 (project graph integration) in progress. 30+ design documents. 100+ architectural decisions logged.

---

## License

MIT
