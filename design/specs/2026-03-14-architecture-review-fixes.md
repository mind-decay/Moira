# Architecture Review Fixes

**Date:** 2026-03-14
**Source:** `design/reports/2026-03-13-architecture-review.md`
**Risk Classification:** ORANGE (design doc updates, knowledge structure changes, budget changes)

## Goal

Apply all approved fixes from the 2026-03-13 architecture review. Updates design documents AND corresponding implementation files (skills, role YAMLs, pipeline YAMLs, schemas) to maintain cross-system consistency.

## Decisions Made

All fixes were discussed and approved in the 2026-03-14 review session. Summary of key decisions:

1. **Theme 1 (structural vs behavioral):** Medium variant — Enforcement Model section in fault-tolerance.md, not a separate subsystem
2. **Theme 2 (over-engineering):** Multi-developer locks deferred. All phases remain in roadmap
3. **F-3 (bench_mode):** Amend Art 4.2 with explicit bench mode exception
4. **Discussion 4 (Tweak/Redo):** Stays in Phase 12, no change — users don't interact with Moira until after Phase 12
5. **Discussion 5 (minimum task size):** Add note to pipelines.md
6. **S-8 (monorepo):** Bootstrap detection + package map + Classifier scoping
7. **Rec 22 (simplify L0/L1/L2):** Deferred — keep three levels, revisit if L1 maintenance proves burdensome
8. **Rec 29 (defer CONFORM/EVOLVE, metrics, LLM-judge):** Rejected — all phases will be implemented as planned

## Deliverables

### Group A: Fault Tolerance & Enforcement Model

**Design files:** `design/subsystems/fault-tolerance.md`
**Implementation files:** `src/global/skills/errors.md`, `src/global/skills/orchestrator.md` (Section 5 routing table), `src/global/core/pipelines/quick.yaml`, `src/global/core/pipelines/standard.yaml` (not yet created), `src/global/core/pipelines/full.yaml`, `src/global/core/pipelines/decomposition.yaml` (not yet created)

1. Add "Enforcement Model" section with three tiers (structural / validated / behavioral)
2. Add E6 subtype: malformed agent output (unparseable response contract)
3. Add E9-SEMANTIC: valid format, wrong content
4. Add E10-DIVERGE: multi-agent factual disagreement
5. Add E11-TRUNCATION: silent context window overflow
6. For each new error: detection mechanism + recovery path + primary defense layer
7. Add E9/E10/E11 to pipeline YAML error_handlers (where pipeline files exist)
8. Add E9/E10/E11 procedure sections to errors.md
9. Add E9/E10/E11 to orchestrator.md quick error routing table
10. Add E9/E10/E11 to pipelines.md error handling summary table

### Group B: Agent Architecture Updates

**Design files:** `design/architecture/agents.md`
**Implementation files:** `src/global/core/rules/roles/themis.yaml` (Reviewer), `src/global/core/rules/roles/mnemosyne.yaml` (Reflector), `src/global/core/rules/roles/metis.yaml` (Architect), `src/global/core/rules/roles/athena.yaml` (Analyst), `src/global/core/rules/roles/daedalus.yaml` (Planner), `src/global/skills/dispatch.md` (QUALITY parsing)

1. Add QUALITY field to response contract (D-049 reconciliation)
2. Add parsing validation note to response contract: "behavioral contract, validated by orchestrator parser, malformed → E6"
3. Reviewer: add explicit mandate as primary behavioral defense + checklist items for upstream role boundary verification and factual claim verification (E9/E10 defense). Update themis.yaml.
4. Reflector: reframe as primary defense against systemic behavioral drift + add exit criteria + minimum output structure (S-10). Update mnemosyne.yaml.
5. Architect: add explicit mandate to detect Explorer/Analyst data contradictions before proceeding (E10 defense). Update metis.yaml.
6. Classifier: fix budget to 20k (confirm, already correct in agents.md)
7. Planner: document 4 sub-phases with distinct success/failure conditions (S-5). Update daedalus.yaml.
8. Section headers: add mythological names — `"## Name (role)"` format per D-034 naming convention (U-6)
9. Analyst and Architect: add L0 access to failures knowledge (U-8). Update athena.yaml and metis.yaml knowledge_access blocks.
10. Update dispatch.md QUALITY line parsing in response templates

### Group C: Constitution Amendment

**Files:** `design/CONSTITUTION.md`

1. Amend Art 4.2 test clause. Proposed text:

> **Test:** All gates require user action to proceed. No auto-proceed logic exists in production pipelines. Bench mode (`/moira bench`, explicitly activated by user) may use predefined gate responses for automated testing.

**Note:** This is the ONLY constitutional change. User explicitly approved this amendment.

### Group D: Knowledge System Updates

**Files:** `subsystems/knowledge.md`, `src/global/core/knowledge-access-matrix.yaml`

