# Gate Presentation System

Reference: `design/architecture/pipelines.md` (Approval Gate UX), `design/architecture/commands.md` (In-Pipeline Actions)

This skill defines how the orchestrator presents approval gates and error gates to the user.

---

## Standard Gate Template

Every gate follows this template structure. Gate content is **extracted from agent artifact required sections** (D-184), not summarized by the orchestrator. This ensures gates present the agent's actual reasoning, not a lossy summary.

```
═══════════════════════════════════════════
 GATE: {Gate Name}
═══════════════════════════════════════════

 {GATE-SPECIFIC CONTENT — extracted from artifact required sections, per gate type below}

 Impact: {files affected, estimated budget usage}

 Details:
 → {path to full artifact file}

 {TRACEABILITY — cross-references to previous gates, if applicable}

 {EPISTEMIC STATUS — UNVERIFIED items, if applicable}

 {HEALTH REPORT}

 {OPTIONS}
═══════════════════════════════════════════
```

**Gate content rules (D-184):**
- Gate-specific content is extracted directly from the agent artifact's required sections — the orchestrator reads the section text and presents it, does not re-summarize
- Each gate type below specifies which artifact sections map to which gate display sections
- If a required section is missing from the artifact, `artifact-validate.sh` would have already blocked the agent — the orchestrator should never encounter missing sections at gate presentation time
- Traceability section appears when cross-gate references exist (plan gate references classification scope, final gate references acceptance criteria)
- Epistemic status section appears when UNVERIFIED items exist in the pipeline

---

## Health Report Section

Include in EVERY gate display:

```
ORCHESTRATOR HEALTH:
├─ Context: ~{used}k/{total}k ({pct}%) {status_emoji}
├─ Violations: {count} {status_emoji}
├─ Agents dispatched: {count}
├─ Gates passed: {passed}/{total}
├─ Retries: {count}
└─ Progress: step {current}/{total}
```

Status emoji rules:
- Context: ✅ <25%, 📊 25-40%, ⚠ 40-60%, 🔴 >60%
- Violations: ✅ if both 0, 🔴 if either >0

Data sources:
- Context: from `current.yaml` → `context_budget.orchestrator_percent` (updated by moira_budget_orchestrator_check)
- Violations: count lines in `.moira/state/violations.log` by prefix (D-099, D-116): `VIOLATION` = orchestrator violations (from guard.sh hook in orchestrator session), `AGENT_VIOLATION` = agent violations (from post-agent git diff check). Display as "{N} orchestrator, {M} agent" (or "0 ✅" if both are 0)
- Agents dispatched: count of entries in `current.yaml` → `history[]`
- Gates passed: count of entries in task's `status.yaml` → `gates[]`
- Retries: sum of `status.yaml` → `retries.total`
- Progress: current step index / total steps from pipeline definition

---

## Budget Report Section

Display at pipeline completion (final gate and post-pipeline). Generate using `moira_budget_generate_report <task_id>`:

```
╔══════════════════════════════════════════════╗
║           CONTEXT BUDGET REPORT              ║
╠══════════════════════════════════════════════╣
║ Agent         │ Budget │ Est.  │ % │ Status  ║
║───────────────┼────────┼───────┼───┼─────────║
{per-agent rows from status.yaml budget.by_agent block}
║ Orchestrator  │ 1000k  │ {est} │{%}│ {emoji} ║
╠══════════════════════════════════════════════╣
║ Orchestrator context: {used}k/1000k ({pct}%) ║
╚══════════════════════════════════════════════╝
```

Per-agent budget status thresholds (individual agent usage vs. allocated budget):
- ✅ <50%: healthy
- ⚠ 50-70%: acceptable but monitor
- 🔴 >70%: over safety margin, quality risk

Note: These are per-agent thresholds, distinct from the orchestrator context thresholds in orchestrator.md Section 6 (Healthy <25%, Monitor 25-40%, Warning 40-60%, Critical >60%).

---

## Approval Gates

### Classification Gate

After Apollo (classifier) completes.

