# Review Phase Spec

You are performing a rigorous review of a Moira phase specification.

## Input

The user provides a path to a spec file (e.g., `design/specs/2026-03-13-phase8-hooks-self-monitoring.md`).

If no argument provided, find the most recently modified `design/specs/*-phase*` file that does NOT end in `-implementation-plan.md`.

## Process

### Phase 1: Load Context

Before dispatching agents, read these files yourself:
1. The spec file being reviewed
2. `design/CONSTITUTION.md`
3. `design/decisions/log.md`
4. `design/IMPLEMENTATION-ROADMAP.md`
5. `CLAUDE.md` — Phase Implementation Process section

Extract from the spec: which phase, what design docs it references, what deliverables it claims.

### Phase 2: Parallel Review Agents (dispatch all in one message)

**Agent 1 — Design Source Verification**

Given the spec file path: read the spec, extract every design document it references. Then for EACH referenced design doc:
- Read the actual design doc
- Verify every quote, number, enum value, threshold, file path, and agent name the spec claims from that doc
- Check: are there sections of the design doc relevant to this spec that the spec IGNORES?
- Check: does the spec make claims not backed by the design doc?

Also read `design/decisions/log.md` and check:
- Does the spec contradict any existing decision?
- Does the spec make implicit decisions that should be explicit (new architectural choices without D-xxx reference)?
- Are all D-xxx references in the spec valid?

Output: list of verified claims (with "VERIFIED" or "WRONG: expected X, spec says Y") and list of uncovered design doc sections.

**Agent 2 — Completeness & Scope Audit**

Given the spec file path: read the spec and check against the Phase Implementation Process requirements from CLAUDE.md:

Required spec sections:
- [ ] Goal clearly stated
- [ ] Deliverables listed (concrete file paths)
- [ ] Design sources listed (which docs are authoritative)
- [ ] Risk classification (RED/ORANGE/YELLOW/GREEN) for each deliverable
- [ ] Success criteria defined (how to verify the phase is done)

Scope checks:
- Does the spec stay within its phase boundaries per `design/IMPLEMENTATION-ROADMAP.md`?
- Does it depend on phases not yet completed?
- Does it try to implement features from future phases?
- Are all deliverable file paths consistent with `design/architecture/overview.md` file structure?

Constitutional check:
- Read `design/CONSTITUTION.md`
- For each deliverable: which constitutional articles are relevant?
- Does the spec risk violating any invariant?
- Are RED-classified changes properly identified?

Output: completeness checklist results + scope issues + constitutional risk assessment.

**Agent 3 — Cross-System Impact Analysis**

Given the spec file path: read the spec, extract what will change. Then check what ELSE in the system is affected but NOT mentioned in the spec:

1. Read `design/architecture/overview.md` — file structure
2. Read `src/global/skills/orchestrator.md`, `dispatch.md`, `gates.md`, `errors.md` — skills that might reference changed components
3. Read ALL schema files in `src/schemas/` — fields that might need updating
4. Read role files in `src/global/core/rules/roles/` that the spec mentions
5. Read pipeline files in `src/global/core/pipelines/` if relevant

For each change the spec proposes:
- What other files reference this component?
- Will those files need updating?
- Does the spec account for these ripple effects?

Output: impact map (change → affected files → whether spec covers them) + list of uncovered ripple effects.

### Phase 3: Consolidation

After all 3 agents return, synthesize findings into a structured review:

```
# Spec Review: {spec file name}

## Verdict: {APPROVE | APPROVE WITH CHANGES | NEEDS REVISION}

## Summary
{1-3 sentences: overall quality, biggest concerns}

## Design Source Verification
### Verified Claims
{list of correct references}
### Incorrect Claims
{list with: what spec says → what design doc actually says}
### Uncovered Design Sections
{design doc sections relevant but not addressed by spec}

## Completeness
{checklist results}

## Scope Issues
{out-of-scope items, missing dependencies, phase boundary violations}

## Constitutional Risk
{which articles are relevant, any risks identified}

## Impact Analysis
{ripple effects the spec doesn't cover}

## Recommended Changes
{numbered list of specific changes needed before approval}
```

Display the review directly to the user (do NOT write to a file unless asked).

## Rules

- Be strict. A spec that goes to implementation with wrong numbers or missing cross-references causes expensive rework.
- Every finding must cite specific file:line.
- "Looks fine" is not an acceptable review for any section — verify concretely.
- If the spec makes an architectural decision without a D-xxx reference, flag it as "IMPLICIT DECISION — needs decision log entry."
- Do NOT suggest improvements beyond the spec's stated scope — only verify correctness and completeness.
