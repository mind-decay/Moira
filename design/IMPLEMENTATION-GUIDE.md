# Implementation Guide

This document provides the full context needed to implement Moira correctly. It captures the intent, priorities, and implicit knowledge from the design sessions that aren't fully expressed in the architectural documents alone.

**Read this BEFORE starting any implementation work. Read it fully, not skimming.**

---

## Who Is This For

You are an AI agent (Claude) tasked with implementing parts of the Moira system. You do NOT have the context of the original design conversations. This document bridges that gap.

## What Moira Is — The Real Motivation

Moira exists because Claude Code, when used directly, has fundamental problems:

1. **Context pollution** — Claude reads files, fills its context, starts hallucinating toward the end of complex tasks
2. **Unpredictable quality** — same task can produce wildly different results depending on session state
3. **Rationalization** — Claude convinces itself that shortcuts are fine ("I'll just quickly check this file myself")
4. **No learning** — knowledge from one task is lost in the next session
5. **No structure** — Claude wings it, with no systematic process from requirements to implementation

Moira solves this by making Claude a **pure orchestrator** that NEVER touches code directly. Instead, it dispatches specialized agents through fixed pipelines. This is not a suggestion — it's the core architectural constraint.

### The Owner's Philosophy

The system owner (the engineer who designed this with the original Claude session) has very specific expectations:

- **Predictability over speed.** A slower system that produces consistent results is better than a fast one that's unpredictable.
- **No vibe coding.** This is an engineering tool, not a toy. Engineers approve every important decision.
- **No rationalization.** If the system is designed to spawn an Explorer agent, it spawns an Explorer agent. It doesn't "just quickly read the file" because it seems faster.
- **Quality code, not clever code.** SOLID, KISS, DRY. No over-engineering. No premature optimization. No magic.
- **Craftsmanship, not compliance.** Agents own the quality of their work. Constraints (NEVER rules) set the floor; quality stance sets the aspiration. YAGNI means don't add unnecessary scope — it doesn't mean write minimal-effort code within scope. (D-185)
- **Evidence over opinion.** The system doesn't "improve" things based on speculation. Changes require evidence from multiple tasks.
- **The system must be self-contained.** No dependencies on external Claude Code skill systems (GSD, Superpowers, etc.). They can change and break us.

## Critical Implementation Context

### The Target Test Project

The first project Moira will be tested on is "ЛК ЮЛ" (личный кабинет юридических лиц — a B2B web portal). It already has some form of orchestration system that Moira will replace. The existing system is considered inadequate — don't reference or build on it.

### Why Not MVP

The owner explicitly rejected an MVP approach. The reasoning: a half-built orchestration system is worse than no orchestration system. If pipelines are incomplete, agents are missing, or quality gates don't work — the system provides false confidence. Build each phase completely before moving to the next.

### Context Budget Is THE Core Engineering Challenge

The entire system exists because of context limits. Every design decision ultimately serves one goal: keep the orchestrator's context clean while agents do heavy work in their own isolated contexts.

When implementing anything, always ask: "Does this add to the orchestrator's context?" If yes, find another way.

### File-Based Communication Is Non-Negotiable

Agents communicate through files, not return messages. When an agent returns to the orchestrator, it returns ONLY a status summary. The detailed work product is in files. This keeps the orchestrator's context minimal.

This means: every agent prompt MUST include instructions to write output to specific state files AND return only a short status. If you write an agent that returns its full analysis to the orchestrator — you've broken the core architecture.

### The Constitution Is Real

`design/CONSTITUTION.md` defines 19 invariants that MUST hold at all times. These are not aspirational — they are binary checks. Before committing any implementation work, verify that no constitutional invariant is violated.

If you find that an invariant makes implementation difficult — that's by design. The invariant exists because violating it leads to system degradation. Find a way to implement within the constraint, or flag it for the user to decide.

---

## How to Implement Each Component

### Agent Prompts (Phase 2)

Agent prompts are the most critical component. A poorly written prompt will produce bad results regardless of how good the pipeline is.

**Structure of every agent prompt:**