**Artifact sections displayed (D-184):** Content extracted from `classification.md` required sections.

**Template:**
```
═══════════════════════════════════════════
 GATE: Classification
═══════════════════════════════════════════

 Problem Statement:
 {extracted from ## Problem Statement — agent's own words, not user copy-paste}

 Classification: {size} | Confidence: {confidence} | Pipeline: {pipeline_type}
 {If user hint disagrees: "⚠ User suggested {hint}, classifier chose {size}: {reasoning}"}

 Scope:
 ├─ In:  {extracted from ## Scope / ### In Scope}
 └─ Out: {extracted from ## Scope / ### Out of Scope}

 Acceptance Criteria:
 {extracted from ## Acceptance Criteria — numbered list of testable conditions}

 Impact: {estimated pipeline budget usage}

 Details:
 → {path to classification.md}

 {HEALTH REPORT}

 1) proceed — Classification correct, continue with {pipeline_type} Pipeline
 2) modify  — Provide different classification (size: small/medium/large/epic)
 3) abort   — Cancel task
═══════════════════════════════════════════
```

**Why this matters:** Scope and acceptance criteria defined here propagate to all subsequent gates. Architecture must stay within scope. Plan is checked against scope. Final gate tests acceptance criteria. Getting these wrong here means the entire pipeline optimizes for the wrong target.

**Gate state:** Record gate: write equivalent of `moira_state_gate("classification_gate", decision)` to `current.yaml` and `status.yaml`

---

### Architecture Gate

After Metis (architect) completes.

**Artifact sections displayed (D-184):** Content extracted from `architecture.md` required sections. All pipelines now show alternatives — not just Full Pipeline.

**Template (Standard/Decomposition Pipeline):**
```
═══════════════════════════════════════════
 GATE: Architecture
═══════════════════════════════════════════

 Recommendation: {extracted from ## Recommendation — chosen approach + reasoning}

 Alternatives considered:
 ┌─ {Alt 1 name}: {brief description}
 │  Trade-offs: {extracted from ### Alternative 1 / #### Trade-offs}
 ├─ {Alt 2 name}: {brief description}
 │  Trade-offs: {extracted from ### Alternative 2 / #### Trade-offs}
 └─ {if more alternatives exist, list them}

 Assumptions:
 ✅ Verified: {count} ({extracted from ### Verified — summarized})
 ⚠  Unverified: {count}
 {per unverified item:}
    • {assumption} {if load-bearing: "⚡ LOAD-BEARING: {consequence if wrong}"}
 Verification plan: {extracted from ## Verification Plan — summarized}

 Impact: {files affected, estimated budget usage}

 Details:
 → {path to architecture.md}

 ─── Traceability ────
 Classification scope: {In Scope summary from classification gate}
 Acceptance criteria: {criteria list from classification gate}

 {EPISTEMIC FLAGS — if any, from orchestrator e3 checks}

 {HEALTH REPORT}

 1) proceed — Architecture approved, continue
 2) details — Show full architecture reasoning
 3) modify  — Provide feedback for revision
 4) abort   — Cancel task
═══════════════════════════════════════════
```

**Template (Full Pipeline — user chooses):**
Same structure as above, but options present alternatives as choices:
```
 1) {Alternative 1 name}: {brief description + key trade-off}
 2) {Alternative 2 name}: {brief description + key trade-off}
 3) {Alternative 3 name}: {brief description + key trade-off}
 4) details — Show full reasoning for all alternatives
 5) modify  — Provide feedback, request different approaches
 6) abort   — Cancel task
```

When a user selects an alternative by number, record gate decision as `proceed` with the selected alternative number noted in the `note` field (e.g., `note: 'Selected alternative 2'`).

**Epistemic flags (D-172):** If epistemic checks (orchestrator.md step e3) produced any flags, include an EPISTEMIC FLAGS section in the gate display. This section appears after the Traceability section and before the Health Report.

