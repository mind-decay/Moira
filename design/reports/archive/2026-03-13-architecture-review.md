# Architecture Review

**Date:** 2026-03-13
**Focus:** Full System
**Reviewed:** CONSTITUTION.md, SYSTEM-DESIGN.md, IMPLEMENTATION-ROADMAP.md, decisions/log.md (all decisions), architecture/overview.md, architecture/agents.md, architecture/pipelines.md, architecture/rules.md, architecture/escape-hatch.md, architecture/tweak-redo.md, subsystems/quality.md, subsystems/knowledge.md, subsystems/context-budget.md, subsystems/fault-tolerance.md, subsystems/self-protection.md, subsystems/self-monitoring.md, subsystems/checkpoint-resume.md, subsystems/metrics.md, subsystems/multi-developer.md, subsystems/audit.md

## Executive Summary

The Moira design is architecturally sound at its core — the orchestrator purity model, deterministic pipelines, knowledge access matrix, and `allowed-tools` structural enforcement are genuinely well-designed. However, the system exhibits significant over-engineering relative to its current maturity (a pre-v1 meta-orchestration tool carrying enterprise-grade subsystem complexity), several cross-document inconsistencies that would produce implementation bugs, and three uncovered failure modes (semantic correctness, multi-agent divergence, silent context truncation) that represent the most dangerous gaps. The design's greatest weakness is the distance between what it claims to guarantee structurally versus what is actually enforced by prompts — a distinction it does not acknowledge.

## Key Themes

### Theme 1: Structural Guarantees vs Behavioral Rules — The Unacknowledged Gap

Multiple agents independently flagged this: the design treats `allowed-tools` enforcement (a true structural guarantee) and agent response contracts (a behavioral rule enforced by prompting) as equivalently reliable. They are not. The fault tolerance system has no explicit acknowledgment that agents can and will deviate from contracts, response formats, and NEVER constraints. The entire pipeline routing depends on agents returning `STATUS: success/blocked/failed` — but this is a prompt, not a contract. The Reviewer and Reflector are the actual safety net for agent misbehavior, but the design frames them as secondary checks rather than primary defenses.

**Impact:** Foundational. If an agent returns malformed output, the orchestrator routing logic has no defined behavior. The lack of a parsing fallback for the response contract is a concrete implementation gap.

### Theme 2: Complexity Disproportionate to Maturity

The system has 10 agents, 4 pipelines, 5 quality gates, 3-level knowledge (×6 categories = 18 documents), 8 error codes, 3-layer self-protection, 4-layer rule hierarchy, checkpoint/resume, multi-developer locks, metrics dashboard, 5-domain audit, and a 3-tier test strategy. This is the design surface of a production platform, not a pre-v1 tool that has executed a handful of test tasks. Several subsystems (multi-developer locks, CONFORM/EVOLVE lifecycle, metrics dashboard, LLM-judge, epic decomposition) are well-designed for a system at 100+ tasks that will never exist if the first 10 tasks don't work well.

**Impact:** Strategic. Over-engineering in the design creates implementation drag and maintenance burden that competes with getting the core loop working.

### Theme 3: Cross-Document Inconsistencies That Would Produce Implementation Bugs

Three independent sources describe the Classifier budget differently: agents.md says 20k, context-budget.md budget YAML omits it entirely, and the budget report example shows 60k. The QUALITY response contract field (D-049) exists only in the decision log, not in agents.md. The guard.sh hook would generate false positives for every legitimate agent file read. Quick Pipeline retry limit (max 1) contradicts fault-tolerance.md's universal "max 2." The knowledge access matrix exists in three locations (knowledge.md, agents.md, knowledge-access-matrix.yaml) with no declared authoritative source.

**Impact:** Structural. These are not theoretical concerns — they would produce wrong implementations.

### Theme 4: Three Missing Failure Modes

The E1-E8 taxonomy covers structural and operational failures well but misses the three most insidious LLM-specific failure modes:

