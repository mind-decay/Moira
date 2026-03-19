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

### 1b. Graph Health (subsection of Structural Conformance)

If `.ariadne/graph/graph.json` does not exist: skip this entire subsection (do not penalize the structural score — per D-106).

If graph exists, run checks via Bash and collect results:

```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_summary'
```

```bash
bash -c 'ariadne query cycles --format json 2>/dev/null'
```

```bash
bash -c 'ariadne query smells --format json 2>/dev/null'
```

```bash
bash -c 'ariadne query stats --format json 2>/dev/null'
```

```bash
bash -c 'ariadne query spectral --format json 2>/dev/null'
```

Parse results and evaluate each check:

1. **Graph freshness:** Run `moira_graph_is_fresh`. Pass if fresh, warning if stale.
   - Pass: "Graph exists and is current"
   - Warning: "Graph is stale (source files changed since last build)"

2. **Circular dependencies:** Count SCCs with size > 1 from cycles query.
   - Pass: "No circular dependencies"
   - Warning: "{N} circular dependencies"

3. **Bottleneck files:** Count files with centrality > 0.9 from stats (centrality field).
   - Pass: "No high-centrality bottlenecks"
   - Warning: "{N} files with centrality > 0.9 (bottlenecks)"

4. **God files:** Check smells output for type "god_file".
   - Pass: "No god files detected"
   - Warning: "{N} god file(s) detected ({file list})"

5. **Cluster sizes:** Check if any cluster has > 50 files from clusters.json.
   - Pass: "All clusters < 50 files"
   - Warning: "{N} oversized cluster(s) (> 50 files)"

6. **Unstable foundations:** Check smells output for type "unstable_foundation".
   - Pass: "No unstable foundations"
   - Warning: "{N} unstable foundation(s)"

7. **Monolith score:** Extract monolith_score from spectral query.
   - Pass (score <= 0.5): "Monolith score: {score} (healthy)"
   - Warning (score > 0.5): "Monolith score: {score} (high coupling)"

Display format:
```
Graph Health:
  {check_icon} {check_description}
  {check_icon} {check_description}
  ...
```

Where check_icon is: pass = checkmark, warning = warning symbol with details.

Include graph check pass/fail counts in the structural conformance pass/fail ratio. If graph has 7 checks and 5 pass, add 5 passes and 2 failures to the structural total.

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
