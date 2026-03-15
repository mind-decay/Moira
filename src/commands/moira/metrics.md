---
name: moira:metrics
description: View Moira performance metrics dashboard
argument-hint: "[details <section>|compare|export]"
allowed-tools:
  - Read
---

# Moira — Metrics

View aggregated performance metrics from completed Moira tasks.

## Setup

- **State dir:** `~/.claude/moira/` is the Moira home (referred to as `MOIRA_HOME`).  Project state is at `.claude/moira/state/` in the current project.
- **Metrics dir:** `.claude/moira/state/metrics/`
- **Monthly file:** `.claude/moira/state/metrics/monthly-{YYYY-MM}.yaml`
- **Schema:** `~/.claude/moira/schemas/metrics.schema.yaml`

## Parse Argument

The user's argument determines the subcommand:

| Argument | Action |
|----------|--------|
| _(none)_ | Show main dashboard |
| `details <section>` | Show drill-down for section (tasks/quality/accuracy/efficiency/knowledge/evolution) |
| `compare` | Show side-by-side comparison with previous period |
| `export` | Generate full markdown export |

## Execution

### 1. Read Monthly Data

Read the current month's metrics file: `.claude/moira/state/metrics/monthly-{YYYY-MM}.yaml` (use today's date for YYYY-MM).

**If the file doesn't exist:** Display "No metrics data yet. Complete tasks via /moira to start collecting metrics." and stop.

For `compare` and trend indicators: also read the previous month's file if it exists.

### 2. Main Dashboard (no argument)

Display a formatted dashboard with these 7 sections:

**TASKS**
- Total completed, breakdown by size (S/M/L/E)
- Bypassed count, aborted count

**QUALITY** (with trend indicator: ↑ improving / ↓ declining / → stable)
- First-pass acceptance: count/total (percentage)
- Tweaks, redos (count and percentage)
- Retry loops total, reviewer criticals

**ACCURACY**
- Classification correct: count/total (percentage)
- Architecture first-try, plan first-try counts

**EFFICIENCY**
- Average orchestrator context %, average implementer context %
- Checkpoints needed
- MCP calls (total, useful, cache hits)

**KNOWLEDGE**
- Patterns: total (+added this period)
- Decisions: total (+added)
- Quality map coverage %, freshness %, stale entries count

**EVOLUTION**
- Improvements proposed, applied, deferred, rejected
- Regressions count (target: 0)

**TRENDS**
- Compare current vs previous period for key metrics
- Trend threshold: a difference of 5+ to register as ↑ or ↓ (D-093a)

### 3. Drill-Down (`details <section>`)

Read the `task_records` array from the monthly file. For each task record, display a per-task line based on the section:

- **tasks**: `{task_id}: {size} ({pipeline})`
- **quality**: `{task_id}: {accepted|tweaked|redone} | retries: N | criticals: N`
- **accuracy**: `{task_id}: pipeline={type} size={size} first_pass={bool}`
- **efficiency**: `{task_id}: orchestrator={N}%`
- **knowledge**: `{task_id}: (knowledge data at aggregate level)`
- **evolution**: `{task_id}: (evolution data at aggregate level)`

### 4. Compare (`compare`)

Read current and previous month files. Display a side-by-side table:

| Metric | Previous | Current | Delta |
|--------|----------|---------|-------|
| Tasks completed | ... | ... | +/-N |
| First-pass accepted | ... | ... | +/-N |
| Tweaks | ... | ... | ... |
| ... | ... | ... | ... |

If no previous month data: show "No previous period data available for comparison."

### 5. Export (`export`)

Generate a complete markdown report with:
- Header with date and period
- Full dashboard
- All 6 drill-down sections
- Period comparison table

Display the report for the user to copy/share.