```
─── Epistemic Flags ────
⚠ HEDGE_WITHOUT_EVIDENCE: "{quoted phrase}" in decision D-{N}
⚠ MISSING_EPISTEMIC_SECTION: architecture mentions external systems but has no ## Epistemic Status section
🔴 CLOSED_WORLD_VIOLATION: claim about {system} without documentation (auto-remediation attempted: {success|failed})
📊 EFFECTIVENESS: {mechanism} → {PREVENTS|PARTIALLY_PREVENTS|DOES_NOT_PREVENT} for {incident}
```

Rules:
- If no flags exist: omit the section entirely (no noise for clean architectures)
- If all flags are WARNING level: show with ⚠ prefix
- If any BLOCK flags survived remediation (D-167): show with 🔴 prefix
- Maximum 5 flags displayed; if more, show count and direct user to artifact: "... and {N} more — see {artifact_path}"
- Effectiveness simulation results (D-170) shown as 📊 lines

**Gate state:** Record gate: write equivalent of `moira_state_gate("architecture_gate", decision)` to `current.yaml` and `status.yaml`

---

### Plan Gate

After Daedalus (planner) completes.

**Artifact sections displayed (D-184):** Content extracted from `plan.md` required sections.

**Template:**
```
═══════════════════════════════════════════
 GATE: Plan
═══════════════════════════════════════════

 Plan: {step count} steps in {batch count} batches
 Files: {file count} ({new count} new, {modified count} modified)

 Scope Check (vs Classification):
 {extracted from ## Scope Check}
 {if ### Added to scope is non-empty:}
    ⚠ Added: {items with justification}
 {if ### Removed from scope is non-empty:}
    ⚠ Removed: {items with justification}
 {if both empty:}
    ✅ Scope unchanged from classification

 Acceptance Test:
 {extracted from ## Acceptance Test — how acceptance criteria will be verified}

 Risks:
 {extracted from ## Risks — each risk with plan B}

 Budget:
 Estimated total: ~{N}k tokens
 Budget risk: {none | N steps near limit}

 Details:
 → {path to plan.md}

 ─── Traceability ────
 Classification scope: {In Scope summary}
 Architecture: {recommendation summary}

 {UNVERIFIED DEPENDENCIES — if ## Unverified Dependencies section exists in plan:}
 ─── Unverified Dependencies ────
 {per item: assumption, impact on plan, mitigation}

 {HEALTH REPORT}

 1) proceed      — Plan approved, continue to implementation
 2) details      — Show full plan details
 3) modify       — Provide feedback for revision
 4) rearchitect  — Return to architecture gate (when feedback implies different technical approach)
 5) abort        — Cancel task
═══════════════════════════════════════════
```

**Why this matters:** The scope check makes scope drift visible — if the plan covers more or less than classification promised, the user sees it explicitly. The acceptance test shows HOW criteria will be verified, not just WHAT they are. Unverified dependencies surface epistemic risk before implementation begins.

**Option handling:**
- `rearchitect` — Re-enter pipeline at architecture step. Preserves Explorer and Analyst data. Metis (architect) receives original exploration/analysis data plus user's architectural feedback.

**Gate state:** Record gate: write equivalent of `moira_state_gate("plan_gate", decision)` to `current.yaml` and `status.yaml`

---

### Phase Gate

After each phase iteration in Full Pipeline (after Aletheia (tester) completes phase tests).

**Summary source:** phase implementation + review + test results.

**Display specifics:**
- Show: what was completed in this phase
- Show: review findings (if any warnings)
- Show: test results summary
- Show: what's next (remaining phases)
- Show: progress: phase {n}/{total}

**Options:**
```
1) proceed    — Phase complete, continue to next
2) checkpoint — Save progress and pause (resumable via /moira:resume)
3) modify     — Rework this phase (re-dispatch phase agents with user feedback)
4) abort      — Stop implementation
```

**Gate state:** Record gate: write equivalent of `moira_state_gate("phase_gate_{n}", decision)` to `current.yaml` and `status.yaml`

On `checkpoint`: write manifest.yaml with current progress, set status to `checkpointed`.

