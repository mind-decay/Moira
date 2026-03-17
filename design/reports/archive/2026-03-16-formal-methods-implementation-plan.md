# Formal Methods & Optimization — Implementation Plan

**Spec:** `design/specs/2026-03-16-formal-methods-optimization.md`

## Dependency Graph

```
Chunk A: Design Doc Updates (D9)  ←── MUST go first (ORANGE prereqs for D3, D7)
    │
    ├── Chunk B: Pipeline Graph Verifier (D1) — independent
    ├── Chunk C: CPM Batch Scheduler (D2) — independent
    ├── Chunk D: Adaptive Budget Margins (D3) — depends on A (design doc update)
    ├── Chunk E: Statistical Testing (D4+D5+D6) — independent
    ├── Chunk F: Knowledge Decay (D7) — depends on A (design doc update)
    ├── Chunk G: Retry Optimization (D8) — independent
    │
    └── Chunk H: Integration & Regression (all) — depends on B-G
```

**Parallelizable:** B, C, E, G can run independently of each other and of A.
**Sequential:** A must complete before D and F. H must be last.

---

## Chunk A: Design Document Updates (D9 — ORANGE prereqs)

Design docs must be updated BEFORE implementing D3 and D7 per Art 6.2.

### A1. Update `context-budget.md` — adaptive margin model
- **File:** `design/subsystems/context-budget.md`
- **Source:** Spec D3 + D9
- **Change:** In § Context Capacity Model, replace "SAFETY MARGIN ~30% ← UNTOUCHABLE" with "SAFETY MARGIN adaptive (20%-50% range, 30% default)". In § Hard rule, change to: "Never load an agent beyond its adaptive capacity limit. Minimum 20% safety margin always reserved. Maximum 50% margin cap. Default 30% during cold start (<5 observations)." Add new section "§ Adaptive Margin Model" with the formula, cold start rules, and bounds (20% floor, 50% ceiling).
- **Key points:** Keep the rest of the budget doc unchanged. The formula is a REFERENCE — implementation in budget.sh.
- **Commit:** `moira(design): update context-budget to adaptive margin model`

### A2. Update `knowledge.md` — exponential decay model
- **File:** `design/subsystems/knowledge.md`
- **Source:** Spec D7 + D9
- **Change:** In § Freshness System, replace the discrete 3-tier table (Fresh/Aging/Stale with task count thresholds) with exponential decay model. Keep the freshness marker format section, add λ= parameter. Replace "Freshness categories" with confidence thresholds (>0.7 trusted, 0.3-0.7 usable, ≤0.3 needs verification). Add verification priority queue concept. Keep the rest of knowledge.md unchanged.
- **Key points:** The decay rate λ values per knowledge type are initial estimates, documented as tunable.
- **Commit:** `moira(design): update knowledge freshness to exponential decay model`

### A3. Update `testing.md` — SPRT, CUSUM, BH sections
- **File:** `design/subsystems/testing.md`
- **Source:** Spec D4-D6 + D9
- **Change:** In § Statistical Model and Decision Thresholds, add three new subsections: (1) "Sequential Testing (SPRT)" with the hypothesis formulation, likelihood ratio, and stopping rules; (2) "Cumulative Sum (CUSUM)" with the accumulator formulas, coexistence note with zone system, DRIFT signal; (3) "Multiple Comparison Correction (BH)" with the Benjamini-Hochberg procedure. In § Decision Rules, add `drift_detected` rule alongside existing `regression_confirmed`.
- **Key points:** CUSUM does NOT replace the zone system — it adds DRIFT signal for small sustained shifts. SPRT is optional — user can always "run all tests."
- **Commit:** `moira(design): add SPRT, CUSUM, BH to testing statistical model`

### A4. Update `fault-tolerance.md` — Markov retry reference
- **File:** `design/subsystems/fault-tolerance.md`
- **Source:** Spec D8 + D9
- **Change:** In § E5-QUALITY and § E6-AGENT recovery sections, add note: "Retry count may be reduced from the hard maximum by the Markov retry optimizer (see retry.sh) when historical data shows low success probability. Hard limits remain as upper bounds." Add brief model description.
- **Commit:** `moira(design): add Markov retry optimization reference to fault-tolerance`