- **E9-SEMANTIC:** Agent returns valid format but wrong content (hallucinated architecture, subtly wrong implementation). No quality gate catches this because gates check structure, not semantics. The architecture gate is the user's only defense.
- **E10-DIVERGE:** Multiple agents disagree about facts (Explorer says 14 endpoints, Analyst scopes 6). The Architect synthesizes both but has no explicit mandate to detect contradictions.
- **E11-TRUNCATION:** Silent context window overflow causes an agent to lose early instructions. Agent returns success. No detection mechanism exists.

**Impact:** Foundational. These are the failure modes most likely to cause real damage in production use, and the design has no recovery strategy for any of them.

## Detailed Findings

### Foundational Issues

**F-1: Response contract is behavioral, not structural**
The entire pipeline routing depends on agents returning `STATUS:` / `SUMMARY:` / `ARTIFACTS:` / `NEXT:` format. This is enforced by prompting, not by parsing guarantees. No fallback for malformed output is defined. E6-AGENT handles crash/timeout but not "output that doesn't parse."
*Files:* `architecture/agents.md:9-18`, `subsystems/fault-tolerance.md` E6
*Direction:* Define a response parsing fallback — if format is unrecognizable, treat as E6.

**F-2: Three uncovered failure modes (E9/E10/E11)**
Semantic correctness failures, multi-agent factual disagreement, and silent context truncation are not in the error taxonomy. These are the highest-impact LLM-specific failures.
*Files:* `subsystems/fault-tolerance.md` (complete)
*Direction:* Add E9-SEMANTIC, E10-DIVERGE, E11-TRUNCATION with detection heuristics and recovery paths. E9's primary defense is the architecture gate UX. E11's defense is agent "context loaded" summary.

**F-3: D-048 bench_mode contradicts Art 4.2**
Art 4.2 says "No auto-proceed logic exists." Bench mode is auto-proceed logic. The decision's reasoning ("user explicitly chose bench") is a constitutional interpretation that requires amendment, not a decision entry.
*Files:* `decisions/log.md` D-048, `CONSTITUTION.md` Art 4.2
*Direction:* Either amend Art 4.2 to exclude bench mode explicitly, or remove bench_mode from the production schema.

**F-4: Knowledge poisoning has no independent verification loop**
Wrong patterns enter knowledge → subsequent tasks use them → Reflector sees success → confidence increases. The consistency check (Art 5.3) compares new entries against existing entries but cannot detect if existing entries are wrong. No mechanism cross-validates knowledge against actual source code.
*Files:* `subsystems/knowledge.md` consistency check, `CONSTITUTION.md` Art 5.1/5.3
*Direction:* Auditor's mandate should include periodic knowledge-vs-source-code cross-validation.

