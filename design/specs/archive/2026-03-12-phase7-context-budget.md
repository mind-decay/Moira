# Phase 7: Context Budget Tracking

> **Note:** This spec was written pre-D-064. Display templates referencing "200k" orchestrator capacity are historical — actual capacity is now 1M tokens per D-064. Living design docs and implementation reflect the updated value.

## Goal

Full context budget lifecycle: estimation before execution, tracking during execution, reporting after completion, and overflow handling with automatic recovery. This phase makes budget management a STRUCTURAL property of the pipeline — not advisory guidance, but enforced limits with deterministic overflow handling.

After Phase 7: every agent dispatch includes a pre-launch budget estimate. Every agent completion records actual usage. The Planner auto-splits steps that exceed budget. Mid-execution overflows trigger partial save + continuation. Every pipeline completion displays a full budget report. MCP calls are budgeted and tracked. The orchestrator monitors its own context health with threshold-based alerts.

## Risk Classification

**YELLOW** — Threshold adjustments to existing config fields, new library functions, updates to existing orchestrator flow. No pipeline gate changes. No agent role boundary changes. Needs regression check + impact analysis.

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | Art 3.2 (budget visibility — budget report MUST be generated, CANNOT be disabled or hidden), Art 3.3 (error transparency — budget overflows reported to user), Art 1.1 (orchestrator purity — budget tracking must not cause orchestrator to read project files), Art 2.1 (pipeline determinism — overflow handling follows deterministic rules), Art 2.3 (no implicit decisions — budget splits follow explicit thresholds) |
| `design/subsystems/context-budget.md` | Complete budget subsystem design: capacity model, per-agent allocations, estimation approach, budget report format, orchestrator thresholds, MCP impact, overflow handling |
| `design/subsystems/fault-tolerance.md` | E4-BUDGET error type: pre-execution (Planner auto-splits), mid-execution (save partial, spawn continuation agent), escalation (double overflow → user) |
| `design/subsystems/self-monitoring.md` | Orchestrator context monitoring: thresholds (healthy/monitor/warning/critical), warning display format, health report section |
| `design/architecture/pipelines.md` | Smart batching: file dependency graph → budget check per cluster → auto-split. Pipeline error handling table: budget exceeded pre/mid-exec. Budget report at pipeline completion. |
| `design/architecture/agents.md` | Agent response contract: `budget_exceeded` status, COMPLETED/REMAINING fields |
| `design/subsystems/mcp.md` | MCP budget impact: per-call token estimation, Planner includes MCP in budget calculations, Reviewer checks MCP necessity |
| `design/architecture/overview.md` | File structure: `config/budgets.yaml` location, orchestrator boundaries |
| `design/decisions/log.md` | D-001 (orchestrator never executes), D-002 (file-based communication), D-008 (smart batching with contracts), D-015 (foreground sequential, background parallel), D-040 (Daedalus writes instruction files) |

## Prerequisites (from Phase 1-6)

- **Phase 1:** State management (state.sh, yaml-utils.sh), all YAML schemas (including `current.schema.yaml` with `context_budget.*` fields, `status.schema.yaml` with `budget.*` fields, `config.schema.yaml` with `budgets.*` fields)
- **Phase 2:** All 10 agent role definitions with `budget` field in `_meta`, response contract with `budget_exceeded` status
- **Phase 3:** Orchestrator skill with Section 6 (Budget Monitoring) stub, gates.md with budget report template, errors.md with E4-BUDGET handling, `moira_state_agent_done()` in state.sh (already records tokens)
- **Phase 4:** Rules assembly (rules.sh), Planner instruction file system (D-040)
- **Phase 5:** Bootstrap engine, config.yaml with budgets section
- **Phase 6:** Quality system (quality.sh), findings system, QUALITY line in response contract, bench infrastructure

## Existing Budget Infrastructure Audit

Before defining deliverables, here is what already exists from previous phases:

