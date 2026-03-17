# Formal Methods & Optimization: Mathematical Foundations for Moira

## Goal

Integrate mathematical and computer science techniques into Moira's existing subsystems to improve efficiency and reliability. This is not a new phase — it's a cross-cutting enhancement that strengthens existing subsystems with formal foundations.

After this work: pipeline integrity is provable via graph algorithms (not just grep); batch scheduling minimizes total pipeline time via Critical Path Method; context budgets adapt per-agent based on telemetry history; statistical testing uses sequential methods and proper multiple comparison correction; knowledge freshness degrades continuously instead of in discrete steps; fault tolerance retry decisions are data-driven via Markov models.

**Why now:** Phases 1-11 are complete. The system is operational and collecting telemetry. Enough data infrastructure exists to support data-driven optimization. The mathematical techniques target measurable improvements to the two core principles: efficiency (less waste, faster pipelines) and reliability (fewer false alarms, better regression detection, provable invariants).

**Roadmap position:** This work is independent of Phase 12 (Checkpoint/Resume, Multi-Developer, Epic Decomposition, Tweak/Redo). It can be implemented before, after, or in parallel with Phase 12. None of the deliverables here depend on Phase 12 features. D8 (retry optimization) references tweak/redo error paths, but only the E5/E6/E9 retry logic that already exists in Phase 3's fault tolerance — not the Phase 12 tweak/redo flows.

## Risk Classification

**ORANGE (overall)** — Modifies existing shell libraries, testing scripts, and design documents. Includes budget allocation changes (D3) and knowledge structure changes (D7), both ORANGE per CLAUDE.md. No pipeline gate changes. No agent role boundary changes. No new agent types.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: Pipeline Graph Verifier | GREEN | New Tier 1 test script, additive |
| D2: CPM Batch Scheduler | YELLOW | New function in existing library, changes Planner behavior |
| D3: Adaptive Budget Margins | ORANGE | Budget allocation change — modifies the 30% safety margin model. Requires design doc update first (D9). |
| D4: SPRT for Bench Testing | YELLOW | New functions in existing bench library |
| D5: CUSUM Change Detection | YELLOW | Modifies existing statistical model in testing |
| D6: BH Multiple Comparison Correction | GREEN | New function, additive |
| D7: Exponential Knowledge Decay | ORANGE | Knowledge structure change — replaces discrete freshness model. Requires design doc update first (D9). |
| D8: Markov Retry Optimization | YELLOW | Modifies retry decision logic |
| D9: Design Document Updates | ORANGE | Updates design docs for D3 and D7 — must be applied BEFORE implementation of those deliverables |

## Design Sources

| Deliverable | Primary Source | Supporting Sources |
|-------------|---------------|-------------------|
| D1 | `CONSTITUTION.md` (Art 2.1, 2.2) | `architecture/pipelines.md`, `subsystems/testing.md` (Tier 1) |
| D2 | `architecture/pipelines.md` (Smart Batching) | `architecture/agents.md` (Daedalus) |
| D3 | `subsystems/context-budget.md` | `subsystems/testing.md` (Live Telemetry) |
| D4-D6 | `subsystems/testing.md` (Statistical Model) | N/A |
| D7 | `subsystems/knowledge.md` (Freshness System) | `subsystems/audit.md` |
| D8 | `subsystems/fault-tolerance.md` (E5, E6, E9) | `architecture/pipelines.md` (Error Handling) |

## Deliverables

### D1: Pipeline Graph Verifier (`src/tests/tier1/test-pipeline-graph.sh`)

**What:** Tier 1 test that parses pipeline YAML definitions as directed graphs and formally verifies structural properties. Replaces heuristic grep-based gate presence checks with graph-theoretic proofs.

**Properties verified:**

1. **Reachability:** Every pipeline has exactly one START node and at least one terminal node (done/abort). Every non-terminal node has a path to at least one terminal node. Verified via BFS/DFS from each node.

2. **Gate completeness (Art 2.2):** For every path from START to any terminal node, the path passes through ALL required gate nodes for that pipeline type. Verified by enumerating all simple paths (pipeline graphs are small — <20 nodes — so enumeration is tractable) and checking each path against the required gate set.