**F-5: Classifier misclassification is the highest-impact single failure with no audit**
A misclassified large task through Quick Pipeline gets no architecture review, no plan approval, 1 retry. The audit system tracks Explorer accuracy and Architect acceptance but not Classifier accuracy.
*Files:* `architecture/agents.md` Classifier, `subsystems/audit.md` Agent Performance
*Direction:* Add Classifier accuracy tracking. The gate override rate (user changes classification at Gate #1) is a direct proxy.

### Structural Issues

**S-1: Classifier budget inconsistency — three different values**
agents.md: 20k. budget YAML in context-budget.md: absent. Budget report example: 60k.
*Files:* `architecture/agents.md:58`, `subsystems/context-budget.md:29-86,133`
*Direction:* Fix to 20k everywhere. Add Classifier to budget YAML.

**S-2: QUALITY response contract field missing from agents.md**
D-049 adds a fifth field. agents.md still shows four fields.
*Files:* `architecture/agents.md:9-18`, `decisions/log.md` D-049
*Direction:* Update agents.md response contract section.

**S-3: guard.sh will generate false positives for all agent file reads**
The path check `file_path != *".moira"*` triggers on agents reading project source files. No mechanism distinguishes orchestrator from agent tool calls.
*Files:* `subsystems/self-monitoring.md:80-85`
*Direction:* guard.sh only runs in orchestrator context (PostToolUse on the command, not on subagents). Clarify this in the design. If Claude Code's hook system fires on subagent tool calls too, this is a platform constraint to document.

**S-4: Quick Pipeline knowledge accumulation gap**
Quick Pipeline reflection is "file note, no agent." The note format is undefined. Knowledge.md says "every task adds knowledge" — but Quick tasks have no Reflector to do this.
*Files:* `architecture/pipelines.md` Quick Pipeline, `subsystems/knowledge.md` Phase 2
*Direction:* Define the file note format and specify who writes it. Either lightweight Reflector invocation or orchestrator-produced structured note.

**S-5: Planner (Daedalus) is a hidden accumulator of 4 responsibilities**
Decomposition, file dependency graph, budget estimation, and instruction file assembly. Art 1.3 prohibits god components. If any of the 4 functions fails, the failure cause is ambiguous.
*Files:* `architecture/agents.md` Planner, `subsystems/context-budget.md` budget estimation
*Direction:* At minimum, define the 4 functions as explicit sub-phases in the Planner's contract with distinct success/failure conditions.

**S-6: Knowledge write-access matrix is missing**
Read access is well-defined. No specification of which agents may write to which knowledge files. Reflector has "full access" — does that include decisions log?
*Files:* `subsystems/knowledge.md` access matrix
*Direction:* Add write-access columns to the knowledge access matrix.

**S-7: Three-source knowledge access matrix creates maintenance trap**
knowledge.md table, per-agent fields in agents.md, and knowledge-access-matrix.yaml. D-039 already resolved one divergence. The structural problem persists.
*Files:* `subsystems/knowledge.md:18-31`, `architecture/agents.md` per-agent sections, `src/global/core/knowledge-access-matrix.yaml`
*Direction:* Declare one authoritative source (knowledge-access-matrix.yaml) and have the others reference it.

**S-8: Monorepo / large codebase — Explorer budget insufficient**
Explorer has 140k budget. A monorepo with 50 packages won't fit breadth-first. No scoping strategy exists.
*Files:* `architecture/agents.md` Explorer budget, `subsystems/context-budget.md`
*Direction:* Add monorepo detection and package-level scoping to Explorer's design.

**S-9: Plan-gate feedback contradicting architecture gate has no re-trigger path**
User approves architecture. At plan gate, gives feedback that implies different architecture. No mechanism returns to architecture gate.
*Files:* `architecture/pipelines.md` Standard Pipeline gates
*Direction:* Plan gate "modify" option should detect architectural-level feedback and offer architecture gate re-entry.

**S-10: Reflector has weakest specification despite highest systemic impact**
No exit criteria, no minimum output structure, no checklist. Feeds knowledge updates and rule change proposals — the most impactful outputs in the system.
*Files:* `architecture/agents.md` Reflector section
*Direction:* Add exit criteria and minimum output structure matching other agents' specificity.

### Surface Issues

**U-1: Audit trigger naming — "full" vs "standard" for 20-task audit**
*Files:* `subsystems/audit.md:11,28`

**U-2: Quick Pipeline retry limit (max 1) not in fault-tolerance.md (says max 2)**
*Files:* `subsystems/fault-tolerance.md:94`, `architecture/pipelines.md:37`

**U-3: Reflector budget (80k, 40k working) tight for L2 access to all 6 knowledge categories**
6 categories × L2 (up to 10k each) = up to 60k. Plus task state. 40k working data is insufficient.
*Files:* `subsystems/knowledge.md:29`, `subsystems/context-budget.md:75-80`

**U-4: self-protection.md references non-existent constitutional-checks.yaml**
*Files:* `subsystems/self-protection.md:213`

**U-5: WARNING gate naming collision with pipeline approval gates**
D-053 introduces a "conditional gate type." The word "gate" is now overloaded.
*Files:* `decisions/log.md` D-053, `CONSTITUTION.md` Art 2.2
*Direction:* Rename to "quality checkpoint" or "quality routing decision."

**U-6: Agent section headers in agents.md use functional names only, not display names**
D-034 convention is "Role (Name)" but agents.md headers say "## Classifier" not "## Classifier (Apollo)."
*Files:* `architecture/agents.md` section headers, `architecture/naming.md`

**U-7: bench_mode flag in current.yaml is production-schema contamination**
D-048 adds test infrastructure to the production state schema.
*Files:* `decisions/log.md` D-048

**U-8: Failures knowledge inaccessible to Analyst and Architect**
The two agents most responsible for preventing failure-prone decisions have no access to failure history (not even L0 index).
*Files:* `subsystems/knowledge.md` access matrix

**U-9: D-064 cites specific model name (Opus 4.6) — fragile to model changes**
*Files:* `decisions/log.md` D-064

**U-10: Rules architecture doesn't show the second assembly path (orchestrator pre-planning)**
D-041 documents that pre-planning agents use orchestrator-assembled rules, but rules.md shows only Planner assembly.
*Files:* `architecture/rules.md`, `decisions/log.md` D-041

## Discussion Points

### 1. Should the knowledge system be simplified to two levels?

**Tension:** L0/L1/L2 creates 18 documents per project. L1 (summary) is the least-referenced level — most agents need either the index (L0) or the full document (L2). The access matrix shows L1 is used by Classifier, Architect, Implementer, and Reviewer — but L1 is the hardest level to maintain because it requires editorial judgment about what to include.

**For three levels:** Finer-grained context control. Some agents genuinely need more than an index but less than the full document.
**For two levels:** 33% fewer knowledge documents. Simpler maintenance. The access matrix adjustments are straightforward (L1 readers get either L0 or L2 depending on their needs).
**At stake:** 6 extra documents per project × ongoing maintenance cost vs. context optimization for 4 agents.
**Recommended direction:** Keep three levels for now, but consider collapsing to two if L1 maintenance proves burdensome in practice.

### 2. Is the 4-layer rule hierarchy justified for a single-developer tool?

**Tension:** Layer 3 (project rules) and Layer 4 (task-specific) are essential. Layers 1-2 (base + role) address multi-project rule reuse — a concern for a system with one user on one project at a time.

**For four layers:** Clean separation, DRY rules, future multi-project support.
**For simplification:** Merge layers 1-2 into "global defaults." Keep project and task layers. Three layers instead of four, same behavior for the common case.
**At stake:** Implementation complexity of conflict detection (4-way vs 3-way merge).
**Recommended direction:** Keep the conceptual model but note that layers 1-2 can be implemented as a single file in v1 without loss.

### 3. Should the multi-developer lock system be deferred entirely?

**Tension:** Locks.yaml with TTL and stale detection is a serious coordination mechanism. The design acknowledges merge conflicts fall through to git anyway. Branch-based isolation may be sufficient.

**For locks:** Advisory protection against wasted work. Visible coordination signal.
**For deferral:** Implementation cost is high. Git branch isolation is free. The lock system's value is advisory (cannot prevent actual conflicts). No evidence of need until multiple users exist.
**At stake:** Phase 12 scope. Multi-developer support is a selling point but may not be needed for v1 validation.
**Recommended direction:** Defer to post-v1. Branch-based isolation is sufficient for initial multi-developer use.

### 4. Should Tweak/Redo be moved earlier in the roadmap?

**Tension:** Currently Phase 12. Users will want to adjust results from the first task they run. "Modify the implementation" is the most natural response to seeing a result.

**For moving earlier:** Essential for practical usability. Users hitting "I want to change this" with no mechanism will bypass the system entirely.
**For keeping late:** Tweak/Redo depends on git integration, state management, and pipeline re-entry — complex infrastructure.
**At stake:** User experience from Phase 5 onward (when `/moira init` works and users start running tasks).
**Recommended direction:** Implement basic Tweak (user feedback → Implementer retry with modified instructions) in Phase 6 or 7. Defer full Redo (git revert + pipeline re-entry at specific step) to Phase 12.

### 5. What is the minimum viable task size below which the pipeline is always wrong?

**Tension:** The Quick Pipeline runs Classifier → Explorer → Implementer → Reviewer — four sequential agents for what might be a one-line fix. The escape hatch exists, but the design doesn't acknowledge that some tasks are below the system's useful range.

**For a minimum:** Honest documentation. Prevents user frustration.
**Against:** Hard to define objectively. What seems "trivial" may have hidden complexity.
**At stake:** User trust. If the system is slower than direct editing for genuinely trivial tasks, users will bypass habitually, which undermines the system's value for tasks where it genuinely helps.
**Recommended direction:** Document that the Quick Pipeline adds ~1-3 minutes of overhead and is designed for tasks where "getting it right the first time" matters more than speed. Tasks that can be done correctly in under 30 seconds are better served by the escape hatch.

## Strengths

**Orchestrator purity with structural enforcement.** The `allowed-tools` mechanism (D-031) is the single most important design decision. It makes orchestrator containment a platform guarantee, not a behavioral rule. This is genuinely novel and well-executed.

**The decision log.** 64+ decisions with explicit alternatives-rejected sections, honest about bugs encountered (D-060, D-061, D-062, D-063), and cross-referenced by subsequent decisions. This is an unusually high-quality design artifact.

**Knowledge access matrix.** The per-agent, per-knowledge-type, per-level access table is one of the best-designed elements. Explorer getting L0 to "stay unbiased" is a subtle and correct design insight.

**Gate system design.** The architecture gate presenting alternatives (not just "approve?") forces genuine engagement. The bypass audit showing error rates (38% vs 17%) creates behavioral incentives. This is systems thinking applied to UX.

**Four-layer rule hierarchy.** The inviolable/overridable distinction with conflict resolution is clean. Layer 4 (task-specific) cannot override Layer 1 (fabrication prohibition). This is the right design.

**Error taxonomy (E1-E6).** Well-matched to real agentic pipeline failures. The user-facing presentations (options with consequences) are concrete and useful. E5-QUALITY's escalation to Architect re-examination on second failure is particularly smart.

**Constitutional model.** Having explicit invariants that require amendment rather than interpretation is the right governance model for a system developed iteratively by an AI.

## Recommendations

### Quick Wins (design doc updates only)

1. Fix Classifier budget to 20k in context-budget.md budget YAML and report example (S-1)
2. Add QUALITY field to response contract in agents.md (S-2)
3. Clarify guard.sh scope re: subagent tool calls (S-3)
4. Fix audit trigger naming: "standard" not "full" for 20-task audit (U-1)
5. Fix Quick Pipeline retry limit in fault-tolerance.md or note pipeline-specific limits (U-2)
6. Add mythological names to agents.md section headers (U-6)
7. Update rules.md to show both assembly paths (U-10)
8. Remove specific model name from D-064, use capability threshold instead (U-9)
9. Note self-protection.md reference to non-existent constitutional-checks.yaml (U-4)

### Targeted Improvements (design changes, localized)

10. Define Quick Pipeline file note format and knowledge accumulation path (S-4)
11. Add write-access matrix to knowledge.md (S-6)
12. Add E9-SEMANTIC, E10-DIVERGE, E11-TRUNCATION to fault tolerance taxonomy (F-2)
13. Add Reflector exit criteria and minimum output structure (S-10)
14. Declare authoritative source for knowledge access matrix (S-7)
15. Add Classifier accuracy tracking to audit system (F-5)
16. Define Planner's 4 sub-functions as explicit contract phases (S-5)
17. Evaluate Analyst/Architect L0 access to failures knowledge (U-8)
18. Rename WARNING gate to "quality checkpoint" (U-5)
19. Add response parsing fallback for malformed agent output (F-1)
20. Address plan-gate / architecture-gate contradiction path (S-9)

### Strategic Considerations (bigger architectural shifts)

21. Acknowledge structural-vs-behavioral guarantee distinction in fault tolerance design (Theme 1)
22. Consider simplifying knowledge L0/L1/L2 to L0/L2 if L1 maintenance proves burdensome
23. Defer multi-developer lock system to post-v1 (Discussion Point 3)
24. Move basic Tweak flow earlier in roadmap (Phase 6-7) (Discussion Point 4)
25. Address monorepo/large codebase Explorer scoping (S-8)
26. Add knowledge-vs-source-code cross-validation to Auditor mandate (F-4)
27. Resolve D-048 bench_mode constitutional status — amend Art 4.2 or restructure (F-3)
28. Document minimum viable task size / pipeline overhead expectations (Discussion Point 5)
29. Evaluate deferring CONFORM/EVOLVE lifecycle, metrics dashboard, and LLM-judge to post-v1