### Already Implemented (no changes needed)
1. **Config schema** (`config.schema.yaml`): `budgets.orchestrator_max_percent`, `budgets.agent_max_load_percent`, `budgets.per_agent.*` for all 10 agents — already defined with correct defaults
2. **Current state schema** (`current.schema.yaml`): `context_budget.orchestrator_tokens_used`, `context_budget.orchestrator_percent`, `context_budget.total_agent_tokens`, `context_budget.warning_level`
3. **Status schema** (`status.schema.yaml`): `budget.estimated_tokens`, `budget.actual_tokens`, `budget.by_agent` (block)
4. **Agent role definitions**: each has `budget: N` in `_meta` section
5. **State tracking** (`state.sh`): `moira_state_agent_done()` records per-agent tokens and updates `context_budget.total_agent_tokens`
6. **Orchestrator skill** (`orchestrator.md` Section 6): budget monitoring thresholds, warning display template, budget report at completion
7. **Gates template** (`gates.md`): budget report table format, per-agent threshold emojis
8. **Error handling** (`errors.md`): E4-BUDGET pre-execution and mid-execution recovery flows
9. **Pipeline definitions**: all 4 pipelines have `E4-BUDGET` in `error_handlers` with `auto_split` and `save_partial` actions, `budget_report: true` in `post`
10. **Dispatch skill** (`dispatch.md`): `budget_exceeded` status in response parsing
11. **Telemetry schema** (`telemetry.schema.yaml`): `execution.budget_total_tokens`, per-agent `context_pct`

### Not Yet Implemented (Phase 7 scope)
1. **Budget library** (`budget.sh`): No dedicated budget library exists — estimation, tracking, reporting, and overflow handling functions
2. **Budgets configuration file** (`config/budgets.yaml`): The project-level file referenced in `overview.md` does not exist as a template
3. **Pre-execution estimation**: Planner role definition mentions budget estimation, but no estimation functions exist
4. **Post-execution tracking**: `moira_state_agent_done()` records raw tokens but no percentage calculation, threshold checks, or budget comparison
5. **Budget report generation**: Template exists in `gates.md` but no function generates the actual report from state data
6. **Overflow detection**: E4-BUDGET flows defined in errors.md but no detection functions
7. **MCP budget integration**: No MCP token estimation or tracking
8. **Orchestrator context monitoring**: Thresholds defined in orchestrator.md but no measurement or alerting functions
9. **Budget data in Planner instructions**: Daedalus mentions budget estimation in capabilities but has no concrete budget data to work with
10. **Token counting utilities**: No token estimation functions (character-based approximation)

## Deliverables

### D1: Budget Library (`src/global/lib/budget.sh`)

Core budget management functions. This is the primary deliverable — the engine that makes budget a structural system property.

#### `moira_budget_estimate_tokens <file_path>`
Estimate token count for a file.

- Read file size in bytes
- Apply ratio: ~1 token per 4 characters (industry-standard approximation for English/code)
- Return estimated token count
- If file doesn't exist → return 0 with warning to stderr

#### `moira_budget_estimate_batch <file_list>`
Estimate total tokens for a list of files.

- `file_list` is newline-separated file paths
- Sum `moira_budget_estimate_tokens` for each file
- Return total estimated tokens

#### `moira_budget_estimate_agent <agent_role> <file_list> <knowledge_tokens> <instruction_tokens>`
Estimate total context usage for an agent invocation.

- `agent_role`: one of the 10 agent roles
- `file_list`: files the agent will read (newline-separated)
- `knowledge_tokens`: estimated tokens from knowledge docs loaded
- `instruction_tokens`: estimated tokens from assembled instructions
- Calculation:
  - `working_data = moira_budget_estimate_batch(file_list)`
  - `total = working_data + knowledge_tokens + instruction_tokens`
  - Look up agent budget from config: `budgets.per_agent.{role}` (via `config.yaml`, fallback to schema defaults)
  - `percentage = (total * 100) / agent_budget`
