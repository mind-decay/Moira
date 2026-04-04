# Phase 18: Context Read Optimization

**Date:** 2026-04-01
**Risk:** YELLOW (hook behavior changes, dispatch path changes — no constitutional impact)
**Design sources:** orchestrator.md Sections 1-2, dispatch.md, gates.md, D-199, D-200, D-201
**Depends on:** Phase 16 (state automation — hooks infrastructure), Phase 17 (standardized contracts)

---

## Problem

Phase 16 eliminated orchestrator state WRITES (~12k tokens). But the orchestrator still performs ~45 Read operations per standard pipeline for three categories:

1. **Init reads** (~10 Reads, ~2000 tokens): graph availability, quality mode, bench mode, audit-pending, checkpointed state, stale knowledge, stale locks
2. **Dispatch reads** (~5-8 Reads per agent × 3 pre-planning agents = ~20 Reads, ~4000 tokens): role YAML, base rules, response contract, task context, quality checklist, traceability context
3. **Gate reads** (~5-6 Reads per gate × 4 gates = ~20 Reads, ~4000 tokens): artifact sections, budget state, violations, gates passed, retries, progress

**Total: ~10,000 tokens and ~45 tool calls** of pure read overhead per standard pipeline.

## Goal

Reduce orchestrator context reads by moving data collection into hooks and shell scripts. The orchestrator receives pre-collected data via `additionalContext` injection and pre-assembled instruction files. Each optimization layer has graceful degradation — if the hook fails, the orchestrator falls back to current behavior.

**Target: ~45 Read calls → ~5-8 Read calls per pipeline.**

## Design Principle

**Shell collects data, LLM decides and formats.** Scripts never render user-facing output or make pipeline decisions. They gather, structure, and inject data. The orchestrator retains all decision-making and formatting authority.

---

## Deliverables

### Chunk 1: Preflight Context Injection (D-199)

**Modified files:**
- `src/global/hooks/task-submit.sh` — extend with preflight data collection
- `src/global/lib/task-init.sh` — add `moira_preflight_collect()` function
- `src/global/skills/orchestrator.md` — add preflight consumption path with fallback

**What changes:**
1. New function `moira_preflight_collect()` in `task-init.sh`:
   - Checks `.ariadne/graph/graph.json` existence + `config.yaml → graph.enabled` → `graph_available`
   - Checks graph staleness (compare `meta.json` timestamp vs `git log -1 --format=%ct`)
   - Reads `config.yaml → quality.mode` and `quality.evolution.current_target`
   - Reads `current.yaml → bench_mode`
   - Checks `audit-pending.yaml` existence + depth
   - Checks `current.yaml → step_status` for checkpointed state
   - Runs `moira_knowledge_stale_entries` for stale knowledge count
   - Checks `locks.yaml` for stale locks (TTL expired)
   - Checks `current.yaml` for orphaned in_progress state
   - Returns structured key=value block to stdout

2. `task-submit.sh` calls `moira_preflight_collect()` after `moira_task_init()`, appends result to `additionalContext`

3. `task-submit.sh` also writes `graph_available` to `current.yaml` (so downstream hooks can read it)

4. `orchestrator.md` Section 2: new "Preflight Fast Path" — if `MOIRA_PREFLIGHT:` present in context, skip manual init reads. Process only interactive flags. Fallback: if marker absent, execute current init sequence.

**What stays manual:**
- Temporal availability check (requires `ariadne_overview` MCP call)
- Deep scan dispatch (requires Agent tool)
- Audit-pending user prompt (interactive)
- Checkpointed task redirect (interactive)

### Chunk 2: Pre-planning Instruction Assembly (D-200)

**New files:**
- `src/global/lib/preflight-assemble.sh` — `moira_preflight_assemble_apollo()` and `moira_preflight_assemble_exploration()`

**Modified files:**
- `src/global/hooks/task-submit.sh` — call Apollo assembly after preflight
- `src/global/skills/orchestrator.md` — note post-classification assembly trigger
- `src/global/skills/dispatch.md` — document unified instruction file path for all agents

**What changes:**
1. `moira_preflight_assemble_apollo()`:
   - Calls `moira_rules_assemble_instruction()` with Apollo role, task input, no prior artifacts
   - Writes to `.moira/state/tasks/{task_id}/instructions/apollo.md`
   - Called by `task-submit.sh` after preflight

2. `moira_preflight_assemble_exploration()`:
   - Called by orchestrator after classification gate (orchestrator Writes a trigger marker, or calls inline)
   - Actually: orchestrator cannot call Bash. So this is triggered by `pipeline-dispatch.sh` hook when dispatching Hermes:
     - Hook detects role=explorer, checks if `instructions/hermes.md` exists
     - If not: calls `moira_rules_assemble_instruction()` for Hermes with classification.md as context
     - Writes instruction file
     - Same for Athena if dispatched in parallel
   - Instruction file available before agent starts (PreToolUse fires before dispatch)

3. Dispatch path in `dispatch.md`: check `instructions/{agent}.md` → if exists, 1 Read → if not, simplified assembly (fallback). Already documented for post-planning agents; extend to all.

### Chunk 3: Gate Data Collection + Input Pre-classification (D-201)

**New files:**
- `src/global/lib/markdown-utils.sh` — `moira_md_extract_section()` utility
- `src/global/hooks/gate-context.sh` — UserPromptSubmit hook for gate context

**Modified files:**
- `src/global/hooks/task-submit.sh` — NO (gate-context.sh is separate hook on same event)
- `src/global/skills/orchestrator.md` — add gate fast path with fallback
- `src/global/skills/gates.md` — document gate data injection contract
- `.claude/settings.json` (via install.sh) — register gate-context.sh

