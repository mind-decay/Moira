# Phase 7: Implementation Plan — Context Budget Tracking

## Chunk Dependency Graph

```
         ┌──────────────────┐
         │  Chunk 0:        │
         │  Housekeeping    │
         └────────┬─────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 1:        │
         │  Budget Library   │
         │  (Core Functions) │
         └────────┬─────────┘
                  │
    ┌─────────────┼──────────────┐
    │             │              │
┌───▼───┐  ┌─────▼─────┐  ┌────▼────┐
│Chunk 2│  │  Chunk 3   │  │ Chunk 4 │
│Planner│  │Orchestrator│  │ Config  │
│Budget │  │  Budget    │  │Template │
│Integr.│  │  Wiring    │  │+Bootstr.│
└───┬───┘  └─────┬─────┘  └────┬────┘
    │             │              │
    └─────────────┼──────────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 5:        │
         │  Tests + Install │
         └──────────────────┘
```

---

## Chunk 0: Pre-Implementation Housekeeping

**Dependencies:** None

### Task 0.1: Record Phase 7 architectural decisions in decision log

- [ ] **Modify** `design/decisions/log.md`
- **Key points:**
  - AD-1: Separate budget library (budget.sh) — rationale: single responsibility, testability, Art 1.3
  - AD-2: Approximate token estimation (file_size / 4) — sufficient for threshold decisions, 30% safety margin absorbs errors
  - AD-3: Budget config as separate file (budgets.yaml) — allows per-project tuning without touching config.yaml
  - AD-4: Orchestrator context estimation is proxy-based — base + per-step + per-gate approximation
  - AD-5: MCP estimates are config-driven — pre-call estimates from budgets.yaml, not runtime measurement
  - Number these as D-055 through D-059
- **Commit:** `moira(design): record Phase 7 architectural decisions D-055 through D-059`

---

## Chunk 1: Budget Library (Core Functions)

**Dependencies:** Chunk 0

### Task 1.1: Create budget library with token estimation functions

