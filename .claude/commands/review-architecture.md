# Review Architecture

You are performing a deep architectural review of the Moira system design. Unlike `/system-audit` (which checks implementation matches design) or `/review-spec`/`/review-plan` (which check specs/plans match design), YOUR job is to question the DESIGN ITSELF.

You are an architectural critic. You look for:
- Design smells and structural weaknesses
- Inconsistencies between design documents
- Questionable decisions lacking justification
- Over-engineering and unnecessary complexity
- Under-engineering and missing abstractions
- Gaps, blind spots, and unaddressed failure modes
- Implicit assumptions that should be explicit

## Input

Optional focus argument: a specific area to concentrate on (e.g., "pipelines", "knowledge system", "agent boundaries", "error handling", "quality gates").

If no argument: perform a full-system architectural review.

## Process

### Phase 1: Load Context

Read these files yourself before dispatching agents:
1. `design/CONSTITUTION.md`
2. `design/SYSTEM-DESIGN.md`
3. `design/decisions/log.md`
4. `design/IMPLEMENTATION-ROADMAP.md`

If a focus area was specified, identify which design documents are most relevant. If no focus, all documents are in scope.

### Phase 2: Parallel Architecture Review (dispatch all in one message)

**Agent 1 — Structural Integrity Analysis**

You are an architecture reviewer analyzing structural soundness of a system design.

Read ALL of:
- `design/architecture/overview.md`
- `design/architecture/agents.md`
- `design/architecture/pipelines.md`
- `design/architecture/rules.md`
- `design/CONSTITUTION.md`
- `design/subsystems/quality.md`
- `design/subsystems/knowledge.md`
- `design/subsystems/context-budget.md`

{If focus specified: concentrate on documents related to "{focus}", but still read the overview and constitution for context.}

Analyze and report on:

**Layering & Dependencies**
- Are the 3 layers (global, project, execution) cleanly separated? Any leaky abstractions?
- Do components have clear, minimal dependency interfaces?
- Are there circular conceptual dependencies between subsystems?
- Is the dependency direction consistent (higher layers depend on lower, never reverse)?

**Decomposition Quality**
- Is the granularity consistent? (e.g., are some agents over-specified while others are vague?)
- Are responsibility boundaries clean or do they create awkward handoffs?
- Is any component a "hidden god object" — nominally single-responsibility but accumulating too much influence?
- Are there missing components — gaps between existing ones where work falls through?

**Abstraction Assessment**
- Are abstractions at the right level? Any that feel forced or unnecessary?
- Are there concrete things that should be abstracted? (repeated patterns without a unifying concept)
- Is the 4-layer rule system pulling its weight? Could it be simpler?
- Is the 3-level knowledge system (L0/L1/L2) justified or could 2 levels suffice?

**Symmetry & Consistency**
- Are similar things handled similarly? (e.g., all agents follow the same contract pattern)
- Are there asymmetries that suggest a design inconsistency?
- Is naming consistent and meaningful throughout?

For each finding, explain: what the issue is, why it matters, and suggest a direction (not a full solution). Cite specific file paths and sections.

---

**Agent 2 — Design Coherence & Decision Audit**

You are an architecture reviewer checking whether design documents form a coherent whole.

Read ALL of:
- `design/decisions/log.md` (COMPLETE — all decisions)
- `design/CONSTITUTION.md`
- `design/architecture/agents.md`
- `design/architecture/pipelines.md`
- `design/architecture/rules.md`
- `design/subsystems/quality.md`
- `design/subsystems/knowledge.md`
- `design/subsystems/fault-tolerance.md`
- `design/subsystems/context-budget.md`
- `design/subsystems/self-protection.md`
- `design/subsystems/audit.md`

{If focus specified: concentrate on documents related to "{focus}", but still read the full decision log.}

Analyze and report on:

**Decision Quality**
- For each decision: is the rationale convincing? Are rejected alternatives genuinely inferior, or is the rejection superficial?
- Are there decisions that SHOULD exist but don't? (important choices made implicitly without documentation)
- Are any decisions outdated — made with assumptions that no longer hold?
- Do any decisions contradict each other?

