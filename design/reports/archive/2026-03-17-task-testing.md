# Moira Task Pipeline Testing Report

**Date:** 2026-03-17
**Scope:** Manual testing of init, status, health, metrics, knowledge, and task execution (Quick Pipeline)
**Test project:** sveltkit-todos (SvelteKit + Prisma + Tailwind)

## Summary

| Result | Count |
|--------|-------|
| Commands tested | 6 (/moira:init, /moira:status, /moira:health, /moira:metrics, /moira:knowledge, /moira:task) |
| Full pass | 5 |
| Pass with finding | 1 (/moira:task) |
| Findings | 2 |

**Overall:** System is functional and conformant. All commands produce output matching design docs. Two findings from task execution: (1) lightweight reflection step skipped, (2) hooks don't fire for subagent tool calls — architectural limitation of Claude Code.

---

## Commands Verified — Full Pass

### /moira:init
- All 12 steps executed in correct order
- 4 parallel Hermes scanners (tech, structure, convention, pattern) — correct
- Scanners detected real project details (Svelte 5 runes, CSRF triplet, no tests)
- MCP discovery found 3 servers — correct
- User gates (review + onboarding) present and functional
- Scaffold, config, rules, knowledge, CLAUDE.md, gitignore, hooks — all created

### /moira:status
- All sections present: Version, Project, Stack, Quality mode, Bootstrap flags, Active Task, Recent Tasks, Knowledge, Locks
- Empty state messaging correct ("No active task", "No tasks completed yet")

### /moira:health
- Score: 100/100 with correct reweighting note (Quality excluded → Structural 60% + Efficiency 40%)
- 19/19 structural checks (matches 6 Constitutional articles: 3+3+3+4+3+3)
- Quality: "no data" — correct for fresh init
- Top issues relevant: deep scan pending, no Tier 1 tests, no task data

### /moira:metrics
- Empty state with correct message, no crash

### /moira:knowledge
- 7 knowledge types with correct levels:
  - quality-map: no L0 (AD-6, intentional)
  - libraries: no L2 (per-library structure, intentional)
- Agent Access Matrix matches `knowledge-access-matrix.yaml` exactly (all 10 agents verified)
- Freshness: 100% for all types — correct for fresh init

---

## Task Execution — Quick Pipeline

**Task:** "Давай добавим логику удаления todo"
**Task ID:** task-2026-03-17-001
**Pipeline:** Quick (small + high confidence)

### Pipeline Steps — All Correct

| Step | Agent | Result | Conformance |
|------|-------|--------|-------------|
| 1 | Apollo (classifier) | small, high confidence | OK — correct agent result format |
| 2 | Hermes (explorer) | Found READ+CREATE, no DELETE | OK — context.md created |
| 3 | Hephaestus (implementer) | deleteTodo action + UI button | OK — implementation.md created |
| 4 | Themis (reviewer) | Q4=pass (0C/1W/1S) | OK — findings accurate |
| 5 | Final Gate | Presented with 5 options | OK — matches design |

### Deep Scan — Correct
- Triggered by `deep_scan_pending: true` — 4 background agents dispatched
- All 4 completed asynchronously (architecture, dependency, test-coverage, security)
- Results saved to knowledge base

### Classification Gate — Correct
- Format matches design (Summary, Key points, Impact, Details, Health, 3 options)
- Health report: all 6 fields present

### Final Gate — Correct
- 5 options (done/tweak/redo/diff/test) — matches design
- Health report: all 6 fields present

### Tweak Flow — Correct
- User selected "tweak" → orchestrator asked for description
- Scope check performed (same 2 files)
- Hephaestus re-dispatched for targeted fixes
- Themis re-reviewed → Q4=PASS (0C/0W/0S)
- Returned to Final Gate with updated summary

### Budget Report — Correct
- Per-agent budgets match design (Apollo 20k, Hermes 140k, Hephaestus 120k, Themis 100k, Orchestrator 1000k)
- Tweak agents shown as separate lines
- Threshold indicators correct (Apollo 51% → ⚠️)

### Agent Result Format — All Conformant
All agents returned: STATUS, SUMMARY, ARTIFACTS, NEXT (+ QUALITY for Themis)