**Checkpoint reason selection** (for `manifest.yaml` `checkpoint.reason` field):
- `context_limit` — orchestrator context budget exceeded warning threshold
- `user_pause` — user chose `checkpoint` at a gate
- `error` — pipeline error that cannot be recovered in current session
- `session_end` — session ending (terminal close, timeout)

---

### Decomposition Gate

After Daedalus (planner) decomposes an epic.

**Summary source:** decomposition artifact — task list with sizes, dependencies, execution order.

**Display specifics:**
- Show: list of sub-tasks with their sizes
- Show: dependency graph
- Show: execution order
- Show: estimated total pipeline time/budget

**Options:**
```
1) proceed — Task breakdown approved, begin execution
2) details — Show full decomposition document
3) modify  — Adjust decomposition
4) abort   — Cancel task
```

**Gate state:** Record gate: write equivalent of `moira_state_gate("decomposition_gate", decision)` to `current.yaml` and `status.yaml`

---

### Per-Task Gate

After each sub-task iteration in Decomposition Pipeline (after sub-pipeline completes).

**Summary source:** sub-task execution results.

**Display specifics:**
- Show: what was completed in this sub-task
- Show: test/review results summary
- Show: what's next (remaining sub-tasks)
- Show: progress: sub-task {n}/{total}

**Options:**
```
1) proceed    — Sub-task complete, continue to next
2) checkpoint — Save progress and pause (resumable via /moira:resume)
3) abort      — Stop execution
```

> **Note:** No `modify` option — sub-task rework is handled within the sub-pipeline's own final gate (tweak/redo flows).

**Gate state:** Record gate: write equivalent of `moira_state_gate("per_task_gate_{n}", decision)` to `current.yaml` and `status.yaml`

On `checkpoint`: write manifest.yaml with current progress, set status to `checkpointed`.

---

### Tweak Scope Gate

Presented when tweak scope check detects files outside original task scope.

```
═══════════════════════════════════════════
 TWEAK: Scope Check
═══════════════════════════════════════════
 Tweak would modify files outside original task scope:
 {list of out-of-scope files}

 Original task modified: {list of in-scope files}

 1) force-tweak — apply tweak anyway (may cause inconsistencies)
 2) new-task    — create separate task for out-of-scope changes
 3) cancel      — keep current result
═══════════════════════════════════════════
```

**Gate decision mapping:** `force-tweak` → `proceed` (note: "force-tweak"), `new-task` → `modify` (note: "new-task recommended"), `cancel` → `abort`.

---

### Redo Re-entry Gate

Presented when user chooses redo at final gate.

```
═══════════════════════════════════════════
 REDO — Choose Re-entry Point
═══════════════════════════════════════════
 What prompted the redo?
 > {user reason}

 Re-enter pipeline at:
 1) architecture — change approach entirely (preserves exploration + analysis)
 2) plan         — keep architecture, change execution plan
 3) implement    — keep plan, re-implement from scratch
 4) cancel       — keep current result
═══════════════════════════════════════════
```

**Gate decision mapping:** `architecture/plan/implement` → `proceed` (note: "re-entry: {point}"), `cancel` → `abort`.

---

### Xref Warning Gate

Presented when xref cross-reference inconsistency detected at final gate.

```
═══════════════════════════════════════════
 ⚠ XREF CONSISTENCY WARNING
═══════════════════════════════════════════
 {per-inconsistency block:}
 Modified: {dependent_file}
 Canonical: {canonical_source}
 Field: {field}
 Issue: {description of mismatch}

 1) fix    — dispatch Hephaestus (implementer) to synchronize
 2) ignore — proceed (inconsistency remains)
═══════════════════════════════════════════
```

**Gate decision mapping:** `fix` → `modify`, `ignore` → `proceed`.

---

### Guard Violation Gate

Presented when post-agent guard check (D-099, D-116) detects agent modification of protected paths. This is a conditional gate (like Xref Warning Gate), not a required pipeline gate (Art 2.2). Violations are logged to `state/violations.log` regardless of user choice.

