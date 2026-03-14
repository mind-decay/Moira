# System Audit

You are performing a comprehensive audit of the Moira system for internal consistency, correctness, and completeness.

## Goal

Find ALL inconsistencies, contradictions, stale references, missing items, and schema/implementation gaps across the entire Moira system. Produce a detailed, actionable fix plan.

## Process

### Phase 1: Parallel Deep Audit

Dispatch **4 parallel agents** (all foreground, single message) covering these audit domains:

**Agent 1 — Agent Architecture Audit**
Read and cross-reference:
- `design/architecture/agents.md` (canonical agent definitions)
- ALL files in `src/global/core/rules/roles/*.yaml`
- `src/global/core/knowledge-access-matrix.yaml`
- `src/global/skills/dispatch.md`
- `design/CONSTITUTION.md` (Art 1.2)

Check for each agent: budget match, knowledge access match (agents.md vs .yaml vs matrix), NEVER constraints present and not weakened, capabilities consistent, response format match, quality gate assignment match. Check dispatch.md agent references, assembly path table completeness.

**Agent 2 — Pipeline & Gate Audit**
Read and cross-reference:
- `design/architecture/pipelines.md`
- ALL files in `src/global/core/pipelines/*.yaml`
- `src/global/skills/orchestrator.md`
- `src/global/skills/gates.md`
- `src/global/skills/errors.md`
- `design/CONSTITUTION.md` (Art 2.1, 2.2)
- `src/schemas/config.schema.yaml`

Check: step sequences match design, all Art 2.2 gates present, gate options match gates.md, error handlers complete across all pipelines, orchestrator Section 3 mapping correct, completion flow consistent, config fields used.

**Agent 3 — Schema & State Audit**
Read and cross-reference:
- ALL files in `src/schemas/*.yaml`
- ALL files in `src/global/lib/*.sh`
- `src/global/skills/orchestrator.md` (Sections 2, 4, 6)
- `src/global/skills/dispatch.md` (state updates)
- `src/global/skills/errors.md` (state updates)
- `src/global/skills/gates.md` (gate state management)
- `design/architecture/overview.md` (file structure)

Check: all fields referenced in skills exist in schemas, no orphaned schema fields, shell functions match skill references, file structure in overview.md matches reality, state paths consistently project-local (D-061), budget constants match design, enum values match between shell code and schemas.

**Agent 4 — Design Document Cross-Reference Audit**
Read and cross-reference:
- `design/CONSTITUTION.md`
- `design/decisions/log.md`
- `design/SYSTEM-DESIGN.md`
- `design/IMPLEMENTATION-ROADMAP.md`
- ALL files in `design/subsystems/`
- ALL files in `design/architecture/`

Check: all documents in SYSTEM-DESIGN.md index exist, all D-xxx references valid, no contradicting decisions, constitutional article references correct, subsystem thresholds match implementation, roadmap reflects latest decisions, knowledge access matrix in knowledge.md complete, no orphaned docs.

### Phase 2: Consolidation & Plan

After all 4 agents return:

1. **Deduplicate** — same issue found by multiple agents = one finding
2. **Classify** by severity:
   - **Critical** — breaks runtime behavior
   - **High** — schema gaps causing silent failures, data loss
   - **Medium** — inconsistencies, documentation gaps affecting correctness
   - **Low** — documentation completeness, cosmetic
3. **Write fix plan** — for each finding:
   - ID, severity, title
   - Exact file paths and line numbers
   - What is wrong (current state)
   - What should be (target state)
   - Concrete fix description (what to change, not full code)
   - Dependencies (if fix X must happen before fix Y)

### Phase 3: Output

Write the audit report to: `design/reports/{date}-system-audit.md`

Use this structure:
```
# Moira System Audit Report
**Date:** {date}
**Scope:** {what was audited}

## Summary
{total findings by severity, overall system health assessment}

## Critical
{findings with fix plans}

## High
{findings with fix plans}

## Medium
{findings with fix plans}

## Low
{findings with fix plans}

## Fix Dependency Graph
{which fixes depend on which, suggested execution order}

## Parallel Fix Groups
{group independent fixes that can be done simultaneously}
```

After writing the report, display a brief summary to the user with the report path.

## Rules

- Every claim must cite specific file path and line number
- Never guess — if uncertain, mark as "NEEDS VERIFICATION"
- Treat design docs as source of truth, implementation must conform
- Flag when design docs contradict each other (don't pick a side — list both)
- Include previous audit reports in context if they exist in `design/reports/`
- Do NOT fix anything — only audit and plan
