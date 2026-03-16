# Gate Presentation System

Reference: `design/architecture/pipelines.md` (Approval Gate UX), `design/architecture/commands.md` (In-Pipeline Actions)

This skill defines how the orchestrator presents approval gates and error gates to the user.

---

## Standard Gate Template

Every gate follows this template structure:

```
═══════════════════════════════════════════
 GATE: {Gate Name}
═══════════════════════════════════════════

 Summary:
 {1-3 sentences from agent artifact}

 Key points:
 • {bullet 1}
 • {bullet 2}
 • {bullet 3}

 Impact: {files affected, estimated budget usage}

 Details:
 → {path to full artifact file}

 {HEALTH REPORT}

 {OPTIONS}
═══════════════════════════════════════════
```

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
- Violations: ✅ if 0, 🔴 if >0

Data sources:
- Context: from `current.yaml` → `context_budget.orchestrator_percent` (updated by moira_budget_orchestrator_check)
- Violations: line count of `.claude/moira/state/violations.log` (0 if file doesn't exist or is empty)
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

**Summary source:** classification artifact — size, confidence, pipeline type, reasoning.

**Display specifics:**
- Show: task size, confidence level, recommended pipeline type
- Show: classifier's reasoning for the classification
- If user provided size hint and classifier disagrees: highlight the override with reasoning

**Options:**
```
1) proceed — Classification correct, continue with {pipeline_type} Pipeline
2) modify  — Provide different classification (size: small/medium/large/epic)
3) abort   — Cancel task
```

**Gate state:** Record gate: write equivalent of `moira_state_gate("classification_gate", decision)` to `current.yaml` and `status.yaml`

---

### Architecture Gate

After Metis (architect) completes.

**Summary source:** architecture artifact — decision summary, alternatives rejected, impact.

**Display specifics:**
- Show: primary architecture decision with brief reasoning
- Show: alternatives considered and why rejected
- Show: impact on files and components
- For Full Pipeline: present alternatives as choices (user CHOOSES, not just approves)

**Note:** The Decomposition Pipeline uses the Standard variant (proceed/details/modify/abort).

**Options (Standard Pipeline):**
```
1) proceed — Architecture approved, continue
2) details — Show full architecture reasoning
3) modify  — Provide feedback for revision
4) abort   — Cancel task
```

**Options (Full Pipeline — user chooses architecture):**
```
1) {Alternative 1 name}: {brief description}
2) {Alternative 2 name}: {brief description}
3) {Alternative 3 name}: {brief description}
4) details — Show full reasoning for all alternatives
5) modify  — Provide feedback, request different approaches
6) abort   — Cancel task
```

When a user selects an alternative by number, record gate decision as `proceed` with the selected alternative number noted in the `note` field (e.g., `note: 'Selected alternative 2'`).

**Gate state:** Record gate: write equivalent of `moira_state_gate("architecture_gate", decision)` to `current.yaml` and `status.yaml`

---

### Plan Gate

After Daedalus (planner) completes.

**Summary source:** plan artifact — step count, batch count, estimated budget, file list.

**Display specifics:**
- Show: number of implementation steps/batches
- Show: estimated total budget usage (from plan artifact budget estimates section)
- Show: budget risk — number of steps near 70% limit (from plan artifact)
- Show: files to be created/modified
- Show: dependency graph summary (if batched)

**Budget preview** (from Daedalus plan artifact):
```
 Estimated total budget: ~{N}k tokens
 Budget risk: {none | N steps near limit}
```

**Options:**
```
1) proceed      — Plan approved, continue to implementation
2) details      — Show full plan details
3) modify       — Provide feedback for revision
4) rearchitect  — Return to architecture gate (when feedback implies different technical approach)
5) abort        — Cancel task
```

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

**Gate state:** Record gate: write equivalent of `moira_state_gate("per_task_gate_{n}", decision)` to `current.yaml` and `status.yaml`

On `checkpoint`: write manifest.yaml with current progress, set status to `checkpointed`.

---

### Final Gate

After pipeline completion (after review/testing in Quick/Standard, after integration in Full/Decomposition).

**IMPORTANT (D-037):** The final gate is recorded as `proceed` via `moira_state_gate()`. Completion actions (done/tweak/redo/diff/test) are NOT gate decisions — they trigger separate orchestrator flows after the gate is recorded.

**Summary source:** completion summary from all pipeline artifacts.

**Display specifics:**
- Show: what was accomplished (1-3 sentences)
- Show: files created/modified
- Show: review findings summary (if any)
- Show: test results summary (if tests were run)
- Show: full budget report

**Options:**
```
1) done  — Accept all changes
2) tweak — Targeted modification (describe what to change)
3) redo  — Full rollback (choose re-entry point: architecture/plan/implement)
4) diff  — Show full git diff
5) test  — Run full test suite
```

**Gate state:** Always record gate: write equivalent of `moira_state_gate("final_gate", "proceed")` to `current.yaml` and `status.yaml`. Then handle completion action separately.

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