- Output (structured, one field per line):
  ```
  working_data: {N}
  knowledge: {N}
  instructions: {N}
  total: {N}
  budget: {agent_budget}
  percentage: {pct}
  status: {ok|warning|exceeded}
  ```
- Status thresholds (from context-budget.md):
  - `ok`: < 50%
  - `warning`: 50-70%
  - `exceeded`: > 70% (over safety margin)

#### `moira_budget_check_overflow <agent_role> <estimated_tokens> [config_path]`
Check if estimated tokens exceed agent budget.

- Read agent budget from config (with fallback to schema defaults)
- Read `budgets.agent_max_load_percent` from config (default: 70)
- Calculate: `max_allowed = agent_budget * max_load_percent / 100`
- If `estimated_tokens > max_allowed` → echo "exceeded" and return 1
- If `estimated_tokens > agent_budget * 50 / 100` → echo "warning" and return 0
- Else → echo "ok" and return 0

#### `moira_budget_record_agent <task_id> <agent_role> <estimated_tokens> <actual_tokens> [state_dir]`
Record budget data after agent completion.

- Append to `status.yaml` `budget.by_agent` block:
  ```yaml
  - role: {agent_role}
    estimated: {estimated_tokens}
    actual: {actual_tokens}
    budget: {agent_budget}
    percentage: {actual * 100 / budget}
  ```
- Update `status.yaml` cumulative fields:
  - `budget.estimated_tokens += estimated_tokens`
  - `budget.actual_tokens += actual_tokens`
- This function is called FROM the orchestrator via state management, complementing `moira_state_agent_done()`

#### `moira_budget_orchestrator_check [state_dir]`
Check orchestrator context health.

- We cannot precisely measure orchestrator token usage at runtime
- Proxy approach: count conversation turns × average tokens per turn
  - Read `context_budget.total_agent_tokens` from `current.yaml` (agent return summaries added to orchestrator context)
  - Read `history` block entry count from `current.yaml` (each entry ≈ orchestrator processing)
  - Estimate: `orchestrator_tokens ≈ base_overhead + (history_count × avg_per_step) + gate_interactions`
  - `base_overhead = 15000` (orchestrator skill + pipeline definition + state files)
  - `avg_per_step = 500` (agent summary parsing + state update)
  - `gate_interactions = gate_count × 2000` (gate presentation + user response processing)
- Calculate percentage: `orchestrator_tokens / 200000 * 100`
- Output:
  ```
  estimated_tokens: {N}
  percentage: {pct}
  level: {healthy|monitor|warning|critical}
  ```
- Thresholds (from context-budget.md / self-monitoring.md):
  - `healthy`: < 25%
  - `monitor`: 25-40%
  - `warning`: 40-60%
  - `critical`: > 60%
- Update `current.yaml`:
  - `context_budget.orchestrator_tokens_used = estimated_tokens`
  - `context_budget.orchestrator_percent = percentage`
  - `context_budget.warning_level = level`

#### `moira_budget_generate_report <task_id> [state_dir]`
Generate the full budget report table for pipeline completion.

- Read `status.yaml` → `budget.by_agent` block for per-agent data
- Read `current.yaml` → `context_budget.*` for orchestrator data
- Read config → `budgets.per_agent.*` for budget limits
- Format the table per `gates.md` budget report template:
  ```
  ╔══════════════════════════════════════════════╗
  ║           CONTEXT BUDGET REPORT              ║
  ╠══════════════════════════════════════════════╣
  ║ Agent         │ Budget │ Est.  │ % │ Status  ║
  ║───────────────┼────────┼───────┼───┼─────────║
  {per-agent rows}
  ║ Orchestrator  │ 200k   │ {est} │{%}│ {emoji} ║
  ╠══════════════════════════════════════════════╣
  ║ Orchestrator context: {used}k/200k ({pct}%)  ║
  ╚══════════════════════════════════════════════╝
  ```
- Per-agent status emoji thresholds (from gates.md):
  - ✅ < 50%: healthy
  - ⚠ 50-70%: acceptable but monitor
  - 🔴 > 70%: over safety margin