```markdown
# Identity
Who you are. ONE sentence. Your single responsibility.

# Input
What you receive. Exact file paths and formats.

# Output
Where you write results. Exact file path.
What you return to orchestrator (STATUS line only).

# Rules
Your constraints. What you MUST do. What you MUST NEVER do.

# Quality Checklist
The specific checklist you must complete (from quality.md).

# Context
Project knowledge loaded for this task (assembled by Planner).
```

**Key prompt engineering principles for Moira agents:**

1. **Be explicit about what NOT to do.** Claude tends to be helpful and do extra work. Every agent needs clear "NEVER" constraints.

2. **Don't rely on Claude "knowing" things.** If an agent needs project conventions, load them explicitly. Don't assume the agent will figure it out.

3. **Make the output format rigid.** Don't say "return a summary." Say "return exactly this format: STATUS: success|failure|blocked / SUMMARY: <1-2 sentences> / ARTIFACTS: <file paths>". Ambiguity in output = context pollution.

4. **Include the anti-fabrication rule in every agent.** Not just in base rules — in the actual prompt. Claude needs constant reminding not to make things up.

5. **Test prompts with adversarial scenarios.** What happens when the agent doesn't have enough information? It should STOP, not guess. Test this explicitly.

### Orchestrator Skill (Phase 3)

The orchestrator is the hardest component because it needs to be powerful (manage complex pipelines) while staying minimal (low context usage).

**Implementation approach:**

The orchestrator skill is a state machine. It reads the current state, determines the next action, dispatches an agent, reads the result status, and transitions to the next state.

```
READ state → DETERMINE next step → DISPATCH agent → READ status → TRANSITION
```

It should NOT:
- Accumulate agent outputs in its context
- Make decisions that agents should make
- Read any file outside `.moira/`
- "Optimize" by combining agent steps

**The orchestrator's internal monologue should be:**
"What state am I in? What does the pipeline say to do next? Dispatch that agent. Read the status. Move to next state."

NOT:
"Let me think about what would be best here... maybe I should read the code first to understand... actually let me just quickly..."

### Rules Assembly (Phase 4)

Rules are assembled by the Planner into per-agent instruction files. The assembly process:

1. Load `core/rules/base.yaml` (Layer 1)
2. Load role-specific rules (Layer 2)
3. Load project rules (Layer 3)
4. Add task-specific instructions (Layer 4)
5. Check for conflicts (higher layer wins, except inviolable)
6. Write to `state/tasks/{id}/instructions/{agent}.md`

**Critical detail:** The assembled instructions must include EVERYTHING the agent needs. The agent should not need to read additional files to understand its task. If it needs project conventions — include them. If it needs the architecture decision — include the relevant excerpt. The agent's context should be self-contained.

This is important because it means the Planner is a critical component that determines agent quality. A bad Planner = bad instructions = bad agent output.

### Bootstrap (/moira init — Phase 5)

Bootstrap must work on ANY project type. Scanners detect everything directly — each scanner writes YAML frontmatter (machine-readable fields) plus a markdown body (human-readable detail). There is no preset layer; config and rules are generated from scanner frontmatter. See D-060 and `design/specs/2026-03-13-bootstrap-scanner-reform.md`.

**Bootstrap scanning strategy:**

1. Read config files first (package.json, tsconfig, Dockerfile, etc.) — these are definitive
2. Read linter configs (.eslintrc, .prettierrc) — these define conventions
3. Sample a few files per directory (not all!) — detect patterns
4. NEVER read the entire codebase — context budget applies to bootstrap agents too

**The quality map generated at bootstrap is PRELIMINARY.** Mark it clearly. Don't let agents treat preliminary assessments as facts. Deep scan happens later in the background.

### Knowledge System (Phase 4)

The three-level system (L0/L1/L2) is not just about file organization — it's about what agents LOAD into their context.

**Practical implementation:**

Each knowledge file has three versions. The KEY is that agents load ONLY their assigned level. This is enforced by the Planner when assembling instructions — Planner includes only the correct level in the agent's instructions file.

Don't implement this as "agent reads L0, then decides if it needs L1." Implement it as "Planner includes exactly the right level in the agent's instructions." The agent never makes the choice.

### Hooks (Phase 8)