### A5. Update `pipelines.md` — CPM algorithm
- **File:** `design/architecture/pipelines.md`
- **Source:** Spec D2 + D9
- **Change:** In § Smart Batching, after "Step 4: Execution phases", add "Step 5: CPM Optimization" with the algorithm summary (topological sort, forward/backward pass, critical path, phase assignment). Note this replaces the fixed 3-phase heuristic with optimal multi-phase scheduling. Add LPT splitting note.
- **Commit:** `moira(design): add CPM batch scheduling algorithm to pipelines`

---

## Chunk B: Pipeline Graph Verifier (D1)

### B1. Create `test-pipeline-graph.sh`
- **File:** `src/tests/tier1/test-pipeline-graph.sh`
- **Source:** Spec D1, pipeline YAMLs at `src/global/core/pipelines/*.yaml`
- **What:** New Tier 1 test script. Source test-helpers.sh. Parse each of the 4 pipeline YAMLs (quick, standard, full, decomposition) and verify 5 properties:
  1. **Reachability:** Build adjacency list from `steps` (step N → step N+1) and `gates` (after_step → next step). BFS from first step must reach `completion`. From each `error_handlers` entry that has `action: stop` or `action: escalate`, verify a path exists to user escalation or abort.
  2. **Gate completeness:** For each pipeline, get required gates from Constitution Art 2.2. Enumerate all paths from first step to completion. Each path must include all required gate IDs.
  3. **No gate bypass:** For each required gate G: remove G's `after_step` → G → next_step edges. Check if next_step is still reachable from `after_step` without G. If reachable → FAIL.
  4. **Fork/join balance:** Find steps with `mode: parallel`. Count outgoing agents. The next sequential step is the implicit join. Verify each parallel step must complete before join proceeds (structural from YAML ordering).
  5. **Error recovery:** For each error_handler entry, verify the action has a resolution path (retry → back to step, escalate → user, auto_split → continue, etc.).
- **Decomposition pipeline:** The `decomposition.yaml` has a loop structure (per-task execution). Verify: loop body contains per-task gate, loop has exit to final gate.
- **Key points:** Use `moira_yaml_get` from yaml-utils.sh for parsing. Test output format matches existing Tier 1 conventions (test_start/test_pass/test_fail/test_skip from test-helpers.sh).
- **Commit:** `moira(pipeline): add graph-theoretic pipeline verification test`

### B2. Register in run-all.sh
- **File:** `src/tests/tier1/run-all.sh`
- **Change:** Add `source "${TESTS_DIR}/test-pipeline-graph.sh"` after test-pipeline-engine.sh (same domain, logical grouping).
- **Commit:** Same as B1 (single commit).

---

## Chunk C: CPM Batch Scheduler (D2)

### C1. Add CPM functions to rules.sh
- **File:** `src/global/lib/rules.sh`
- **Source:** Spec D2
- **What:** Add new functions:
  - `moira_rules_cpm_schedule <dep_graph_yaml>` — Takes a dependency graph (nodes=file clusters, edges=dependencies). Returns optimal phase assignment as YAML. Algorithm: topological sort → forward pass (earliest_start) → backward pass (latest_start) → phase assignment (group by earliest_start) → budget check per phase → LPT split if needed.
  - `moira_rules_cpm_critical_path <dep_graph_yaml>` — Returns the critical path (nodes with zero slack). Used for informational display in plan output.
  - `moira_rules_lpt_split <phase_files> <budget_limit>` — Splits a single phase into multiple batches using LPT when total exceeds budget. Sort files by estimated size descending, assign to batch with smallest total.
- **Key points:** Functions operate on YAML input/output via yaml-utils.sh. The Planner agent calls these conceptually (agent implements the logic; shell functions are canonical reference). Shared files (in multiple clusters) are excluded from CPM and always placed in final batch.
- **Commit:** `moira(pipeline): add CPM batch scheduling functions`