```
═══════════════════════════════════════════
 🔴 GUARD VIOLATION
═══════════════════════════════════════════
 Agent: {agent_name} ({role})

 Protected files modified:
 {per-file block:}
 • {file_path} — {protection_reason}

 1) revert  — revert protected file changes (git checkout), keep other changes
 2) accept  — accept changes (user override)
 3) abort   — abort pipeline
═══════════════════════════════════════════
```

**Gate decision mapping:** `revert` → revert protected files via `git checkout -- <files>`, continue pipeline. `accept` → `proceed`. `abort` → `abort`.

---

### Passive Audit Warning

Inline warning displayed during pipeline execution. Non-blocking — no gate ID, no user response required.

```
⚠ {warning_type}: {description}
{details if any}
(Non-blocking — recorded in status.yaml warnings)
```

**Warning types:** `STALE LOCKS`, `ORPHANED STATE`, `KNOWLEDGE DRIFT`, `CONVENTION DRIFT`

Passive audit warnings are informational only. They do not create gate state and are recorded in `status.yaml` `warnings[]` block using existing schema fields.

---

### Final Gate

After pipeline completion (after review/testing in Quick/Standard, after integration in Full/Decomposition).

**IMPORTANT (D-037):** The final gate is recorded as `proceed` via `moira_state_gate()`. Completion actions (done/tweak/redo/diff/test) are NOT gate decisions — they trigger separate orchestrator flows after the gate is recorded.

**Assembly (D-184):** The orchestrator assembles the final gate content mechanically from pipeline artifacts — no agent dispatch needed. It reads classification.md (scope, acceptance criteria), review.md (findings), test results, and implementation artifacts to build the display.

**Template:**
```
═══════════════════════════════════════════
 GATE: Final Review
═══════════════════════════════════════════

 Completed: {1-3 sentences — what was built/changed}
 Files: {list of created/modified files}

 Acceptance Results:
 {per criterion from classification ## Acceptance Criteria:}
    {✅|❌} {criterion text} — {evidence: test name, file path, or "not tested"}

 Scope Delivery:
 {comparison of classification ## Scope / ### In Scope vs what was actually delivered}
 ├─ Delivered: {items completed}
 {if any deferred:}
 └─ Deferred: {count} items (see below)

 {if deferred items exist:}
 Deferred Items:
 {per item: what was deferred + justification}

 Review: {findings summary — N critical, N warning, N suggestion}
 Tests: {test results summary — N passed, N failed, N skipped}

 {if UNVERIFIED items existed in pipeline:}
 ─── Epistemic Status ────
 {per UNVERIFIED item from architecture:}
    {✅ VERIFIED|⚠ UNVERIFIED|🛡 MITIGATED}: {assumption} — {resolution detail}

 {BUDGET REPORT}

 {HEALTH REPORT}

 1) done  — Accept all changes
 2) tweak — Targeted modification (describe what to change)
 3) redo  — Full rollback (choose re-entry point: architecture/plan/implement)
 4) diff  — Show full git diff
 5) test  — Run full test suite
═══════════════════════════════════════════
```

**Why this matters:** The user sees exactly which acceptance criteria passed/failed, what scope was delivered vs deferred, and whether UNVERIFIED assumptions were resolved. This replaces "what was accomplished" summaries that hide gaps.

**Completion action flows:**
- `tweak` triggers the tweak pipeline (orchestrator Section 7)
- `redo` triggers the redo pipeline (orchestrator Section 7)

**Gate state:** Always record gate: write equivalent of `moira_state_gate("final_gate", "proceed")` to `current.yaml` and `status.yaml`. Then handle completion action separately.

---

### Analytical Final Gate

After analytical pipeline completion (after review step, at completion step).

**Summary source:** analytical deliverables — synthesis of all findings.

**Field sources:**
- summary_source: deliverables.md → first 1-3 sentences
- summary_fallback: "No summary available."
- keypoints_source: deliverables.md → key findings (confirmed/refuted)
- keypoints_max: 5
- impact_source: scope.md → coverage percentage + finding count
- impact_fallback: "N/A"
- artifact_path: state/tasks/{task_id}/deliverables.md

**Template:**