The guard hook (`guard.sh`) is the structural enforcement for orchestrator purity. But Claude Code hooks have limitations — research the exact hook API before implementing.

Key questions to verify:
- What arguments does the hook receive? (tool name, file path, etc.)
- Can the hook block a tool call? (critical for guard functionality)
- What's the hook's execution context?

If hooks can't block tool calls, we need an alternative enforcement mechanism. The design assumes hooks CAN block — if they can't, this needs redesign and user approval.

---

## Common Mistakes to Avoid

### Mistake 1: Making the orchestrator too smart

The orchestrator should be dumb — a state machine that follows the pipeline definition. If you find yourself writing complex logic in the orchestrator, you're probably putting logic in the wrong place. Agent selection, task analysis, quality assessment — these belong in agents, not the orchestrator.

### Mistake 2: Leaking agent output into orchestrator context

When an agent returns, the return message goes into the orchestrator's context. If the agent returns 2000 tokens of analysis — that's 2000 tokens of orchestrator context wasted. Agents must return ONLY the status line. Everything else goes to files.

### Mistake 3: Soft constraints instead of hard constraints

"The agent should try to..." is a soft constraint. Claude will ignore it under pressure. "The agent MUST... If not, STATUS: blocked" is a hard constraint. Every important behavior needs hard constraints.

### Mistake 4: Assuming the happy path

Every pipeline step can fail. Every agent can block. Every gate can be rejected. Design for the failure paths with the same rigor as the success paths. The fault tolerance document (`design/subsystems/fault-tolerance.md`) has the full error taxonomy — implement ALL recovery paths, not just the obvious ones.

### Mistake 5: Over-engineering templates

Stack presets and templates should be minimal starting points. They'll be refined by actual project scanning. Don't try to anticipate every possible project configuration in the template — that's the bootstrap agent's job.

### Mistake 6: Ignoring the Constitution during implementation

It's tempting to think "I'll add the constitutional check later." Don't. Run the constitutional invariant checklist against your implementation at the end of every session. Violations found late are much harder to fix.

---

## Implementation Session Checklist

Before starting work:
- [ ] Read CONSTITUTION.md
- [ ] Read CLAUDE.md (development rules)
- [ ] Read the specific design doc for what you're implementing
- [ ] Read the relevant Decision Log entries
- [ ] Understand the current state (what's implemented, what's not)

During work:
- [ ] One goal per session
- [ ] Changes match design docs
- [ ] No scope creep
- [ ] Agent prompts include anti-fabrication rules
- [ ] Agent prompts specify exact output format
- [ ] File-based communication maintained (no context leaking)

After work:
- [ ] Run moira-verifier agent
- [ ] All constitutional invariants still hold
- [ ] Design docs still match implementation
- [ ] New decisions documented in Decision Log
- [ ] Summary of what was done and what's next

---

## File References

All design documents that inform implementation:

| What you're implementing | Read these first |
|--------------------------|------------------|
| File structure / state | `architecture/overview.md` (file structure section) |
| Agent prompts | `architecture/agents.md`, `subsystems/quality.md` (checklists) |
| Orchestrator skill | `architecture/pipelines.md`, `subsystems/fault-tolerance.md` |
| Rules assembly | `architecture/rules.md` |
| Knowledge system | `subsystems/knowledge.md` |
| Bootstrap | `architecture/distribution.md` (init section), `subsystems/knowledge.md` (bootstrapping) |
| Quality gates | `subsystems/quality.md` |
| Budget tracking | `subsystems/context-budget.md` |
| Hooks | `subsystems/self-monitoring.md` |
| MCP integration | `subsystems/mcp.md` |
| Reflection | `subsystems/knowledge.md` (freshness, evolution) |
| Metrics/Audit | `subsystems/metrics.md`, `subsystems/audit.md` |
| Checkpoint/Resume | `subsystems/checkpoint-resume.md` |
| Multi-developer | `subsystems/multi-developer.md` |
| UX/Commands | `architecture/commands.md`, `architecture/onboarding.md` |
| Escape hatch | `architecture/escape-hatch.md` |
| Tweak/Redo | `architecture/tweak-redo.md` |
