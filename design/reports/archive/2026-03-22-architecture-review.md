# Architecture Review

**Date:** 2026-03-22
**Focus:** Full System (emphasis on Analytical Pipeline additions D-117 through D-126)
**Reviewed:** CONSTITUTION.md, SYSTEM-DESIGN.md, IMPLEMENTATION-ROADMAP.md, decisions/log.md (D-001 through D-126), architecture/overview.md, architecture/agents.md, architecture/pipelines.md, architecture/rules.md, architecture/analytical-pipeline.md, architecture/escape-hatch.md, architecture/tweak-redo.md, subsystems/quality.md, subsystems/knowledge.md, subsystems/context-budget.md, subsystems/fault-tolerance.md, subsystems/self-protection.md, subsystems/self-monitoring.md, subsystems/checkpoint-resume.md, subsystems/metrics.md, subsystems/multi-developer.md, subsystems/audit.md
**Previous review:** `design/reports/2026-03-19-architecture-review.md`

## Executive Summary

The Moira design continues to evolve with discipline. All three foundational issues (F-1 through F-3) from the March 19 review are addressed via D-110, D-112, and D-113. The most significant addition since that review is the Analytical Pipeline (D-117 through D-126), which introduces two-dimensional classification, an 11th agent (Calliope), progressive depth with non-linear branching, six CS methods, and four new quality gates. The analytical pipeline direction is architecturally sound — analytical tasks genuinely need a different pipeline structure than code-producing tasks.

The primary concerns in this review are: (1) the analytical pipeline's CS methods are specified at inconsistent levels of detail, with four of six depending heavily on mature Ariadne integration that is itself being designed simultaneously; (2) multiple design documents have not been updated to reflect the analytical pipeline additions, creating a significant cross-document consistency gap; (3) the Constitution requires amendment to accommodate the analytical pipeline's variable-count depth gates; and (4) the analytical pipeline has under-specified error handling, failure modes, and degradation behavior compared to the mature implementation pipelines.

## Key Themes

### Theme 1: The Analytical Pipeline Is Architecturally Sound But Document-Incomplete

Four independent analyses flagged cross-document gaps. Calliope is missing from `context-budget.md` agent budgets and `knowledge.md` access matrix. Hermes's role in `agents.md` doesn't reflect its new Ariadne baseline responsibility (D-125). The `self-protection.md` agent count is hardcoded at "10" (now 11). The Constitution's Article 2.2 gate enumeration doesn't include the Analytical Pipeline. `context-budget.md` still describes the adaptive margin model that D-111 deferred to post-v1. These aren't design flaws — they're document propagation failures from a rapid design session. But the system's own principle (Art 6.2: "Design documents are authoritative source of truth") means stale documents are functional defects.

**Impact:** Foundational. Implementation agents reading these documents will build from inconsistent specifications.

### Theme 2: CS Methods Are Premature Without Mature Ariadne Analytical Integration

CS-1 (fixpoint convergence), CS-2 (graph coverage), CS-4 (abductive reasoning), and CS-5 (information gain) all depend on Ariadne for their primary value — coverage metrics, centrality computations, smell density, structural queries. Without Ariadne, these methods degrade from formal techniques to prompt decoration. The design acknowledges graceful degradation for Ariadne absence but doesn't trace the implication: four of six CS methods become unenforceable without Ariadne data. Meanwhile, CS-3 (hypothesis-driven) and CS-6 (lattice organization) work at any scale without Ariadne and change agent behavior in directly verifiable ways.

The six CS methods are also specified at inconsistent levels of detail. CS-1 has a precise formula but its "qualitatively changed finding" term is undefined. CS-5 uses a proportionality symbol (∝) without concrete weights or computation. CS-3 and CS-6 have actionable output templates. This inconsistency means some methods will be faithfully implemented and others will be interpreted by the LLM differently per invocation.

**Impact:** Strategic. Implementing all six CS methods for v1 adds prompt complexity with uncertain value for the four Ariadne-dependent methods.

### Theme 3: Analytical Pipeline Error Handling Is Under-Specified

The implementation pipelines have a mature 11-code error taxonomy with individual recovery strategies. The analytical pipeline is described as using "the same error handling" but has several unaddressed failure modes:

