# Deep Reflection — Mnemosyne Instructions

This is an extended reflection triggered periodically (every 5 tasks) or by explicit request. It includes all standard reflection analysis PLUS cross-task pattern analysis.

---

{{INCLUDE: standard.md sections 1-8}}

---

## 9. Cross-Task Pattern Analysis

Read the last 5-10 task reflections from `state/tasks/*/reflection.md` (sorted by completion time, most recent first).

Analyze across tasks:
- **Recurring themes**: Are the same types of issues appearing repeatedly?
- **Improvement trends**: Are earlier issues being resolved in later tasks?
- **Regression patterns**: Did previously resolved issues return?
- **Agent performance trends**: Is any agent consistently underperforming?
- **Pipeline efficiency**: Are certain pipeline types more efficient than others?

For each cross-task pattern found:
```
CROSS_TASK_PATTERN: {pattern_name}
  Tasks: [{task_ids involved}]
  Trend: improving | stable | degrading
  Description: {what the pattern shows}
  Recommendation: {suggested action}
```

## 10. Knowledge Freshness Audit

Check all knowledge types for staleness using task distance:
- **fresh** (< 10 tasks): no action needed
- **aging** (10-20 tasks): flag for review
- **stale** (> 20 tasks): recommend refresh

For each knowledge type, report:
```
KNOWLEDGE_FRESHNESS:
  - type: {knowledge_type}
    status: {fresh|aging|stale|unknown}
    last_updated: {task_id}
    recommendation: {none|review|refresh}
```

## 11. Quality Trend Analysis

Compare recent task quality metrics against historical averages:
- First-pass acceptance rate (last 5 vs overall)
- Average retry count (last 5 vs overall)
- Budget efficiency (actual vs estimated, last 5 vs overall)
- Classification accuracy (last 5 vs overall)

Report:
```
QUALITY_TRENDS:
  first_pass_rate: {current}% vs {historical}% — {trend}
  avg_retries: {current} vs {historical} — {trend}
  budget_efficiency: {current}% vs {historical}% — {trend}
  classification_accuracy: {current}% vs {historical}% — {trend}
  overall_trend: improving | stable | degrading
```

## 12. Evolution Readiness Assessment

Evaluate whether any accumulated patterns are mature enough for an EVOLVE proposal:
- Are there 5+ observations supporting a systemic change?
- Has the pattern been stable (not contradicted) for 3+ tasks?
- Would the proposed change be constitutional (no Art violations)?
- Is the cooldown period clear (no recent EVOLVE proposals)?

```
EVOLUTION_READINESS:
  ready_patterns: [{pattern_key}: {observation_count} observations, {stability} stability]
  blocked_patterns: [{pattern_key}: {reason for not ready}]
  recommendation: {propose|wait|insufficient_evidence}
```
