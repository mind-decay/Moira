# Architecture Review Fixes — Implementation Plan

**Spec:** `design/specs/2026-03-14-architecture-review-fixes.md`
**Date:** 2026-03-14

## Dependency Graph

```
Chunk 1 (Decision Log + Constitution)  ──→  independent, no deps
Chunk 2 (Fault Tolerance + Enforcement)  ──→  independent, no deps
Chunk 3 (Error System Implementation)  ──→  depends on Chunk 2 (E9/E10/E11 definitions)
Chunk 4 (Agent Architecture)  ──→  depends on Chunk 2 (enforcement model refs)
Chunk 5 (Knowledge System)  ──→  independent, no deps
Chunk 6 (Pipeline & Budget)  ──→  depends on Chunk 2 (retry limit note)
Chunk 7 (Miscellaneous Fixes)  ──→  depends on Chunk 2 (quality checkpoint rename)
Chunk 8 (Monorepo Design)  ──→  depends on Chunk 2 (E2-SCOPE subtype)

Parallel groups:
  Group 1: Chunks 1, 2, 5 (no deps)
  Group 2: Chunks 3, 4, 6, 7, 8 (depend on Chunk 2)
```

---

## Chunk 1: Decision Log + Constitution Amendment

### Task 1.1: Amend Art 4.2

**File:** `design/CONSTITUTION.md`
**Change:** Line 102, replace test clause:
- Current: `**Test:** All gates require user action to proceed. No auto-proceed logic exists.`
- New: `**Test:** All gates require user action to proceed. No auto-proceed logic exists in production pipelines. Bench mode (/moira bench, explicitly activated by user) may use predefined gate responses for automated testing.`
- Also update Invariant Verification Checklist line 176: add "(bench mode excepted)" to the 4.2 check

### Task 1.2: Fix D-064 model name

**File:** `design/decisions/log.md`
**Change:** Line 597-598, replace "Claude Opus 4.6" with "models with 1M+ context window" or similar capability threshold. Keep the decision reasoning intact.

### Task 1.3: Add D-065 through D-071

**File:** `design/decisions/log.md`
**Change:** Append after D-064. Each decision needs: Context, Decision, Alternatives rejected, Reasoning.