- [ ] **Create** `src/global/lib/budget.sh`
- **Source:** Spec D1 — `moira_budget_estimate_tokens`, `moira_budget_estimate_batch`, `moira_budget_estimate_agent`
- **Key points:**
  - Preamble: `#!/usr/bin/env bash`, `set -euo pipefail`, source `yaml-utils.sh` from same directory
  - `moira_budget_estimate_tokens <file_path>`:
    - Get file size: `wc -c < "$file_path"` (or 0 if file doesn't exist, with stderr warning)
    - Return `$(( file_size / 4 ))` — industry-standard approximation
  - `moira_budget_estimate_batch <file_list>`:
    - Read newline-separated file paths
    - Sum `moira_budget_estimate_tokens` per file
    - Return total
  - `moira_budget_estimate_agent <agent_role> <file_list> <knowledge_tokens> <instruction_tokens> [mcp_tokens]`:
    - `working_data = moira_budget_estimate_batch(file_list)`
    - `mcp_tokens` defaults to 0 if not provided
    - `total = working_data + knowledge_tokens + instruction_tokens + mcp_tokens`
    - Read agent budget: first try `budgets.yaml` (`agent_budgets.{role}`), fallback to `config.yaml` (`budgets.per_agent.{role}`), fallback to hardcoded defaults per schema
    - `percentage = total * 100 / agent_budget`
    - Status: `ok` (<50%), `warning` (50-70%), `exceeded` (>70%)
    - Output structured key-value pairs (one per line)
- **Commit:** `moira(budget): create budget library with token estimation functions`

### Task 1.2: Add overflow detection and agent recording functions

- [ ] **Modify** `src/global/lib/budget.sh`
- **Source:** Spec D1 — `moira_budget_check_overflow`, `moira_budget_record_agent`
- **Key points:**
  - `moira_budget_check_overflow <agent_role> <estimated_tokens> [config_path]`:
    - Read agent budget (same lookup chain as estimate_agent)
    - Read `max_load_percent` from budgets.yaml (default: 70)
    - `max_allowed = agent_budget * max_load_percent / 100`
    - Return "exceeded" (exit 1) / "warning" (exit 0) / "ok" (exit 0)
  - `moira_budget_record_agent <task_id> <agent_role> <estimated_tokens> <actual_tokens> [state_dir]`:
    - Build YAML entry for `budget.by_agent` block in status.yaml
    - Use `moira_yaml_block_append` to add entry
    - Read and increment `budget.estimated_tokens` and `budget.actual_tokens` in status.yaml
    - Look up agent budget for percentage calculation
- **Commit:** `moira(budget): add overflow detection and agent recording functions`

### Task 1.3: Add orchestrator health check and report generation

- [ ] **Modify** `src/global/lib/budget.sh`
- **Source:** Spec D1 — `moira_budget_orchestrator_check`, `moira_budget_generate_report`
- **Key points:**
  - `moira_budget_orchestrator_check [state_dir]`:
    - Read `context_budget.total_agent_tokens` from current.yaml
    - Count history entries (grep pattern or simple line count)
    - Count gates from history (entries with "awaiting_gate")
    - Calculate: `base_overhead(15000) + steps × 500 + gates × 2000`
    - Percentage against 200000
    - Level: healthy (<25%), monitor (25-40%), warning (40-60%), critical (>60%)
    - Update current.yaml fields: `orchestrator_tokens_used`, `orchestrator_percent`, `warning_level`
    - Output key-value pairs
  - `moira_budget_generate_report <task_id> [state_dir]`:
    - Read `status.yaml` → `budget.by_agent` entries
    - Read orchestrator data from `current.yaml` → `context_budget.*`
    - Read budget limits from config
    - Format the table exactly per gates.md template
    - Token values as `{N}k` (divide by 1000, round)
    - Per-agent emoji: ✅ (<50%), ⚠ (50-70%), 🔴 (>70%)
    - Return the formatted string
- **Commit:** `moira(budget): add orchestrator health check and report generation`

### Task 1.4: Add telemetry writing and overflow handling functions

- [ ] **Modify** `src/global/lib/budget.sh`
- **Source:** Spec D1 — `moira_budget_write_telemetry`, `moira_budget_handle_overflow`
- **Key points:**
  - `moira_budget_write_telemetry <task_id> [state_dir]`:
    - Read `status.yaml` → `budget.by_agent`
    - For each agent entry: extract role and percentage for telemetry format
    - Calculate total budget tokens
    - Update telemetry.yaml `execution.budget_total_tokens` field
    - Note: telemetry.yaml may already exist from completion flow — this function adds budget fields
  - `moira_budget_handle_overflow <task_id> <agent_role> <completed> <remaining> [state_dir]`:
    - Read current `retries.budget_splits` from status.yaml (default 0)
    - If `budget_splits >= 2`: output `action: escalate`, return 1
    - Else: increment `budget_splits`, output continuation data (action, agent, completed, remaining, partial_result_path)
    - The orchestrator uses this output to decide whether to spawn continuation or escalate
- **Commit:** `moira(budget): add telemetry writing and overflow handling functions`

---

## Chunk 2: Planner Budget Integration

**Dependencies:** Chunk 1 (budget library functions exist)

### Task 2.1: Update Planner (Daedalus) role definition for budget estimation

- [ ] **Modify** `src/global/core/rules/roles/daedalus.yaml`
- **Source:** Spec D3a (Planner Role Update), D3b (Budget Section in Plan Output)
- **Key points:**
  - Update `identity` section: add explicit budget estimation requirement
    - "For each implementation step, you MUST include a budget estimate"
    - "List files with approximate sizes, knowledge documents with levels"
    - "If estimate exceeds 70% of agent budget → auto-split into smaller batches"
  - Add new capability: "Estimate context budget per step using file sizes and knowledge levels"
  - Update `output_structure`: add section 6 — "Budget estimates per step"
  - Plan step format includes: FILES TO MODIFY (~Nk), CONTEXT TO LOAD (~Nk), ESTIMATED WORKING DATA, BUDGET: N/Mk (pct%) — status
  - Keep existing capabilities, never, knowledge_access, quality_checklist unchanged
- **Commit:** `moira(budget): add budget estimation requirements to Planner role`

### Task 2.2: Update dispatch instructions with budget context

- [ ] **Modify** `src/global/skills/dispatch.md`
- **Source:** Spec D3c (Dispatch Budget Instructions)
- **Key points:**
  - Add new section after existing quality checklist injection: "## Context Budget"
  - Template text: "Your budget allocation: {agent_budget}k tokens."
  - Include: "Maximum safe load: 70% ({max_safe}k tokens)."
  - Include budget_exceeded instructions: "If context is getting large: STOP, write partial results, return STATUS: budget_exceeded"
  - This reinforces the existing response contract `budget_exceeded` status
  - Pre-planning agents: budget included via simplified assembly
  - Post-planning agents: budget included via Daedalus instruction files
- **Commit:** `moira(budget): add budget context to agent dispatch instructions`

---

## Chunk 3: Orchestrator Budget Wiring

**Dependencies:** Chunk 1 (budget library functions exist)

### Task 3.1: Enhance state.sh agent_done to integrate budget recording

- [ ] **Modify** `src/global/lib/state.sh`
- **Source:** Spec D4a (Enhanced moira_state_agent_done)
- **Key points:**
  - At the end of `moira_state_agent_done()`, after updating `context_budget.total_agent_tokens`:
    - Source `budget.sh` (if not already sourced)
    - Call `moira_budget_record_agent "$task_id" "$step_name" "$tokens_used" "$tokens_used"`
      - Note: we use agent-reported tokens for both estimate and actual (approximate by nature)
      - Extract task_id from current.yaml (already read in the function)
    - Call `moira_budget_orchestrator_check "$state_dir"`
  - Existing behavior is PRESERVED — budget recording is additive
  - If budget.sh is not available (partial install), the function should still work (guard with `|| true`)
- **Commit:** `moira(budget): wire budget recording into agent completion flow`

### Task 3.2: Update orchestrator skill for concrete budget monitoring

- [ ] **Modify** `src/global/skills/orchestrator.md`
- **Source:** Spec D4b (Orchestrator Health Display), D5a (Completion Flow Update), D5b (Plan Gate Budget Preview)
- **Key points:**
  - **Section 6 (Budget Monitoring):** Add concrete instructions for the orchestrator to:
    - After each agent returns: read `context_budget.warning_level` from current.yaml
    - If level is `warning` or `critical`: display the warning template (already defined)
    - Include health data in every gate display (already templated)
  - **Section 7 (Completion Flow):** In the `done` action, add step:
    - "Read budget report: call `moira_budget_generate_report` or generate from status.yaml data"
    - "Display the full budget report table"
    - "The budget report format is defined in gates.md (Budget Report Section)"
    - Note: orchestrator cannot call bash functions directly. Instead, it reads the status.yaml budget data and formats the report inline using the gates.md template. The budget.sh function is available for hooks/scripts, but the orchestrator renders the report from file data.
  - **Plan gate:** Add instruction to include Planner's budget estimate from plan.md:
    - "Show: estimated total budget usage (from plan artifact)"
    - "Show: steps with budget risk (any step near or over 70%)"
- **Commit:** `moira(budget): wire budget monitoring and reporting into orchestrator flow`

### Task 3.3: Update gates skill for budget data sources

- [ ] **Modify** `src/global/skills/gates.md`
- **Source:** Spec D5b (Plan Gate Budget Preview)
- **Key points:**
  - Plan gate template: add budget preview fields
    - "Estimated total budget: ~{N}k tokens"
    - "Budget risk: {none | N steps near limit}"
  - Clarify in budget report section: data source is `status.yaml budget.by_agent` block + `current.yaml context_budget.*`
  - No changes to the table format itself (already correct)
- **Commit:** `moira(budget): add budget preview to plan gate template`

### Task 3.4: Update errors skill E4-BUDGET with concrete handling references

- [ ] **Modify** `src/global/skills/errors.md`
- **Source:** Spec D6b (Mid-Execution Overflow Recovery), D6c (Double Overflow Escalation)
- **Key points:**
  - E4-BUDGET section: add concrete instructions for the orchestrator
  - Pre-execution: "Planner handles auto-splitting (see Daedalus role definition)"
  - Mid-execution recovery:
    - "When agent returns STATUS: budget_exceeded with COMPLETED and REMAINING fields"
    - "Read partial result from agent's output file"
    - "Spawn new agent with: partial result as context, remaining items as task, same budget allocation"
  - Double overflow:
    - "If continuation agent also returns budget_exceeded"
    - "Present escalation gate to user with completed/remaining items"
    - Add the escalation gate template from spec D6c
  - State updates: "Increment retries.budget_splits in status.yaml"
- **Commit:** `moira(budget): add concrete E4-BUDGET handling instructions`

---

## Chunk 4: Config Template & Bootstrap Integration

**Dependencies:** Chunk 1 (budget library exists)

### Task 4.1: Create budget configuration template

- [ ] **Create** `src/global/templates/budgets.yaml.tmpl`
- **Source:** Spec D2 (Budget Configuration Template)
- **Key points:**
  - `agent_budgets:` with all 10 agents and default values (matching config.schema.yaml defaults)
  - `max_load_percent: 70`
  - `orchestrator_capacity: 200000`
  - `mcp_estimates:` section with `context7_query: 14000`, `default_call: 5000`
  - Comments explaining each section's purpose
  - Values match the context-budget.md design document
- **Commit:** `moira(budget): create budget configuration template`

### Task 4.2: Update scaffold to copy budgets template

- [ ] **Modify** `src/global/lib/scaffold.sh`
- **Source:** Spec D11 (Bootstrap Integration)
- **Key points:**
  - In `moira_scaffold_project()`, after the knowledge template copy block (line ~84):
  - Copy `$MOIRA_HOME/templates/budgets.yaml.tmpl` → `$base/config/budgets.yaml`
  - Only if `$base/config/budgets.yaml` does NOT already exist (preserve user customizations)
  - Use: `[[ -f "$base/config/budgets.yaml" ]] || cp "$moira_home/templates/budgets.yaml.tmpl" "$base/config/budgets.yaml"`
  - `config/` directory already created at line 61 — no additional mkdir needed
  - Note: bootstrap.sh delegates all scaffolding to scaffold.sh (see bootstrap.sh line 9)
- **Commit:** `moira(budget): integrate budget config into scaffold flow`

---

## Chunk 5: Tests & Install

**Dependencies:** Chunks 1-4 (all implementations complete)

### Task 5.1: Create Tier 1 budget system tests

- [ ] **Create** `src/tests/tier1/test-budget-system.sh`
- **Source:** Spec D8 (Tier 1 Test Additions)
- **Key points:**
  - Follow existing test file pattern (source test-helpers.sh, use pass/fail functions)
  - **Budget library tests:**
    - `budget.sh` exists and has valid bash syntax (`bash -n`)
    - Functions exist: source budget.sh, check each function via `declare -f`
    - All 9 functions: `moira_budget_estimate_tokens`, `moira_budget_estimate_batch`, `moira_budget_estimate_agent`, `moira_budget_check_overflow`, `moira_budget_record_agent`, `moira_budget_orchestrator_check`, `moira_budget_generate_report`, `moira_budget_write_telemetry`, `moira_budget_handle_overflow`
  - **Budget config tests:**
    - `budgets.yaml.tmpl` exists in templates/
    - Template contains `agent_budgets:`, `max_load_percent:`, `orchestrator_capacity:`, `mcp_estimates:`
    - All 10 agent roles present in template
  - **Integration tests:**
    - orchestrator.md mentions "budget" in Sections 6 and 7
    - gates.md contains budget report template
    - errors.md contains E4-BUDGET section
    - dispatch.md contains "Context Budget" section
    - daedalus.yaml mentions budget estimation
  - **Health threshold tests:**
    - orchestrator.md defines 4 health levels (healthy, monitor, warning, critical)
    - Values match design: <25%, 25-40%, 40-60%, >60%
- **Commit:** `moira(budget): add Tier 1 budget system tests`

### Task 5.2: Update run-all.sh to include budget tests

- [ ] **Modify** `src/tests/tier1/run-all.sh`
- **Source:** Spec D10
- **Key points:**
  - Add `test-budget-system.sh` to the test list
  - Maintain alphabetical or logical order consistent with existing entries
- **Commit:** `moira(budget): add budget tests to test runner`

### Task 5.3: Update install.sh for Phase 7 artifacts

- [ ] **Modify** `src/install.sh`
- **Source:** Spec D9 (Updated install.sh)
- **Key points:**
  - In `install_global()`: add comment `# Copy budget template (Phase 7)` and copy:
    - `budgets.yaml.tmpl` → `$MOIRA_HOME/templates/budgets.yaml.tmpl`
    - Note: `budget.sh` is already copied by the existing `cp -f "$SCRIPT_DIR/global/lib/"*.sh "$MOIRA_HOME/lib/"` glob
  - In `verify()`: add verification checks:
    - `budget.sh` exists and has valid syntax (add to the lib_file loop: include `budget.sh` — check if it's already in the loop)
    - `budgets.yaml.tmpl` template exists
  - Check: `budget.sh` is likely already covered by the existing `*.sh` glob copy and the lib_file verify loop — confirm and add only if missing
- **Commit:** `moira(budget): update install and verification for Phase 7 artifacts`

### Task 5.4: Update existing test files for Phase 7

- [ ] **Modify** `src/tests/tier1/test-file-structure.sh`
- **Source:** Spec D8 (Extended existing tests)
- **Key points:**
  - Add check: `budget.sh` exists in lib/
  - Add check: `budgets.yaml.tmpl` exists in templates/
- [ ] **Verify** `src/tests/tier1/test-install.sh` — confirm Phase 7 artifacts are covered
- **Commit:** `moira(budget): extend file structure tests for Phase 7 artifacts`

---

## Summary

| Chunk | Tasks | Creates | Modifies | Depends On |
|-------|-------|---------|----------|------------|
| 0 | 1 | — | decisions/log.md | None |
| 1 | 4 | budget.sh | — | 0 |
| 2 | 2 | — | daedalus.yaml, dispatch.md | 1 |
| 3 | 4 | — | state.sh, orchestrator.md, gates.md, errors.md | 1 |
| 4 | 2 | budgets.yaml.tmpl | scaffold.sh | 1 |
| 5 | 4 | test-budget-system.sh | run-all.sh, install.sh, test-file-structure.sh | 1-4 |

**Total:** 6 chunks, 17 tasks

**Parallelism:** Chunks 2, 3, and 4 can run in parallel after Chunk 1 completes. They have no cross-dependencies.

**Risk assessment:** YELLOW — all changes are additive to existing code (new library, new template, updates to existing skills). No pipeline gates changed. No agent role boundaries changed. Primary risk is in Task 3.1 (modifying state.sh) — needs careful regression check since state.sh is used by everything.
