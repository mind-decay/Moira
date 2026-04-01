# Architecture Review

**Date:** 2026-03-19
**Focus:** Full System
**Reviewed:** CONSTITUTION.md, SYSTEM-DESIGN.md, IMPLEMENTATION-ROADMAP.md, decisions/log.md (D-001 through D-109), architecture/overview.md, architecture/agents.md, architecture/pipelines.md, architecture/rules.md, architecture/escape-hatch.md, architecture/tweak-redo.md, subsystems/quality.md, subsystems/knowledge.md, subsystems/context-budget.md, subsystems/fault-tolerance.md, subsystems/self-protection.md, subsystems/self-monitoring.md, subsystems/checkpoint-resume.md, subsystems/metrics.md, subsystems/multi-developer.md, subsystems/audit.md, subsystems/project-graph.md, subsystems/mcp.md
**Previous review:** `design/reports/archive/2026-03-13-architecture-review.md`

## Executive Summary

The Moira design has matured significantly since the March 13 review. Of the 10 structural issues previously flagged, 7 are fully addressed and 2 are partially addressed. The foundational findings (F-1 through F-5) are all resolved or substantially mitigated — notably, the enforcement model (D-065), error taxonomy expansion (E9-E11), bench mode constitutional amendment (D-067), and post-agent guard verification (D-099) demonstrate disciplined design evolution. The architecture's core strengths — orchestrator purity with structural enforcement, the decision log, knowledge access matrix, and deterministic pipelines — remain excellent.

The primary concerns in this review are: (1) the orchestrator skill is becoming a god component with no formal complexity constraint, (2) the formal methods suite (D-094) adds graduate-level statistics to a pre-v1 shell-script tool, (3) one high-impact previous finding remains unaddressed (no backward path from plan gate to architecture), and (4) mid-pipeline state consistency has no structural protection against external file mutations or orchestrator flow errors.

## Key Themes

### Theme 1: The Orchestrator Is Becoming What the Constitution Forbids

Three independent analyses flagged this. The orchestrator skill handles pipeline logic, gate presentation, error routing, budget checking, state management, dispatch, MCP authorization (for Quick Pipeline), and now graph data injection. Art 1.3 says "No single file, agent, or component may accumulate responsibilities that belong to multiple system parts." The Art 1.3 test ("No skill file contains logic for multiple pipeline steps") is subjective enough to pass technically while being violated in spirit. As graph integration (Phase 13), checkpoint/resume (Phase 12), and MCP authorization (Phase 9) are added, this will intensify. No decision constrains orchestrator complexity, and D-064 explicitly defers size optimization.

**Impact:** Foundational. The orchestrator is the single most critical component. Its unbounded growth creates the exact god-component risk the Constitution was designed to prevent.

### Theme 2: Formal Methods Are Premature Optimization

D-094 introduced SPRT (sequential testing), CUSUM (drift detection), Markov retry optimization, Benjamini-Hochberg multiple testing correction, CPM (critical path scheduling), and exponential decay with per-type lambda values. Each is individually well-motivated, but collectively they represent a statistics package for a system that has processed fewer than 10 tasks. SPRT is useful with hundreds of tests — Moira's Tier 2 bench has 3-5. CUSUM needs thousands of data points — Moira processes ~47 tasks/month. BH correction matters with 20+ hypotheses — Moira has 4 metrics. The formal methods add ~30% implementation surface to the subsystems they touch (budget, metrics, testing, knowledge freshness).

**Impact:** Strategic. Implementation drag from statistical machinery competes with getting core features working and battle-tested.

### Theme 3: Previous Finding S-9 Remains the Biggest UX Gap

User approves architecture at the architecture gate. At the plan gate, realizes the plan doesn't match their intent. The only options are: proceed, details, modify (sends to Planner, not Architect), or abort. There is no controlled backward path to re-trigger architecture. The user must abort and restart, losing all work. This will frustrate users from the first real task and push them toward the escape hatch.

**Impact:** Structural. Affects the most common user correction flow. Multiple agents flagged this independently.

### Theme 4: Mid-Pipeline State Has No Structural Protection

Three related gaps: (1) State YAML files have no atomic write protection — a partial write during checkpoint could corrupt the manifest. (2) External file mutations during an active pipeline (human editing files while waiting at a gate) go undetected, causing agents to work from stale data. (3) The orchestrator's pipeline step transitions are behavioral — no structural validation that "step X may follow step Y" per the pipeline definition. These combine to create a class of silent corruption risks.

**Impact:** Structural. Each individual risk is low-likelihood but the combined attack surface on state consistency warrants attention.

## Detailed Findings

