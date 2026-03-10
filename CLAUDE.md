# Forge Development Rules

## What Is This Project

Forge is a meta-orchestration framework for Claude Code. It transforms Claude from a code executor into a pure orchestrator that dispatches specialized agents through deterministic pipelines.

**Design documents are the source of truth.** All implementation must conform to `design/` documents.

## Critical Files — Read Before ANY Work

Before making any change, you MUST read:

1. `design/CONSTITUTION.md` — inviolable invariants (NEVER violate these)
2. `design/SYSTEM-DESIGN.md` — index of all design documents
3. `design/decisions/log.md` — architectural decisions (don't contradict these)
4. The specific design document relevant to your current task

## Development Protocol

### Before Changes

1. **Read the relevant design docs** for what you're implementing
2. **Impact analysis**: which components are affected? Which constitutional articles?
3. **Design-first**: if implementation needs to deviate from design, update design docs FIRST with user approval. NEVER implement first and document later.
4. **Scope discipline**: implement ONLY what was requested. Note other improvements for future sessions, don't act on them now.

### During Changes

5. **One goal per session**: don't mix unrelated changes
6. **Additive over modifying**: prefer new capabilities alongside existing, over rewriting existing
7. **No speculative improvements**: don't "improve" what hasn't been proven broken through actual use
8. **Maintain all cross-references**: if you change a component, update everything that references it

### After Changes

9. **Regression check**: does everything that worked before still work?
10. **Conformance check**: does implementation match design docs?
11. **Constitutional check**: are all invariants satisfied?
12. **Decision log**: if any new architectural decision was made, add it to `design/decisions/log.md`

## Absolute Prohibitions

- NEVER modify `design/CONSTITUTION.md` — only the user can edit this directly
- NEVER remove or weaken an agent's "NEVER" constraints without constitutional amendment
- NEVER skip approval gates in pipeline definitions
- NEVER merge agent responsibilities (each agent = one role)
- NEVER add auto-proceed logic to gates (user must always confirm)
- NEVER create code paths that modify the Constitution or design docs without user interaction
- NEVER implement features that contradict the Decision Log without updating the Decision Log first

## Change Risk Classification

### RED — Needs constitutional verification + user approval
- Pipeline gate changes
- Agent role boundary changes
- Orchestrator restriction changes
- Inviolable rule changes
- Bypass mechanism changes

### ORANGE — Needs design doc update first
- New agent types
- Pipeline flow changes
- Knowledge structure changes
- Budget allocation changes
- Quality checklist changes

### YELLOW — Needs regression check + impact analysis
- Agent prompt wording
- Rule defaults
- Threshold adjustments
- New MCP integrations

### GREEN — Safe with basic check
- Documentation additions
- Typo fixes
- New knowledge entries
- Example updates

## File Structure Conventions

- Design documents: `design/` (markdown)
- Implementation source: `src/` (to be created per roadmap phases)
- Agent definitions: `src/agents/` (markdown prompt files)
- Skills: `src/skills/` (markdown skill files)
- Core rules: `src/core/rules/` (YAML)
- Hooks: `src/hooks/` (shell scripts)

## Implementation Roadmap

Follow the phase order in `design/IMPLEMENTATION-ROADMAP.md`. Each phase builds on previous phases. Do not skip phases or implement out of order unless explicitly approved.

## Commit Messages

Format: `forge(<scope>): <description>`

Scopes: design, agents, pipeline, rules, knowledge, quality, budget, hooks, mcp, reflection, metrics, audit, checkpoint, ux

Examples:
- `forge(design): add self-protection system documentation`
- `forge(agents): implement explorer agent prompt definition`
- `forge(pipeline): implement standard pipeline state machine`
