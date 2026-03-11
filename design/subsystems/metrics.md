# Metrics & Reporting

## Metrics Categories

### Task Metrics
- Total tasks completed
- Distribution by size (small/medium/large/epic)
- Bypass usage count and percentage
- Abort count and reasons

### Quality Metrics
- **First-pass acceptance rate** — % of tasks accepted without tweak/redo
- **Tweak rate** — % requiring targeted modification
- **Redo rate** — % requiring full rollback
- **Avg retry loops per task** — how many quality gate retries
- **Reviewer critical findings** — issues caught before delivery

### Accuracy Metrics
- **Classification accuracy** — was size assessment correct?
- **Architecture acceptance** — first-try approval rate
- **Plan acceptance** — first-try approval rate

### Efficiency Metrics
- **Avg orchestrator context** — at task completion (target: <25%)
- **Avg implementer context** — peak usage per task
- **Checkpoint frequency** — how often context overflow forced new session
- **MCP precision** — % of MCP calls that were actually useful
- **MCP cache hits** — savings from cached documentation

### Knowledge Metrics
- Patterns documented (total and growth rate)
- Decisions logged
- Quality map coverage (% of project)
- Knowledge freshness (% entries confirmed recent)
- Stale entries count

### Evolution Metrics
- Pattern improvements proposed
- Applied vs deferred vs rejected
- Regressions from evolution (should be 0)

## Metric Storage

```yaml
# .claude/moira/state/metrics/monthly-{YYYY-MM}.yaml

period: "2024-01"
tasks:
  total: 47
  by_size: {small: 18, medium: 21, large: 6, epic: 2}
  bypassed: 4
  aborted: 2
quality:
  first_pass_accepted: 38
  tweaks: 7
  redos: 2
  retry_loops_total: 19
  reviewer_criticals: 5
accuracy:
  classification_correct: 44
  architecture_first_try: 41
  plan_first_try: 45
efficiency:
  avg_orchestrator_context_pct: 16
  avg_implementer_context_pct: 47
  checkpoints_needed: 1
  mcp_calls: 23
  mcp_useful: 21
  mcp_cache_hits: 8
knowledge:
  patterns_total: 31
  patterns_added: 8
  decisions_total: 12
  decisions_added: 4
  quality_map_coverage_pct: 84
  freshness_pct: 91
  stale_entries: 3
```

Per-task data also stored for drill-down.

## Dashboard Display

### Main dashboard (/moira metrics)

Shows last 30 days with trend indicators:
- ↑ improving
- ↓ declining
- → stable

Sections: Tasks, Quality, Accuracy, Efficiency, Knowledge, Evolution, Trends

### Drill-down (/moira metrics details <section>)

Shows individual data points:
- Which tasks needed tweaks and why
- Which tasks triggered retries and what failed
- Per-agent budget usage distribution

### Comparison (/moira metrics compare)

Side-by-side with previous period.

### Export (/moira metrics export)

Markdown report for sharing with team.

## Metric-Driven Recommendations

Metrics feed into audit system:
- High tweak rate → analyst checklist may need update
- High retry rate → implementer rules may need strengthening
- High orchestrator context → agents returning too much data
- Low MCP precision → tighten MCP authorization rules
- Declining first-pass rate → investigate what changed

These appear as audit recommendations, not automatic changes.