- No retry path when QA2 (evidence quality) fails at the final gate — re-synthesis against deficient findings loops Calliope without fixing the evidence gap
- No E10-DIVERGE detection when Metis and Argus produce contradictory findings in parallel analytical passes
- No specified behavior for mid-analysis Ariadne unavailability
- No E2-SCOPE equivalent for mid-implementation scope expansion discovered by Implementer
- Ariadne data staleness is not modeled as E8 — potentially stale graph data produces confidently wrong structural analysis
- Calliope's behavior when findings contradict existing document content is unspecified

**Impact:** Structural. These are common-case scenarios, not edge cases, and they affect the analytical pipeline's most important output: architectural findings that drive refactoring decisions.

### Theme 4: Constitutional Amendments Needed for the Analytical Pipeline

Article 2.2 enumerates gates for four pipeline types. The Analytical Pipeline's variable-count depth gates don't fit this enumeration. Article 1.2's Explorer definition ("reads code, reports facts") predates Hermes's new Ariadne baseline responsibility. Article 1.3's test ("No skill file contains logic for multiple pipeline steps") remains unenforceable for the orchestrator despite D-110's governance metric — the exemption isn't constitutionally formalized. The `self-protection.md` verifier YAML for `article_2_2` only covers four pipeline types.

**Impact:** Foundational. Constitutional verification will produce false results for the Analytical Pipeline until amendments are made.

## Detailed Findings

### Foundational Issues

**F-1: Constitution Article 2.2 does not accommodate Analytical Pipeline gates (HIGH confidence)**
Art 2.2 enumerates gate structures for Quick/Standard/Full/Decomposition. The Analytical Pipeline (classify, scope, depth checkpoint(s), final) is absent. The `self-protection.md` verifier YAML also covers only four pipeline types. The analytical-pipeline.md compliance table claims compliance via interpretation ("depth checkpoints may repeat but never skip"), but this is not what Art 2.2 says.
*Files:* `CONSTITUTION.md` Art 2.2, `subsystems/self-protection.md` article_2_2 check, `architecture/analytical-pipeline.md` compliance table
*Direction:* Amend Art 2.2 to accommodate variable-count gates, or explicitly annotate the gate enumeration as implementation-pipeline-specific. Update the verifier YAML.

**F-2: Calliope missing from context-budget.md agent_budgets (HIGH confidence)**
Calliope has an 80k budget defined in `agents.md` and `analytical-pipeline.md` but is absent from the `agent_budgets` YAML block in `context-budget.md`. The budget management system reads this YAML — Calliope will be invisible to budget planning.
*Files:* `subsystems/context-budget.md` agent_budgets, `architecture/agents.md` Calliope section
*Direction:* Add Calliope entry: system_prompt 8k, project_context 10k, working_data 40k, max_total 80k.

**F-3: context-budget.md describes adaptive margin model deferred by D-111 (HIGH confidence)**
The adaptive margin formula (μ + 2σ, cold-start tiers, EMA smoothing) is fully specified in `context-budget.md` as current design. D-111 explicitly defers this to post-v1, choosing "fixed 30% margin." The document was never rolled back.
*Files:* `subsystems/context-budget.md` lines 30-56, `decisions/log.md` D-111
*Direction:* Mark the adaptive margin section as "post-v1 per D-111" or remove it from the active specification. Ensure the v1 behavior (fixed 30%) is clearly stated.

**F-4: CS methods specified at inconsistent levels of detail (HIGH confidence)**
CS-1's "qualitatively changed finding" is undefined. CS-5's proportionality formula has no concrete weights or computation. CS-3 and CS-6 have actionable output templates. Agents will interpret under-specified methods differently per invocation, violating Art 2.1's spirit.
*Files:* `architecture/analytical-pipeline.md` CS method sections
*Direction:* Either fully specify all six methods to the same rigor, or explicitly tier them: "CS-3, CS-6 are operational (v1); CS-1, CS-2, CS-4, CS-5 are heuristic guidance (activate when Ariadne analytical integration matures)."

