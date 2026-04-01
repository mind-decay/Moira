# Implementation Plan: Fix F-001 & F-002

**Spec:** `design/specs/2026-03-17-fix-f001-f002.md`

---

## Chunk 1: Design Doc Updates (F-002 prerequisite — ORANGE requires design docs first)

Design docs must be updated before implementation per CLAUDE.md rules. All tasks in this chunk are independent and can be done in parallel.

### Task 1.1: Decision Log — D-099

**File:** `design/decisions/log.md`
**Action:** Append new decision after D-098.

**Key points:**
- ID: D-099
- Title: Post-Agent Guard Verification
- Context: F-002 revealed PostToolUse hooks don't fire for subagents. Guard.sh (Layer 2) is bypassed for all agent work.
- Decision: Replace hook-based Layer 2 for agents with post-agent git diff verification. Guard.sh stays for orchestrator. Two sub-decisions: (1) protected paths defined inline in orchestrator.md, (2) agent self-reporting via `moira_state_agent_done` is authoritative for budget tracking.
- Alternatives rejected: (a) inject hooks into agent prompts — unreliable, violates SoC; (b) agent worktree isolation — overhead, complex merge; (c) project-level hooks propagation — undocumented CC behavior; (d) accept limitation with no structural check — Art 6.3 unsatisfied
- Reasoning: Post-agent diff is strictly stronger than hooks (can block pipeline, D-075 shows hooks can only detect). More efficient (one check per agent vs dozens of per-tool-call hooks). Independent of CC subprocess architecture.

**Commit:** `moira(design): add D-099 post-agent guard verification decision`

### Task 1.2: self-monitoring.md — Fix Layer 2 description

**File:** `design/subsystems/self-monitoring.md`
**Action:** Update Layer 2 section (lines 58-88).

**Key points:**
- Fix factually incorrect claim on line 60: "Claude Code hooks fire for ALL tool uses in the session, including those made by dispatched subagents" → correct to state that hooks fire only in the main session, not in subagent subprocesses (per F-002 finding)
- Describe two-tier Layer 2: (a) guard.sh PostToolUse hook for orchestrator-level violations, (b) post-agent git diff check for agent-level violations (D-099)
- Note that post-agent diff can block pipeline (unlike guard.sh which is detection-only per D-075)
- Reference Guard Violation Gate in gates.md for agent violation handling
- Keep the existing guard.sh code example but annotate it as "orchestrator session only"

**Commit:** `moira(design): fix self-monitoring Layer 2 for post-agent guard (D-099)`

### Task 1.3: context-budget.md — Fix post-execution section

**File:** `design/subsystems/context-budget.md`
**Action:** Update "Post-execution (by budget tracker hook)" section (lines 141-155).

**Key points:**
- Current description is already inaccurate — says hooks log "Input size, Output size, Estimated total usage" but budget-track.sh actually logs `timestamp tool_name file_path file_size`
- Fix description to match actual hook behavior
- Add clarification: hooks fire only in orchestrator session (D-099), not for agent tool calls
- Document that agent budget tracking uses self-reporting via `moira_state_agent_done` (tokens_used, context_pct) as authoritative source
- Keep "Measurement Approach" section as-is (it correctly describes approximation)

**Commit:** `moira(design): fix budget post-execution section for self-reporting (D-099)`

---

## Chunk 2: Implementation — orchestrator.md, gates.md, errors.md, dispatch.md, telemetry schema

Depends on Chunk 1 (design docs must exist before implementation references them).

### Task 2.1: orchestrator.md — Add reflection as completion step (F-001)

**File:** `src/global/skills/orchestrator.md`
**Section:** Section 7 — Completion Flow

**Action:**
- In the `done` action list (lines 363-385), add a new bullet before "Set pipeline status to `completed`" (currently the last bullet at line 385):
  - "Reflection dispatch: Read the current pipeline's `post.reflection` value from the pipeline YAML. If `lightweight`: write reflection note directly to `state/tasks/{id}/reflection.md` using `templates/reflection/lightweight.md` (substitute placeholders: {task_id}, {pipeline_type}, {final_gate_action}, {retry_count}, {budget_pct}). For all other modes (`background`, `deep`, `epic`): invoke the `reflection.md` skill for Mnemosyne dispatch."
