<p align="center">
  <strong>M O I R A</strong><br>
  <em>Μοῖρα — the Fates who spin, measure, and cut the threads of destiny</em>
</p>

<p align="center">
  Meta-orchestration framework for Claude Code.<br>
  10 specialized agents. Deterministic pipelines. Engineer in control.<br>
</p>

<p align="center">
  <code>task → classify → analyze → architect → plan → implement → review → test</code><br>
  <code>you approve at every step</code>
</p>

---

**You know the problem.** You describe a task to Claude. It reads half your codebase, fills its context window, forgets what it was doing, and produces something that sort of works. You ask the same thing tomorrow — different approach, different quality, different bugs. You spend more time fixing the output than you saved not writing it yourself.

**Moira replaces improvisation with engineering process.** Claude never touches your code. Instead, it orchestrates 10 specialized agents — each with one job and strict boundaries — through deterministic pipelines. Requirements are formalized before architecture. Architecture is approved before planning. Plans are verified before implementation. Code is reviewed before you see it. Same task type, same process, every time.

**This is not vibe coding.** There are no prayers, no "just make it work", no hoping for the best. Moira is a meta-framework for engineers who want to stop typing code — but not stop engineering. You make every architectural decision. You approve every gate. The AI executes; you decide.

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

## What changes

| Today | With Moira |
|---|---|
| Claude fills its context and starts hallucinating at 60% | Each agent gets an isolated context. Orchestrator stays under 25%. |
| Ask the same task twice — get two different results | Same classification → same pipeline → same process. Deterministic. |
| Claude does everything: reads, thinks, decides, codes, reviews itself | 10 agents, each with one job. Explorer never proposes. Implementer never decides. Reviewer never fixes. |
| You review at the end and hope it's okay | 5 quality gates: requirements, architecture, plan, code, tests. Problems caught early. |
| Knowledge dies when the session ends | Project model, decisions, patterns, failures — accumulated, committed, shared. |
| "It works on my machine" — no one knows how | Every decision is traceable. Every gate is logged. Every task has an audit trail. |

---

## 60 seconds to start

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/moira/main/install.sh | bash
```

```bash
cd my-project && claude

> /moira init
# Moira scans your project: stack, structure, conventions, patterns.
# Generates project-specific agents, rules, and knowledge base.

> /moira Add pagination to the products API endpoint
# Apollo classifies → Hermes explores → Athena analyzes → Metis architects
# → Daedalus plans → Hephaestus implements → Themis reviews → Aletheia tests
# You approve at every gate. Done.
```

Requirements: [Claude Code CLI](https://docs.anthropic.com/claude-code), git, bash 3+. Nothing else — Moira is markdown, YAML, and shell scripts. No daemon, no server, no runtime dependencies.

---

## Who this is for

**Engineers who build production software** and want AI to handle execution while they keep control over decisions. You know that requirements → architecture → plan → implementation → review is not overhead — it's how good software gets built. You want that process automated, not abandoned.

**Not for:** weekend prototypes (just use Claude directly), single-line fixes (`/moira bypass:` exists), or anyone who wants AI to make all the decisions (Moira requires an engineer at the wheel).

---

## The Pantheon — 10 agents, strict boundaries

Each agent is named after a Greek deity whose mythological role mirrors its function. Names always appear as **Name (role)** in output — mythology is flavor, not friction.

| Name | Role | Does | NEVER does |
|---|---|---|---|
| **Apollo** | Classifier | Determines task size and pipeline | Read source code, propose solutions |
| **Hermes** | Explorer | Scouts codebase, reports facts | Propose solutions |
| **Athena** | Analyst | Formalizes requirements, finds edge cases | Propose technical implementation |
| **Metis** | Architect | Makes technical decisions, chooses patterns | Write code |
| **Daedalus** | Planner | Decomposes into executable steps | Make architectural decisions |
| **Hephaestus** | Implementer | Writes code per plan | Decide what to build |
| **Themis** | Reviewer | Judges code against standards | Fix code |
| **Aletheia** | Tester | Writes and runs tests | Modify application code |
| **Mnemosyne** | Reflector | Analyzes outcomes for learning | Change rules directly |
| **Argus** | Auditor | Independent system health checks | Modify system files |

**Why this matters:** when one AI does everything, it cuts corners. When an Explorer is structurally forbidden from proposing solutions, it actually explores. When an Implementer can't decide what to build, it follows the plan. Boundaries create reliability.

---

## 4 pipelines, zero guesswork

Apollo classifies the task. Classification determines the pipeline. Pipeline determines the process. No judgment calls, no "let me figure out the best approach."

### Quick — 1-3 minutes

Small task, high confidence. Classify → explore → implement → review. Two gates.

### Standard — the workhorse

Medium tasks. Explore + analyze in parallel → architect → plan → implement in batches → review → test. Four gates. Implementers run in parallel with dependency-aware scheduling (Critical Path Method).

### Full — large tasks

Standard + per-phase gates and checkpoints. Each phase can resume in a new session. Integration testing across boundaries.

### Decomposition — epics

Breaks epic into independent tasks, each runs through its own pipeline. Dependency ordering, per-task checkpoints, cross-task integration.

| Size | Criteria | Pipeline | Gates |
|---|---|---|---|
| **Small** (high confidence) | 1-2 files, local change | Quick | 2 |
| **Small** (low confidence) | Uncertain scope → auto-upgrades | Standard | 4 |
| **Medium** | 3-10 files, needs context | Standard | 4 |
| **Large** | Architecture changes, >10 files | Full | 5+ |
| **Epic** | Multiple related tasks | Decomposition | Many |

---

## Gates — you decide, always

Named **Atropos** — the Fate who cuts the thread. Irreversible decision points.

```
═══════════════════════════════════════
 GATE: Architecture Approval
