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
- Context: ✅ <25%, ⚠ 25-60%, 🔴 >60%
- Violations: ✅ if 0, 🔴 if >0

---

## Budget Report Section

Display at pipeline completion (final gate and post-pipeline):

```
╔══════════════════════════════════════════════╗
║           CONTEXT BUDGET REPORT              ║
╠══════════════════════════════════════════════╣
║ Agent         │ Budget │ Est.  │ % │ Status  ║
║───────────────┼────────┼───────┼───┼─────────║
{per-agent rows from status.yaml history}
║ Orchestrator  │ 200k   │ {est} │{%}│ {emoji} ║
╠══════════════════════════════════════════════╣
║ Orchestrator context: {used}k/200k ({pct}%)  ║
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
▸ proceed — Classification correct, continue with {pipeline_type} Pipeline
▸ modify  — Provide different classification (size: small/medium/large/epic)
▸ abort   — Cancel task
```

**Gate state:** `moira_state_gate("classification_gate", decision)`

---

### Architecture Gate

After Metis (architect) completes.

**Summary source:** architecture artifact — decision summary, alternatives rejected, impact.

**Display specifics:**
- Show: primary architecture decision with brief reasoning
- Show: alternatives considered and why rejected
- Show: impact on files and components
- For Full Pipeline: present alternatives as choices (user CHOOSES, not just approves)

**Options (Standard Pipeline):**
```
▸ proceed — Architecture approved, continue
▸ details — Show full architecture reasoning
▸ modify  — Provide feedback for revision
▸ abort   — Cancel task
```

**Options (Full Pipeline — user chooses architecture):**
```
▸ 1 — {Alternative 1 name}: {brief description}
▸ 2 — {Alternative 2 name}: {brief description}
▸ 3 — {Alternative 3 name}: {brief description}
▸ details — Show full reasoning for all alternatives
▸ modify  — Provide feedback, request different approaches
▸ abort   — Cancel task
```

**Gate state:** `moira_state_gate("architecture_gate", decision)`

---

### Plan Gate

After Daedalus (planner) completes.

**Summary source:** plan artifact — step count, batch count, estimated budget, file list.

**Display specifics:**
- Show: number of implementation steps/batches
- Show: estimated total budget usage
- Show: files to be created/modified
- Show: dependency graph summary (if batched)

**Options:**
```
▸ proceed — Plan approved, continue to implementation
▸ details — Show full plan details
▸ modify  — Provide feedback for revision
▸ abort   — Cancel task
```

**Gate state:** `moira_state_gate("plan_gate", decision)`

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
▸ proceed    — Phase complete, continue to next
▸ checkpoint — Save progress and pause (resumable via /moira:resume)
▸ abort      — Stop implementation
```

**Gate state:** `moira_state_gate("phase_gate_{n}", decision)`

On `checkpoint`: write manifest.yaml with current progress, set status to `checkpointed`.

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
▸ proceed — Task breakdown approved, begin execution
▸ modify  — Adjust decomposition
▸ abort   — Cancel task
```

**Gate state:** `moira_state_gate("decomposition_gate", decision)`

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
▸ done  — Accept all changes
▸ tweak — Targeted modification (describe what to change)
▸ redo  — Full rollback (choose re-entry point: architecture/plan/implement)
▸ diff  — Show full git diff
▸ test  — Run full test suite
```

**Gate state:** Always `moira_state_gate("final_gate", "proceed")`. Then handle completion action separately.

---

## Error/Blocked Gates

These are presented when an error occurs, distinct from approval gates.

### Blocked Gate (E1-INPUT)

See `errors.md` → E1-INPUT → Display for template.

**Options:**
```
▸ answer — provide the information
▸ point  — point to a file/doc with the answer
▸ skip   — mark as TODO in code
▸ abort  — stop task
```

---

### Scope Change Gate (E2-SCOPE)

See `errors.md` → E2-SCOPE → Display for template.

**Options:**
```
▸ upgrade  — re-plan at larger size
▸ split    — break into separate tasks
▸ reduce   — simplify scope
▸ continue — proceed as-is (⚠ quality risk)
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
▸ redesign — send back to Metis (architect)
▸ manual   — you'll handle this part
▸ simplify — remove feature, find simpler approach
```

---

### Agent Failure Gate (E6-AGENT)

See `errors.md` → E6-AGENT → Display (After Failure) for template.

**Options:**
```
▸ retry-split — split work and retry
▸ retry-as-is — retry same task
▸ manual      — handle manually
▸ rollback    — undo all, re-plan
```

---

## Gate State Management

For ALL gates:

1. **Before presenting gate:** set `gate_pending` in `current.yaml` via `moira_yaml_set`
2. **After user decision:** record via `moira_state_gate(gate_name, decision)`
   - `decision` must be one of: `proceed`, `modify`, `abort`
   - For error gates: map user choice to nearest gate decision
     - answer/point/skip/upgrade/split/reduce/continue/a/b → `proceed` (continuing with modification)
     - abort/rollback → `abort`
3. **Gate clears:** `moira_state_gate()` sets `gate_pending: null` in `current.yaml`

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