3. **No gate bypass:** There is no path from any pre-gate state to the corresponding post-gate state that does not pass through the gate node. Verified by removing the gate node from the graph and checking if post-gate is still reachable from pre-gate. If reachable → bypass exists → FAIL.

4. **Fork/join balance:** Every parallel fork (dispatch multiple agents) has a corresponding join (synchronization point). The number of tokens entering a join equals the number of outgoing edges from the corresponding fork. Verified by matching fork/join pairs and counting edges.

5. **Error recovery reachability:** From every error state (E1-E11), there exists a path to either a recovery state or user escalation. No error state is a dead end.

**Decomposition pipeline handling:** The Decomposition pipeline has dynamic per-task gates (one gate per sub-task). The graph verifier treats the per-task loop as a cycle with a loop-exit condition (all tasks complete). Verification checks: (a) the loop body contains the required per-task gate, (b) the loop has a reachable exit to the final gate, (c) no path bypasses the per-task gate within the loop body. The architecture gate (D-085) is verified as a static gate like in other pipelines.

**Algorithm complexity:** O(V² + V×E) for all checks combined. Pipeline graphs have V < 20, E < 30 — runs in microseconds.

**Output format:** Same as existing Tier 1 tests (pass/fail with detail on failure).

**Integration:** Added to `src/tests/tier1/run-all.sh`.

### D2: CPM Batch Scheduler

**What:** Critical Path Method implementation for optimizing parallel batch execution within the Planner agent's instruction assembly. Replaces the current 3-phase heuristic (Phase 1: independent clusters → Phase 2: dependent clusters → Final: shared files) with optimal multi-phase scheduling.

**Where:** New functions added to `src/global/lib/rules.sh` (Planner instruction assembly utilities). Referenced in Daedalus role rules as the scheduling algorithm to use.

**Algorithm:**

```
Input: File dependency DAG from Planner's Step 1-2 (already computed)
Output: Optimal phase assignment minimizing total pipeline time

1. Topological sort the DAG
2. Forward pass: compute earliest_start(v) = max(earliest_finish(u)) for all predecessors u
3. Backward pass: compute latest_start(v) from terminal nodes
4. Critical path = nodes where earliest_start == latest_start (zero slack)
5. Phase assignment: nodes with same earliest_start go in same phase
6. Budget check: if any phase exceeds agent budget, split using LPT heuristic
```

**LPT (Longest Processing Time first) for budget-constrained splitting:**

```
When a phase has total estimated tokens > agent budget:
1. Sort files in phase by estimated size (descending)
2. Assign each file to the batch with smallest current total
3. Guarantee: total makespan ≤ (4/3) × optimal (for m identical parallel agents)
```

**Impact:** Current 3-phase system (independent → dependent → shared-files) can miss parallelism opportunities. Example:

```
Current:  Phase 1: {A, C}  Phase 2: {B, D}   (B depends on A, D depends on B,C)
CPM:      Phase 1: {A, C}  Phase 2: {B}  Phase 3: {D}

If B is fast and D is slow, CPM starts D as soon as possible.
More importantly, CPM correctly identifies that D cannot start
until BOTH B and C complete, while B only needs A.
```

**Integration with Planner:** Daedalus role rules (`daedalus.yaml`) reference the scheduling algorithm. The Planner agent applies CPM logic when creating batched implementation phases. The shell functions serve as canonical reference; the agent implements the logic.

**Constraints preserved:**
- Shared files (modified by multiple clusters) still go in FINAL batch (unchanged)
- Contract interfaces between batches still defined by Architect (unchanged)
- Budget per batch still checked (now uses LPT for splitting instead of arbitrary splits)

### D3: Adaptive Budget Margins

**What:** Replace the fixed 30% safety margin with per-agent adaptive margins computed from telemetry history.

**Design doc prerequisite:** `context-budget.md` currently states the 30% safety margin is "UNTOUCHABLE" and a "Hard rule." D9 MUST update `context-budget.md` BEFORE D3 implementation to change the margin model from fixed to adaptive, with user approval. The updated design doc will replace the fixed 30% hard rule with: "Safety margin is adaptive per agent type, with a minimum floor of 20% and a default of 30% during cold start." This is an ORANGE risk change (budget allocation).

