<p align="center">
  <strong>M O I R A</strong><br>
  <em>Meta-orchestration framework for Claude Code</em>
</p>

<p align="center">
  11 specialized agents. 5 deterministic pipelines. You approve at every gate.
</p>

<p align="center">
  <code>curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash</code>
</p>

---

## The problem

AI coding assistants are single-agent systems. One model reads your codebase, decides what to build, writes code, and reviews its own work — all in one context window. This architecture has four structural failures that no amount of prompting can fix:

**Context overflow.** The model reads too much, fills its context window, and output quality silently degrades. Hallucinations, forgotten requirements, inconsistent decisions — all symptoms of a single agent holding too much at once. You don't see it happening until the code is wrong.

**Non-determinism.** The same task described twice produces different approaches, different architecture, different bugs. There is no process — just improvisation that sometimes works.

**No separation of concerns.** The model decides what to build, how to build it, writes the code, and signs off on its own work. This is a developer who writes requirements, codes, and approves their own PR. There is no structural accountability.

**Zero memory.** Every session starts from scratch. Patterns discovered yesterday, decisions made last week, failures from last month — gone. The next session repeats the same mistakes because there is nothing to learn from.

These are not prompting problems. They are architecture problems. You cannot solve context overflow by asking the model to "be concise." You cannot solve non-determinism by writing a better system prompt. You need structural guarantees.

---

## What Moira does

Moira transforms Claude Code from a general-purpose assistant into a **structured engineering system**. Instead of one agent doing everything, Moira coordinates 11 specialized agents through deterministic pipelines with quality gates at every step.

You describe a task. Moira classifies it, selects the appropriate pipeline, and dispatches agents in sequence: exploration, analysis, architecture, planning, implementation, review, testing. Each agent has exactly one responsibility and explicit constraints on what it cannot do. You approve at numbered gates before the pipeline advances.

```
You describe a task
       |
  +----------+     +---------+     +------+     +-------+     +--------+
  | Classify | --> | Analyze | --> | Plan | --> | Build | --> | Review |
  +----------+     +---------+     +------+     +-------+     +--------+
       |               |              |             |              |
  "how big?"     "what's needed?"  "how?"     "write code"   "check quality"
       |               |              |             |              |
    [gate]          [gate]         [gate]                       [gate]
  you approve    you approve    you approve                  you approve
```

The result: predictable output, problems caught early, knowledge that accumulates across sessions, and context that never overflows.

---

## What makes the architecture work

Multi-agent AI systems are easy to build and hard to make reliable. The default failure mode: agents drift from their roles, the orchestrator accumulates context, quality checks are done by the same model that wrote the code, and there is no structural guarantee that the process will be the same twice. Moira solves these with six architectural properties that reinforce each other.

### 1. The agent that writes code never reviews it

In a single-agent system, Claude writes code and then evaluates its own output. It is structurally incapable of catching its own blind spots — the same reasoning that produced the bug produces the "looks good" verdict.

Moira runs the Implementer (Hephaestus) and the Reviewer (Themis) as separate agent instances with separate context windows and separate instructions. Themis cannot see Hephaestus's reasoning — only the resulting code and the original requirements. This is the AI equivalent of independent code review: the reviewer has no access to the author's justifications, only to the artifact.

The same separation runs through the entire pipeline: the Analyst (Athena) who defines requirements cannot propose technical solutions. The Architect (Metis) who makes technical decisions cannot write code. The Planner (Daedalus) who decomposes tasks cannot make architectural choices. At every stage, the agent that does the work is structurally different from the agent that checks the work.

### 2. The orchestrator physically cannot touch project code

The orchestrator (main Claude session) is restricted via Claude Code's `allowed-tools` mechanism at the platform level. It cannot call Read, Write, Edit, Grep, or Glob on project files. This is not a prompt instruction that can be ignored — it is a tool whitelist enforced by the runtime.

The consequence: the orchestrator's context window stays clean. It reads one-line summaries from agents, never full source code. In practice it stays under 25% of context capacity, which means its decision quality does not degrade as the task grows in complexity.

This is the core insight: **context overflow in AI coding is not a prompting problem, it is an isolation problem.** If the orchestrator can read files, it will. And once it does, its context fills, its output quality drops, and there is no way to undo it within the same session.

### 3. Pipeline selection is a pure function