**F-5: Analytical pipeline error handling is under-specified (HIGH confidence)**
No retry path for QA2/QA4 failure at final gate (re-synthesis loops without fixing evidence). No E10-DIVERGE detection for contradictory Metis/Argus findings. No mid-analysis Ariadne failure handling. No Calliope conflict resolution with existing documents.
*Files:* `subsystems/fault-tolerance.md`, `architecture/analytical-pipeline.md`
*Direction:* Add analytical-specific error recovery paths: re-analyze branch from final gate, E10 cross-comparison in organize step, Ariadne mid-analysis degradation protocol, Calliope supersession rules.

### Structural Issues

**S-1: agents.md Hermes section not updated for D-125 Ariadne baseline responsibility (HIGH confidence)**
D-125 adds Ariadne baseline queries and `ariadne-baseline.md` output to Hermes. The agents.md definition still says "reads code, reports facts" with no mention of graph queries. This also stretches Art 1.2's Explorer definition.
*Files:* `architecture/agents.md` Hermes section, D-125
*Direction:* Update Hermes role definition to include structural graph queries as part of fact-gathering. Consider whether this warrants an Art 1.2 annotation.

**S-2: self-protection.md hardcodes "10 agents" — now 11 with Calliope (HIGH confidence)**
Layer 1 Regression Detection checks "All 10 agents still defined?" This is stale. Every future agent addition requires manual update.
*Files:* `subsystems/self-protection.md` line 58
*Direction:* Replace hardcoded count with enumeration check — "All agents defined in agents.md are present in role files."

**S-3: Duplicate "Agent Spawning Strategy" section in agents.md (HIGH confidence, documentation)**
The section appears twice — at lines 363-370 and again at lines 412-420 (copy-paste artifact from Calliope addition).
*Files:* `architecture/agents.md` lines 412-420
*Direction:* Remove the duplicate.

**S-4: Calliope missing from knowledge.md access matrix (MEDIUM confidence)**
The access matrix in `knowledge.md` lists 10 agents. Calliope's access is defined only in `analytical-pipeline.md`. The authoritative YAML should include Calliope.
*Files:* `subsystems/knowledge.md` access matrix, `architecture/analytical-pipeline.md` Calliope section
*Direction:* Add Calliope row to `knowledge.md` table.

**S-5: Gather step YAML contradicts D-125 prose (HIGH confidence)**
The pipeline YAML shows `ariadne-baseline` as a parallel `action` alongside Hermes. D-125 says Hermes handles both. The YAML abstraction ("action" type) has no defined execution mechanism and breaks the "orchestrator dispatches agents" model.
*Files:* `architecture/analytical-pipeline.md` gather step YAML
*Direction:* Revise YAML to show a single Hermes dispatch with both outputs. Remove the `action` type.

**S-6: Organize step agent unspecified per subtype (MEDIUM confidence)**
The organize step says "agent: metis or athena depending on subtype" but the `agent_map` doesn't include an `organize` field. This forces an implicit orchestrator decision (violates Art 2.3).
*Files:* `architecture/analytical-pipeline.md` organize step, agent_map
*Direction:* Extend agent_map to include organize field per subtype, or designate Metis as universal organizer.

**S-7: "Chronos" appears without definition (MEDIUM confidence)**
`analytical-pipeline.md` references "Chronos tracks normally" for budget tracking. Chronos is not defined in any design document. D-034 naming convention requires `Name (role)` format.
*Files:* `architecture/analytical-pipeline.md` lines 191, 604
*Direction:* Either define Chronos as a named subsystem or replace with the actual mechanism name ("budget-track.sh hook").

**S-8: Redirect option has underspecified state management (MEDIUM confidence)**
The depth checkpoint `redirect → scope` path doesn't specify: what happens to prior analysis findings, whether redirect is limited (like rearchitect's max 1x), or whether Athena receives prior findings as context when re-scoping.
*Files:* `architecture/analytical-pipeline.md` depth checkpoint, D-123
*Direction:* Specify finding preservation, redirect limit, and Athena context on redirect.

**S-9: Calliope write scope not structurally enforced (MEDIUM confidence)**
Calliope's "scoped to documentation paths" constraint is behavioral only. The post-agent git diff check protects Moira system files but doesn't validate against Calliope's authorized file list.
*Files:* `architecture/agents.md` Calliope section, D-099
*Direction:* Include explicit authorized file list in Calliope instructions (same pattern as Hephaestus). Extend post-agent diff check to validate.