**Where:** Modified functions in `src/global/lib/budget.sh`. New data section in telemetry aggregation.

**Mathematical model:**

```
For each agent type a:
  ε_a = (actual_usage - estimated_usage) / estimated_usage

  From historical telemetry (last 20 tasks with this agent type):
    μ_a = mean(ε_a)          — systematic bias
    σ_a = stddev(ε_a)        — estimation variance

  Adaptive margin:
    margin_a = max(0.20, μ_a + 2×σ_a)

    - Lower bound 20% (structural minimum — preserves meaningful safety margin)
    - Upper bound 50% (cap to prevent excessive waste)
    - Default (cold start, <5 observations): 30% (current value)
```

**Cold start behavior:** Until 5+ observations exist for an agent type, use the fixed 30% margin. Between 5 and 20 observations, use wider confidence (μ + 3σ instead of μ + 2σ). After 20+, use standard formula.

**Data source:** `telemetry.yaml` already records `context_pct` per agent. The budget library reads monthly aggregate to compute per-agent statistics.

**Telemetry extension:** Add per-agent estimation accuracy to task telemetry:

```yaml
# Added to telemetry.yaml per-agent records
budget_accuracy:
  explorer:
    estimated_pct: 42
    actual_pct: 45
    error: 0.07  # (45-42)/42
```

Planner already estimates budget. Actual is already recorded. The error ratio connects them.

**Expected improvement:** Agents with stable estimation (Explorer, Classifier) get tighter margins → 10-15% more usable context. Agents with volatile estimation (Implementer on complex tasks) get wider margins → fewer mid-execution overflows.

**Constitutional compliance:** Art 3.2 (Budget Visibility) — adaptive margins are reported in budget report with the source data (N observations, computed margin). Not hidden.

### D4: SPRT for Bench Testing

**What:** Sequential Probability Ratio Test for bench runs, allowing early termination when enough statistical evidence exists.

**Where:** New functions in `src/global/lib/bench.sh` (bench statistical analysis).

**Mathematical model:**

```
H₀: μ ≥ μ₀           (quality ≥ baseline, no regression)
H₁: μ ≤ μ₀ - δ       (quality dropped by at least δ)

δ = minimum_effect_size from testing.md (3 points for composite, 5 for sub-metric)

After each test i with score xᵢ:
  Λᵢ = Λᵢ₋₁ × L(xᵢ | H₁) / L(xᵢ | H₀)

Decision:
  Λ > A = (1-β)/α     → reject H₀ (regression confirmed), STOP
  Λ < B = β/(1-α)     → accept H₀ (no regression), STOP
  B ≤ Λ ≤ A            → continue testing

Default parameters:
  α = 0.05  (false positive rate: claiming regression when there isn't one)
  β = 0.10  (false negative rate: missing a real regression)
  A = (1-0.10)/0.05 = 18
  B = 0.10/(1-0.05) ≈ 0.105
```

**Integration with existing tiered testing:**
- SPRT applies to Tier 2 and Tier 3 bench runs only (Tier 1 is deterministic — no statistics needed)
- SPRT can terminate a bench run early → reduces cost
- Displayed to user: "Regression confirmed after 3/5 tests (SPRT early stop)" or "No regression detected after 4/5 tests (SPRT early stop)"
- User can always override: "run all tests anyway"

**Distributional assumption:** Scores are modeled as normally distributed: xᵢ ~ N(μ, σ²) where σ is estimated from `aggregate.yaml` variance data. The likelihood ratio becomes:

```
L(xᵢ | H₁) / L(xᵢ | H₀) = exp(-δ(2xᵢ - 2μ₀ + δ) / (2σ²))

where δ = minimum_effect_size, μ₀ = baseline mean, σ = baseline stddev
```

If normality is a poor fit (e.g., bimodal scores), SPRT may converge slowly. The "run all tests anyway" override ensures correctness regardless.