```
═══════════════════════════════════════════
 GATE: Analytical — Final Review
═══════════════════════════════════════════

 Summary:
 {1-3 sentences from deliverables.md}

 Key points:
 • {key finding 1}
 • {key finding 2}
 ...

 Impact: {coverage}% coverage, {finding_count} findings

 Details:
 → {path to deliverables.md}

 {HEALTH REPORT with progress tree}

 1) done    — Accept findings
 2) details — Show all findings in full
 3) modify  — Adjust scope and re-analyze
 4) abort   — Discard analysis
═══════════════════════════════════════════
```

**Option handling:**
- `done` → record gate as `proceed`, proceed to completion
- `details` → display full deliverables.md content (display only, re-present gate — NOT a gate decision)
- `modify` → jump back to `synthesis` step with user feedback
- `abort` → record gate as `abort`, stop pipeline

**Gate state:** Record gate: write equivalent of `moira_state_gate("analytical_final_gate", decision)` to `current.yaml` and `status.yaml`

---

### Scope Gate (Analytical Pipeline)

After Athena (analyst) completes scope formalization in the analytical pipeline.

**Summary source:** scope artifact — questions, boundaries, depth recommendation.

**Template:**

```
═══════════════════════════════════════════
 GATE: Analytical Scope
═══════════════════════════════════════════

 Questions to answer:
 • {question_list from Athena scope}

 Scope boundaries:
 • In scope: {in_scope_description}
 • Out of scope: {out_of_scope_description}

 Depth recommendation: {light | standard | deep}
 Rationale: {why this depth}

 {HEALTH REPORT}

 1) proceed — scope confirmed, begin analysis
 2) modify  — adjust scope
 3) abort   — cancel
═══════════════════════════════════════════
```

**Gate state:** Record gate: write equivalent of `moira_state_gate("scope_gate", decision)` to `current.yaml` and `status.yaml`

---

### Depth Checkpoint Gate (Analytical Pipeline)

After Themis (reviewer) completes convergence computation at depth checkpoint in the analytical pipeline.

**Summary source:** depth checkpoint artifact — finding count, convergence delta/trend, coverage, gaps, insufficient hypotheses.

**Template:**

```
═══════════════════════════════════════════
 GATE: Depth Checkpoint (Pass {N})
═══════════════════════════════════════════

 Findings: {total} total ({confirmed} confirmed, {refuted} refuted, {insufficient} insufficient)

 Convergence: delta = {delta} (Pass {N})
              {trend_description}

 Coverage: {coverage_pct}% ({analyzed}/{relevant} relevant nodes)
   Gaps: {gap_list with priority}

 Insufficient hypotheses:
   • {list of insufficient findings needing more evidence}

 {HEALTH REPORT}

 1) sufficient — proceed to synthesis with current findings
 2) deepen    — investigate gaps + insufficient hypotheses (Pass {N+1})
 3) redirect  — re-scope analysis (back to Athena)
 4) details   — show all findings
 5) abort     — cancel
═══════════════════════════════════════════
```

**Option handling:**
- `sufficient` → record gate, advance to `organize` step
- `deepen` → record gate, increment pass number, jump to `analysis` step
- `redirect` → record gate, reset pass number to 1, jump to `scope` step
- `details` → display all findings from all passes (display only — same pattern as "diff" in implementation final gate). Re-present the gate after display. Do NOT record as gate decision.
- `abort` → record gate as abort, stop pipeline

**Gate state:** Record gate: write equivalent of `moira_state_gate("depth_checkpoint_gate", decision)` to `current.yaml` and `status.yaml`

---

## Quality Checkpoint

<!-- Quality Checkpoint is a conditional gate defined here, not in pipeline YAML step sequences. It is triggered dynamically when a quality-gate agent returns fail_warning. -->

Presented when a quality-gate agent returns `fail_warning` verdict (zero critical findings, but 1+ warning findings).

This is a CONDITIONAL gate — only presented when warnings exist. It does NOT replace required pipeline gates (Art 2.2).