### Foundational Issues

**F-1: Orchestrator skill violates Art 1.3 in spirit (NEW)**
The orchestrator accumulates 7+ responsibilities: pipeline logic, gate presentation, error routing, budget checking, state management, agent dispatch, MCP authorization (Quick Pipeline), and graph data injection. Art 1.3's test is too subjective to catch this. No decision or design constraint limits orchestrator scope.
*Files:* `CONSTITUTION.md` Art 1.3, all pipeline/dispatch/orchestrator references
*Direction:* Either formalize what "one responsibility" means for the orchestrator (with a concrete complexity metric), or acknowledge it as an intentional exception with documented reasoning. Consider whether some responsibilities (e.g., MCP authorization, budget checking) could be factored into pre-dispatch utility functions rather than inline orchestrator logic.

**F-2: No backward path from plan gate to architecture (S-9 STILL OPEN)**
When user feedback at the plan gate implies architectural disagreement, "modify" sends to Planner (who can't change architecture), and "abort" loses all work. No re-trigger of architecture step exists.
*Files:* `architecture/pipelines.md` Standard/Full Pipeline gates
*Direction:* Add a "rethink" option at the plan gate that routes back to the Architect with user feedback. This creates a controlled backward loop without full abort.

**F-3: Agent instruction size has no limit or validation (NEW)**
The instruction assembly process can produce large prompts (Layers 1-4 + knowledge at various levels + graph data + MCP rules). No maximum instruction size is documented or checked before Agent tool dispatch. If the Agent tool has a platform limit, trailing instructions (Layer 4 task-specific — the most important part) would be silently truncated.
*Files:* `architecture/agents.md` (response contract), `architecture/rules.md` (assembly)
*Direction:* Add a budget check for assembled instruction size before dispatch. If total exceeds a threshold (e.g., 50k tokens), warn or split knowledge/graph data to lower levels.

### Structural Issues

**S-1: Dual assembly paths must stay synchronized (LOW)**
The simplified assembly path (pre-planning, Quick Pipeline) and Daedalus's full assembly path both need to understand rule file structure. If rule format changes, both must be updated.
*Files:* `src/global/skills/dispatch.md`, `architecture/rules.md`
*Direction:* Consider a shared shell function for rule assembly that both paths invoke.

**S-2: Ariadne's `.ariadne/` breaks three-layer containment model (LOW)**
`.ariadne/` sits alongside `.moira/`, not within it. Pragmatic but breaks the "all project data in `.moira/`" containment.
*Files:* D-105
*Direction:* Document `.ariadne/` as an "external data source" category in `overview.md`. No architectural change needed.

**S-3: Architect-to-Planner graph data handoff is implicit (MEDIUM)**
Both Metis and Daedalus independently query graph data. No structured section in the architecture document format captures graph-derived conclusions for Daedalus to consume authoritatively.
*Files:* `knowledge-access-matrix.yaml`, `architecture/agents.md` Architect/Planner sections
*Direction:* Add a structured `## Structural Analysis` section to the architecture document format.

**S-4: External file mutations during pipeline go undetected (MEDIUM)**
Post-agent git diff (D-099) protects Moira infrastructure. But if a human edits project source files between Explorer and Implementer steps (e.g., while reviewing at a gate), the Implementer works from stale exploration data.
*Files:* D-099, `architecture/pipelines.md`
*Direction:* Quick `git status` check at pipeline step boundaries against last-known workspace state. If changed files overlap with the pipeline's working set, pause and present options.

**S-5: Pipeline state machine transitions are behavioral, not structural (MEDIUM)**
The orchestrator "decides" the next step based on its understanding of the pipeline flow. If context degradation causes it to skip or misorient steps, no validation catches this.
*Files:* `architecture/pipelines.md`, `subsystems/fault-tolerance.md`
*Direction:* Validate each state transition against the pipeline YAML definition: "Am I allowed to move from step X to step Y?" This makes step-skipping structurally detectable.

**S-6: State YAML writes are not atomic (LOW)**
Partial writes during checkpoint could corrupt `manifest.yaml`. No one-back backup exists.
*Files:* `subsystems/checkpoint-resume.md`
*Direction:* Write to temp file then rename. Keep `manifest.yaml.bak` updated on each write.

**S-7: Reviewer carries dual mandate — quality gate AND behavioral defense (MEDIUM)**
Themis is both the Q4 code reviewer and the "primary per-task defense against upstream agent behavioral violations." Under budget pressure, behavioral defense items may be abbreviated first.
*Files:* `architecture/agents.md` Reviewer section, D-065 enforcement model
*Direction:* Monitor in practice. If behavioral defense items are consistently skipped, consider a lightweight structural "contract verifier" step for the mechanical parts.

**S-8: D-094c adaptive margin weakens E11 defense without discussing trade-off (MEDIUM)**
Moving from fixed 30% to adaptive model with 20% floor reduces the safety margin that fault-tolerance.md explicitly cites as E11-TRUNCATION mitigation. The decision frames this purely as efficiency gain.
*Files:* D-094c, `subsystems/context-budget.md`, `subsystems/fault-tolerance.md`
*Direction:* Add a note explicitly acknowledging the E11 risk trade-off and documenting that the adaptive model's telemetry is the mitigation.

**S-9: `quality.md` and `fault-tolerance.md` don't cross-reference (LOW)**
Quality gates are the primary mechanism for catching behavioral violations, but `quality.md` doesn't reference the enforcement model. `fault-tolerance.md` references "Reviewer" as primary defense but doesn't point to Q4 where that defense is defined.
*Direction:* Add cross-references between the two documents.

**S-10: Graph dimension missing from knowledge.md summary table (LOW)**
The knowledge-access-matrix.yaml (authoritative per D-039) includes a `graph` column. The summary table in `knowledge.md` still shows only 7 dimensions.
*Direction:* Update `knowledge.md` table to include graph, or note that YAML is authoritative and the table is illustrative only.

### Surface Issues

**U-1: Infrastructure MCP category lacks formal classification criteria**
D-108 creates `infrastructure: true` for Ariadne but doesn't formalize the criteria (read-only, zero external API risk, near-zero cost, Moira-owned). Future tools may argue for infrastructure status without clear bar.
*Direction:* Document explicit criteria in `mcp.md`.

**U-2: No compound error handling precedence**
11 error types with individual recovery paths, but no discussion of what happens when multiple errors fire simultaneously (e.g., E4-BUDGET + E9-SEMANTIC).
*Direction:* Add an error precedence rule (e.g., "budget errors take priority over quality errors").

**U-3: Token estimation ratio (D-056) may be systematically biased for code**
`file_size_bytes / 4` approximates English text. Code with short identifiers may have 2-3 bytes/token, causing underestimates. Cold-start 30% margin absorbs this, but adaptive margin doesn't discuss it.
*Direction:* Note the bias in D-056 or context-budget.md. The adaptive model self-corrects once data accumulates.

**U-4: Art 5.3 (Knowledge Consistency) implies rigor that D-042 acknowledges is shallow**
The Constitution says "Knowledge write operations include consistency check step." D-042 makes this structural-only (keyword heuristics). The test technically passes but the implied rigor doesn't match.
*Direction:* Either soften the constitutional language to "structural consistency check" or strengthen the implementation plan for post-v1.

**U-5: No gate timeout / abandonment handling**
If a user walks away from a displayed gate, no timeout or session recovery handles the stale state. Probably fine for interactive Claude Code sessions, but undocumented.
*Direction:* Document as an accepted limitation.

## Discussion Points

### 1. How should orchestrator complexity be governed?

**Tension:** The orchestrator must be self-contained for reliability (D-064 reasoning), but it's accumulating responsibilities that approach Art 1.3 violation. Decomposing it into multiple skills creates coordination overhead; keeping it monolithic creates a god component.

**Arguments for decomposition:** Multiple smaller skills (dispatch.md, gates.md, budget.md, errors.md) that the orchestrator calls in sequence. Each skill is independently testable. Art 1.3 is satisfied.
**Arguments for keeping monolithic:** The orchestrator needs full pipeline context to make decisions. Splitting increases prompt overhead (each sub-skill needs pipeline context). More moving parts, more failure modes.
**At stake:** Whether the system's most critical component remains maintainable as features accumulate.
**Recommended direction:** Don't split now. Instead, define a concrete complexity metric (e.g., line count, responsibility count) and a threshold that triggers mandatory review. Track orchestrator complexity growth per phase.

### 2. Should D-094 formal methods be deferred to post-v1?

**Tension:** The techniques are mathematically sound and would improve efficiency/reliability at scale. But the system hasn't reached the scale where they provide value, and implementing them adds significant complexity to already-deferrable phases.

**Arguments for keeping:** The techniques are designed with cold-start defaults that match current simple behavior. Implementation can be incremental. Having the infrastructure ready means it "just works" as data accumulates.
**Arguments for deferral:** Simple thresholds and fixed retry limits achieve ~85-90% of the value. The formal methods add ~30% implementation surface. Developer time is better spent on core features and battle-testing.
**At stake:** Phase 7, 10, 11 implementation scope and timeline.
**Recommended direction:** Keep CPM (directly useful for batch scheduling). Defer SPRT, CUSUM, BH correction, Markov retry, and exponential decay to post-v1. Use fixed thresholds and simple staleness heuristics.

### 3. Should checkpoint/resume and basic tweak be reordered before budget and MCP?

**Tension:** Current roadmap places budget tracking (Phase 7) and MCP integration (Phase 9) before checkpoint/resume and tweak (Phase 12). This means the system can track context usage but cannot resume an interrupted task, and can integrate MCP tools but cannot let users adjust results.

**Arguments for reordering:** Checkpoint/resume and tweak are essential usability features. Users hitting "my session expired, I lost everything" or "I want to change this but there's no mechanism" will bypass the system entirely. Budget tracking and MCP are enhancements, not enablers.
**Arguments against:** Checkpoint/resume has complex dependencies (manifest, state validation, git integration). Tweak requires plan-gate re-entry logic. Current phase order respects implementation dependencies.
**At stake:** User experience from first real usage onward.
**Recommended direction:** Move a basic checkpoint/resume (save state on context threshold, resume from last checkpoint) and basic tweak (user feedback to Implementer retry) into Phase 7 or 8 timeframe. Defer the full versions (multi-step resume, redo with git revert) to Phase 12.

## Strengths

**Design evolution discipline.** The system addressed 7/10 structural issues and all 5 foundational issues from the previous review within 6 days. The decision log grew from D-064 to D-109 with consistently high quality. D-065 (enforcement model) and D-099 (post-agent guard verification) show genuine architectural insight in response to discovered platform constraints.

**Decision log quality remains exceptional.** 109 decisions with explicit alternatives-rejected sections. Decisions reference each other (D-094 references D-042, D-051; D-099 references D-031, D-075). Bug-driven decisions (D-060-D-063, D-099) are honest about what went wrong. The log is a genuinely useful artifact for understanding why the system is what it is.

**Enforcement model (D-065) is the most important addition since the last review.** Classifying every constraint into structural/validated/behavioral tiers forces honesty about what the system actually guarantees. This is the kind of architectural self-awareness that prevents false confidence.

**Ariadne separation (D-104) was the right call.** Clean project boundary, separate toolchain, graceful degradation. The integration design (D-105 through D-109) makes thoughtful choices about infrastructure vs. managed MCP, direct reads vs. copies, and per-agent graph access levels.

**Constitutional amendment process works.** D-067 (bench mode exception to Art 4.2) and D-085 (architecture gate amendment to Art 2.2) show the Constitution can evolve without losing rigor. The amendment trail is documented in the decision log.

**Knowledge access matrix is now fully consistent.** The three-source problem (S-7) is resolved. YAML is authoritative. Write access is explicit. Graph dimension is integrated. The matrix remains one of the best-designed elements.

## Recommendations

### Quick Wins (design doc updates only)

1. Update `knowledge.md` summary table to include graph dimension or note YAML authority (S-10)
2. Add cross-references between `quality.md` and `fault-tolerance.md` enforcement model (S-9)
3. Document `.ariadne/` as "external data source" category in `overview.md` (S-2)
4. Add explicit infrastructure MCP classification criteria to `mcp.md` (U-1)
5. Add error precedence rule to `fault-tolerance.md` (U-2)
6. Add note to D-094c acknowledging E11 risk trade-off (S-8)
7. Document gate timeout as accepted limitation (U-5)
8. Note token estimation bias for code in `context-budget.md` (U-3)

### Targeted Improvements (design changes, localized)

9. Add "rethink" option at plan gate for backward flow to Architect (F-2 / S-9 STILL OPEN) — **highest priority**
10. Add structured `## Structural Analysis` section to architecture document format for graph data handoff (S-3)
11. Add instruction size budget check before Agent tool dispatch (F-3)
12. Add `git status` check at pipeline step boundaries for mid-pipeline mutation detection (S-4)
13. Validate pipeline state transitions against YAML definition (S-5)
14. Make state YAML writes atomic (temp file + rename) with one-back backup (S-6)

### Strategic Considerations (bigger architectural shifts)

15. Define orchestrator complexity governance — metric, threshold, and review trigger (F-1 / Theme 1)
16. Defer D-094 formal methods (SPRT, CUSUM, BH, Markov, exponential decay) to post-v1 (Theme 2)
17. Reorder roadmap: move basic checkpoint/resume and basic tweak earlier (Discussion Point 3)
18. Evaluate whether Reviewer's behavioral defense mandate needs structural support (S-7)
19. Soften Art 5.3 constitutional language to match D-042 structural-only implementation, or plan stronger post-v1 implementation (U-4)