- Format token values as `{N}k` (divide by 1000, round to nearest integer)
- Return the formatted report string (for orchestrator to display)

#### `moira_budget_write_telemetry <task_id> [state_dir]`
Write budget data to telemetry.yaml for the task.

- Read `status.yaml` → `budget.by_agent`
- For each agent entry, produce telemetry record with `context_pct`
- Write `execution.budget_total_tokens` to telemetry
- This complements existing telemetry fields — called during completion flow

### D2: Budget Configuration Template (`src/global/templates/budgets.yaml.tmpl`)

Project-level budget configuration template. Copied to `.claude/moira/config/budgets.yaml` during `/moira:init`.

```yaml
# Context Budget Configuration
# Per-agent allocations in tokens. Adjust based on project complexity.
# Hard rule: never load an agent beyond 70% capacity (30% safety margin).

agent_budgets:
  classifier: 20000
  explorer: 140000
  analyst: 80000
  architect: 100000
  planner: 70000
  implementer: 120000
  reviewer: 100000
  tester: 90000
  reflector: 80000
  auditor: 140000

# Maximum safe load percentage (30% safety margin = 70% max)
max_load_percent: 70

# Orchestrator context capacity (approximate)
orchestrator_capacity: 200000

# MCP call budget estimates (tokens per call, approximate)
mcp_estimates:
  context7_query: 14000
  default_call: 5000
```

**Note:** This template provides project-level overrides. The `config.schema.yaml` `budgets.per_agent.*` fields provide the fallback defaults. The project-level `budgets.yaml` is the authority when present — it allows teams to tune budgets without modifying config.yaml.

### D3: Planner Budget Integration

Update Daedalus (planner) role definition and dispatch instructions to perform concrete budget estimation for each plan step.

#### D3a: Planner Role Update (`src/global/core/rules/roles/daedalus.yaml`)

Update identity and capabilities to reference the budget estimation approach explicitly:

**New in identity:**
```
For each implementation step, you MUST include a budget estimate:
- List files the agent will read (with approximate sizes)
- List knowledge documents to be loaded (with level)
- Estimate total working data tokens
- Compare against agent budget allocation
- If estimate exceeds 70% of agent budget → auto-split into smaller batches
```

**New capability:**
```
- Estimate context budget per step using file sizes and knowledge levels
- Auto-split steps that exceed 70% agent budget threshold
```

#### D3b: Budget Section in Plan Output

Update `output_structure` in `daedalus.yaml` to require a budget section per step:

```
Your plan.md artifact MUST include these sections:
...existing sections...
6. Budget estimates per step — files to load, estimated tokens, percentage of agent budget, split decisions
```

Each plan step format:
```markdown
## Step N: {description}

AGENT: {role}
FILES TO MODIFY: {file} (~{N}k), {file} (~{N}k), ...
CONTEXT TO LOAD: {knowledge} ({level} ~{N}k), {pattern} (~{N}k)
ESTIMATED WORKING DATA: ~{N}k tokens
BUDGET: {N}k / {agent_budget}k ({pct}%) — {✅|⚠️|🔴}
{If exceeded: SPLIT: auto-splitting into Step Na and Step Nb}
```

This format matches exactly what context-budget.md specifies in "Pre-execution (by Planner)".

#### D3c: Dispatch Budget Instructions (`src/global/skills/dispatch.md`)

Add budget context to agent dispatch. When the orchestrator dispatches an agent, the dispatch instructions include:

```markdown
## Context Budget
Your budget allocation: {agent_budget}k tokens.
Maximum safe load: 70% ({max_safe}k tokens).

If you detect your context is getting large:
1. STOP immediately
2. Write partial results to your output file with clear boundary marker
3. Return: STATUS: budget_exceeded, COMPLETED: "{done items}", REMAINING: "{remaining items}"
```

This instruction is already implied by the response contract (`budget_exceeded` status) but making it explicit in dispatch reinforces the behavior.

### D4: Post-Execution Budget Tracking

