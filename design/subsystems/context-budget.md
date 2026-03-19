# Context Budget Management

## Problem

Context is the only non-renewable resource. An agent with a full context hallucinates. We manage context like a financial budget.

## Context Capacity Model

```
┌─────────────────────────────────────────┐
│            Agent Context (~1M)           │
├─────────────────────────────────────────┤
│ System prompt + agent rules    ~5-10k   │ ← fixed
│ Task instructions              ~2-5k    │ ← fixed
│ Project context (docs, model)  ~5-20k   │ ← MANAGED
│ Working data (code, files)     ~20-80k  │ ← MANAGED
│ Agent reasoning                ~30-50k  │ ← uncontrolled
│ ─────────────────────────────────────── │
│ SAFETY MARGIN           adaptive 20-50% │ ← data-driven
└─────────────────────────────────────────┘
```

**Hard rule: Never load an agent beyond its adaptive capacity limit. Minimum 20% safety margin always reserved. Maximum 50% margin cap. Default 30% during cold start (<5 observations).**

Note: With 1M context (D-064), agent budgets remain at pre-1M allocations — they define maximum useful work, not context limits. Orchestrator has significant headroom.

### Adaptive Margin Model

The safety margin is adaptive per agent type, computed from telemetry history:

```
For each agent type a:
  ε_a = (actual_usage - estimated_usage) / estimated_usage

  From historical telemetry (last 20 tasks with this agent type):
    μ_a = mean(ε_a)          — systematic bias
    σ_a = stddev(ε_a)        — estimation variance

  Adaptive margin:
    margin_a = max(0.20, min(0.50, μ_a + 2×σ_a))

    - Lower bound 20% (structural minimum — preserves meaningful safety margin)
    - Upper bound 50% (cap to prevent excessive waste)
    - Default (cold start, <5 observations): 30% (current value)
```

**Cold start behavior:**
- <5 observations for an agent type → fixed 30% margin (identical to pre-adaptive behavior)
- 5-20 observations → wider confidence: max(0.20, μ + 3σ) instead of μ + 2σ
- 20+ observations → standard formula: max(0.20, min(0.50, μ + 2σ))

**Data source:** `telemetry.yaml` records `context_pct` per agent. Budget library reads monthly aggregate to compute per-agent estimation accuracy statistics.

**Transparency (Art 3.2):** Adaptive margins are reported in budget report with source data (N observations, computed margin). Not hidden.

**E11-TRUNCATION risk acknowledgment (D-094c):** Reducing the safety margin below the 30% cold-start default accepts increased E11-TRUNCATION risk in exchange for improved context efficiency. The adaptive model mitigates this by requiring sufficient observations before narrowing margins (cold start holds at 30%, 5-20 observations use wider confidence intervals). Operators should be aware that tighter margins mean less buffer against silent context truncation — the telemetry-based approach is the mitigation, not a guarantee.

## Budget Allocations Per Agent

```yaml
# .claude/moira/config/budgets.yaml

agent_budgets:
  classifier:
    system_prompt: 6k
    project_context: 5k       # minimal — just task + history
    working_data: 5k
    max_total: 20k

  explorer:
    system_prompt: 8k
    project_context: 10k     # project-model summary only
    working_data: 80k        # can read a LOT of code
    max_total: 140k

  analyst:
    system_prompt: 8k
    project_context: 15k     # needs domain understanding
    working_data: 30k        # requirements, not code
    max_total: 80k

  architect:
    system_prompt: 10k
    project_context: 20k     # full project model + decisions
    working_data: 40k        # exploration + requirements
    max_total: 100k

  planner:
    system_prompt: 8k
    project_context: 10k
    working_data: 30k        # architecture + file list
    max_total: 70k

  implementer:
    system_prompt: 10k
    project_context: 15k     # conventions + patterns
    working_data: 60k        # code to write/modify
    max_total: 120k

  reviewer:
    system_prompt: 10k
    project_context: 15k     # conventions + architecture
    working_data: 50k        # code to review
    max_total: 100k

  tester:
    system_prompt: 8k
    project_context: 10k
    working_data: 50k
    max_total: 90k

  reflector:
    system_prompt: 6k
    project_context: 10k
    working_data: 40k
    max_total: 80k

  auditor:
    system_prompt: 8k
    project_context: 20k
    working_data: 80k        # needs to cross-reference many files
    max_total: 140k
```

## Budget Estimation

### Pre-execution (by Planner)

Planner estimates context usage for each step:

```markdown
## Plan Step 3: Implement API handlers

AGENT: implementer
FILES TO MODIFY: src/api/users.ts (~3.2k), src/api/auth.ts (~2.8k), src/middleware/validate.ts (~1.5k)
CONTEXT TO LOAD: conventions.md (~2k), api-patterns (~1.5k)
ESTIMATED TOTAL WORKING DATA: ~11k tokens
BUDGET STATUS: ✅ well within 60k limit
```

If estimate exceeds budget → Planner splits step into sub-batches automatically.

### Post-execution (budget tracking)

**Orchestrator tool calls:** `budget-track.sh` PostToolUse hook logs `timestamp tool_name file_path file_size` for each tool call in the orchestrator session. Note: this hook fires only in the orchestrator session, not for agent tool calls (agents run as separate subprocesses — D-099).

**Agent budget tracking:** Agent self-reporting via `moira_state_agent_done` is the authoritative source for agent budget data. After each agent returns, the orchestrator calls `moira_state_agent_done` which records `tokens_used`, `context_pct`, `duration_sec` per agent. This provides the budget-relevant data that hooks cannot capture from agent subprocesses.

### Measurement Approach

We cannot precisely measure runtime token usage. We use:
1. **Pre-launch estimate**: count tokens in input files + instructions + docs
2. **Post-completion estimate**: input size + output size
3. **Proxy metric**: file count × average file size

This is approximate but sufficient for budget decisions.

**Token estimation bias note:** The `file_size_bytes / 4` ratio assumes ~4 bytes per token, which is reasonable for natural language and typical code. However, code with short identifiers or dense syntax may tokenize at 2-3 bytes per token, causing underestimation. The cold-start 30% safety margin absorbs this bias in practice; once the adaptive model accumulates sufficient observations, it self-corrects based on actual telemetry data.

## Budget Report

Displayed after every pipeline completion:

```
╔══════════════════════════════════════════════╗
║           CONTEXT BUDGET REPORT              ║
╠══════════════════════════════════════════════╣
║ Agent         │ Budget │ Est.  │ % │ Status  ║
║───────────────┼────────┼───────┼───┼─────────║
║ Classifier    │  20k   │   8k  │40%│ ✅      ║
║ Explorer      │ 140k   │  67k  │48%│ ✅      ║
║ Analyst       │  80k   │  34k  │43%│ ✅      ║
║ Architect     │ 100k   │  58k  │58%│ ⚠️      ║
║ Planner       │  70k   │  29k  │41%│ ✅      ║
║ Impl-1        │ 120k   │  45k  │38%│ ✅      ║
║ Impl-2        │ 120k   │  52k  │43%│ ✅      ║
║ Reviewer      │ 100k   │  71k  │71%│ 🔴      ║
║ Orchestrator  │ 1000k  │  80k  │ 8%│ ✅      ║
╠══════════════════════════════════════════════╣
║ Orchestrator context: 80k/1000k (8%) — CLEAN║
╚══════════════════════════════════════════════╝
```

Thresholds:
- ✅ < 50%: healthy
- ⚠️ 50-70%: acceptable but worth monitoring
- 🔴 > 70%: over safety margin, quality risk

## MCP Budget Impact

MCP calls significantly affect budget:

```
MCP call: context7:query-docs("react-datepicker") → ~14k tokens
```

Planner includes MCP estimates in budget calculations.
Reviewer checks that MCP calls were actually necessary.
Reflector tracks repeated MCP calls → recommends caching.

## Orchestrator Context Management

Orchestrator context capacity is 1M tokens (D-064). Thresholds are percentage-based:

| Threshold | ~Tokens (1M) | Action |
|-----------|-------------|--------|
| < 25% | < 250k | Healthy — normal operation |
| 25-40% | 250-400k | Monitor — report in status |
| 40-60% | 400-600k | Warning — display alert to user |
| > 60% | > 600k | Critical — recommend checkpoint + new session |

Orchestrator context is kept minimal by:
1. Agents return only status summaries (not full results)
2. Orchestrator reads only summary-level knowledge (L0-L1)
3. Large agent outputs go to files, not orchestrator context
4. Gate displays are generated from file contents, not memory

## Budget Overflow Handling

### Pre-execution (detected by Planner)
- Auto-split into smaller batches
- No gate needed (technical optimization)
- Logged in plan

### Mid-execution (detected by agent)
1. Agent STOPS
2. Writes partial result to file
3. Returns: `STATUS: budget_exceeded, COMPLETED: "A,B done", REMAINING: "C,D"`
4. Orchestrator spawns new agent for remaining work
5. New agent reads partial results as input