**Expected improvement:** 30-50% fewer bench tests needed on average to reach a conclusion, based on theoretical SPRT efficiency for normal distributions.

### D5: CUSUM Change Detection

**What:** Replace the "2 consecutive WARNs = regression" heuristic with CUSUM (Cumulative Sum) algorithm for detecting small sustained metric shifts.

**Where:** Modified statistical analysis in `src/global/lib/bench.sh`.

**Mathematical model:**

```
For each tracked metric m, maintain:
  S⁺ₙ = max(0, S⁺ₙ₋₁ + (xₙ - μ₀ - k))   — detects upward shift
  S⁻ₙ = max(0, S⁻ₙ₋₁ + (μ₀ - k - xₙ))   — detects downward shift

Parameters:
  μ₀ = baseline mean (from aggregate.yaml)
  k = δ/2 where δ = minimum_effect_size (allowable shift)
  h = decision threshold = 4σ (from existing variance data)

Alarm when S⁺ₙ > h (improvement) or S⁻ₙ > h (regression)
```

**Advantages over "2 consecutive WARNs":**
- Detects small sustained shifts (e.g., 1-point degradation over 5 runs) that individual runs would classify as NORMAL
- Mathematically guaranteed Average Run Length (ARL) — expected runs before false alarm is quantifiable
- Self-resetting: after alarm, S resets to 0

**Coexistence with existing zones:** CUSUM runs alongside the existing NORMAL/WARN/ALERT zone system. CUSUM adds a new signal: "DRIFT" — a sustained small shift that individual observations miss. The existing zone system remains for detecting large single-observation shifts.

**State persistence:** CUSUM accumulator values (S⁺, S⁻) stored in `bench/results/aggregate.yaml` alongside existing baseline statistics.

### D6: BH Multiple Comparison Correction

**What:** Benjamini-Hochberg procedure for controlling false discovery rate when evaluating multiple metrics simultaneously.

**Where:** New function in bench reporting library.

**Mathematical model:**

```
Given m metrics tested simultaneously (m = 4 for standard rubric):
  p₁ ≤ p₂ ≤ ... ≤ pₘ  (sorted p-values from statistical tests)

Find largest k such that pₖ ≤ (k/m) × α

Reject hypotheses 1..k (these are significant)
Accept hypotheses k+1..m (these are noise)

For α = 0.05, m = 4:
  p₁ compared against 0.0125
  p₂ compared against 0.025
  p₃ compared against 0.0375
  p₄ compared against 0.05
```

**Why BH over Bonferroni:** Bonferroni (divide α by m) is too conservative — with 4 metrics, each test needs p < 0.0125. BH controls False Discovery Rate (FDR) instead of Family-Wise Error Rate (FWER), giving more power while still controlling false alarms.

**Impact:** Without correction, P(≥1 false alarm) = 1 - 0.95⁴ ≈ 18.5% per bench run. With BH at α=0.05, FDR ≤ 5%.

**Integration:** Applied automatically in bench report generation when multiple metrics are evaluated. Report notes which findings survive BH correction.

### D7: Exponential Knowledge Decay

**What:** Replace the discrete 3-tier freshness system (fresh/aging/stale) with continuous exponential decay.

**Where:** Modified `src/global/lib/knowledge.sh` freshness functions. Updated freshness markers in knowledge files.

**Mathematical model:**

```
confidence(entry) = e^(-λ × tasks_since_verified)

Per-knowledge-type decay rates:
  λ_conventions = 0.02    (slow decay — conventions rarely change)
  λ_patterns = 0.05       (moderate — patterns evolve)
  λ_project_model = 0.08  (faster — project structure changes with development)
  λ_decisions = 0.01      (very slow — architectural decisions are stable)
  λ_failures = 0.03       (moderate — failure lessons remain relevant)
  λ_quality_map = 0.07    (faster — code quality evolves)

Thresholds:
  confidence > 0.7  → trusted (equivalent to "fresh")
  0.3 < confidence ≤ 0.7  → usable but verification welcome
  confidence ≤ 0.3  → needs verification before use (equivalent to "stale")
```

**Backward compatibility with existing freshness markers:**