**S-10: Themis plays two structurally different roles in analytical pipeline (MEDIUM confidence)**
Depth checkpoint Themis does convergence analysis (meta-analytical). Final review Themis does QA1-QA4 quality assurance. These are different responsibilities dressed in the same agent.
*Files:* `architecture/analytical-pipeline.md` depth_checkpoint and review steps
*Direction:* Acknowledge as design exception with documented reasoning, or separate depth checkpoint convergence into a distinct step.

**S-11: Analytical pipeline QA1/QA2 implicitly require Ariadne (HIGH confidence)**
QA1 requires "Ariadne data consulted for structural coverage verification." QA2 requires "Ariadne metrics cited with concrete numbers." Without Ariadne, both produce systematic CRITICAL failures, making the pipeline unusable — contradicting D-102 (graceful degradation).
*Files:* `architecture/analytical-pipeline.md` QA1/QA2 checklists, D-102
*Direction:* Mark Ariadne-dependent QA items as conditional on availability. Without this, analytical tasks fail by design when Ariadne is absent.

**S-12: Ariadne data staleness not modeled as E8 (MEDIUM confidence)**
Ariadne graph data can go stale between indexing and analytical task execution. Unlike knowledge entries with freshness markers, Ariadne data has no stated freshness tracking. Stale graph data produces confidently wrong structural analysis.
*Files:* `subsystems/fault-tolerance.md` E8, `architecture/analytical-pipeline.md`
*Direction:* Before Tier 1 baseline queries, check Ariadne last-index timestamp vs last git commit. Flag staleness and offer re-index.

**S-13: 3 of 6 analytical subtypes have identical agent composition (MEDIUM confidence)**
Research, design, and decision subtypes all map to `primary: metis, support: []`. The distinction exists only in Ariadne query focus. Without Ariadne, these three subtypes are behaviorally identical.
*Files:* `architecture/analytical-pipeline.md` agent_map
*Direction:* Consolidate to single "investigation" subtype or specify concrete behavioral differences.

**S-14: Analytical pipeline compliance table omits Article 6 (MEDIUM confidence)**
The compliance table covers Art 1-5 but omits Art 6 (Self-Protection) entirely.
*Files:* `architecture/analytical-pipeline.md` compliance table
*Direction:* Add Art 6 entries.

**S-15: Analytical pipeline gate format extends the standard without documentation (MEDIUM confidence)**
The depth checkpoint gate adds Convergence, Coverage sections not in the standard gate format. The standard format in `pipelines.md` is not documented as extensible.
*Files:* `architecture/pipelines.md` gate format, `architecture/analytical-pipeline.md` depth checkpoint UX
*Direction:* Add extensibility note to `pipelines.md` gate format specification.

**S-16: fault-tolerance.md describes Markov retry optimizer in present tense despite D-111 deferral (MEDIUM confidence)**
The Markov retry optimizer is deferred to post-v1 but `fault-tolerance.md` describes it as current behavior.
*Files:* `subsystems/fault-tolerance.md`, D-111
*Direction:* Mark as post-v1 or remove from active specification.

### Surface Issues

**U-1: Metis analytical_mode sections not reflected in agents.md (MEDIUM confidence)**
D-126 specifies `analytical_mode` sections in Metis/Argus role YAMLs. The agents.md definitions have no reference to this structural requirement.
*Direction:* Update agents.md to note analytical_mode extension for Metis, Argus, and Athena.

**U-2: Apollo two-dimensional SUMMARY format increases parse failure risk (MEDIUM confidence)**
The `mode=`, `size=`/`subtype=`, `confidence=` format is more complex. Parse failure would misroute analytical tasks into implementation pipelines.
*Direction:* Treat SUMMARY parsing as validated-tier constraint with explicit parse failure handling in fault-tolerance.md.

**U-3: Progressive depth cost unpredictability not documented as trade-off (LOW confidence)**
Users starting analytical tasks cannot know if it will take 3 gates or 7+. No upfront budget estimate exists for analytical tasks.
*Direction:* Add cost-unpredictability note to analytical-pipeline.md and scope gate UX.

**U-4: D-110 baseline "7 responsibilities" not enumerated (LOW confidence)**
The governance metric has no published list of what counts as a responsibility. The threshold of 10 has no justification for why not 8 or 12.
*Direction:* Enumerate baseline responsibilities in agents.md or orchestrator skill.