Given a task classification (size + mode), the pipeline is determined by a lookup, not by AI judgment. Small high-confidence task → Quick pipeline. Medium task → Standard pipeline. Analytical task → Analytical pipeline. There are no heuristics, no "let me figure out the best approach," no conditional logic beyond the classification result.

This is a testable property: you can grep the pipeline selection code and verify there are zero branches beyond the classification map. The same task described twice will always follow the same process.

Why this matters: non-determinism in AI workflows usually comes from the AI choosing its own process. Remove that choice, and the remaining non-determinism is limited to content generation within each step — which is bounded by quality gates.

### 4. Three-tier enforcement, not prompt rules

LLM prompt instructions are suggestions, not guarantees. Any system that relies solely on "NEVER do X" in agent prompts will eventually see X happen. Moira accounts for this with three enforcement tiers:

- **Structural** — platform-level tool restrictions (`allowed-tools`). The orchestrator literally cannot call Read on project files. An agent without Edit in its tool list cannot modify files. Impossible to violate regardless of prompt content.
- **Validated** — the orchestrator checks every agent response against a contract (required fields, status values, artifact format). Malformed responses trigger retry, not silent acceptance.
- **Behavioral** — prompt-based NEVER constraints. These *can* be violated. That is why they are independently verified: Themis (Reviewer) checks per-task, Mnemosyne (Reflector) detects systemic patterns across tasks, Argus (Auditor) runs periodic health checks. Three independent agents watching for drift, none of which can fix what they find — they can only report.

The key design: critical invariants are structural (tier 1). Important constraints are validated (tier 2). Behavioral rules (tier 3) are treated as probabilistic and monitored accordingly.

### 5. Knowledge has access levels to prevent bias

Most knowledge systems give all agents full access to everything. This creates confirmation bias: if the Explorer can read prior architectural conclusions, it will find evidence that confirms them and miss evidence that contradicts them.

Moira scopes knowledge access per agent role:
- **L0 (Index)** — topic list only, no content. Explorer gets L0 so it reports what it actually finds, not what previous sessions concluded.
- **L1 (Summary)** — key facts. Most agents work at this level.
- **L2 (Full detail)** — complete information with examples. Architect gets L2 for technical decisions, Implementer gets L2 for coding conventions.

This is a deliberate trade-off: agents at lower access levels are less informed but less biased. The pipeline compensates by having higher-access agents (Architect at L2) make decisions based on lower-access agents' (Explorer at L0) unbiased observations.

### 6. Each agent runs in its own context window

When a single agent reads 80k tokens of source code, that source code competes with task context, requirements, and reasoning space in the same window. When the Architect needs to make a decision, it is working in a context polluted by the Explorer's file reads.

In Moira, each agent is a separate Claude subagent with its own context window. The Explorer can read 80k tokens of source code without affecting the Architect's available reasoning capacity. The Implementer's code generation does not compete with the Reviewer's evaluation criteria.

Combined with the orchestrator's isolation (property 2), this means the system can handle tasks of arbitrary complexity without any single context window approaching capacity. The total context used across all agents may be large; the context used by any one agent stays within its budget.

---

## Quick start

**Install** (once per machine):
```bash
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
```

**Set up a project:**
```bash
cd your-project && claude

> /moira:init
# Moira scans your project: stack, structure, conventions, patterns.
# Generates project-specific rules, knowledge base, and agent configuration.
# You review and approve before anything is saved.
```

**Run a task:**
```bash
> /moira:task Add pagination to the products API endpoint
# Apollo classifies -> Hermes explores -> Athena analyzes -> Metis architects
# -> Daedalus plans -> Hephaestus implements -> Themis reviews -> Aletheia tests
# You approve at every gate.
```

**Requirements:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview), git, bash 3+. Nothing else.

---

## The Pantheon — 11 agents with strict boundaries

Each agent has one job and explicit NEVER constraints that prevent role creep. An Explorer that cannot propose solutions actually explores. An Implementer that cannot make architectural decisions follows the plan. Boundaries create reliability.