### C2. Update Daedalus role rules
- **File:** `src/global/core/rules/roles/daedalus.yaml`
- **Change:** In the batch scheduling section, add reference to CPM algorithm: "Use Critical Path Method for phase assignment: compute earliest_start per cluster, group by phase level, split oversized phases via LPT. Preserve shared-file-last constraint."
- **Commit:** Same as C1 (single commit).

---

## Chunk D: Adaptive Budget Margins (D3) — depends on A1

### D1. Add adaptive margin functions to budget.sh
- **File:** `src/global/lib/budget.sh`
- **Source:** Spec D3 (after A1 updates the design doc)
- **What:** Add new functions:
  - `moira_budget_adaptive_margin <agent_type> [state_dir]` — Reads telemetry history for the agent type. Computes μ (mean estimation error) and σ (stddev). Returns margin = max(0.20, min(0.50, μ + 2σ)). Cold start: <5 obs → 0.30, 5-20 obs → max(0.20, μ + 3σ).
  - `moira_budget_estimation_error <task_id> <agent_type> [state_dir]` — Records estimation accuracy for one agent invocation. Writes to telemetry.yaml budget_accuracy section.
- **Key points:** Reads from monthly aggregate telemetry. Falls back to 30% default gracefully. Reports source data (N observations, computed margin) for Art 3.2 transparency.
- **Commit:** `moira(budget): add adaptive safety margin computation`

### D2. Update telemetry schema
- **File:** `src/schemas/telemetry.schema.yaml`
- **Change:** Add `budget_accuracy` section to per-agent records: `estimated_pct` (number), `actual_pct` (number), `error` (number).
- **Commit:** Same as D1 (single commit).

---

## Chunk E: Statistical Testing Improvements (D4+D5+D6)

### E1. Add SPRT functions to bench.sh
- **File:** `src/global/lib/bench.sh`
- **Source:** Spec D4
- **What:** Add new functions:
  - `moira_bench_sprt_init <baseline_mean> <baseline_stddev> <effect_size> [alpha] [beta]` — Initialize SPRT state. Compute decision thresholds A = (1-β)/α, B = β/(1-α). Store in local state.
  - `moira_bench_sprt_update <score>` — Update cumulative likelihood ratio Λ given new observation. Uses normal likelihood: L(x|H₁)/L(x|H₀) = exp(-δ(2x - 2μ₀ + δ)/(2σ²)). Returns decision: "continue", "reject_h0" (regression), or "accept_h0" (no regression).
  - `moira_bench_sprt_report` — Returns human-readable SPRT status for display.
- **Integration:** Called by `moira_bench_run_tier` after each test. If SPRT reaches decision → offer early stop to user ("Regression confirmed after N/M tests. Stop? [y/run-all]").
- **Commit:** `moira(metrics): add SPRT sequential testing for bench runs`

### E2. Add CUSUM functions to bench.sh
- **File:** `src/global/lib/bench.sh`
- **Source:** Spec D5
- **What:** Add new functions:
  - `moira_bench_cusum_update <metric_name> <score> [aggregate_path]` — Update CUSUM accumulators S⁺ and S⁻ for the given metric. Reads baseline (μ₀) and variance (σ) from aggregate.yaml. Parameters: k = effect_size/2, h = 4σ. Returns: "normal", "drift_up", or "drift_down".
  - `moira_bench_cusum_reset <metric_name> [aggregate_path]` — Reset accumulators after alarm (S⁺ = 0, S⁻ = 0).
  - `moira_bench_cusum_state <metric_name> [aggregate_path]` — Read current accumulator values for reporting.
- **Persistence:** S⁺, S⁻ values stored in `bench/results/aggregate.yaml` under `cusum:` section per metric.
- **Commit:** `moira(metrics): add CUSUM change point detection for bench`

