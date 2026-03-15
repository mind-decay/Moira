---
name: moira:health
description: Check Moira system health
argument-hint: "[report|details|history]"
allowed-tools:
  - Agent
  - Read
  - Bash
---

# /moira:health — System Health Check

Comprehensive health assessment combining structural conformance, result quality, and efficiency metrics.

## Usage

Parse the argument to determine subcommand:

- **No args / `report`**: Display composite health score with sub-metrics.
- **`details`**: Show per-metric breakdown with zone indicators.
- **`history`**: Show trend over last 5 periods.

## Execution

### 1. Structural Conformance (30% weight)

Run Tier 1 structural verifier:
```bash
bash ~/.claude/moira/tests/tier1/run-all.sh 2>&1
```
Parse output for pass/fail counts. Score = (pass_count / total_count) * 100.

### 2. Result Quality (50% weight)

Load live telemetry aggregate from `.claude/moira/testing/live/index.yaml` (if exists).
If judge data available (telemetry has quality scores):
- Read recent task evaluations
- Calculate average composite score across recent tasks
- Normalize using `moira_judge_normalize_score`
If no judge data: display "Quality: no data (run /moira bench first)" and exclude from composite.

### 3. Efficiency (20% weight)

Calculate from telemetry:
- Orchestrator context usage average (lower is better): score = max(0, 100 - avg_context_pct)
- Retry rate (lower is better): score = max(0, 100 - retry_rate * 50)
- Average of both sub-scores

### 4. Composite Health Score

```
Health Score = Structural * 0.30 + Quality * 0.50 + Efficiency * 0.20
```

If Quality is null (no judge data): reweight to Structural * 0.60 + Efficiency * 0.40

### 5. Display

```
Moira Health Score: {score}/100

  Structural Conformance:  {s_score}/100 (30%)  {indicator}
  Result Quality:          {q_score}/100 (50%)  {indicator}
  Efficiency:              {e_score}/100 (20%)  {indicator}

Quality breakdown:
  Requirements coverage:   {avg} avg  ({zone})
  Code correctness:        {avg} avg  ({zone})
  Architecture quality:    {avg} avg  ({zone})
  Conventions adherence:   {avg} avg  ({zone})

Top issues:
  {numbered list of top issues from recent reflections}

  details  — show per-metric breakdown
  history  — show trend over last 5 periods
```

Indicators: score >= 80 → good, 60-79 → caution, < 60 → warning

### Details Subcommand

Show per-metric breakdown including:
- Each quality criterion with score, trend arrow, zone
- Structural test results grouped by category
- Efficiency breakdown (context usage, retry rate, budget usage)

### History Subcommand

Show trend over last 5 measurement periods:
- Composite score per period
- Direction arrows (up/down/stable)
- Zone changes highlighted