Wire budget recording into the orchestrator's agent completion flow.

#### D4a: Enhanced `moira_state_agent_done()` (`src/global/lib/state.sh`)

The existing function records tokens in the history block. Enhance to also:

1. After recording history entry, call `moira_budget_record_agent` to update `status.yaml` budget data
2. After recording, call `moira_budget_orchestrator_check` to update orchestrator health
3. Return the orchestrator health level so the orchestrator can display warnings if needed

**New function signature extension:**
```bash
moira_state_agent_done <step> <status> <duration> <tokens> <summary> [state_dir]
# Enhancement: after existing logic, also:
# 1. Source budget.sh
# 2. Call moira_budget_record_agent with estimated=tokens actual=tokens
#    (estimation is approximate — we use agent-reported tokens as both estimate and actual)
# 3. Call moira_budget_orchestrator_check
# 4. Read warning_level from current.yaml
# 5. If warning_level != "healthy" → append to result output
```

#### D4b: Orchestrator Health Display in Gates

Update orchestrator skill (Section 6) to use `moira_budget_orchestrator_check` output for health display at gates. The orchestrator already has the health report template — this wires it to actual data:

```
ORCHESTRATOR HEALTH:
├─ Context: ~{tokens}k/200k ({pct}%) {emoji}
├─ Violations: {count} {emoji}
├─ Agents dispatched: {count}
├─ Gates passed: {passed}/{total}
├─ Retries: {count}
└─ Progress: step {current}/{total}
```

The budget library provides `estimated_tokens` and `percentage`. The orchestrator reads violation count from `state/violations.log` line count. Other fields come from `current.yaml` history.

### D5: Budget Report at Completion

Wire the budget report generation into the pipeline completion flow.

#### D5a: Completion Flow Update (`src/global/skills/orchestrator.md`)

In Section 7 (Completion Flow), after the final gate, the `done` action should:

1. Call `moira_budget_generate_report` (via Read of a pre-generated report, or inline generation)
2. Display the formatted budget report to the user
3. Call `moira_budget_write_telemetry` to persist budget data

This is already specified in orchestrator.md ("Display full budget report") — Phase 7 provides the actual generation function.

#### D5b: Plan Gate Budget Preview

In the plan gate display, include the Planner's total budget estimate:

```
═══════════════════════════════════════════
 GATE: Plan Approval
═══════════════════════════════════════════

 Summary: {plan summary}

 Key points:
 • {N} implementation steps across {M} batches
 • Estimated total budget: ~{N}k tokens
 • {parallel_count} steps can run in parallel
 • Budget risk: {none|{N} steps near limit}

 ...
═══════════════════════════════════════════
```

The budget estimate comes from the plan artifact itself (Planner writes it per D3b).

### D6: Overflow Detection and Recovery Functions

Implement the E4-BUDGET detection and recovery mechanisms as concrete functions.

#### D6a: Pre-Execution Overflow Detection

The Planner (Daedalus) handles pre-execution overflow as part of plan creation (D3). When a step's estimated budget exceeds 70%:

1. Planner identifies the overflow in the plan
2. Planner auto-splits into sub-steps with independent file sets
3. Planner includes dependency information between sub-steps
4. The split is logged in `plan.md` with reasoning

No new library function needed — this is Planner behavior specified in D3b. The `moira_budget_check_overflow` function (D1) provides the check.

#### D6b: Mid-Execution Overflow Recovery (`src/global/lib/budget.sh`)

#### `moira_budget_handle_overflow <task_id> <agent_role> <completed> <remaining> [state_dir]`

Called by the orchestrator when an agent returns `STATUS: budget_exceeded`.

1. Parse `COMPLETED` and `REMAINING` from agent response
2. Log overflow in `status.yaml`:
   ```yaml
   retries:
     budget_splits: {increment}
   ```
3. Record partial result in budget tracking
4. Return structured data for orchestrator to spawn continuation agent:
   ```
   action: spawn_continuation
   agent: {role}
   completed: {completed items}
   remaining: {remaining items}
   partial_result_path: state/tasks/{id}/{artifact}
   ```