```
Current format: <!-- moira:freshness task-078 2024-01-20 -->
New format:     <!-- moira:freshness task-078 2024-01-20 λ=0.05 -->

Parser reads both formats. Old format uses default λ for the knowledge type.
```

**Verification priority queue:** Instead of binary "stale → verify", the system can sort entries by confidence and verify lowest-confidence entries first during `/moira refresh`. This is more efficient than verifying everything past a fixed threshold.

**Audit integration:** Argus uses confidence scores instead of discrete categories. Audit finding: "12 entries below confidence 0.3, 7 between 0.3-0.5" instead of "5 stale entries."

### D8: Markov Retry Optimization

**What:** Data-driven retry decisions based on historical success probabilities per error type and agent type.

**Where:** New lookup table and decision function in `src/global/lib/state.sh` or new `src/global/lib/retry.sh`. Referenced by orchestrator error handling (errors.md).

**Mathematical model:**

```
For each (error_type, agent_type) pair, maintain from telemetry:
  p₁ = P(success on first retry)
  p₂ = P(success on second retry | first retry failed)

Cost model:
  c_retry = cost of one retry attempt (estimated agent tokens)
  c_escalate = cost of escalation to user (disruption + context switch)

Expected cost of N retries:
  E[cost | N] = Σᵢ₌₁ᴺ (cᵢ × ∏ⱼ₌₁ⁱ⁻¹(1-pⱼ)) + c_escalate × ∏ⱼ₌₁ᴺ(1-pⱼ)

Optimal N* = argmin_N E[cost | N]
```

**Default lookup table (before sufficient telemetry):**

```yaml
retry_defaults:
  E5_QUALITY:
    implementer: {max_retries: 2, p1: 0.7, p2: 0.3}  # 2 attempts total per fault-tolerance.md
    architect: {max_retries: 1, p1: 0.5}               # 1 retry only
  E6_AGENT:
    any: {max_retries: 1, p1: 0.6}                     # 1 retry per fault-tolerance.md, no p2
  E9_SEMANTIC:
    implementer: {max_retries: 2, p1: 0.5, p2: 0.3}   # 2 attempts via E5-QUALITY retry path
```

Note: `p2` is only present for error types where the design permits a second retry (E5-QUALITY with max 2 attempts, E9-SEMANTIC which follows E5 path). E6-AGENT allows only 1 retry per `fault-tolerance.md` — no `p2` field.

**Telemetry-driven updates:** After every retry outcome (success/failure), update the success probability:

```
p_new = (α × p_old) + ((1-α) × outcome)
where α = 0.8 (exponential moving average smoothing)
```

**Constitutional compliance:** Art 4.2 — retry decisions are transparent. The pipeline reports: "Retry recommended (estimated 70% success probability based on 15 historical observations)" or "Escalating to user (estimated 20% success probability — retry unlikely to help)."

**Bounds preserved:** The existing hard limits from fault-tolerance.md (max 2 attempts total for E5, max 1 retry for E6) serve as upper bounds. The Markov model can recommend FEWER retries than the max, never more.

### D9: Design Document Updates

**What:** Update relevant design documents to reflect the mathematical foundations.

**Files modified:**

| File | Change |
|------|--------|
| `subsystems/testing.md` § Statistical Model | Add SPRT, CUSUM, BH sections. Note coexistence with existing zone system. |
| `subsystems/testing.md` § Decision Rules | Update regression_confirmed to include CUSUM DRIFT signal |
| `subsystems/context-budget.md` § Budget Estimation | Replace "UNTOUCHABLE" 30% hard rule with adaptive margin model (20% floor, 30% default, data-driven). Add formula and cold start. **ORANGE — must be applied before D3 implementation.** |
| `subsystems/knowledge.md` § Freshness System | Replace discrete tiers with exponential decay model |
| `subsystems/fault-tolerance.md` § Recovery Strategies | Add Markov model reference to E5, E6 retry sections |
| `architecture/pipelines.md` § Smart Batching | Add CPM algorithm description alongside existing heuristic |

## Dependencies on Previous Phases

