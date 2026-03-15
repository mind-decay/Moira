# Epic Reflection — Mnemosyne Instructions

This is the most comprehensive reflection level, used after decomposition pipeline (epic) task completion. It includes all deep reflection analysis PLUS cross-subtask coherence analysis.

---

{{INCLUDE: deep.md sections 1-12}}

---

## 13. Subtask Coherence Check

Analyze the decomposed subtasks for architectural consistency:
- Did all subtasks follow the same architectural patterns?
- Were shared interfaces defined consistently across subtasks?
- Did later subtasks contradict decisions made in earlier ones?
- Were cross-cutting concerns (error handling, logging, naming) consistent?

```
SUBTASK_COHERENCE:
  subtasks_analyzed: [{subtask_ids}]
  architectural_consistency: {consistent|minor_deviations|inconsistent}
  interface_consistency: {consistent|minor_deviations|inconsistent}
  decision_conflicts: [{description of any conflicts}]
  cross_cutting_consistency: {consistent|minor_deviations|inconsistent}
  overall: {coherent|mostly_coherent|fragmented}
```

## 14. Cross-Subtask Duplication Analysis

Identify patterns that were unnecessarily repeated across subtasks:
- Were similar utility functions implemented independently in multiple subtasks?
- Were the same configuration values hardcoded in multiple places?
- Could shared abstractions have reduced duplication?

```
DUPLICATION_ANALYSIS:
  duplicated_patterns: [{description, subtasks involved, consolidation opportunity}]
  shared_abstractions_missing: [{description of what could be shared}]
  severity: none | minor | significant
```

## 15. Decomposition Quality Assessment

Evaluate the Planner's decomposition effectiveness:
- Were subtask boundaries well-chosen?
- Were dependencies between subtasks correctly identified?
- Was the decomposition granularity appropriate (not too coarse, not too fine)?
- Could fewer subtasks have achieved the same result?

```
DECOMPOSITION_QUALITY:
  boundary_quality: {good|adequate|poor} — {reasoning}
  dependency_accuracy: {correct|mostly_correct|missed_dependencies}
  granularity: {appropriate|too_coarse|too_fine}
  optimal_subtask_count: {estimated number} vs actual {actual number}
  overall: {effective|adequate|needs_improvement}
```

## 16. Integration Gap Analysis

Check for gaps at subtask integration points:
- Were all integration interfaces tested?
- Are there data format mismatches between subtask outputs and consumers?
- Were error propagation paths across subtask boundaries handled?
- Are there orphaned artifacts (outputs from one subtask that nothing consumes)?

```
INTEGRATION_GAPS:
  untested_interfaces: [{interface description, risk level}]
  format_mismatches: [{source subtask, target subtask, mismatch description}]
  error_propagation_gaps: [{boundary description, gap description}]
  orphaned_artifacts: [{artifact, producing subtask, reason unused}]
  overall_integration: {solid|minor_gaps|significant_gaps}
```