**Cross-Document Consistency**
- When two documents describe the same concept (e.g., agent budgets in agents.md vs context-budget.md), do they agree on specifics (numbers, enums, behaviors)?
- Are there concepts that appear in one document but are absent from documents that should reference them?
- Do subsystem documents reference each other appropriately, or are they silos?

**Assumption Audit**
- What implicit assumptions underlie the design? (e.g., "agents always return parseable responses", "context budget is knowable", "users always respond to gates")
- Which assumptions are fragile — likely to break in practice?
- Which assumptions are undocumented — held by the design but never stated?

**Constitutional Coherence**
- Does the Constitution cover the right invariants? Too many? Too few?
- Are any constitutional articles unenforceable in practice?
- Do the verification tests actually test what they claim?

For each finding, provide: the inconsistency or concern, the specific documents/decisions involved (with file paths), and the potential impact.

---

**Agent 3 — Complexity & Trade-off Analysis**

You are an architecture reviewer evaluating whether the system's complexity is justified.

Read ALL of:
- `design/architecture/overview.md`
- `design/architecture/agents.md`
- `design/architecture/pipelines.md`
- `design/subsystems/quality.md`
- `design/subsystems/knowledge.md`
- `design/subsystems/fault-tolerance.md`
- `design/subsystems/context-budget.md`
- `design/subsystems/checkpoint-resume.md`
- `design/subsystems/self-monitoring.md`
- `design/subsystems/self-protection.md`
- `design/subsystems/metrics.md`
- `design/subsystems/multi-developer.md`
- `design/IMPLEMENTATION-ROADMAP.md`

{If focus specified: concentrate on documents related to "{focus}", but still read the overview for scope.}

Analyze and report on:

**Complexity Budget**
- What is the total complexity of this system? Is it proportional to the problem being solved?
- Identify the TOP 5 most complex subsystems. For each: is the complexity essential (problem is inherently hard) or accidental (design choice made it hard)?
- Are there simpler alternatives that would achieve 80% of the benefit with 20% of the complexity?

**Over-Engineering Signals**
- Features designed but never likely to be used
- Configuration points that will realistically never change from defaults
- Abstractions built for "future flexibility" that may never be needed
- Multiple mechanisms solving the same problem at different levels (redundant safety nets)

**Under-Engineering Signals**
- Areas where the design hand-waves important details ("will be handled later", "TBD")
- Subsystems whose design seems thin relative to their importance
- Error paths that are under-specified compared to happy paths
- Missing integrations between subsystems that should talk to each other

**Trade-off Transparency**
- For each major design choice: what was gained and what was lost?
- Are the trade-offs documented, or just the winning choice?
- Are there trade-offs the design doesn't acknowledge? (e.g., pipeline determinism trades flexibility for predictability — is this always the right trade?)

**YAGNI Assessment**
- Which features are essential for v1?
- Which are "nice to have" that could be deferred without harm?
- Is the 12-phase roadmap front-loaded with essentials, or does it mix must-haves with nice-to-haves?

For each finding: describe the issue, quantify complexity impact where possible (e.g., "this subsystem adds ~15% of total system complexity for a feature used in <5% of tasks"), and suggest whether to simplify, defer, or keep.

---

**Agent 4 — Robustness & Gap Analysis**

You are an architecture reviewer looking for failure modes, edge cases, and gaps in a system design.

Read ALL of:
- `design/architecture/pipelines.md`
- `design/architecture/agents.md`
- `design/subsystems/fault-tolerance.md`
- `design/subsystems/context-budget.md`
- `design/subsystems/checkpoint-resume.md`
- `design/subsystems/self-protection.md`
- `design/subsystems/self-monitoring.md`
- `design/subsystems/knowledge.md`
- `design/subsystems/quality.md`
- `design/architecture/escape-hatch.md`
- `design/architecture/tweak-redo.md`
- `design/CONSTITUTION.md`

{If focus specified: concentrate on documents related to "{focus}", but still read fault-tolerance and self-protection for context.}

Analyze and report on:

**Failure Mode Coverage**
- The E1-E8 error taxonomy: are there failure modes NOT covered? Think about:
  - Agent returns valid format but wrong content (hallucinated architecture decisions)
  - Agent produces output that's technically correct but subtly wrong
  - Multiple agents disagree about facts
  - Pipeline state corruption
  - External environment changes mid-pipeline (files modified by human during execution)
  - Context window silently truncates important information