| Dependency | Phase | Status | What's Used |
|-----------|-------|--------|-------------|
| Pipeline YAML definitions | 3 | Done | Parsed as graphs by D1 |
| Planner dependency graph | 3 | Done | Input for CPM (D2) |
| Budget estimation | 7 | Done | Extended with adaptive margins (D3) |
| Bench testing infrastructure | 6/10 | Done | Extended with SPRT/CUSUM/BH (D4-D6) |
| Knowledge freshness markers | 4 | Done | Replaced with exponential decay (D7) |
| Fault tolerance retry logic | 3 | Done | Extended with Markov model (D8) |
| Per-task telemetry | 3 | Done | Data source for D3, D8 |
| Monthly metrics aggregation | 11 | Done | Data source for D3, D5 |

## Files Created

| File | Type | Description |
|------|------|-------------|
| `src/tests/tier1/test-pipeline-graph.sh` | Test | Graph-theoretic pipeline verification |
| `src/global/lib/retry.sh` | Shell library | Markov-based retry optimization |

## Files Modified

| File | Change | Reason |
|------|--------|--------|
| `src/global/lib/rules.sh` | Add CPM scheduling functions | D2 |
| `src/global/lib/budget.sh` | Add adaptive margin computation | D3 |
| `src/global/lib/bench.sh` | Add SPRT early termination, CUSUM accumulator, BH correction | D4-D6 |
| `src/global/lib/knowledge.sh` | Replace discrete freshness with exponential decay | D7 |
| `src/global/lib/state.sh` | Wire retry optimization into error recovery | D8 |
| `src/global/core/rules/roles/daedalus.yaml` | Reference CPM algorithm for batch scheduling | D2 |
| `src/global/skills/errors.md` | Reference Markov retry model in E5/E6 handling | D8 |
| `src/schemas/telemetry.schema.yaml` | Add budget_accuracy per-agent field | D3 |
| `src/tests/tier1/run-all.sh` | Add test-pipeline-graph.sh | D1 |
| `design/subsystems/testing.md` | SPRT, CUSUM, BH sections | D9 |
| `design/subsystems/context-budget.md` | Adaptive margin section | D9 |
| `design/subsystems/knowledge.md` | Exponential decay model | D9 |
| `design/subsystems/fault-tolerance.md` | Markov retry reference | D9 |
| `design/architecture/pipelines.md` | CPM algorithm description | D9 |
| `src/install.sh` | Add retry.sh to install manifest | D8 |
| `src/tests/tier1/test-file-structure.sh` | Add retry.sh existence check | D8 |
| `design/architecture/overview.md` | Add retry.sh to file tree | D8 |
| `src/tests/tier1/test-knowledge-system.sh` | Update freshness marker format validation for new λ= parameter | D7 |
| `src/global/templates/audit/knowledge-light.md` | Replace discrete freshness categories with confidence score thresholds | D7 |
| `src/global/templates/audit/knowledge-standard.md` | Replace discrete freshness categories with confidence score thresholds | D7 |
| `src/global/templates/audit/knowledge-deep.md` | Replace discrete freshness categories with confidence score thresholds | D7 |
| `src/global/core/xref-manifest.yaml` | Add entries for retry.sh cross-references | D8 |

## Success Criteria

1. `test-pipeline-graph.sh` formally verifies all 4 pipeline types pass reachability, gate completeness, no-bypass, fork/join balance, and error recovery reachability
2. CPM scheduling produces optimal or near-optimal phase assignments for dependency DAGs (verifiable on test graphs)
3. Adaptive margins produce tighter bounds for agents with stable estimation history (measurable: margin decreases from 30% toward 20% floor for agents with low σ)
4. SPRT terminates bench runs early when evidence is sufficient (measurable: average tests-per-run decreases)
5. CUSUM detects sustained 3-point shifts within 5 observations (theoretical ARL verifiable)
6. BH correction reduces false alarm rate from ~18.5% to ≤5% FDR
7. Exponential decay produces continuous confidence scores and correct verification priority ordering
8. Markov retry model recommends fewer retries than fixed max for low-success-probability scenarios
9. All existing Tier 1 tests continue to pass (regression check)
10. Design documents accurately reflect the new mathematical foundations