═══════════════════════════════════════

 Summary:
 Adapter pattern for OAuth2 integration, abstracting
 provider-specific logic behind a common interface.

 Key points:
 • 3 new files, 2 modified
 • Strategy pattern rejected — over-engineering for 2 providers
 • No breaking changes to existing auth flow

 Impact: 5 files, ~12% estimated budget

 ▸ proceed   — approve and continue
 ▸ details   — show full reasoning document
 ▸ modify    — provide feedback for revision
 ▸ abort     — cancel task
═══════════════════════════════════════
```

Gates cannot be skipped, reordered, or made optional. Not by configuration, not by prompt, not by any agent. This is a constitutional invariant.

---

## Knowledge that survives sessions

Every task Moira runs makes the system smarter for the next one. All knowledge is evidence-based — no speculation, only verified facts from actual execution.

| Type | What it captures |
|---|---|
| **Project model** | Architecture, components, data flow, entry points |
| **Conventions** | Naming, imports, patterns, file organization |
| **Decisions** | Why this approach was chosen, what was rejected |
| **Patterns** | What works, what doesn't — with evidence from real tasks |
| **Failures** | What went wrong, root cause, prevention strategy |
| **Quality map** | Per-area quality assessment of your codebase |

Knowledge lives in your repo. Committed, versioned, shared with the team. New team members get the full context on day one.

Three access levels keep context clean: **L0** (index) → **L1** (summary) → **L2** (full detail). Agents get only what they need. Orchestrator never reads L2.

---

## 5 quality gates — problems caught early, not late

| Gate | What | Agent |
|---|---|---|
| **Q1** | Requirements complete? Edge cases? Error scenarios? | Athena |
| **Q2** | Architecture sound? SOLID? No circular deps? APIs verified? | Metis |
| **Q3** | Plan feasible? Files exist? Budget fits? Dependencies ordered? | Daedalus |
| **Q4** | Code correct? Standards? Security? Performance? No fabrication? | Themis |
| **Q5** | Tests cover happy path, errors, edge cases, regression? | Aletheia |

Critical issues → Implementer retries with feedback (up to 3 attempts) → then escalation to you. Not silent. Not hidden.

---

## Context under control

The #1 failure mode of AI coding: context window overflow. Claude reads too much, starts hallucinating, produces garbage. Moira prevents this structurally:

- **Isolated agent contexts** — each agent gets its own context window
- **Orchestrator diet** — summaries only, never full files, stays under 25%
- **Pre-execution estimation** — budget overflow caught before it happens
- **Auto-checkpoint at 60%** — work is saved, resume in a new session

```
⚡ context: 23k/1M ▓▓░░░░░░░░ 2%
```

Green (0-25%) → yellow (25-40%) → orange (40-60%) → red (60%+, forced checkpoint).

---

## Commands

| Command | What it does |
|---|---|
| `/moira init` | Scan project, generate config and knowledge base |
| `/moira <task>` | Execute task through the appropriate pipeline |
| `/moira resume` | Resume interrupted task from last checkpoint |
| `/moira status` | Current task, progress, system health |
| `/moira knowledge` | Browse accumulated project knowledge |
| `/moira metrics` | Performance dashboard and trends |
| `/moira audit` | System health check (5 domains) |
| `/moira bench` | Run behavioral test suite |
| `/moira refresh` | Re-scan project without full re-init |
| `/moira upgrade` | Upgrade to latest version |
| `/moira bypass: <task>` | Skip the pipeline (logged, requires confirmation) |
| `/moira help` | Documentation and glossary |

### After completion

```
▸ done    — accept changes
▸ tweak   — targeted modification ("make the error message more specific")
▸ redo    — rollback + re-enter at architecture, plan, or implementation
▸ diff    — show full git diff
▸ test    — run additional tests
```

---

## Architecture

```
┌───────────────────────────────────────────────────┐
│         GLOBAL LAYER (~/.claude/moira/)           │
│                                                   │
│  Installed once per machine. Shared across all    │
│  projects. Orchestrator, agent templates,         │
│  pipeline defs, quality criteria, hooks.          │
└────────────────────────┬──────────────────────────┘
                         │  /moira init generates