- For each covered error type: is the recovery strategy realistic? Will it actually work in practice?

**Edge Cases**
- What happens at the boundaries? (0 files to change, 1000 files to change, empty project, monorepo)
- What happens with adversarial input? (task description designed to confuse classifier)
- What if the user gives contradictory gate responses? (approves plan, then later rejects its implementation)
- What about very long-running tasks? (decomposition pipeline with 20+ subtasks)

**Single Points of Failure**
- What components, if they fail, bring down the whole system?
- Is the orchestrator itself a single point of failure? What if IT hallucinates or loses context?
- Is the knowledge system a SPOF? What if knowledge is wrong?
- Is state management a SPOF? What if current.yaml becomes corrupt?

**Degradation Behavior**
- How does the system degrade gracefully? Does it even?
- What's the minimum viable execution path if knowledge, quality maps, and metrics are all unavailable?
- Can the system self-diagnose when it's not working well?

**Security & Trust**
- What prevents a malicious CLAUDE.md or project config from subverting agent behavior?
- What prevents knowledge poisoning (bad patterns stored from a flawed task)?
- How does the system maintain trust boundaries between layers?

For each finding: describe the gap/risk, assess likelihood and impact (high/medium/low), and suggest a mitigation direction.

### Phase 3: Consolidation & Synthesis

After all 4 agents return:

1. **Cross-reference findings** — multiple agents flagging the same area = high-confidence issue
2. **Prioritize** — not by severity alone, but by architectural impact:
   - **Foundational** — affects the system's core model; changing later is very expensive
   - **Structural** — affects component boundaries or interfaces; moderate cost to change
   - **Surface** — affects details within a component; relatively cheap to change
3. **Synthesize discussion points** — group related findings into coherent themes for discussion

### Phase 4: Output

Write the review to: `design/reports/{date}-architecture-review.md`

Use this structure:

```
# Architecture Review
**Date:** {date}
**Focus:** {focus area or "Full System"}
**Reviewed:** {list of documents read}

## Executive Summary
{3-5 sentences: overall architectural health, top concerns, strongest aspects}

## Key Themes
{2-4 overarching themes that emerged across multiple agents' findings}

### Theme 1: {name}
{description of the theme, which findings contribute to it, why it matters}

### Theme 2: {name}
...

## Detailed Findings

### Foundational Issues
{issues that affect the core model — highest priority}

### Structural Issues
{issues that affect component boundaries — moderate priority}

### Surface Issues
{issues within components — lower priority}

## Discussion Points
{questions that don't have clear answers — need user input}

Each question should include:
- The tension or trade-off involved
- Arguments for each side
- What's at stake
- Recommended direction (if one exists)

## Strengths
{what the architecture gets RIGHT — not just problems, also acknowledge good design}

## Recommendations
{prioritized list of suggested changes, grouped by effort:}

### Quick Wins (design doc updates only)
{things that can be fixed by clarifying or correcting documentation}

### Targeted Improvements (design changes, localized)
{changes to specific subsystems or components}

### Strategic Considerations (bigger architectural shifts)
{larger changes to consider — not urgent, but worth discussing}
```

After writing the report, display a summary to the user with the report path and the top 3-5 findings.

## Rules

- You are a CRITIC, not a cheerleader. Be direct about problems. But also acknowledge genuine strengths — good design deserves recognition.
- Every finding must cite specific file paths and sections. No vague claims.
- Distinguish between "this IS broken" and "this COULD be a problem." Use clear confidence levels.
- Don't propose complete solutions — propose directions. The design owner makes the decisions.
- Consider the design's stated goals (predictability, determinism, quality). Evaluate against THOSE goals, not abstract "best practices."
- Accept trade-offs that are intentional and acknowledged. Flag trade-offs that are unacknowledged.
- This is NOT an implementation audit. Don't check if code matches design. Check if the DESIGN makes sense.
- If you find something brilliant, say so. Architecture review should identify what to preserve, not just what to change.
- Be skeptical of complexity. The burden of proof is on the design to justify each layer of indirection, each subsystem, each mechanism.
- Previous architecture reviews in `design/reports/` should be referenced for context (are past issues resolved?).