The orchestrator then spawns a new agent with:
- Task-specific instruction: "Continue work. Previously completed: {completed}. Your task: {remaining}."
- Reference to partial result file
- Same budget allocation as original agent

#### D6c: Double Overflow Escalation

If the continuation agent ALSO returns `budget_exceeded`:
1. `moira_budget_handle_overflow` detects this is a second overflow (check `retries.budget_splits >= 2`)
2. Returns `action: escalate` instead of `action: spawn_continuation`
3. Orchestrator presents escalation gate to user:

```
🔴 REPEATED BUDGET OVERFLOW
Agent: {Name} ({role})

This step has overflowed twice.
Original estimate may be significantly wrong.

Completed so far: {all completed items}
Still remaining: {remaining items}

▸ split   — manually split remaining work
▸ retry   — try again with larger budget (not recommended)
▸ abort   — stop task, keep partial results
```

### D7: MCP Budget Integration

Connect MCP tool usage to the budget system.

#### D7a: MCP Estimate in Budget Calculations

Update `moira_budget_estimate_agent` (D1) to accept an optional `mcp_tokens` parameter:

```bash
moira_budget_estimate_agent <agent_role> <file_list> <knowledge_tokens> <instruction_tokens> [mcp_tokens]
```

Where `mcp_tokens` is the estimated token impact of MCP calls planned for this step. Default: 0.

The Planner estimates MCP usage per step from the `mcp_estimates` in `budgets.yaml`:
- If a step uses `context7_query` → add 14000 tokens
- If a step uses unknown MCP → add `default_call` (5000) tokens
- Multiple MCP calls → sum of estimates

#### D7b: MCP in Plan Budget Display

Planner step format extended:

```markdown
## Step N: {description}

AGENT: {role}
FILES TO MODIFY: {files}
CONTEXT TO LOAD: {knowledge}
MCP CALLS: context7:query-docs("react-datepicker") (~14k)
ESTIMATED WORKING DATA: ~{N}k tokens (including MCP)
BUDGET: {N}k / {agent_budget}k ({pct}%) — {status}
```

### D8: Tier 1 Test Additions (`src/tests/tier1/test-budget-system.sh`)

New test file for budget system structural verification.

**Budget library tests:**
- `budget.sh` exists with valid bash syntax
- Functions exist: `moira_budget_estimate_tokens`, `moira_budget_estimate_batch`, `moira_budget_estimate_agent`, `moira_budget_check_overflow`, `moira_budget_record_agent`, `moira_budget_orchestrator_check`, `moira_budget_generate_report`, `moira_budget_write_telemetry`, `moira_budget_handle_overflow`
- Each function is callable (source budget.sh, check function existence via `declare -f`)

**Budget configuration tests:**
- `budgets.yaml.tmpl` template exists with required fields (agent_budgets, max_load_percent, orchestrator_capacity, mcp_estimates)
- All 10 agent roles present in template `agent_budgets`
- `config.schema.yaml` budget fields exist and have correct defaults

**Budget integration tests:**
- Orchestrator skill references budget monitoring (Section 6)
- Orchestrator skill references budget report at completion (Section 7)
- Gates skill contains budget report template
- Errors skill contains E4-BUDGET handling
- Dispatch skill contains budget context section
- Planner role definition mentions budget estimation
- Response contract includes `budget_exceeded` status

**Orchestrator health tests:**
- Orchestrator skill defines all 4 health thresholds (healthy, monitor, warning, critical)
- Self-monitoring orchestrator thresholds match context-budget.md values (<25%, 25-40%, 40-60%, >60%)

**Extended existing tests:**
- `test-file-structure.sh`: add checks for `budget.sh`, `budgets.yaml.tmpl`
- `test-install.sh`: add verification for Phase 7 artifacts

### D9: Updated `install.sh`

Add Phase 7 artifacts to installation:

