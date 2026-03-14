# Review Implementation Plan

You are performing a rigorous review of a Moira phase implementation plan.

## Input

The user provides a path to a plan file (e.g., `design/specs/2026-03-13-phase8-implementation-plan.md`).

If no argument provided, find the most recently modified `design/specs/*-implementation-plan.md` file.

## Process

### Phase 1: Load Context

Before dispatching agents, read:
1. The plan file being reviewed
2. The corresponding spec (same date/phase prefix, without `-implementation-plan`)
3. `CLAUDE.md` — Phase Implementation Process section, especially plan rules

Extract from the plan: chunks, tasks, file paths, dependency graph.

### Phase 2: Parallel Review Agents (dispatch all in one message)

**Agent 1 — Spec Coverage Verification**

Read the plan AND the spec. Check:

- For EACH deliverable in the spec: is there at least one task in the plan that produces it?
- For EACH success criterion in the spec: does the plan include verification?
- Does the plan introduce work NOT in the spec? (scope creep)
- Does the plan skip any spec deliverable? (coverage gap)
- Does the plan's dependency order match the spec's implied order?

Output: coverage matrix (spec deliverable → plan task(s)) + gaps + scope creep items.

**Agent 2 — Accuracy & File Verification**

Read the plan. For EACH task that references existing files:

1. Verify the file actually exists at the specified path (use Glob/Read)
2. If the task says "modify line X" or "add after section Y" — verify that content exists
3. If the task quotes values from design docs (thresholds, enum values, agent names) — read the source and verify
4. If the task creates a new file — verify the directory exists and the path matches `design/architecture/overview.md` conventions

Also check:
- Are commit messages in the correct format (`moira(<scope>): <description>`)?
- Do chunk boundaries make sense (each chunk is independently committable)?
- Are there circular dependencies in the dependency graph?

Output: file verification results + incorrect references + dependency issues.

**Agent 3 — Design Rule Compliance**

Read the plan and check against CLAUDE.md plan rules:

- [ ] Plan describes WHAT, not full code (no full file contents in the plan)
- [ ] Plan does NOT make design decisions (no new architectural choices without D-xxx)
- [ ] Each task specifies: files to create/modify, source design doc, key points
- [ ] Dependency graph included
- [ ] Each chunk has explicit dependencies listed

Read `design/decisions/log.md` and check:
- Does the plan contradict any decision?
- Does the plan make implicit decisions? (choosing between approaches, defining new constants, inventing field names not in schemas)
- If the plan adds fields to schemas — are they justified by design docs or do they need a decision?

Read the relevant design docs referenced by tasks and verify:
- Each "key point" in the plan actually comes from the cited design doc
- No design doc changes are needed that the plan doesn't mention

Output: rule compliance checklist + implicit decisions found + design doc verification.

**Agent 4 — Cross-Reference & Ripple Effect Check**

Read the plan. For EACH file the plan modifies or creates:

1. Search the codebase for other files that import/reference/depend on it
2. Check: does the plan account for updating those dependent files?
3. If the plan changes a value (threshold, name, path) — grep for all occurrences across the codebase
4. Check: does the plan update ALL occurrences or just some?

Special attention to:
- Schema changes → do skills/libs reference the new/changed fields?
- Role file changes → does agents.md, dispatch.md, knowledge-access-matrix.yaml agree?
- Pipeline changes → do orchestrator.md, gates.md, errors.md agree?
- Shell lib changes → do skills that reference these functions get updated?

Output: ripple effect map (planned change → all affected files → covered by plan yes/no).

### Phase 3: Consolidation

After all 4 agents return, synthesize:

```
# Plan Review: {plan file name}

## Verdict: {APPROVE | APPROVE WITH CHANGES | NEEDS REVISION}

## Summary
{1-3 sentences: coverage quality, biggest concerns}

## Spec Coverage
### Covered
{deliverables with matching tasks}
### Gaps
{spec deliverables without plan tasks}
### Scope Creep
{plan tasks not justified by spec}

## Accuracy
### Verified References
{correct file paths, values, quotes}
### Incorrect References
{wrong paths, stale values, missing files}

## Dependency Analysis
{dependency order issues, circular deps, chunk boundary problems}

## Design Compliance
{rule violations, implicit decisions}

## Cross-Reference Coverage
### Covered Ripple Effects
{changes where all dependent files are updated}
### Uncovered Ripple Effects
{changes where dependent files are NOT updated in the plan}

## Recommended Changes
{numbered list of specific changes needed before approval}
```

Display the review directly to the user (do NOT write to a file unless asked).

## Rules

- The #1 source of implementation bugs is wrong numbers copied into plans. Verify EVERY value against its source.
- Plans that make design decisions are the #2 source of bugs. If the plan says "we'll use X approach" without a D-xxx reference — it's making a decision.
- Cross-reference gaps are the #3 source of bugs. If the plan changes a threshold in budget.sh but doesn't update orchestrator.md — the system becomes inconsistent.
- Be strict on these three. Be lenient on style/formatting.
- Every finding must cite specific file:line.
- Do NOT suggest improvements beyond correctness — only verify the plan is accurate, complete, and compliant.