---

## Findings

### F-001 | Lightweight reflection skipped on Quick Pipeline completion

- **Severity:** Medium
- **Component:** Orchestrator completion flow (Section 7)
- **Pipeline:** Quick
- **Observed:** After user selected "done" at Final Gate, orchestrator completed the task without writing a lightweight reflection note.
- **Expected:** Per orchestrator.md Section 7 (Reflection Dispatch table), Quick Pipeline maps to `lightweight` mode, which requires writing a minimal reflection note to `state/tasks/{id}/reflection.md` using `templates/reflection/lightweight.md`. No agent dispatch needed.
- **Root cause analysis:** Three contributing factors:
  1. **Split instructions** — orchestrator.md says "write minimal note" but implementation details are in separate `reflection.md` skill. If orchestrator doesn't load the reflection skill, the step is lost.
  2. **Negative-first phrasing** — table entry starts with "No Reflector dispatched" which reads as "do nothing", though the second sentence says "Write minimal reflection note."
  3. **Position in flow** — reflection dispatch comes after 18 completion steps (budget, telemetry, metrics, checkpoint cleanup). By this point orchestrator may consider the task done.
- **Self-correction:** Orchestrator recognized the omission when prompted and offered to write the note retroactively.
- **Proposed fix:** Make lightweight reflection an explicit numbered step in the completion checklist rather than a table lookup. Example: "Step 19: Write reflection note (lightweight: use template directly, no agent dispatch)."
- **Dependencies:** None.
- **Files to modify:** `src/global/skills/orchestrator.md` (Section 7 completion flow)

### F-002 | PostToolUse hooks don't fire for subagent tool calls

- **Severity:** High
- **Component:** Hooks system (guard.sh, budget-track.sh)
- **Pipeline:** All pipelines
- **Observed:** Both `tool-usage.log` and `budget-tool-usage.log` remained empty (0 bytes) after a full Quick Pipeline task execution with 6 agents making dozens of tool calls on project files.
- **Expected:** Hooks should log every tool call — guard.sh for violation detection, budget-track.sh for token tracking.
- **Root cause:** Claude Code architectural limitation. `PostToolUse` hooks defined in `settings.json` fire only for tool calls in the **main session** (orchestrator). Agents dispatched via the `Agent` tool run as **separate subprocesses** that do not inherit parent hooks.
- **Impact:**
  - **guard.sh:** Cannot detect or block prohibited file modifications by agents (e.g., Constitution edits, design doc changes without approval). The entire guard rail system is bypassed for agent work — which is where ALL project file modifications happen.
  - **budget-track.sh:** Cannot track per-tool token usage for agents. Budget report numbers in the completion flow come from agent self-reporting, not independent measurement.
- **Evidence:**
  - Hooks work correctly when triggered manually or by orchestrator tool calls
  - 0 log entries from task execution window (12:05–13:39) despite 6 agents with dozens of tool calls
  - All project file Read/Write/Edit operations were performed by agents (Hephaestus, Hermes, Themis), not orchestrator
- **Workaround options:**
  1. **Inject hooks into agent prompts** — instruct each agent to call guard/budget functions explicitly (unreliable, violates separation of concerns)
  2. **Post-hoc verification** — run guard checks after agent completion by scanning git diff (delayed but reliable)
  3. **Orchestrator-level validation** — orchestrator reads agent artifacts and validates against guard rules before proceeding to next step (adds latency)
  4. **Accept limitation** — document that hooks are orchestrator-only, rely on agent prompt constraints (NEVER rules) and Themis review for safety
- **Recommended approach:** Option 2 + 4 combined. Add a post-agent guard check step in the orchestrator (scan git diff after each agent that modifies files) while documenting that real-time hook interception is not possible for subagents. This preserves safety without depending on agent self-discipline.
- **Dependencies:** Affects guard system design (`design/subsystems/guard.md`), budget tracking design (`design/subsystems/context-budget.md`), and potentially Constitutional Article 6 (Self-Protection) verification strategy.
- **Files to modify:** `src/global/skills/orchestrator.md`, `design/subsystems/guard.md`, `design/subsystems/context-budget.md`