┌────────────────────────▼──────────────────────────┐
│        PROJECT LAYER (.claude/moira/)             │
│                                                   │
│  Generated per project. Committed to repo.        │
│  Project-adapted rules, knowledge base,           │
│  conventions, MCP registry, budgets.              │
└────────────────────────┬──────────────────────────┘
                         │  executes via
┌────────────────────────▼──────────────────────────┐
│         EXECUTION LAYER (agents)                  │
│                                                   │
│  Apollo · Hermes · Athena · Metis · Daedalus      │
│  Hephaestus · Themis · Aletheia · Mnemosyne       │
│  Argus                                            │
└───────────────────────────────────────────────────┘
```

### How data flows

```
User → /moira <task>
  │
  Orchestrator reads: pipeline definition + task state (minimal tokens)
  Orchestrator spawns: Apollo (classifier)
  │
  Apollo writes: full classification to state/tasks/{id}/classification.md
  Apollo returns to orchestrator: one-line summary only
  │
  Orchestrator presents: GATE → you approve or redirect
  │
  ... each agent writes full output to state files ...
  ... orchestrator reads only summaries ...
  ... orchestrator context stays minimal ...
```

**Key insight:** the orchestrator never reads full agent output. It reads one-line summaries. All the detailed work lives in agent contexts (isolated, disposable). This is why Moira can handle large tasks without context degradation.

### File structure

```
~/.claude/moira/
├── core/rules/           # Base rules + 10 agent roles + Q1-Q5 quality checklists
├── core/pipelines/       # quick.yaml, standard.yaml, full.yaml, decomposition.yaml
├── skills/               # Orchestrator, gates, dispatch, errors, reflection
├── hooks/                # guard.sh (violation detection), budget-track.sh
├── templates/            # Bootstrap scanners, LLM-judge rubrics, audit templates
├── schemas/              # 12 YAML schemas (config, state, metrics, telemetry, etc.)
├── statusline/           # Real-time context tracking in terminal
└── lib/                  # 20 shell libraries