### E3. Add BH correction function to bench.sh
- **File:** `src/global/lib/bench.sh`
- **Source:** Spec D6
- **What:** Add function:
  - `moira_bench_bh_correct <p_values_csv> [alpha]` — Takes comma-separated p-values (one per metric), applies Benjamini-Hochberg procedure. Returns list of metric indices that survive correction (significant after FDR control). Default α=0.05.
- **Integration:** Called by bench report generation when comparing multiple metrics simultaneously. Report annotates which findings survive BH correction.
- **Commit:** `moira(metrics): add Benjamini-Hochberg multiple comparison correction`

---

## Chunk F: Exponential Knowledge Decay (D7) — depends on A2

### F1. Replace freshness functions in knowledge.sh
- **File:** `src/global/lib/knowledge.sh`
- **Source:** Spec D7 (after A2 updates the design doc)
- **What:** Modify existing freshness functions:
  - `moira_knowledge_freshness_score <entry_path> <knowledge_type> [current_task_count]` — Compute confidence = e^(-λ × tasks_since_verified). λ determined by knowledge_type. Returns numeric score 0.0-1.0.
  - `moira_knowledge_freshness_category <score>` — Map score to human label: >0.7="trusted", 0.3-0.7="usable (verification welcome)", ≤0.3="needs-verification". Labels match spec terminology.
  - `moira_knowledge_freshness_marker_write <entry_path> <task_id> <date> <knowledge_type>` — Write freshness marker with λ parameter: `<!-- moira:freshness {task_id} {date} λ={λ} -->`.
  - `moira_knowledge_freshness_marker_read <entry_path>` — Parse freshness marker. Handle both old format (no λ) and new format (with λ). Old format defaults to λ for the knowledge type.
  - `moira_knowledge_verification_priority <knowledge_dir> [current_task_count]` — Return entries sorted by confidence score ascending (lowest confidence first = highest priority for verification).
- **Key points:** λ values per type defined as constants in knowledge.sh. Backward compatible with existing markers. The discrete labels (fresh/aging/stale) become derived from continuous scores for human readability.
- **Commit:** `moira(knowledge): replace discrete freshness with exponential decay`

### F2. Update knowledge Tier 1 test
- **File:** `src/tests/tier1/test-knowledge-system.sh`
- **Change:** Update freshness marker format validation to accept both old format and new format with λ= parameter. Add test that exponential decay function returns valid 0.0-1.0 range.
- **Commit:** Same as F1 (single commit).

### F3. Update audit knowledge templates
- **Files:**
  - `src/global/templates/audit/knowledge-light.md`
  - `src/global/templates/audit/knowledge-standard.md`
  - `src/global/templates/audit/knowledge-deep.md`
- **Change:** Replace references to discrete "fresh/aging/stale" categories with confidence score thresholds. Example: "Count entries with confidence < 0.3" instead of "Count stale entries."
- **Commit:** Same as F1 (single commit).

---

## Chunk G: Retry Optimization (D8)

### G1. Create retry.sh library
- **File:** `src/global/lib/retry.sh`
- **Source:** Spec D8
- **What:** New shell library with functions:
  - `moira_retry_should_retry <error_type> <agent_type> [state_dir]` — Consult lookup table + telemetry history. Return "yes" or "no" with probability and reasoning. Respects hard limits from fault-tolerance.md as upper bounds.
  - `moira_retry_expected_cost <error_type> <agent_type> <attempt_number> [state_dir]` — Compute expected cost of retrying vs escalating. Uses formula from spec.
  - `moira_retry_record_outcome <error_type> <agent_type> <attempt_number> <success|failure> [state_dir]` — Update EMA-smoothed success probability. α = 0.8.
  - `moira_retry_lookup_table [state_dir]` — Return current lookup table (defaults merged with telemetry-learned values).