**U-5: No session lock prevents concurrent Moira sessions on same branch (LOW confidence)**
Two `/moira:task` in separate terminals against the same branch would collide on state files. Atomic writes prevent corruption but last-write-wins on manifest.
*Direction:* Add session lock file with TTL and PID at pipeline start.

**U-6: Freshness decay model in knowledge.md still shows exponential formula (LOW confidence)**
Same underlying issue as F-3. `knowledge.md` specifies the full `e^(-λ × tasks_since_verified)` model with per-type λ values. D-111 defers this to task-count staleness.
*Direction:* Update knowledge.md to specify task-count staleness per D-111.

## Discussion Points

### 1. Should CS-1, CS-2, CS-4, CS-5 be deferred to post-Ariadne-validation?

**Tension:** These four methods are mathematically motivated and address real analytical failure modes. But their primary value depends on mature Ariadne analytical integration — which is itself being designed simultaneously (Phase 14 deliverable).

**Arguments for keeping all six in v1:** The methods are designed with Ariadne-absent fallbacks. Having the instruction templates ready means agents can use them as soon as Ariadne data quality is demonstrated. Cold-start degradation (informal guidance without Ariadne metrics) still improves over no method at all.

**Arguments for deferring four:** CS-3 (hypothesis-driven) and CS-6 (lattice organization) change agent behavior in directly verifiable ways without Ariadne. CS-1/CS-2/CS-4/CS-5 without Ariadne degrade from formal methods to prompt decoration. Implementing all six adds prompt complexity across 4 agents (Metis, Argus, Athena, Themis) with uncertain v1 value. The methods assume mature Ariadne analytical queries, and the queries assume the methods provide the framework — a chicken-and-egg design.

**At stake:** Phase 14 implementation scope and analytical pipeline prompt complexity.
**Recommended direction:** Implement CS-3 and CS-6 fully for v1. Design CS-1/CS-2/CS-4/CS-5 as stub placeholders that activate when Ariadne analytical integration is validated.

### 2. Does the Analytical Pipeline require Ariadne as a hard dependency?

**Tension:** D-102 says "Moira operates normally without Ariadne." But QA1 and QA2 checklists require Ariadne data, four CS methods depend on it, the gather step assumes it, and coverage computation (CS-2) is undefined without it. The analytical pipeline is functionally crippled without Ariadne — not just "less efficient" (the implementation pipeline degradation) but "unable to pass its own quality gates."

**Arguments for keeping graceful degradation:** Some analytical tasks (documentation, pure research) don't need structural data. Making Ariadne a hard dependency blocks adoption for users who can't install the binary.

**Arguments for acknowledging the dependency:** Pretending the analytical pipeline works without Ariadne sets false expectations. A user running a `weakness` or `audit` analytical task without Ariadne will get systematic QA failures and a confusing experience. Honesty is better than false graceful degradation.

**At stake:** Whether the analytical pipeline has a soft or hard Ariadne dependency, and whether QA gates should be conditional.
**Recommended direction:** Make Ariadne-dependent QA items conditional. Document which analytical subtypes genuinely degrade gracefully (documentation, research) vs which are effectively unusable without Ariadne (audit, weakness). Be honest about the dependency spectrum rather than claiming uniform graceful degradation.

### 3. Should Hermes's expanded analytical role be formalized or reconsidered?

**Tension:** D-125 adds Ariadne baseline queries to Hermes's responsibilities. This is pragmatic (no new agent needed for 6 CLI calls) but stretches the "reads code, reports facts" single responsibility into "reads code AND queries structural graph AND produces two distinct output files."

**Arguments for formalizing:** Hermes already runs CLI commands. Ariadne queries are fact-gathering. The output is still "reports facts." The distinction between code facts and structural graph facts is artificial.

**Arguments for reconsidering:** The 6 Ariadne baseline queries produce structured output (ariadne-baseline.md) that all subsequent analytical agents depend on. This is a substantial second artifact with a different purpose than exploration.md. Budget allocation between two distinct tasks within a single dispatch is underspecified.