| Agent | Role | Responsibility | Never does |
|---|---|---|---|
| **Apollo** | Classifier | Determines task mode, size, and pipeline | Read source code, propose solutions |
| **Hermes** | Explorer | Scouts codebase and structural graph, reports facts only | Propose solutions, modify files |
| **Athena** | Analyst | Formalizes requirements, finds edge cases | Propose technical implementation |
| **Metis** | Architect | Makes technical decisions, chooses patterns | Write code |
| **Daedalus** | Planner | Decomposes into executable steps with dependencies | Make architectural decisions |
| **Hephaestus** | Implementer | Writes code according to plan | Decide what to build, fabricate APIs |
| **Themis** | Reviewer | Judges code against standards and requirements | Fix code, suppress findings |
| **Aletheia** | Tester | Writes and runs tests | Modify application code |
| **Mnemosyne** | Reflector | Analyzes outcomes, proposes rule improvements | Change rules directly |
| **Argus** | Auditor | Independent system health verification | Modify system files |
| **Calliope** | Scribe | Synthesizes analytical findings into documents | Write code, perform analysis |

Agent names come from Greek mythology — each deity's mythological role mirrors the agent's function. Names always appear as **Name (role)** in output so the mapping is clear.

Every agent returns a structured response (status, summary, artifacts, quality findings) and writes full output to state files. The orchestrator only reads one-line summaries, keeping its own context minimal.

---

## Pipelines — deterministic execution

Apollo classifies the task on two dimensions: **mode** (implementation or analytical) and **size/subtype**. Classification determines the pipeline. Pipeline determines the process. No judgment calls, no heuristics, no "let me figure out the best approach."

| Classification | Criteria | Pipeline | Gates |
|---|---|---|---|
| **Small** (high confidence) | 1-2 files, local change | Quick | 2 |
| **Small** (low confidence) | Uncertain scope | Standard | 4 |
| **Medium** | 3-10 files, project context needed | Standard | 4 |
| **Large** | Architecture changes, >10 files | Full | 5+ |
| **Epic** | Multiple related tasks | Decomposition | Per-task |
| **Analytical** | Analysis, audit, documentation — no code | Analytical | 3-5+ |

**Quick** — Classify, explore, implement, review. Done in minutes.

**Standard** — The workhorse. Explore + analyze run in parallel, then architect, plan, implement in batches, review, test. Implementers run in parallel when tasks are independent, scheduled via Critical Path Method.

**Full** — Standard pipeline with per-phase gates and checkpoints. Each phase can resume in a new Claude session without losing progress. Integration testing across component boundaries.

**Decomposition** — Breaks an epic into independent tasks. Each task runs through its own pipeline (Quick, Standard, or Full). Dependency ordering ensures tasks execute in the right sequence. Cross-task integration verification at the end.

**Analytical** — For tasks that produce analysis, not code: architecture reviews, audits, weakness analysis, decision comparison, documentation. Uses progressive depth — analysis runs in passes, and you decide at each depth checkpoint whether the findings are sufficient, need deepening, or need re-scoping. Calliope synthesizes findings into deliverable documents.

This is a constitutional invariant: the same classification always triggers the same pipeline. No exceptions.

---

## Quality gates — problems caught before code is written

### Implementation quality (Q1-Q5)

Five gates are embedded in implementation pipelines. Each gate has a structured checklist. Critical issues block the pipeline. Gates cannot be skipped, reordered, or made optional by any configuration.

| Gate | Checks | Agent |
|---|---|---|
| **Q1: Completeness** | Happy path, error cases, edge cases, input validation, security, backward compatibility | Athena |
| **Q2: Soundness** | SOLID principles, no circular dependencies, verified API contracts, no God objects, performance | Metis |
| **Q3: Feasibility** | Files exist, dependencies ordered, budget fits, rollback path defined, contract interfaces | Daedalus |
| **Q4: Correctness** | Matches spec, standards compliance, security (injection, XSS, credentials), no fabrication | Themis |
| **Q5: Coverage** | Happy path, error cases, edge cases, integration points, tests actually run and pass | Aletheia |

### Analytical quality (QA1-QA4)

Analytical pipeline uses four dedicated quality gates focused on analysis rigor rather than code correctness:

| Gate | Checks | Agent |
|---|---|---|
| **QA1: Scope Completeness** | All questions answered, structural coverage, no high-centrality gaps left unexplored | Athena + Themis |
| **QA2: Evidence Quality** | Hypothesis-evidence-verdict format, concrete citations, calibrated confidence | Themis |
| **QA3: Actionability** | Concrete recommendations, justified priorities, effort/impact estimates | Themis |
| **QA4: Analytical Rigor** | Competing explanations, no confirmation bias, cross-validated findings, convergence documented | Themis |