- **Default table:** Hardcoded initial values from spec. Telemetry updates stored in `state/retry-stats.yaml`.
- **Key points:** Source yaml-utils.sh. Never recommends more retries than design doc hard limits. Returns human-readable justification for transparency (Art 3.1, 4.2).
- **Note on state.sh:** The spec lists `state.sh` as an alternative location ("in state.sh or new retry.sh"). We choose the new `retry.sh` file to keep retry logic self-contained. The spec's "Files Modified: state.sh — Wire retry optimization into error recovery" is superseded by: (a) retry.sh as standalone library, (b) errors.md wiring in G2. No changes to state.sh needed.
- **Commit:** `moira(pipeline): add Markov-based retry optimization`

### G2. Wire into error handling
- **File:** `src/global/skills/errors.md`
- **Change:** In E5-QUALITY and E6-AGENT handling sections, add: "Before retrying, consult retry optimizer: `moira_retry_should_retry {error_type} {agent_type}`. If optimizer recommends skipping retry (low success probability), present recommendation to user with probability and suggest escalation instead."
- **Commit:** Same as G1 (single commit).

### G3. Update file structure and install
- **Files:**
  - `src/install.sh` — Add retry.sh to install manifest and verify loop.
  - `src/tests/tier1/test-file-structure.sh` — Add retry.sh existence check.
  - `design/architecture/overview.md` — Add `lib/retry.sh` to the `~/.claude/moira/lib/` section of the Global Layer file tree.
  - `src/global/core/xref-manifest.yaml` — Add xref entry for retry.sh dependencies (yaml-utils.sh, state.sh, error_handlers in pipeline YAMLs).
- **Commit:** Same as G1 (single commit).

---

## Chunk H: Integration & Regression Check

### H1. Run full Tier 1 test suite
- **Action:** Run `src/tests/tier1/run-all.sh` and verify all tests pass including the new test-pipeline-graph.sh.
- **Verify:** No regressions in existing tests. New pipeline graph tests pass on all 4 pipeline types.

### H2. Verify xref-manifest consistency
- **Action:** Run `src/tests/tier1/test-xref-manifest.sh` and verify new retry.sh xref entry is valid.

### H3. Verify install
- **Action:** Run `src/install.sh` in dry-run mode (or inspect) to confirm all new files are in the manifest.

### H4. Decision log entry
- **File:** `design/decisions/log.md`
- **Change:** Add D-094 entry per spec.
- **Commit:** `moira(design): add D-094 formal methods architectural choices`

---

## Commit Sequence

```
A1: moira(design): update context-budget to adaptive margin model
A2: moira(design): update knowledge freshness to exponential decay model
A3: moira(design): add SPRT, CUSUM, BH to testing statistical model
A4: moira(design): add Markov retry optimization reference to fault-tolerance
A5: moira(design): add CPM batch scheduling algorithm to pipelines
─── design docs complete, implementation can proceed ───
B1+B2: moira(pipeline): add graph-theoretic pipeline verification test
C1+C2: moira(pipeline): add CPM batch scheduling functions
D1+D2: moira(budget): add adaptive safety margin computation
E1: moira(metrics): add SPRT sequential testing for bench runs
E2: moira(metrics): add CUSUM change point detection for bench
E3: moira(metrics): add Benjamini-Hochberg multiple comparison correction
F1+F2+F3: moira(knowledge): replace discrete freshness with exponential decay
G1+G2+G3: moira(pipeline): add Markov-based retry optimization
H4: moira(design): add D-094 formal methods architectural choices
```

**Total commits:** 14 (5 design + 8 implementation + 1 decision log)

---

## Risk Mitigations

1. **ORANGE changes (D3, D7):** Design docs updated first (Chunk A). User approves the design doc changes before implementation proceeds.
2. **Backward compatibility (D7):** New freshness parser reads both old and new marker formats. No migration needed — old markers work with default λ.
3. **Cold start (D3):** Adaptive margins gracefully fall back to 30% default with <5 observations. System behaves identically to current on day 1.
4. **Hard limit preservation (D8):** Retry optimizer respects existing max_attempts from pipeline YAMLs. Can only recommend fewer retries, never more.
5. **Statistical soundness (D4-D6):** SPRT has user override ("run all anyway"). CUSUM coexists with zones. BH is strictly more conservative than no correction.