**Trigger:** Agent returns `QUALITY: {gate}=fail_warning` in response.

**Template:**

```
═══════════════════════════════════════════
 GATE: Quality Checkpoint — {Gate Name}
═══════════════════════════════════════════

 {Agent Name} ({role}) found {N} warnings:

 {formatted warnings from moira_quality_format_warnings()}

 Impact: {summary — one-line description of warning implications}

 ORCHESTRATOR HEALTH:
 {standard health report}

 1) proceed — Accept warnings, continue pipeline
 2) fix     — Send back to Hephaestus (implementer) for fixes
 3) details — Show full findings
 4) abort   — Cancel task
═══════════════════════════════════════════
```

**Gate state mapping:**
- `proceed` → record gate as `proceed`, advance to next step
- `fix` → record gate as `modify`, re-dispatch Hephaestus (implementer) with warning findings as feedback
- `details` → display full findings file content, return to gate options (do NOT record as gate decision)
- `abort` → record gate as `abort`, stop pipeline

**Finding display:** Use `moira_quality_format_warnings()` from `quality.sh` to format warning items.

**Gate state:** Record gate: write equivalent of `moira_state_gate("quality_checkpoint_{gate}", decision)` to `current.yaml` and `status.yaml`

---

## Error/Blocked Gates

These are presented when an error occurs, distinct from approval gates.

### Blocked Gate (E1-INPUT)

See `errors.md` → E1-INPUT → Display for template.

**Options:**
```
1) answer — provide the information
2) point  — point to a file/doc with the answer
3) skip   — mark as TODO in code
4) abort  — stop task
```

---

### Scope Change Gate (E2-SCOPE)

See `errors.md` → E2-SCOPE → Display for template.

**Options:**
```
1) upgrade  — re-plan at larger size
2) split    — break into separate tasks
3) reduce   — simplify scope
4) continue — proceed as-is (⚠ quality risk)
```

---

### Conflict Gate (E3-CONFLICT)

See `errors.md` → E3-CONFLICT → Display for template.

**Options:** Present Option A and Option B with agent recommendation. User chooses.

---

### Quality Failure Gate (E5-QUALITY, after max retries)

See `errors.md` → E5-QUALITY → Display (After Max Retries) for template.

**Options:**
```
1) redesign — send back to Metis (architect)
2) manual   — you'll handle this part
3) simplify — remove feature, find simpler approach
```

---

### Agent Failure Gate (E6-AGENT)

See `errors.md` → E6-AGENT → Display (After Failure) for template.

**Options:**
```
1) retry-split — split work and retry
2) retry-as-is — retry same task
3) manual      — handle manually
4) rollback    — undo all, re-plan
```

---

## Gate State Management

For ALL gates, the orchestrator writes YAML directly (see `orchestrator.md` Section 1 — State Management Mechanism):

1. **Before presenting gate:** write `gate_pending: {gate_id}` to `current.yaml`
2. **After user decision:** write the equivalent of `moira_state_gate(gate_name, decision)` — update `current.yaml` (`gate_pending: null`) and append to `status.yaml` `gates[]` array (see `lib/state.sh` for field logic)
   - `decision` must be one of: `proceed`, `modify`, `abort`
   - `rearchitect` (plan gate only) records as `modify` with note indicating re-architecture requested.
   - For error gates: map user choice to nearest gate decision
     - answer/point/skip/upgrade/split/reduce/continue/a/b → `proceed` (continuing with modification)
     - abort/rollback → `abort`
3. **Gate clears:** the gate write sets `gate_pending: null` in `current.yaml`

### Agent Naming Convention

All gate displays use `Name (role)` format for agent references (D-034). Examples:
- "Apollo (classifier)" not "Classifier" or "apollo"
- "Hermes (explorer)" not "Explorer"
- "Metis (architect)" not "Architect"
- "Daedalus (planner)" not "Planner"
- "Hephaestus (implementer)" not "Implementer"
- "Themis (reviewer)" not "Reviewer"
- "Aletheia (tester)" not "Tester"
- "Mnemosyne (reflector)" not "Reflector"