Gates are presented as numbered prompts where you choose: **proceed**, **details** (see full reasoning), **modify** (provide feedback), or **abort**.

```
========================================
 GATE: Architecture Approval
========================================

 Adapter pattern for OAuth2 integration.
 Provider-specific logic behind a common interface.

 * 3 new files, 2 modified
 * Strategy pattern rejected -- over-engineering for 2 providers
 * No breaking changes to existing auth flow

  > proceed  > details  > modify  > abort
========================================
```

Critical findings trigger automatic retry (up to 3 attempts with feedback), then escalation to you. Nothing is silent or hidden.

---

## CS methods — formal rigor for analytical tasks

The analytical pipeline embeds six computer science methods to ensure analysis quality. Methods are tiered by readiness:

**Tier A (always active):**
- **CS-3: Hypothesis-Driven Analysis** — every finding follows hypothesis, evidence, verdict format. No vague claims.
- **CS-6: Lattice-Based Organization** — findings organized into a causal/containment hierarchy before synthesis. Documents have natural structure rather than flat lists.

**Tier B (activate when [Ariadne](https://github.com/mind-decay/ariadne) is available):**
- **CS-1: Fixpoint Convergence** — tracks finding delta between analysis passes. Formal termination criterion for depth.
- **CS-2: Graph-Based Coverage** — uses Ariadne's dependency graph as the coverage space. Reports what percentage of relevant nodes have been analyzed.
- **CS-4: Abductive Reasoning** — generates competing explanations for structural symptoms. No finding accepted without considering alternatives.
- **CS-5: Information Gain** — prioritizes deepening direction by centrality, unexplored ratio, and smell density.

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

When you run `/moira:init`, four parallel scanners analyze your project in 2-3 minutes: technology stack, project structure, coding conventions, and established patterns. This gives Moira a working knowledge base from day one. Subsequent tasks refine and expand it organically.

---

## Context budget — overflow is structurally impossible

Context overflow is the most common failure mode in AI-assisted coding. Moira prevents it at the architecture level:

**Isolated agent contexts.** Each agent runs in its own context window. An Explorer reading 80k tokens of source code does not affect the Architect's reasoning capacity.

**Orchestrator on a diet.** The orchestrator reads one-line summaries from agents, never full output. It typically stays under 25% of its context capacity.

**Pre-execution estimation.** Before a task runs, the Planner estimates token usage per step. If any step would exceed an agent's budget, it is automatically split into smaller units.

**Adaptive safety margin.** Based on telemetry from previous tasks, the system calculates how much margin to reserve per agent type. Minimum 20% is always kept, with the actual margin adapting to observed estimation accuracy. Cold start uses a fixed 30% until enough data accumulates.

**Auto-checkpoint at 60%.** If the orchestrator's context reaches 60%, work is automatically saved. You can resume in a new Claude session with `/moira:resume` — no progress lost, no quality degradation.

Per-agent budget allocations range from 20k tokens (Classifier) to 140k tokens (Explorer, Auditor), tuned to each role's needs.

---

## Error handling — 11 error types with structured recovery

Every failure mode is classified, detected, and recovered from through a defined path:

| Code | Category | Recovery |
|---|---|---|
| E1-INPUT | Missing data | Agent stops, asks you for specific information |
| E2-SCOPE | Scope change | Pipeline pauses, presents upgrade/split/reduce options |
| E3-CONFLICT | Contradiction | Both sides documented, you decide |
| E4-BUDGET | Context overflow | Auto-split into smaller batches |
| E5-QUALITY | Quality failure | Retry with feedback (up to 3x), then escalate |
| E6-AGENT | Agent failure | Retry 1x, diagnose, escalate with full report |
| E7-DRIFT | Rule violation | Logged, flagged for audit, rules strengthened if recurring |
| E8-STALE | Outdated knowledge | Flagged for refresh, verified by Explorer |
| E9-SEMANTIC | Wrong content | Reviewer catches factual errors, architecture gate catches design errors |
| E10-DIVERGE | Data disagreement | Architect cross-checks, presents contradiction to user |
| E11-TRUNCATION | Context loss | Budget pre-check prevents, Reviewer catches post-hoc |

Retry decisions are informed by a Markov optimizer that tracks success probability per error type and agent. When historical data shows low retry success probability, the system escalates to you instead of wasting tokens.

---

## The Constitution — six inviolable articles

These are not guidelines. They are structural invariants enforced at every level of the system. No agent, configuration, or automated process can violate them. Only you can amend the Constitution.

| Article | Protects | Key invariant |
|---|---|---|
| **1. Separation** | Role boundaries | Orchestrator never touches code. Each agent has one role with NEVER constraints. |
| **2. Determinism** | Predictability | Same classification = same pipeline. Gates cannot be skipped or reordered. |
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

Argus (Auditor) runs independently via `/moira:audit`, checking five domains: rules consistency, knowledge integrity, agent configuration, system config, and cross-reference validity. Findings are classified by risk (low/medium/high) with specific fix recommendations.

This creates a feedback loop: tasks produce knowledge, knowledge improves agents, better agents produce better tasks. But all changes go through you.

---

## Teams

```bash
# First developer
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
cd project && claude
> /moira:init                              # scan project, generate config
git add .moira/ && git commit       # share config + knowledge

# Everyone else
curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
git pull && cd project && claude
> /moira:init                              # detects existing config, ready
```

Project configuration and knowledge travel with the repo (committed). Task state is per-developer (gitignored). New team members inherit all accumulated project knowledge — conventions, decisions, patterns, quality assessments — on their first session.

---

## Built on Claude Code, not beside it

Moira is not a wrapper around Claude Code. It is built entirely from Claude Code's native extension points — every feature maps to a platform mechanism. No external runtime, no daemon, no compiled dependencies.

### Custom commands as entry points

Every `/moira:*` command is a Claude Code custom command (`.md` skill file) with an explicit `allowed-tools` whitelist. The orchestrator's `/moira:task` command can only call `Agent`, `Read`, `Write` on `.moira/` paths, and task management tools. It physically cannot call `Read` on project source files, `Edit` on code, or run arbitrary `Bash` commands — this is enforced by the platform, not by a prompt.

### Subagents as isolated execution units

Each agent is dispatched via Claude Code's native `Agent` tool as a subagent — a separate Claude instance with its own context window. The orchestrator dispatches, the subagent executes, the orchestrator reads the one-line return. This is how context isolation works: it is not a Moira abstraction, it is a direct use of the platform's subprocess model.

### Hooks as the enforcement layer

Claude Code hooks fire shell scripts on specific events (tool calls, agent lifecycle, session events). Moira uses 16 hooks across 7 event types to enforce invariants, track state, and coordinate the system in real time:

**Pipeline enforcement:**
- `pipeline-dispatch.sh` fires **before** every Agent call — validates that the dispatch matches the pipeline's transition table. If the orchestrator tries to skip a step or dispatch the wrong agent, the hook blocks it.
- `agent-inject.sh` fires when a subagent starts — injects the response contract, assembled rules (4 layers), and traceability context into the agent's prompt.
- `agent-output-validate.sh` fires when a subagent completes — checks the response against the contract (STATUS/SUMMARY/ARTIFACTS/NEXT format). Malformed responses are caught here, not by the orchestrator.
- `agent-done.sh` records completion in history, updates budget counters, triggers pipeline state transitions.

**Orchestrator guard:**
- `guard-prevent.sh` fires **before** Read/Write/Edit — blocks the orchestrator from touching project files outside `.moira/`. This is the structural enforcement of Article 1.1 (orchestrator purity).
- `guard.sh` fires **after** every tool call — logs all tool usage to an audit trail. Violations are recorded with task ID for post-hoc analysis.

**Context budget:**
- `budget-track.sh` fires after every tool call — reads the session transcript size and updates the orchestrator's real context usage. When usage crosses 60%, it triggers auto-checkpoint.

**Graph maintenance:**
- `graph-update.sh` fires after Write/Edit on code files — triggers an incremental Ariadne graph rebuild so agents always query current structural data.

### Shell libraries as the state machine

22 shell libraries (13k+ lines) handle everything that must be deterministic and cannot be left to LLM judgment:

| Library | What it does |
|---|---|
| `state.sh` | Pipeline state machine — step transitions, gate decisions, agent history, retry tracking |
| `budget.sh` | Token estimation, adaptive safety margins (Welford's algorithm), per-agent budget tracking, overflow detection |
| `rules.sh` | Four-layer rule assembly — loads base/role/project/task rules, detects conflicts, enforces inviolable rules |
| `yaml-utils.sh` | Pure-bash YAML parser (dot-path access, 3-level nesting) — no jq, no Python, no external dependencies |
| `knowledge.sh` | Knowledge lifecycle — freshness decay, archival, entry management, confidence scoring |
| `checkpoint.sh` | Task save/restore — serializes pipeline state so `/moira:resume` can pick up in a new session |
| `quality.sh` | Quality gate evaluation — loads checklists, tracks gate pass/fail history |
| `reflection.sh` | Post-task pattern extraction — feeds Mnemosyne's learning loop |
| `metrics.sh` | Telemetry collection — token usage, durations, gate pass rates per agent type |
| `graph.sh` | Ariadne CLI wrapper — graph build, incremental update, query routing |
| `bootstrap.sh` | Project scanning — stack detection, convention extraction, pattern identification |
| `epic.sh` | Epic decomposition — dependency ordering, cross-task state management |

The design principle: **shell scripts handle state and enforcement, LLM agents handle reasoning and generation.** Scripts are deterministic, testable (1900+ structural tests), and cannot hallucinate. Agents are creative, contextual, and bounded by what scripts allow them to do.

### Four-layer rule system

Agent instructions are assembled from four layers, merged at dispatch time by `rules.sh`:

1. **Base rules** — universal constraints (inviolable + overridable)
2. **Role rules** — per-agent NEVER constraints and responsibilities
3. **Project rules** — detected stack, conventions, patterns, boundaries
4. **Task rules** — specific context for the current task

Higher layers override lower ones, except inviolable rules from Layer 1, which cannot be overridden. `rules.sh` detects conflicts between layers and exits with an error if an inviolable rule would be weakened — this is checked before the agent is dispatched, not after.

---

## Commands

| Command | What it does |
|---|---|
| `/moira:init` | Scan project, generate config and knowledge base |
| `/moira:task <description>` | Execute task through the appropriate pipeline |
| `/moira:resume` | Resume interrupted task from last checkpoint |
| `/moira:status` | Current task, pipeline progress, system health |
| `/moira:knowledge` | Browse and manage accumulated knowledge |
| `/moira:metrics` | Performance dashboard and trends |
| `/moira:audit` | System health check across 5 domains |
| `/moira:bench` | Run behavioral test suite |
| `/moira:health` | Quick system health overview |
| `/moira:refresh` | Re-scan project, update knowledge and MCP registry |
| `/moira:upgrade` | Upgrade Moira to a newer version |
| `/moira:graph` | Query project structure graph (requires [Ariadne](https://github.com/mind-decay/ariadne)) |
| `/moira bypass: <task>` | Skip the pipeline — logged, requires explicit confirmation |
| `/moira:help` | Documentation and command reference |

After task completion:
- **done** — accept changes
- **tweak** — targeted modification
- **redo** — rollback and re-enter at architecture, plan, or implementation
- **diff** — show full git diff
- **test** — run additional tests

---

## Structural intelligence via Ariadne MCP

Without structural data, AI agents navigate codebases by reading files and guessing relationships. They don't know which file is a bottleneck, what the blast radius of a change is, or whether a module has hidden coupling. They discover structure by accident, one file at a time.

[Ariadne](https://github.com/mind-decay/ariadne) is a separate Rust project that parses source code via tree-sitter, builds a dependency graph, and exposes it through an MCP server. When Ariadne is installed, Moira agents query structural data in real time — not as a convenience, but as a fundamentally different way of understanding a codebase.

### What agents can query

Ariadne exposes 17 MCP tools. Each gives agents a view of the codebase that would take a human developer hours to build manually:

| Tool | What it returns |
|---|---|
| `ariadne_blast_radius` | Every file affected by changing a given file — reverse BFS through the dependency graph |
| `ariadne_centrality` | Bottleneck files ranked by betweenness centrality — the files that most dependency paths pass through |
| `ariadne_importance` | Files ranked by combined centrality + PageRank — the structurally critical parts of the codebase |
| `ariadne_smells` | Architectural anti-patterns: god files, layer violations, hub-and-spoke, circular dependencies |
| `ariadne_cycles` | Strongly connected components — groups of files with circular dependencies |
| `ariadne_layers` | Topological layers from foundational to high-level — shows the natural dependency ordering |
| `ariadne_cluster` | Module boundaries with cohesion/coupling metrics — where the natural seams are |
| `ariadne_metrics` | Martin metrics per module: instability, abstractness, distance from the main sequence |
| `ariadne_spectral` | Algebraic connectivity, monolith score — how tightly coupled the overall architecture is |
| `ariadne_compressed` | Hierarchical views at three zoom levels (L0: clusters, L1: files, L2: neighborhood) |
| `ariadne_diff` | Structural changes since last graph update — new dependencies, removed edges, shifted layers |

### How agents use it

Structural data flows into every pipeline stage where decisions depend on codebase understanding:

- **Hermes (Explorer)** queries file dependencies, layer assignments, and cluster membership to report structural facts — not just what a file contains, but where it sits in the architecture and what depends on it.
- **Metis (Architect)** queries blast radius before making design decisions — knowing that a change to `auth.ts` affects 47 downstream files versus 3 changes the architecture choice. Queries smells and cycles to avoid reinforcing existing anti-patterns.
- **Daedalus (Planner)** queries centrality and importance to prioritize implementation order — high-centrality files get implemented first because downstream tasks depend on them. This is Critical Path Method scheduling informed by actual dependency data.
- **Themis (Reviewer)** queries blast radius to verify that the implementation touched everything it should have. Checks for new architectural smells introduced by the change.
- **Analytical pipeline** uses Ariadne as the primary data source for architecture reviews and audits. CS-2 (Graph-Based Coverage) uses the dependency graph as the coverage space — reports what percentage of relevant nodes have been analyzed. CS-5 (Information Gain) prioritizes deepening direction by centrality and smell density.

### Live graph updates

The `graph-update.sh` hook fires after every Write/Edit on code files, triggering an incremental Ariadne rebuild. Agents always query current structural data, not a stale snapshot. The graph is committed to git (`.ariadne/graph/`), so team members share the same structural view.

### Graceful degradation

Ariadne is optional. When not installed, all graph queries return empty results and agents fall back to file-by-file exploration. The analytical pipeline runs with Tier A CS methods (hypothesis-driven analysis, lattice organization) regardless. Tier B methods (fixpoint convergence, graph coverage, information gain) activate only when Ariadne data is available.

---

## Testing

| Tier | Method | Cost | When |
|---|---|---|---|
| **Structural** | Shell scripts + grep. Deterministic checks on YAML schemas, file structure, NEVER constraints, gate presence. 1900+ tests across 38 suites. | 0 tokens | Every change |
| **Behavioral** | Full Moira runs on fixture projects (greenfield, mature, legacy). LLM-as-judge scoring with calibrated rubrics. | High | Prompt or rule changes |
| **Full bench** | All tests + statistical confidence bands across multiple runs. | Very high | Pipeline, gate, or role changes |

Live telemetry tracks per-task metrics passively — token usage, durations, gate pass rates, quality scores. Numbers only, never content.

---

## Design documents

The system is designed before it is built. All implementation conforms to design documents, not the other way around.

| Document | Contents |
|---|---|
| [System Design](design/SYSTEM-DESIGN.md) | Index of all design documents |
| [Constitution](design/CONSTITUTION.md) | Six inviolable articles |
| [Architecture Overview](design/architecture/overview.md) | Layers, data flow, file structure |
| [Agents](design/architecture/agents.md) | 11 agent types, contracts, boundaries, knowledge access |
| [Pipelines](design/architecture/pipelines.md) | 5 execution flows, batching, CPM scheduling |
| [Analytical Pipeline](design/architecture/analytical-pipeline.md) | Progressive depth, CS methods, QA gates |
| [Knowledge](design/subsystems/knowledge.md) | Types, access levels, freshness, bootstrapping |
| [Quality](design/subsystems/quality.md) | Gates Q1-Q5, QA1-QA4, severity, code evolution |
| [Budget](design/subsystems/context-budget.md) | Context management, estimation, adaptive margins |
| [Rules](design/architecture/rules.md) | Four-layer rule system |
| [Fault Tolerance](design/subsystems/fault-tolerance.md) | E1-E11 error taxonomy, recovery strategies |
| [Decision Log](design/decisions/log.md) | 195 architectural decisions with reasoning |
| [Roadmap](design/IMPLEMENTATION-ROADMAP.md) | 18 implementation phases |

---

## Status

18 phases complete. 195 architectural decisions logged. 1900+ structural tests passing. Tested on real projects.

---

## License

MIT