1. Add write-access columns to knowledge access matrix (S-6)
2. Declare `knowledge-access-matrix.yaml` as authoritative source, add references from knowledge.md and agents.md (S-7)
3. Add Analyst L0 and Architect L0 for failures knowledge (U-8)
4. Add Auditor checklist item: sample N knowledge claims, verify via Explorer against source code (F-4)

### Group E: Pipeline & Budget Updates

**Design files:** `design/architecture/pipelines.md`, `design/subsystems/context-budget.md`
**Implementation files:** `src/schemas/budgets.schema.yaml`, `src/global/skills/gates.md`, `src/global/skills/orchestrator.md`, `src/global/core/pipelines/quick.yaml`, `src/global/core/pipelines/full.yaml`

1. Add minimum viable task size note to pipelines.md (Discussion 5)
2. Fix Classifier budget in context-budget.md YAML and report example to 20k (S-1)
3. Add Classifier to budget YAML if missing (S-1)
4. Sync Quick Pipeline retry limit: Quick Pipeline keeps max 1, fault-tolerance.md adds note that pipeline-specific limits override general default (U-2)
5. Plan gate "modify" option: detect architectural-level feedback → offer architecture gate re-entry (S-9). Applies to Standard AND Full pipelines. Update gates.md plan gate template, orchestrator.md handling, and pipeline YAMLs.

### Group F: Miscellaneous Design Fixes

**Files:** various

1. `subsystems/self-monitoring.md`: clarify guard.sh scope — orchestrator context only, document platform constraint re: subagent hooks (S-3)
2. `architecture/pipelines.md`: define Quick Pipeline structured note format for knowledge accumulation (S-4)
3. `subsystems/audit.md`: fix trigger naming "full" → "standard" for 20-task audit (U-1). Add Classifier accuracy tracking via gate override rate (F-5)
4. `subsystems/self-protection.md`: fix reference to non-existent constitutional-checks.yaml (U-4)
5. `architecture/rules.md`: add second assembly path (orchestrator pre-planning) (U-10)
6. `decisions/log.md` D-064: replace specific model name with capability threshold (U-9)
7. `design/subsystems/fault-tolerance.md` D-053 reference: rename WARNING gate → "quality checkpoint" (U-5). Also update `src/global/skills/gates.md` and `src/global/skills/orchestrator.md` terminology.

### Group G: Monorepo Support Design

**Design files:** `design/architecture/agents.md`, `design/subsystems/knowledge.md`, `design/architecture/pipelines.md`
**Implementation files:** `src/global/core/rules/roles/apollo.yaml` (Classifier), `src/global/core/rules/roles/hermes.yaml` (Explorer)
**Note:** config schema and bootstrap.sh changes are future implementation work, not part of this design batch

1. Add monorepo detection to bootstrap design (init) — detect workspaces/packages patterns
2. Define package map knowledge structure in knowledge.md (extension of project-model, not new knowledge type)
3. Classifier: add monorepo scoping — use package map to determine relevant packages. Update apollo.yaml.
4. Explorer: receive scoped instruction with target packages. Update hermes.yaml.
5. Define new E2-SCOPE subtype for monorepo insufficient package scope (distinct from task size reclassification)

### Group H: Decision Log

**Files:** `decisions/log.md`

New decisions:
- D-065: Enforcement Model — three-tier trust classification (structural / validated / behavioral)
- D-066: Monorepo support — bootstrap detection + package map + Classifier scoping
- D-067: Art 4.2 amendment — bench mode exception
- D-068: Multi-developer locks deferred to post-v1 branch isolation
- D-069: Tweak/Redo stays in Phase 12 — users don't interact until post-Phase 12
- D-070: E2-SCOPE extended with monorepo subtype for insufficient package scope
- D-071: Quick Pipeline retry limit is 1 (pipeline-specific override of general max 2)

### Group I: Multi-developer Locks Deferral

**Files:** `design/IMPLEMENTATION-ROADMAP.md`

1. Phase 12: mark multi-developer locks as deferred, note that branch isolation is interim solution

## Success Criteria

1. All 29 recommendations from architecture review addressed (including deliberate deferrals documented in decision log)
2. No new cross-document inconsistencies introduced
3. Constitutional amendment is minimal and precise
4. Knowledge access matrix is consistent across all sources
5. All new error codes (E9/E10/E11) have detection + recovery + defense layer
6. Enforcement Model section clearly classifies every key constraint

## Risk Notes

- Group C (Constitution) is RED — requires user approval (already granted)
- Groups A, B, D, G are ORANGE — design doc changes with structural impact
- Group E is YELLOW — budget/pipeline fixes with implementation file sync
- Group F is YELLOW — localized fixes across multiple files
- Group H is GREEN — decision log additions
- Group I is GREEN — roadmap annotation