## Deferred (Tier C — Research-Grade)

The following techniques require more accumulated data and are deferred to post-v1:

1. **Bayesian rule induction** — replacing the fixed 3-observation threshold with posterior probability. Requires history of reflection outcomes.
2. **Item Response Theory for LLM-judge** — modeling task difficulty and judge ability simultaneously. Requires large corpus of judge evaluations.
3. **Information-theoretic knowledge value** — computing mutual information between knowledge entries and task outcomes. Requires outcome tracking infrastructure.
4. **ADWIN concept drift detection** — detecting when project conventions shift. Requires long observation series.
5. **Thompson Sampling for rule variants** — A/B testing rule changes. Requires controlled experimentation framework.

These are documented here for future reference but are explicitly out of scope.

## New Decision Log Entries Required

- **D-094: Formal Methods & Optimization Architectural Choices** — covers: (a) pipeline graph verification uses path enumeration (tractable for small graphs <20 nodes), Decomposition pipeline per-task gates treated as loop with verified loop-body gate; (b) CPM replaces 3-phase heuristic but preserves shared-file-last constraint; (c) adaptive margin formula uses μ + 2σ with 20% floor and 50% ceiling — requires updating context-budget.md "UNTOUCHABLE" 30% hard rule to adaptive model (ORANGE change); (d) SPRT uses α=0.05, β=0.10 as defaults, assumes normal distribution; (e) CUSUM coexists with zone system (adds DRIFT signal, does not replace WARN/ALERT); (f) BH chosen over Bonferroni for better power with controlled FDR; (g) exponential decay rates per knowledge type are initial estimates, tunable — requires updating knowledge.md freshness model (ORANGE change); (h) Markov retry model can recommend fewer retries than existing hard limits but never more, p2 only defined for error types permitting second retry; (i) deferred Tier C techniques documented for post-v1.

## Constitutional Compliance

```
ARTICLE 1: Separation of Concerns
Art 1.1 OK  All changes are in moira infrastructure, not project files.
            Pipeline graph verifier reads pipeline YAML only.
Art 1.2 OK  No agent NEVER constraints modified. Daedalus gets CPM
            as a tool, not a new responsibility.
Art 1.3 OK  Each technique maps to existing component boundaries.
            No new god components.

ARTICLE 2: Determinism
Art 2.1 OK  Pipeline selection unchanged. CPM changes execution
            order within implementation step, not pipeline selection.
Art 2.2 OK  Gate definitions unchanged. Graph verifier PROVES
            gates cannot be bypassed — strengthens Art 2.2.
Art 2.3 OK  All mathematical models are explicit formulas with
            documented parameters. No implicit decisions.

ARTICLE 3: Transparency
Art 3.1 OK  Adaptive margins reported in budget report.
            SPRT decisions reported in bench output.
            CUSUM state persisted in aggregate.yaml.
Art 3.2 OK  Budget report shows adaptive margin source data.
            D3 requires updating context-budget.md FIRST (Art 6.2)
            to change the 30% hard rule to adaptive model.
Art 3.3 OK  All statistical decisions include justification
            (p-value, confidence, probability).

ARTICLE 4: Safety
Art 4.1 OK  No fabrication — all values from formulas + data.
Art 4.2 OK  Retry optimization is advisory — user can always
            override. SPRT early stop shows "run all anyway" option.
Art 4.3 OK  No irreversible changes introduced.
Art 4.4 OK  No escape hatch interaction.

ARTICLE 5: Knowledge Integrity
Art 5.1 OK  Exponential decay is evidence-based (task count).
Art 5.2 OK  Rule change threshold unchanged. Markov model
            affects retry count, not rule evolution.
Art 5.3 OK  Knowledge consistency validation unchanged.

ARTICLE 6: Self-Protection
Art 6.1 OK  No code path modifies CONSTITUTION.md.
Art 6.2 OK  This spec written before implementation.
Art 6.3 OK  Pipeline graph verifier STRENGTHENS invariant
            verification — provable guarantees instead of grep.
```