**New copy operations:**
- `global/lib/budget.sh` → `$MOIRA_HOME/lib/budget.sh`
- `global/templates/budgets.yaml.tmpl` → `$MOIRA_HOME/templates/budgets.yaml.tmpl`

**New verification checks:**
- `budget.sh` exists and has valid syntax
- `budgets.yaml.tmpl` exists and has required fields

### D10: Updated `run-all.sh`

Add `test-budget-system.sh` to the test runner.

### D11: Scaffold Integration (`src/global/lib/scaffold.sh`)

Update the scaffold process to copy `budgets.yaml.tmpl` to `.claude/moira/config/budgets.yaml` if it doesn't already exist. This makes budget configuration available immediately after init.

**Function to update:** `moira_scaffold_project()` in `scaffold.sh` (bootstrap.sh delegates all scaffolding here)

- Copy `$MOIRA_HOME/templates/budgets.yaml.tmpl` → `$base/config/budgets.yaml`
- Do NOT overwrite if file already exists (preserves user customizations)

## Non-Deliverables (explicitly deferred)

- **Token-based bench budget guards** (Phase 7 scope note from Phase 6): The bench infrastructure uses test count limits (Phase 6). Adding token-based limits would require running the bench through the actual pipeline, which is already covered by the bench runner. Phase 7 provides the budget functions that bench could use, but wiring them into the bench runner is not in scope — bench already has count-based guards.
- **Real-time token counting** (not feasible): We cannot precisely measure runtime token usage in Claude Code. All estimates are approximations based on file sizes and conversation structure. This is a known limitation documented in context-budget.md.
- **Budget-based pipeline selection** (not designed): The system does not select pipelines based on budget. Pipeline selection is purely based on task classification (Art 2.1). Budget only affects step splitting within a pipeline.
- **Budget alerts via hooks** (`budget-track.sh` in Phase 8): The PostToolUse hook for real-time budget tracking is Phase 8. Phase 7 provides the estimation and reporting functions; Phase 8 wires them into hooks.
- **Budget trend analysis** (Phase 11): Metrics aggregation and trend analysis across tasks is Phase 11 (Metrics & Audit).
- **Adaptive budget allocation** (not designed): Budget allocations are static per config. Adaptive allocation based on historical data is not in the current design.

## Architectural Decisions

### AD-1: Separate Budget Library (Not Inline in State)

Budget functions live in `budget.sh`, separate from `state.sh`. While `state.sh` has `moira_state_agent_done()` which records tokens, the budget-specific logic (estimation, overflow detection, reporting) is complex enough to warrant its own module.

**Rationale:**
1. Single responsibility: `state.sh` handles state transitions, `budget.sh` handles budget logic
2. Testability: budget estimation can be tested independently
3. Size: adding 9+ functions to state.sh would violate Art 1.3 (no god components)

### AD-2: Approximate Token Estimation

We use `file_size_bytes / 4` as the token estimation ratio. This is intentionally imprecise:
- Industry-standard approximation for English text and code
- Sufficient for budget DECISIONS (split/no-split) — we only need to know if usage is below 50%, near 70%, or above 70%
- Exact counts would require tokenizer access which we don't have in shell

The system is designed to work with estimates. The 30% safety margin absorbs estimation errors.

### AD-3: Budget Config as Separate File

`config/budgets.yaml` is a separate file from `config.yaml`, even though `config.schema.yaml` already has `budgets.per_agent.*` fields.

**Rationale:**
- `config.yaml` is the general project config (stack, pipelines, quality mode)
- `budgets.yaml` is specialized and may need per-project tuning by the team
- Separation allows updating budget allocations without touching the main config
- `config.schema.yaml` fields serve as FALLBACK defaults when `budgets.yaml` doesn't exist
- The budget library reads `budgets.yaml` first, falls back to `config.yaml`, then to schema defaults

### AD-4: Orchestrator Context Estimation is Proxy-Based

We cannot directly measure orchestrator token usage. Instead, we use a proxy:
- Base overhead (skill + pipeline def + state) ≈ 15k
- Per-step processing ≈ 500 tokens
- Per-gate interaction ≈ 2k tokens
- Agent return summaries add to orchestrator context