**At stake:** Whether Art 1.2's single-responsibility definition is being stretched or legitimately applied.
**Recommended direction:** Formalize in agents.md. Hermes's responsibility is "gathers facts about the project" — code reading and structural graph queries are both fact-gathering. Update the role definition, not the architecture.

## Strengths

**Decision log quality remains the system's greatest asset.** 126 decisions with consistent format, explicit alternatives-rejected sections, and inter-decision references. D-117 through D-126 maintain this quality standard. The log is genuinely usable as an architectural knowledge base.

**The Analytical Pipeline's progressive depth is a genuinely novel design choice.** Rather than forcing analytical tasks into size categories (which is the wrong abstraction), the design lets depth emerge from user-guided iteration. This is architecturally honest about the fundamental difference between code tasks (scope is estimable) and analytical tasks (depth is unknowable upfront).

**D-112 (rearchitect option) and D-123 (conditional branching) are well-designed extensions.** Both add non-linear flow to a deterministic pipeline system without breaking the core model. The "max 1 rearchitect" constraint prevents loops. The `next_step` gate extension is minimal and consistent.

**The Analytical Pipeline's separation of analysis and synthesis (via Calliope) is the right call.** Art 1.2 compliance aside, the practical effect is that analysis agents can focus on depth and rigor without worrying about document structure, and Calliope can focus on clarity and structure without worrying about analytical quality. This is a genuine quality improvement over single-agent analytical tasks.

**D-115 (infrastructure MCP universal injection) demonstrates good feedback-driven design.** The evidence ("72k tokens wasted on sequential file reads, zero MCP calls") led to a precise, minimal fix. This is the design process working as intended.

## Recommendations

### Quick Wins (design doc updates only)

1. Add Calliope to `context-budget.md` agent_budgets (F-2)
2. Add Calliope to `knowledge.md` access matrix (S-4)
3. Fix `self-protection.md` agent count from 10 → 11 or enumeration check (S-2)
4. Remove duplicate Agent Spawning Strategy in `agents.md` (S-3)
5. Update Hermes role definition in `agents.md` for D-125 (S-1)
6. Add Art 6 to analytical pipeline compliance table (S-14)
7. Mark adaptive margin model as post-v1 in `context-budget.md` (F-3)
8. Mark Markov retry optimizer as post-v1 in `fault-tolerance.md` (S-16)
9. Replace "Chronos" with actual mechanism name (S-7)
10. Update `knowledge.md` freshness model to task-count staleness per D-111 (U-6)
11. Add extensibility note to `pipelines.md` gate format (S-15)
12. Note `analytical_mode` extension in `agents.md` for Metis/Argus/Athena (U-1)
13. Fix gather step YAML to reflect D-125 (single Hermes dispatch) (S-5)

### Targeted Improvements (design changes, localized)

14. **Amend Art 2.2** to accommodate variable-count analytical depth gates — **highest priority** (F-1)
15. Make QA1/QA2 Ariadne-dependent items conditional on availability (S-11)
16. Add analytical-specific error recovery paths to `fault-tolerance.md` (F-5)
17. Specify redirect state management: finding preservation, limit, Athena context (S-8)
18. Extend `agent_map` to include organize field per subtype (S-6)
19. Add Ariadne freshness check before Tier 1 baseline queries (S-12)
20. Add Calliope authorized file list in instructions + post-agent diff validation (S-9)
21. Specify E2-SCOPE mid-implementation subtype (Theme 3 / robustness finding)
22. Add E10-DIVERGE detection in organize step for parallel Metis/Argus (Theme 3)

### Strategic Considerations (bigger architectural shifts)

23. **Tier CS methods:** CS-3 and CS-6 as v1 operational; CS-1/CS-2/CS-4/CS-5 as stub placeholders activating with Ariadne maturity (Theme 2)
24. Consolidate research/design/decision subtypes or specify concrete behavioral differences (S-13)
25. Acknowledge Themis dual-role in analytical pipeline as documented design exception (S-10)
26. Add analytical reflection variant for Mnemosyne (implementation-oriented reflection structure doesn't fit analytical tasks)
27. Document cost unpredictability as explicit trade-off in analytical pipeline (U-3)
28. Formalize Art 1.3 orchestrator exemption constitutionally, bounded by D-110 governance (CC-3 from coherence analysis)