<project>/.claude/moira/
├── project/rules/        # Stack, conventions, patterns, boundaries
├── knowledge/            # 6 types × 3 levels — committed, shared with team
├── config/               # MCP registry, budgets, locks
└── state/                # Task execution (gitignored, per-developer)
```

---

## Self-protection — the system guards itself

### The Constitution (Ananke)

Six articles of inviolable invariants. No agent, skill, hook, or automated process can modify them. Only you can.

| Article | Guards |
|---|---|
| **1. Separation** | Orchestrator never touches code. Agents never cross role boundaries. |
| **2. Determinism** | Same classification → same pipeline. Gates cannot be skipped. No implicit decisions. |
| **3. Transparency** | Every decision traceable. Budget visible. Errors reported, never swallowed. |
| **4. Safety** | No fabrication. User has final authority. Everything is reversible. |
| **5. Knowledge** | Evidence-based only. Rule changes require 3+ confirmations. |
| **6. Self-protection** | Constitution is immutable. Design docs are truth. Invariants verified before every change. |

### Three-layer defense (Aegis)

```
┌──────────────────────────────────────────┐
│  Constitutional Verifier                 │
│  BLOCKS changes that violate invariants  │
├──────────────────────────────────────────┤
│  Design Conformance Checker              │
│  WARNS on deviations from design docs    │
├──────────────────────────────────────────┤
│  Regression Detection                    │
│  Verifies existing capabilities survive  │
└──────────────────────────────────────────┘
```

---

## Testing

| Tier | What | Cost | When |
|---|---|---|---|
| **1** Structural | bash + grep, deterministic checks | 0 tokens | Every change |
| **2** Behavioral | Full Moira runs on fixture projects, LLM-as-judge | High | Prompt/rule changes |
| **3** Full Bench | All tests + statistical confidence bands | Very high | Pipeline/gate/role changes |

Plus live telemetry — passive, per-task metrics (numbers only, never content).

---

## Teams

```bash
# First developer
curl -fsSL https://.../install.sh | bash   # one-time
cd project && claude
> /moira init                                # scan + generate
git add .claude/moira/ && git commit         # share config + knowledge

# Everyone else
curl -fsSL https://.../install.sh | bash   # one-time
git pull && cd project && claude
> /moira init                                # detects existing config, ready
```

Project config and knowledge travel with the repo. Task state is per-developer (gitignored). New team members inherit accumulated project knowledge immediately.

---

## Glossary

| Name | Greek | What |
|---|---|---|
| **Moira** | Μοῖρα | The system itself — weaves all threads |
| **Ananke** | Ἀνάγκη | Constitution — the force above fate |
| **Kloto** | Κλωθώ | "The spinner" — dispatch phase |
| **Lachesis** | Λάχεσις | "The allotter" — execution phase |
| **Atropos** | Ἄτροπος | "The unturnable" — approval gates |
| **Aegis** | Αἰγίς | Self-protection shield |
| **Chronos** | Χρόνος | Context budget system |
| **Klosthos** | κλωστή | Thread — unit of work |
| **Moiragetes** | Μοιραγέτης | Metrics — "leader of the Fates" |

---

## Principles

1. **Orchestrator never executes** — dispatches agents, never reads/writes project code
2. **File-based communication** — agents write to state files, orchestrator reads summaries
3. **Deterministic pipelines** — same task type = same path, always
4. **Gates before action** — no code without engineer approval
5. **Knowledge compounds** — system learns, but changes require 3+ confirmations
6. **Never fabricate** — unknown information → stop and report
7. **Design docs are truth** — implementation follows design, not the reverse

---

## Under the hood

No compiled code. No runtime dependencies. No daemon. No server. No npm install.

| Files | Purpose |
|---|---|
| Markdown (`.md`) | Agent prompts, skills, orchestrator logic |
| YAML (`.yaml`) | Rules, configs, schemas, pipelines |
| Shell (`.sh`) | Hooks, libraries, installation |

Moira runs entirely within Claude Code's native infrastructure. Installation = copying files to the right places.

---

## Design documents

| Document | What's inside |
|---|---|
| [System Design](design/SYSTEM-DESIGN.md) | Complete index of everything |
| [Architecture](design/architecture/overview.md) | Layers, data flow, file structure |
| [Agents](design/architecture/agents.md) | Types, contracts, boundaries |
| [Pipelines](design/architecture/pipelines.md) | Flows, batching, CPM scheduling |
| [Rules](design/architecture/rules.md) | 4-layer rule system |
| [Distribution](design/architecture/distribution.md) | Install, setup, updates |
| [Naming](design/architecture/naming.md) | Greek mythology system |
| [Commands](design/architecture/commands.md) | Full command reference |
| [Constitution](design/CONSTITUTION.md) | Inviolable invariants |
| [Decisions](design/decisions/log.md) | Every architectural decision with reasoning |
| [Roadmap](design/IMPLEMENTATION-ROADMAP.md) | 12-phase build order |

---

## Status

All 12 implementation phases complete. System design: 30+ documents. 100+ architectural decisions logged.

---

## License

MIT