This is rough but sufficient for threshold-based decisions (healthy vs. warning vs. critical). The 25%/40%/60% thresholds have wide gaps specifically because estimation is approximate.

### AD-5: MCP Estimates are Config-Driven

MCP call token estimates come from `budgets.yaml` (`mcp_estimates` section), not from runtime measurement. This is because:
- MCP call sizes vary by query but have predictable ranges
- The Planner needs estimates BEFORE the call happens
- Projects can tune estimates based on their actual MCP usage patterns
- Default values are conservative (14k for context7, 5k for unknown)

## Success Criteria

1. **Budget library exists and passes syntax checks:** All 9 functions callable, valid bash
2. **Token estimation works:** `moira_budget_estimate_tokens` returns reasonable estimate for a known file
3. **Overflow detection works:** `moira_budget_check_overflow` correctly identifies exceeded budget
4. **Agent budget recording works:** `moira_budget_record_agent` writes to status.yaml
5. **Orchestrator health check works:** `moira_budget_orchestrator_check` returns valid level
6. **Budget report generates:** `moira_budget_generate_report` produces formatted table matching gates.md template
7. **Planner includes budgets:** Daedalus role definition requires budget estimates per step
8. **MCP estimates in budget:** Budget calculations include MCP token estimates
9. **Overflow handling works:** `moira_budget_handle_overflow` produces correct continuation data
10. **Budgets template exists:** `budgets.yaml.tmpl` installed during init
11. **Tier 1 tests pass:** All existing + new Phase 7 structural tests pass
12. **Constitutional compliance:** All 19 invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Budget tracking operates on .claude/moira/ state files ONLY.
         Budget library reads config, state, and status files — never project source.
         Token estimation reads file sizes via `wc -c`, not file content.
[✓] 1.2 — Budget functions do not expand agent roles.
         Planner already had "estimate context budget" in capabilities.
         Budget estimation is a tool for Planner, not a new responsibility.
[✓] 1.3 — Budget is a separate library (budget.sh), not merged into state.sh.
         Clear boundary: state.sh = transitions, budget.sh = estimation/tracking/reporting.

ARTICLE 2: Determinism
[✓] 2.1 — Overflow handling follows deterministic rules:
         >70% → auto-split (pre-exec) or spawn continuation (mid-exec).
         No heuristics, no judgment.
[✓] 2.2 — Budget system does not affect gate definitions.
         Budget report is informational display, not a gate.
         Overflow is error recovery (E4-BUDGET), not a gate decision.
[✓] 2.3 — All budget thresholds are explicit in config/design.
         No implicit "probably too big" decisions.

ARTICLE 3: Transparency
[✓] 3.1 — All budget data written to state files (status.yaml, current.yaml, telemetry.yaml).
         Budget report displayed at completion. Per-agent tracking in history.
[✓] 3.2 — Budget report generated after every pipeline completion.
         Report includes orchestrator context usage. Cannot be disabled (Art 3.2).
[✓] 3.3 — Budget overflows reported to user immediately.
         Double overflow escalates to user with full context.
         No silent budget degradation.

ARTICLE 4: Safety
[✓] 4.1 — Budget estimates are explicitly approximate. No fabricated precision.
         Token counts are labeled as estimates, not exact values.
[✓] 4.2 — Double overflow escalation requires user decision.
         Auto-split is transparent (logged in plan) but does not require gate
         because it's a technical optimization, not a decision.
[✓] 4.3 — Budget-triggered splits are reversible. Each sub-step is git-backed.
[✓] 4.4 — N/A (budget system does not interact with bypass)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — N/A (budget data is operational, not knowledge)
[✓] 5.2 — N/A (budget thresholds are design constants, not learned rules)
[✓] 5.3 — N/A (no knowledge writes from budget system)

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation
[✓] 6.3 — Tier 1 tests validate budget system artifacts
```
