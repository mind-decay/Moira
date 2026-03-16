# Moira — System Design

## Overview

Moira is a meta-orchestration framework for Claude Code that transforms Claude from a code executor into a pure orchestrator. The system ensures predictable, high-quality engineering output by enforcing deterministic pipelines, strict agent boundaries, and continuous quality control.

## Design Documents

### Architecture
- [Architecture Overview](architecture/overview.md) — layers, components, data flow
- [Agent Architecture](architecture/agents.md) — agent types, responsibilities, contracts
- [Pipeline Architecture](architecture/pipelines.md) — execution flows per task size
- [Rules Architecture](architecture/rules.md) — modular rule system, layers, assembly
- [Distribution & Installation](architecture/distribution.md) — install, setup, update, team adoption
- [Naming & Identity](architecture/naming.md) — mythology-based naming system, display conventions

### Subsystems
- [Context Budget Management](subsystems/context-budget.md) — token tracking, allocation, monitoring
- [Knowledge System](subsystems/knowledge.md) — layered docs, bootstrapping, freshness
- [Quality Enforcement](subsystems/quality.md) — gates, checklists, code standards, evolution
- [Fault Tolerance](subsystems/fault-tolerance.md) — error taxonomy, recovery strategies
- [MCP Integration](subsystems/mcp.md) — managed MCP usage, registry, caching
- [Audit System](subsystems/audit.md) — rules/knowledge/agent/config/consistency audits
- [Metrics & Reporting](subsystems/metrics.md) — dashboard, trends, drill-down
- [Multi-Developer](subsystems/multi-developer.md) — locks, branch-scoped state, knowledge merge
- [Checkpoint & Resume](subsystems/checkpoint-resume.md) — state persistence, resume validation
- [Orchestrator Self-Monitoring](subsystems/self-monitoring.md) — guard hooks, context tracking
- [Testing](subsystems/testing.md) — structural verification, behavioral bench, live telemetry

### Implementation
- [Implementation Guide](IMPLEMENTATION-GUIDE.md) — full context for implementing agents (read BEFORE any work)
- [Implementation Roadmap](IMPLEMENTATION-ROADMAP.md) — 12-phase build order with dependencies

### Reports
- [Reports directory](reports/) — audit and analysis reports (historical, never modified after creation)

### Self-Protection
- [Constitution](CONSTITUTION.md) — inviolable system invariants
- [Self-Protection System](subsystems/self-protection.md) — three-layer defense against degradation

### Implementation Specs
Active implementation specs live in `design/specs/` by convention. Completed specs are moved to `design/specs/archive/`.

### Decisions
- [Decision Log](decisions/log.md) — all architectural decisions with reasoning
- [Blocker Resolution Design](specs/archive/2026-03-11-blocker-resolution-design.md) — pre-implementation review: Classifier, YAML schemas, distribution, guard mechanism, bootstrap scanners

### Guides
- [Metrics Guide](guides/metrics-guide.md) — what metrics exist, how to read them, when to react

### UX
- [Command Reference](architecture/commands.md) — user-facing commands and flows
- [Onboarding](architecture/onboarding.md) — micro-onboarding flow
- [Escape Hatch](architecture/escape-hatch.md) — controlled bypass mechanism
- [Tweak & Redo](architecture/tweak-redo.md) — post-completion modification flows

## Core Principles

1. **Orchestrator Never Executes** — main Claude dispatches agents, never reads/writes project code
2. **File-Based Communication** — agents write to files, orchestrator reads only summaries
3. **Deterministic Pipelines** — same task type = same execution path
4. **Gates Before Action** — no architecture or code passes without engineer approval
5. **Knowledge Accumulates, Rules Evolve** — system learns, but changes require validation

## North Star

**Predictability.** Given good input, the system produces predictable, high-quality output. No guessing, no rationalization, no creative shortcuts.