- Remove the standalone "### Reflection Dispatch" section (lines 407-420) — the table and reference text. The `tweak` action definition (line 422+) follows directly after the Xref Consistency Check section.

**Commit:** `moira(pipeline): move reflection dispatch to explicit completion step (F-001)`

### Task 2.2: orchestrator.md — Add post-agent guard check (F-002)

**File:** `src/global/skills/orchestrator.md`
**Section:** Section 2 — Pipeline Execution (Main Loop)

**Action:** Add a new sub-step between step (d) "On agent return: parse response" and step (e) "Check STATUS" in the Main Loop. Insert as step (d1):

```
d1. **Post-agent guard check** (D-099): If the agent's role can modify files (implementer, explorer), verify no protected paths were touched:
    1. Run `git diff --name-only` (unstaged) and `git diff --name-only --cached` (staged) to get files modified since step start
    2. Check modified files against protected paths:
       - `design/CONSTITUTION.md` — absolute prohibition (Art 6.1)
       - `design/**` — design docs (Art 6.2)
       - `.moira/config/**` — system configuration
       - `.moira/core/**` — core rules and pipelines
       - `src/global/**` — Moira source code
       Allowed exceptions (not violations):
       - `.moira/state/tasks/{current_task_id}/**`
       - `.moira/knowledge/**`
       - `.moira/state/current.yaml`
       - `.moira/state/queue.yaml`
       - All project source files
    3. If violation found → log to `state/violations.log` (same format as guard.sh: `timestamp AGENT_VIOLATION agent_role file_path`), then present Guard Violation Gate (per `gates.md`)
    4. If clean → proceed to step (e)
```

Also update **Section 6 — Violation Monitoring** (lines 335-341):
- Add a note that violations can come from two sources: (1) guard.sh hookSpecificOutput warnings for orchestrator violations (prefix `VIOLATION`), (2) post-agent guard check for agent violations (prefix `AGENT_VIOLATION`). Both write to `state/violations.log`.
- Update violation counting instruction (line 339): distinguish counts by prefix — "orchestrator violations: count `VIOLATION` lines; agent violations: count `AGENT_VIOLATION` lines."

**Commit:** `moira(pipeline): add post-agent guard check step (F-002, D-099)`

### Task 2.3: gates.md — Add Guard Violation Gate + fix health report violation count

**File:** `src/global/skills/gates.md`
**Action:** Add a new gate template section + update health report violation display.

**Key points:**
- Gate name: "GUARD VIOLATION"
- Template follows standard gate format (═══ header)
- Body: list of violated files with agent role that modified them
- Options: `revert` (revert protected files via `git checkout -- <files>`, keep other changes), `accept` (user override, continue), `abort` (stop pipeline)
- Note: this is a conditional gate (like Xref Warning Gate), not a required pipeline gate (Art 2.2)
- Log violation to `state/violations.log` regardless of user choice
- Update health report template (line 59): violation count data source now has two entry types. Show separate counts: "Violations: {N} orchestrator, {M} agent" (count by `VIOLATION` vs `AGENT_VIOLATION` prefix in violations.log). If both are 0, show "Violations: 0 ✅".

**Commit:** `moira(pipeline): add Guard Violation Gate and update health report (F-002)`

### Task 2.4: errors.md — Update E7-DRIFT scope + fix violation counting

**File:** `src/global/skills/errors.md`
**Section:** E7-DRIFT (lines 387-445)

**Action:**
- Add a scope note at the top of E7-DRIFT: "**Scope:** Orchestrator-level violations only. Agent-level violations are handled by the post-agent guard check (D-099) via the Guard Violation Gate in `gates.md`."
- In the "Detection" subsection (lines 389-394), add: "Note: guard.sh fires only in the orchestrator session. Agent tool calls are not covered by this hook (D-099). Agent violations are detected via post-agent git diff check in the pipeline execution loop."
- In the "Post-Task Audit" subsection (line 407): fix violation counting to filter by prefix — count only `VIOLATION` lines (exclude `AGENT_VIOLATION`). Change from `wc -l < state/violations.log` to counting lines matching the `VIOLATION` prefix (not `AGENT_VIOLATION`).

**Commit:** `moira(pipeline): clarify E7-DRIFT scope and fix violation counting (F-002)`

### Task 2.5: dispatch.md — Update post-dispatch flow

**File:** `src/global/skills/dispatch.md`
**Section:** "After Successful Dispatch" (lines 203-211)

**Action:** Add step between "Record agent completion" (step 1) and "If a gate follows" (step 2):

```
1b. Post-agent guard check (D-099): If agent role is implementer or explorer, run guard verification against protected paths (see orchestrator.md Section 2, step d1). If violation → present Guard Violation Gate before any approval gate.
```

**Commit:** `moira(pipeline): add post-agent guard reference in dispatch flow (F-002)`

### Task 2.6: telemetry.schema.yaml — Add agent violation count

**File:** `src/schemas/telemetry.schema.yaml`
**Action:** Add new field after `compliance.orchestrator_violation_count` (line 127):

```yaml
  compliance.agent_guard_violation_count:
    type: number
    required: false
    default: 0
    description: "Count of agent-level protected path violations detected by post-agent guard check (D-099)"
```

**Commit:** `moira(pipeline): add agent guard violation telemetry field (F-002)`

### Task 2.7: orchestrator.md — Fix violation counting in completion flow

**File:** `src/global/skills/orchestrator.md`
**Section:** Section 7 — Completion Flow, `done` action (lines 366-369)

**Action:** Update violation-related telemetry writes in the `done` action list to handle dual-format violations.log:

- `structural.constitutional_pass` (line 368): currently `true` if violations.log has zero entries. Change to: `true` if violations.log has zero `VIOLATION`-prefixed lines (orchestrator violations). `AGENT_VIOLATION` lines do NOT affect `constitutional_pass` — Art 1.1 is about orchestrator purity, not agent protected path violations.
- `structural.violations` (line 369): array of violation entries — filter to `VIOLATION`-prefixed lines only.
- `compliance.orchestrator_violation_count` (line 367): count `VIOLATION`-prefixed lines only (was already scoped to orchestrator, now needs explicit prefix filtering).
- Add: write `compliance.agent_guard_violation_count` from count of `AGENT_VIOLATION`-prefixed lines.

**Commit:** `moira(pipeline): fix violation counting for dual-format violations.log (F-002)`

---

## Dependency Graph

```
Chunk 1 (design docs — all parallel):
  Task 1.1 (decision log)  ─┐
  Task 1.2 (self-monitoring) ├── all independent
  Task 1.3 (context-budget) ─┘
           │
           ▼
Chunk 2 (implementation):
  Task 2.1 (orchestrator reflection, F-001) ── independent
  Task 2.2 (orchestrator guard, F-002) ──────── depends on 1.1 (references D-099)
  Task 2.3 (gates.md) ──────────────────────── depends on 2.2 (references guard check + violation log format)
  Task 2.4 (errors.md E7-DRIFT) ────────────── depends on 2.2 (references violation log format)
  Task 2.5 (dispatch.md) ───────────────────── depends on 2.2 (references orchestrator step)
  Task 2.6 (telemetry schema) ──────────────── depends on 2.2 (uses violation log format)
  Task 2.7 (orchestrator violation counting) ── depends on 2.1 + 2.2 (modifies same `done` section)
```

Execution order:
1. Chunk 1: Tasks 1.1, 1.2, 1.3 (parallel)
2. Chunk 2: Task 2.1 + 2.2 (parallel, different sections of orchestrator.md)
3. Chunk 2: Tasks 2.3, 2.4, 2.5, 2.6 (parallel, after 2.2)
4. Chunk 2: Task 2.7 (after 2.1 + 2.2, since it modifies the `done` section that both touch)