- **D-065:** Enforcement Model — three-tier trust classification
- **D-066:** Monorepo support — bootstrap detection + package map + Classifier scoping
- **D-067:** Art 4.2 amendment — bench mode exception (references the constitutional change)
- **D-068:** Multi-developer locks deferred to post-v1 (branch isolation interim)
- **D-069:** Tweak/Redo stays in Phase 12 (users don't interact until post-Phase 12)
- **D-070:** E2-SCOPE extended with monorepo subtype for insufficient package scope
- **D-071:** Quick Pipeline retry limit is 1 (pipeline-specific override of general max 2)

### Task 1.4: Mark multi-developer locks as deferred

**File:** `design/IMPLEMENTATION-ROADMAP.md`
**Change:** Phase 12 section (line 234), add "(deferred to post-v1, branch isolation is interim — D-068)" next to lock system line item.

**Commit:** `moira(design): add D-065–D-071, amend Art 4.2 bench mode, defer multi-dev locks`

---

## Chunk 2: Fault Tolerance & Enforcement Model

### Task 2.1: Add Enforcement Model section

**File:** `design/subsystems/fault-tolerance.md`
**Change:** Add new section after the Error Taxonomy table (after line 18, before E1-INPUT section). Content:

- Title: "## Enforcement Model"
- Three-tier classification table:
  - **Structural** (platform-guaranteed): `allowed-tools`, pipeline selection logic, gate presence in pipeline definitions
  - **Validated** (behavioral + verification): response contract (orchestrator parser validates), quality findings (YAML schema), knowledge writes (consistency check)
  - **Behavioral** (prompt-only): NEVER constraints, fabrication prohibition, agent role boundaries, knowledge consistency execution
- Defense layer per tier:
  - Structural → platform handles, no recovery needed
  - Validated → parsing fallback to E6-AGENT, schema validation
  - Behavioral → Reviewer (primary per-task defense), Reflector (primary systemic defense), Auditor (periodic cross-validation)
- Note: "This model acknowledges that behavioral rules enforced by prompting are not equivalent to structural platform guarantees. The design relies on layered defense rather than single-point enforcement."

### Task 2.2: Add E6 malformed output subtype

**File:** `design/subsystems/fault-tolerance.md`
**Change:** In E6-AGENT section (around line 122), add subtype:
- E6-AGENT (malformed output): Agent returns text but response does not match STATUS/SUMMARY/ARTIFACTS/NEXT contract format.
- Detection: Orchestrator parser fails to extract required fields.
- Recovery: Same as E6 — retry 1x, then diagnostic + escalate.

### Task 2.3: Add E9-SEMANTIC

**File:** `design/subsystems/fault-tolerance.md`
**Change:** Add new section after E8-STALE. Format matching existing E1-E8 sections.
- Trigger: Agent returns structurally valid output but content is factually wrong (hallucinated API, wrong architecture, incorrect code).
- Detection: Reviewer checklist item "verify factual claims against Explorer data." Architecture gate (user review). Reflector post-hoc analysis.
- Primary defense: Reviewer + architecture gate (human in the loop).
- Recovery: If caught at review → E5-QUALITY retry path. If caught at gate → modify/redesign. If caught post-deployment → log in failures knowledge.
- Note: "This is the hardest failure mode to detect automatically. The architecture gate presenting alternatives is the primary user-facing defense."

### Task 2.4: Add E10-DIVERGE

**File:** `design/subsystems/fault-tolerance.md`
**Change:** Add after E9.
- Trigger: Multiple agents report contradictory facts about the same codebase (e.g., Explorer reports 14 endpoints, Analyst scopes 6).
- Detection: Architect mandate to compare Explorer and Analyst data explicitly. Reviewer cross-referencing implementation against exploration data.
- Primary defense: Architect (explicit contradiction detection mandate).
- Recovery: Architect flags contradiction → presents both versions to user at architecture gate → user decides which is correct. If not caught until review → E5-QUALITY with note to verify factual basis.

### Task 2.5: Add E11-TRUNCATION

**File:** `design/subsystems/fault-tolerance.md`
**Change:** Add after E10.
- Trigger: Agent's context window fills silently, early instructions (including NEVER constraints, role boundaries) are lost. Agent returns success but output is incomplete or violates constraints.
- Detection: Agent "context loaded" summary at start of execution (agent lists what instructions it received — orchestrator can detect omissions). Budget system pre-execution estimation (flag agents near budget limit). Reviewer catches output that violates known constraints.
- Primary defense: Budget system (prevent overflow) + Reviewer (catch violations post-hoc).
- Recovery: If detected by budget system → E4-BUDGET path (split work). If detected by Reviewer → E5-QUALITY retry with reduced scope. If undetected → Reflector post-hoc analysis + failures knowledge.

### Task 2.6: Add pipeline-specific retry note

**File:** `design/subsystems/fault-tolerance.md`
**Change:** In E5-QUALITY section header area (line 94), add note: "Pipeline-specific retry limits may override this default. Quick Pipeline uses max 1 attempt (D-071)."

### Task 2.7: Rename WARNING gate terminology

**File:** `design/subsystems/fault-tolerance.md`
**Change:** Search for "WARNING gate" or "warning gate" references and rename to "quality checkpoint." This may be in the E5-QUALITY section or general references.

**Commit:** `moira(design): add enforcement model, E9/E10/E11 error codes, E6 malformed subtype`

---

## Chunk 3: Error System Implementation Files

Depends on Chunk 2 (E9/E10/E11 definitions in design doc).

### Task 3.1: Add E9/E10/E11 to errors.md

**File:** `src/global/skills/errors.md`
**Change:** Add three new procedure sections after E8, following existing format (Detection/Recovery/Display/State Updates/Escalation). Content derived from Chunk 2 design definitions.

### Task 3.2: Add E9/E10/E11 to orchestrator.md routing table

**File:** `src/global/skills/orchestrator.md`
**Change:** Section 5 routing table (lines 184-190). Add rows:
- E9-SEMANTIC → route to E5-QUALITY retry path (reviewer-detected) or present at gate (gate-detected)
- E10-DIVERGE → present contradiction at architecture gate
- E11-TRUNCATION → route to E4-BUDGET split path

### Task 3.3: Add E9/E10/E11 to pipeline YAML error_handlers

**Files:** `src/global/core/pipelines/quick.yaml`, `src/global/core/pipelines/standard.yaml`, `src/global/core/pipelines/full.yaml`, `src/global/core/pipelines/decomposition.yaml`
**Change:** Add error handler entries for E9, E10, E11 in each file's error_handlers block. Follow existing format.

### Task 3.4: Add E9/E10/E11 to pipelines.md error table

**File:** `design/architecture/pipelines.md`
**Change:** Error handling summary table (lines 245-256). Add rows for E9/E10/E11.

### Task 3.5: Rename quality checkpoint in gates.md

**File:** `src/global/skills/gates.md`
**Change:** Quality Warning Gate section (lines 282-322):
- Rename section header to "## Quality Checkpoint"
- Rename template gate name from "Quality Warning" to "Quality Checkpoint"
- Update gate state name from `quality_warning_{gate}` to `quality_checkpoint_{gate}`

### Task 3.6: Rename quality checkpoint in orchestrator.md

**File:** `src/global/skills/orchestrator.md`
**Change:** Line 103 area — rename `fail_warning` / "WARNING gate" references to "quality checkpoint."

### Task 3.7: Plan gate architecture re-entry

**File:** `src/global/skills/gates.md`
**Change:** Plan Gate section (lines 143-170). Add handling for "modify" option:
- If user feedback is architectural in nature (changes approach, not just plan details), present option to re-enter at architecture gate.
- Add new option `rearchitect` to plan gate options.

### Task 3.8: Plan gate re-entry in orchestrator.md

**File:** `src/global/skills/orchestrator.md`
**Change:** Main loop handling for plan gate "rearchitect" response — re-enter pipeline at architecture step, preserving Explorer/Analyst data.

### Task 3.9: Plan gate re-entry in pipeline YAMLs

**Files:** `src/global/core/pipelines/standard.yaml` (not yet created — check), `src/global/core/pipelines/full.yaml`
**Change:** Add `rearchitect` option to plan gate in both Standard and Full pipeline definitions.

**Commit:** `moira(pipeline): add E9/E10/E11 to error system, rename quality checkpoint, add plan gate re-entry`

---

## Chunk 4: Agent Architecture Updates

Depends on Chunk 2 (enforcement model for context).

### Task 4.1: Update response contract

**File:** `design/architecture/agents.md`
**Change:** Lines 8-18. Add QUALITY field after NEXT:
```
QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)
```
Add note: "This is a behavioral contract enforced by prompting. The orchestrator MUST validate response format and treat malformed responses as E6-AGENT."

### Task 4.2: Rename all section headers

**File:** `design/architecture/agents.md`
**Change:** Rename all 10 agent section headers to `## Name (role)` format per D-034:
- `## Classifier` → `## Apollo (classifier)`
- `## Explorer` → `## Hermes (explorer)`
- `## Analyst` → `## Athena (analyst)`
- `## Architect` → `## Metis (architect)`
- `## Planner` → `## Daedalus (planner)`
- `## Implementer` → `## Hephaestus (implementer)`
- `## Reviewer` → `## Themis (reviewer)`
- `## Tester` → `## Aletheia (tester)`
- `## Reflector` → `## Mnemosyne (reflector)`
- `## Auditor` → `## Argus (auditor)`

### Task 4.3: Add Analyst/Architect L0 failures access

**File:** `design/architecture/agents.md`
**Change:** Analyst section (around line 102): add `Knowledge access: ... L0 (failures index)`. Architect section (around line 131): add `L0 (failures index)`.

### Task 4.4: Reviewer mandate update

**File:** `design/architecture/agents.md`
**Change:** Reviewer section. Add:
- Framing: "Primary behavioral defense — catches upstream agents' role boundary violations and factual errors."
- New checklist items:
  - `[ ] Upstream agents stayed within role boundaries (Explorer didn't propose, Architect didn't fabricate)`
  - `[ ] Factual claims in architecture match Explorer data (E10 defense)`
  - `[ ] Implementation matches approved architecture (E9 defense)`

### Task 4.5: Reflector reframe + exit criteria

**File:** `design/architecture/agents.md`
**Change:** Reflector section. Add:
- Framing: "Primary defense against systemic behavioral drift."
- Exit criteria: Must produce at minimum: (1) accuracy assessment, (2) efficiency assessment, (3) at least one concrete observation for knowledge update, (4) agent boundary compliance note.
- Minimum output structure: ACCURACY, EFFICIENCY, OBSERVATIONS, KNOWLEDGE_UPDATES, BOUNDARY_COMPLIANCE sections.

### Task 4.6: Architect contradiction detection mandate

**File:** `design/architecture/agents.md`
**Change:** Architect section. Add to rules:
- "MUST compare Explorer and Analyst data for contradictions before proceeding. If factual disagreement found → report as E10-DIVERGE with both versions."

### Task 4.7: Planner sub-phases

**File:** `design/architecture/agents.md`
**Change:** Planner section. Document 4 sub-phases as explicit contract:
1. **Decomposition** — break architecture into steps. Success: each step has clear input/output. Failure: circular dependencies or missing steps.
2. **Dependency Graph** — map file dependencies. Success: DAG with no cycles. Failure: unresolvable cycles.
3. **Budget Estimation** — estimate tokens per batch. Success: all batches within agent limits. Failure: batch exceeds limit after splitting.
4. **Instruction Assembly** — assemble Layer 1-4 rules per agent. Success: each agent instruction includes all required rule layers. Failure: missing rule layer.

### Task 4.8: Add authoritative source reference

**File:** `design/architecture/agents.md`
**Change:** Add note near the top or near first knowledge access reference: "Authoritative source for knowledge access levels is `src/global/core/knowledge-access-matrix.yaml`. Per-agent sections below are summaries."

### Task 4.9: Update Reviewer role YAML

**File:** `src/global/core/rules/roles/themis.yaml`
**Change:** Add behavioral defense mandate to capabilities. Add new quality_checklist items for boundary verification and factual verification.

### Task 4.10: Update Reflector role YAML

**File:** `src/global/core/rules/roles/mnemosyne.yaml`
**Change:** Add behavioral drift defense to identity. Add exit_criteria and minimum_output_structure sections.

### Task 4.11: Update Architect role YAML

**File:** `src/global/core/rules/roles/metis.yaml`
**Change:** Add contradiction detection mandate to capabilities. Add `failures: L0` to knowledge_access.

### Task 4.12: Update Analyst role YAML

**File:** `src/global/core/rules/roles/athena.yaml`
**Change:** Add `failures: L0` to knowledge_access.

### Task 4.13: Update Planner role YAML

**File:** `src/global/core/rules/roles/daedalus.yaml`
**Change:** Add sub-phases to capabilities or output_structure section.

### Task 4.14: Update dispatch.md QUALITY parsing

**File:** `src/global/skills/dispatch.md`
**Change:** Lines 153-168. Add QUALITY to expected format. Add parsing step 6 for QUALITY line (optional field, present only for quality-gate agents).

**Commit:** `moira(agents): update response contract, agent mandates, role YAMLs, header names`

---

## Chunk 5: Knowledge System Updates

### Task 5.1: Add write-access columns to YAML matrix

**File:** `src/global/core/knowledge-access-matrix.yaml`
**Change:** For each agent entry, add write-access fields. Based on design:
- Reflector: write to all knowledge types
- Auditor: read-only (never modifies)
- Explorer: write to project-model (during init/refresh)
- Reviewer: write to quality-map (findings)
- All others: no write access
Add metadata comment declaring this as authoritative source.

### Task 5.2: Update Analyst/Architect failures access in YAML

**File:** `src/global/core/knowledge-access-matrix.yaml`
**Change:** Set `athena.failures: L0` and `metis.failures: L0` (currently null).

### Task 5.3: Update knowledge.md access table

**File:** `design/subsystems/knowledge.md`
**Change:** Lines 19-30.
- Add `failures: L0` for Analyst and Architect rows (currently `—`).
- Add write-access columns to the markdown table (or add note: "Write access defined in authoritative source: `src/global/core/knowledge-access-matrix.yaml`").
- Add note declaring YAML as authoritative: "The authoritative source for the knowledge access matrix is `src/global/core/knowledge-access-matrix.yaml`. This table is a summary."

### Task 5.4: Add Auditor knowledge cross-validation

**File:** `design/subsystems/knowledge.md` or `design/subsystems/audit.md`
**Change:** Add to Auditor's knowledge audit scope: "Sample 3-5 knowledge claims per audit. Dispatch Explorer to verify each claim against current source code. Flag discrepancies as E8-STALE." This belongs in audit.md's Knowledge Audit section.

**Commit:** `moira(knowledge): add write-access matrix, declare YAML authoritative, add cross-validation`

---

## Chunk 6: Pipeline & Budget Fixes

Depends on Chunk 2 (retry limit note).

### Task 6.1: Fix Classifier budget in context-budget.md

**File:** `design/subsystems/context-budget.md`
**Change:**
- Add Classifier entry to budget YAML block (lines 30-86): `classifier: 20000`
- Fix report example (line 134): change "60k" to "20k" for Classifier row.

### Task 6.2: Add minimum viable task size note

**File:** `design/architecture/pipelines.md`
**Change:** Add note near Task Classification table (after line 12 area):
"**Note:** The Quick Pipeline adds ~1-3 minutes of overhead (classification + exploration + implementation + review). Tasks that can be done correctly in under 30 seconds are better served by the escape hatch (`/moira bypass:`)."

### Task 6.3: Confirm budgets.schema.yaml

**File:** `src/schemas/budgets.schema.yaml`
**Change:** Verify classifier is present at 20000 (it is, line 11). No changes needed.

**Commit:** `moira(budget): fix Classifier budget values, add minimum task size note`

---

## Chunk 7: Miscellaneous Design Fixes

Depends on Chunk 2 (quality checkpoint rename reference).

### Task 7.1: Clarify guard.sh scope

**File:** `design/subsystems/self-monitoring.md`
**Change:** guard.sh section (lines 58-86). Add clarification:
- "guard.sh runs as a PostToolUse hook in the orchestrator session. Claude Code hooks fire for ALL tool uses in the session, including subagent tool calls. Guard must filter by context: only log/alert on tool calls made by the orchestrator skill itself, not by dispatched agents (agents are expected to read/write project files)."
- Add note: "Platform constraint: Claude Code does not currently distinguish orchestrator vs subagent tool calls in hooks. Guard.sh must use heuristics (e.g., check if the tool call is within a subagent dispatch) or accept that agent tool calls will be logged but not flagged."

### Task 7.2: Define Quick Pipeline note format

**File:** `design/architecture/pipelines.md`
**Change:** Quick Pipeline section (line 44 "Post: lightweight reflection (file note, no agent)"). Add format specification:
```
Post: lightweight reflection — orchestrator writes structured note to
.claude/moira/state/tasks/{id}/reflection-note.yaml:
  task_id: {id}
  classification_correct: true|false
  implementation_accepted: true|false|tweaked
  issues_found: [list of review findings]
  knowledge_updates: [] # empty for most quick tasks
```

### Task 7.3: Fix audit trigger naming + Classifier tracking

**File:** `design/subsystems/audit.md`
**Change:**
- Line 10: change "full audit" to "standard audit" (U-1).
- Agent Performance section (lines 73-89): add "Classifier accuracy: gate override rate (percentage of tasks where user changes classification at Gate #1)."

### Task 7.4: Fix self-protection.md stale reference

**File:** `design/subsystems/self-protection.md`
**Change:** Line 211, reference to `design/verification/constitutional-checks.yaml`. Replace with note: "Constitutional verification checklist is defined in CONSTITUTION.md Invariant Verification Checklist section."

### Task 7.5: Add second assembly path to rules.md

**File:** `design/architecture/rules.md`
**Change:** After the existing Rule Assembly Process section (lines 167-188), add:
"### Simplified Assembly (Pre-Planning Agents)"
- For pre-planning agents (Classifier, Explorer, Analyst) and Quick Pipeline agents, the orchestrator assembles rules directly (not Planner).
- Assembly: Layer 1 (base.yaml) + Layer 2 (role YAML) + Layer 3 (project rules from config) + Layer 4 (task-specific from orchestrator context).
- Reference: `src/global/skills/dispatch.md` Simplified Assembly section.
- Per D-041.

**Commit:** `moira(design): fix guard.sh scope, audit naming, self-protection ref, rules assembly path, Quick Pipeline note format`

---

## Chunk 8: Monorepo Design

Depends on Chunk 2 (E2-SCOPE subtype defined there).

### Task 8.1: Add monorepo detection to agents.md

**File:** `design/architecture/agents.md`
**Change:** Classifier section: add note about monorepo scoping:
- "For monorepo projects (detected at bootstrap via package.json workspaces, lerna.json, or packages/ directory), Classifier uses the package map from knowledge to determine which packages are relevant to the task. Explorer receives scoped instructions targeting only those packages."

Explorer section: add note:
- "For monorepo projects, Explorer may receive package-scoped instructions limiting exploration to specific packages. If Explorer discovers that additional packages are relevant, it reports this as E2-SCOPE (monorepo subtype) for scope expansion."

### Task 8.2: Add package map to knowledge.md

**File:** `design/subsystems/knowledge.md`
**Change:** In Project Model section (lines 38-60), add:
```markdown
## Package Map (monorepo only)
When project is a monorepo, bootstrap creates a package map:
- Package name, path, description (one-line)
- Internal dependencies between packages
- Package role (library, app, shared, config)
Stored as extension of project-model: `knowledge/project-model/package-map.md`
Classifier uses L0 (package list), Explorer uses L1 (with dependencies).
```

### Task 8.3: Add monorepo note to pipelines.md

**File:** `design/architecture/pipelines.md`
**Change:** Near Task Classification section, add:
"**Monorepo:** For monorepo projects, Classifier includes package scoping in classification output. Explorer receives target packages as part of scoped instructions. If scope proves insufficient, E2-SCOPE (monorepo subtype) triggers re-scoping."

### Task 8.4: Update Classifier role YAML

**File:** `src/global/core/rules/roles/apollo.yaml`
**Change:** Add capability: monorepo package scoping using package map from knowledge.

### Task 8.5: Update Explorer role YAML

**File:** `src/global/core/rules/roles/hermes.yaml`
**Change:** Add capability: accept package-scoped instructions for monorepo. Add E2-SCOPE monorepo reporting.

**Commit:** `moira(design): add monorepo support design — package map, Classifier scoping, Explorer scoping`

---

## Execution Order

1. **Parallel Group 1:** Chunks 1, 2, 5 (no dependencies)
2. **Parallel Group 2:** Chunks 3, 4, 6, 7, 8 (depend on Chunks 1-2 for decision numbers and error definitions)
3. Final verification: cross-reference all changes for consistency