**What changes:**
1. `moira_md_extract_section()` in `markdown-utils.sh`:
   - Arguments: `<file> <section_heading>`
   - Returns text from `## Section` to next `## ` or EOF
   - Handles: nested `###`, empty sections, sections at EOF, missing sections (exit 1)
   - Portable: no bashisms (POSIX sed/awk)

2. `gate-context.sh` (UserPromptSubmit hook):
   - Checks `current.yaml → gate_pending` — if null/empty, exit 0
   - Reads gate type from `gate_pending` value
   - Collects gate data:
     - Artifact sections via `moira_md_extract_section()` (per gate type mapping)
     - Health metrics from current.yaml, status.yaml, violations.log
     - Progress from pipeline definition step count
   - Pre-classifies user input:
     - Numeric → `menu_selection:{N}` (if within option count)
     - Keyword exact match → `menu_selection:{keyword}`
     - "clear feedback" → `clear_feedback`
     - Ends with `?` → `question`
     - Else → `needs_llm`
   - Injects `GATE_DATA:` and `INPUT_CLASS:` via `additionalContext`

3. `orchestrator.md` Section 2 gate loop: if `GATE_DATA:` present, use injected data for rendering. If `INPUT_CLASS:` is `menu_selection` or `clear_feedback`, skip LLM classification. Fallback: if markers absent, read files and classify manually.

### Chunk 4: Settings, Install, Orchestrator Updates

**Modified files:**
- `.claude/settings.json` — register `gate-context.sh` in UserPromptSubmit
- `src/install.sh` — copy new files
- `src/global/skills/orchestrator.md` — consolidated updates from chunks 1-3
- `src/global/skills/dispatch.md` — unified instruction file documentation

### Chunk 5: Tests

**New/modified test files:**
- `src/tests/tier1/test-preflight.sh` — preflight collection, all field paths
- `src/tests/tier1/test-markdown-utils.sh` — section extraction edge cases
- `src/tests/tier1/test-gate-context.sh` — gate data collection, input classification
- `src/tests/tier1/test-instruction-assembly.sh` — Apollo/Hermes pre-assembly
- Modified: `src/tests/tier1/test-hooks-system.sh` — structural tests for new hooks

**Test patterns:**
- Preflight: mock config.yaml/current.yaml with known values, verify output matches
- Markdown extraction: test files with nested sections, empty sections, missing sections, Unicode
- Gate input: test all classification categories with edge cases
- Instruction assembly: verify file created, contains required sections, size within limits
- zsh compatibility: all new scripts tested with `zsh -n` syntax check

---

## Dependency Graph

```
Chunk 1 (Preflight)
    │
    ├──► Chunk 2 (Instruction Assembly) — needs preflight for graph_available
    │
    │    Chunk 3 (Gate Context) — independent of 1 and 2
    │        │
    ▼        ▼
Chunk 4 (Settings + Orchestrator Updates) — needs 1, 2, 3
    │
    ▼
Chunk 5 (Tests) — needs 1, 2, 3, 4
```

Chunks 1 and 3 can be implemented in parallel.

---

## Token Savings Estimate

| Layer | Reads eliminated | Tokens saved | Per pipeline |
|-------|-----------------|-------------|-------------|
| Preflight (D-199) | ~10 | ~2000 | 1x |
| Instruction assembly (D-200) | ~15-20 | ~3000-4000 | 1x |
| Gate context (D-201) | ~20 | ~4000-5000 | per gate × 3-5 |
| **Total** | **~45-50** | **~9000-11000** | ~40-50% of orchestrator context |

Combined with Phase 16 savings (~12k tokens on writes), total pipeline overhead reduction: **~20-23k tokens** (~60-70% of original orchestrator overhead).

---

## Risk Analysis

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Hook failure → missing context | Low | Every layer has explicit fallback to current behavior |
| Markdown extraction edge case | Medium | Dedicated test file with adversarial inputs; function returns exit 1 on failure |
| Pre-assembled instruction stale | Low | Instruction files are per-task (not cached); regenerated each pipeline |
| Gate data race (hook reads while agent writes) | Low | Gate data collected after agent done (gate_pending set only after agent completes) |
| zsh incompatibility | Medium | All scripts POSIX-compatible; `zsh -n` syntax check in tests; no bashisms |
| Hook ordering (gate-context.sh vs task-submit.sh on same event) | Low | gate-context.sh checks gate_pending; task-submit.sh checks /moira:task pattern; no overlap |

### Constitutional Impact

- **Art 1.1 (orchestrator boundaries):** NOT affected — hooks run in shell, orchestrator still doesn't use Bash
- **Art 2.2 (mandatory steps):** NOT affected — pipeline steps unchanged, only data collection method changes
- **Art 3.1 (audit trail):** NOT affected — state recording unchanged (Phase 16 hooks)
- **Art 4.2 (user authority):** NOT affected — gates still require user decision

---

## Success Criteria

1. All existing tier1 tests pass
2. New tier1 tests pass (preflight, markdown-utils, gate-context, instruction-assembly)
3. All scripts pass `zsh -n` syntax check
4. Standard pipeline completes with ~9k fewer Read-related tokens (measured via budget report)
5. Orchestrator performs ≤8 Read operations for init + pre-planning dispatch (down from ~30)
6. Gate rendering works with injected data (no manual reads when hook succeeds)
7. Gate input pre-classification correctly handles: numbers, keywords, questions, free text
8. Fallback paths work: disable hooks → orchestrator completes pipeline using current behavior
9. No new zsh-incompatible constructs (`bash -n` AND `zsh -n` pass for all new files)
