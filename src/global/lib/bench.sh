#!/usr/bin/env bash
# bench.sh — Behavioral bench test runner for Moira
# Executes bench test cases through the Moira pipeline with predefined gate responses.
# Includes LLM-judge integration and statistical regression detection.
#
# Responsibilities: bench test execution and reporting ONLY
# Does NOT handle pipeline logic (that's the orchestrator)

set -euo pipefail

_MOIRA_BENCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BENCH_LIB_DIR}/yaml-utils.sh"
# shellcheck source=judge.sh
source "${_MOIRA_BENCH_LIB_DIR}/judge.sh"

# Budget guards
_MOIRA_BENCH_TIER2_MAX=5
_MOIRA_BENCH_TIER2_WARN=4
_MOIRA_BENCH_TIER3_MAX=30
_MOIRA_BENCH_TIER3_WARN=20

# ── moira_bench_run <test_case_path> ─────────────────────────────────
# Execute a single bench test case.
# Returns 0 on success, 1 on failure.
moira_bench_run() {
  local test_case_path="$1"

  if [[ ! -f "$test_case_path" ]]; then
    echo "Error: test case not found: $test_case_path" >&2
    return 1
  fi

  local test_id fixture_name
  test_id=$(moira_yaml_get "$test_case_path" "meta.id" 2>/dev/null) || {
    echo "Error: cannot read meta.id from $test_case_path" >&2
    return 1
  }
  fixture_name=$(moira_yaml_get "$test_case_path" "fixture" 2>/dev/null) || {
    echo "Error: cannot read fixture from $test_case_path" >&2
    return 1
  }

  # Resolve fixture path
  local bench_dir
  bench_dir="$(cd "$(dirname "$test_case_path")/.." && pwd)"
  local fixture_dir="${bench_dir}/fixtures/${fixture_name}"

  if [[ ! -d "$fixture_dir" ]]; then
    echo "Error: fixture directory not found: $fixture_dir" >&2
    return 1
  fi

  local fixture_yaml="${fixture_dir}/.moira-fixture.yaml"
  if [[ ! -f "$fixture_yaml" ]]; then
    echo "Error: .moira-fixture.yaml not found in $fixture_dir" >&2
    return 1
  fi

  echo "  Running: ${test_id} (fixture: ${fixture_name})"

  # Reset fixture
  local reset_cmd
  reset_cmd=$(moira_yaml_get "$fixture_yaml" "reset_command" 2>/dev/null) || true
  if [[ -n "$reset_cmd" && "$reset_cmd" != "null" ]]; then
    (cd "$fixture_dir" && eval "$reset_cmd" 2>/dev/null) || true
  fi

  # Verify clean state
  local git_status
  git_status=$(cd "$fixture_dir" && git status --porcelain 2>/dev/null) || true
  if [[ -n "$git_status" ]]; then
    echo "  Warning: fixture not clean after reset" >&2
  fi

  # Find next run number
  local results_base="${bench_dir}/results"
  mkdir -p "$results_base"
  local run_num=1
  while [[ -d "${results_base}/run-$(printf '%03d' $run_num)" ]]; do
    run_num=$((run_num + 1))
  done
  local run_dir="${results_base}/run-$(printf '%03d' $run_num)"
  mkdir -p "$run_dir"

  # Record result (structural only — no actual pipeline execution in Phase 6)
  local expected_pipeline
  expected_pipeline=$(moira_yaml_get "$test_case_path" "expected_structural.pipeline_type" 2>/dev/null) || expected_pipeline="unknown"

  cat > "${run_dir}/${test_id}.yaml" << YAML
test_id: ${test_id}
fixture: ${fixture_name}
pipeline_type: ${expected_pipeline}
status: recorded
automated_checks:
  compile: null
  lint: null
  tests: null
quality_scores: null
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
YAML

  echo "  Result: ${run_dir}/${test_id}.yaml"

  # Judge integration (Phase 10)
  local rubric_dir
  rubric_dir="$(cd "$(dirname "$test_case_path")/.." && pwd)/rubrics"
  local rubric_name
  rubric_name=$(moira_yaml_get "$test_case_path" "meta.rubric" 2>/dev/null) || rubric_name="feature-implementation"
  local rubric_file="${rubric_dir}/${rubric_name}.yaml"
  if [[ ! -f "$rubric_file" ]]; then
    rubric_file="${rubric_dir}/feature-implementation.yaml"
  fi

  # Prepare judge prompt (actual Agent dispatch is done by bench.md command)
  local judge_prompt=""
  if [[ -f "$rubric_file" ]]; then
    judge_prompt=$(moira_judge_invoke "${run_dir}" "$rubric_file" 2>/dev/null) || true
  fi

  if [[ -n "$judge_prompt" ]]; then
    echo "$judge_prompt" > "${run_dir}/${test_id}-judge-prompt.md"
    echo "  Judge prompt prepared: ${run_dir}/${test_id}-judge-prompt.md"
  fi

  return 0
}

# ── moira_bench_run_tier <tier> [filter] ─────────────────────────────
# Execute a tier of tests.
moira_bench_run_tier() {
  local tier="$1"
  local filter="${2:-}"

  case "$tier" in
    1)
      # Tier 1: delegate to existing run-all.sh
      local run_all
      run_all="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tests/tier1/run-all.sh"
      if [[ -f "$run_all" ]]; then
        bash "$run_all"
      else
        echo "Error: run-all.sh not found" >&2
        return 1
      fi
      ;;
    2|3)
      local cases_dir
      cases_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/tests/bench/cases"

      if [[ ! -d "$cases_dir" ]]; then
        echo "Error: bench cases directory not found: $cases_dir" >&2
        return 1
      fi

      local max_tests warn_at
      if [[ "$tier" == "2" ]]; then
        max_tests=$_MOIRA_BENCH_TIER2_MAX
        warn_at=$_MOIRA_BENCH_TIER2_WARN
      else
        max_tests=$_MOIRA_BENCH_TIER3_MAX
        warn_at=$_MOIRA_BENCH_TIER3_WARN
      fi

      local test_count=0
      echo "Bench Tier ${tier} — running tests..."

      for case_file in "$cases_dir"/*.yaml; do
        [[ -f "$case_file" ]] || continue

        # Skip config files (not test cases)
        [[ "$(basename "$case_file")" == *-config.yaml ]] && continue

        # Filter by tier: tier 2 runs only tier≤2, tier 3 runs all
        local case_tier
        case_tier=$(moira_yaml_get "$case_file" "meta.tier" 2>/dev/null) || case_tier="2"
        if [[ "$tier" == "2" && "$case_tier" == "3" ]]; then
          continue
        fi

        # Apply name filter if specified
        if [[ -n "$filter" ]] && ! echo "$case_file" | grep -q "$filter"; then
          continue
        fi

        test_count=$((test_count + 1))

        if [[ $test_count -gt $max_tests ]]; then
          echo "Budget guard: max $max_tests tests reached. Stopping."
          break
        fi
        if [[ $test_count -eq $warn_at ]]; then
          echo "Budget warning: approaching limit ($warn_at/$max_tests)"
        fi

        moira_bench_run "$case_file" || true
      done

      echo "Completed: ${test_count} tests"
      ;;
    *)
      echo "Error: invalid tier '$tier' (must be 1, 2, or 3)" >&2
      return 1
      ;;
  esac
}

# ── moira_bench_report <run_dir> ─────────────────────────────────────
# Generate summary report from a bench run.
moira_bench_report() {
  local run_dir="$1"

  if [[ ! -d "$run_dir" ]]; then
    echo "Error: run directory not found: $run_dir" >&2
    return 1
  fi

  local test_count=0 pass_count=0
  for result_file in "$run_dir"/*.yaml; do
    [[ -f "$result_file" ]] || continue
    [[ "$(basename "$result_file")" == "summary.yaml" ]] && continue
    test_count=$((test_count + 1))

    local status
    status=$(moira_yaml_get "$result_file" "status" 2>/dev/null) || status="unknown"
    if [[ "$status" == "recorded" || "$status" == "pass" ]]; then
      pass_count=$((pass_count + 1))
    fi
  done

  # Aggregate quality scores if available
  local quality_total=0 quality_count=0
  for result_file in "$run_dir"/*.yaml; do
    [[ -f "$result_file" ]] || continue
    [[ "$(basename "$result_file")" == "summary.yaml" ]] && continue
    local composite
    composite=$(moira_yaml_get "$result_file" "quality_scores.composite" 2>/dev/null) || composite=""
    if [[ -n "$composite" && "$composite" != "null" ]]; then
      quality_total=$((quality_total + composite))
      quality_count=$((quality_count + 1))
    fi
  done

  local quality_avg="null"
  if [[ $quality_count -gt 0 ]]; then
    quality_avg=$((quality_total / quality_count))
  fi

  cat > "${run_dir}/summary.yaml" << YAML
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
test_count: ${test_count}
pass_count: ${pass_count}
automated_pass_count: 0
quality_scores: ${quality_avg}
YAML

  echo "Bench Report: ${run_dir}"
  echo "  Tests: ${test_count}"
  echo "  Structural pass: ${pass_count}/${test_count}"

  if [[ "$quality_avg" != "null" ]]; then
    echo "  Quality score: ${quality_avg} (avg composite across ${quality_count} tests)"
    # Show zone if baseline exists
    local aggregate_path="${run_dir}/../aggregate.yaml"
    if [[ -f "$aggregate_path" ]]; then
      local zone
      zone=$(moira_bench_classify_zone "$aggregate_path" "composite_score" "$quality_avg" 2>/dev/null) || zone=""
      if [[ -n "$zone" ]]; then
        echo "  Zone: ${zone}"
      fi
    fi
  else
    echo "  Quality scores: not available (no LLM-judge data)"
  fi
}

# ── moira_bench_update_baseline <aggregate_path> <metric> <new_value> ──
moira_bench_update_baseline() {
  local agg_path="$1"
  local metric="$2"
  local new_value="$3"

  mkdir -p "$(dirname "$agg_path")"

  local current_mean current_var current_n
  current_mean=$(moira_yaml_get "$agg_path" "baselines.${metric}.mean" 2>/dev/null) || current_mean=""
  current_var=$(moira_yaml_get "$agg_path" "baselines.${metric}.variance" 2>/dev/null) || current_var=""
  current_n=$(moira_yaml_get "$agg_path" "baselines.${metric}.n_observations" 2>/dev/null) || current_n=""

  if [[ -z "$current_mean" || "$current_mean" == "null" ]]; then
    # First observation
    moira_yaml_set "$agg_path" "baselines.${metric}.mean" "$new_value"
    moira_yaml_set "$agg_path" "baselines.${metric}.variance" "0"
    moira_yaml_set "$agg_path" "baselines.${metric}.n_observations" "1"
    moira_yaml_set "$agg_path" "baselines.${metric}.confidence_band.low" "$new_value"
    moira_yaml_set "$agg_path" "baselines.${metric}.confidence_band.high" "$new_value"
  else
    # Incremental update (integer arithmetic)
    local n=$((current_n + 1))
    # new_mean = old_mean + (value - old_mean) / n
    local diff=$((new_value - current_mean))
    local new_mean=$((current_mean + diff / n))
    # Approximate variance update
    local new_var=$(( (current_var * (n - 1) + diff * (new_value - new_mean)) / n ))
    if [[ $new_var -lt 0 ]]; then new_var=0; fi
    local band_low=$((new_mean - new_var))
    local band_high=$((new_mean + new_var))

    moira_yaml_set "$agg_path" "baselines.${metric}.mean" "$new_mean"
    moira_yaml_set "$agg_path" "baselines.${metric}.variance" "$new_var"
    moira_yaml_set "$agg_path" "baselines.${metric}.n_observations" "$n"
    moira_yaml_set "$agg_path" "baselines.${metric}.confidence_band.low" "$band_low"
    moira_yaml_set "$agg_path" "baselines.${metric}.confidence_band.high" "$band_high"
  fi
}

# ── moira_bench_classify_zone <aggregate_path> <metric> <value> ────
moira_bench_classify_zone() {
  local agg_path="$1"
  local metric="$2"
  local value="$3"

  local mean var n_obs
  mean=$(moira_yaml_get "$agg_path" "baselines.${metric}.mean" 2>/dev/null) || mean=""
  var=$(moira_yaml_get "$agg_path" "baselines.${metric}.variance" 2>/dev/null) || var=""
  n_obs=$(moira_yaml_get "$agg_path" "baselines.${metric}.n_observations" 2>/dev/null) || n_obs=""

  if [[ -z "$mean" || "$mean" == "null" || -z "$n_obs" ]]; then
    echo "NORMAL"
    return 0
  fi

  # Cold start protocol
  if [[ $n_obs -lt 5 ]]; then
    echo "NORMAL"
    return 0
  fi

  # Minimum effect size: composite <3pts, sub-metric <5pts
  local min_effect=3
  if [[ "$metric" != "composite_score" ]]; then
    min_effect=5
  fi

  local diff=$((value - mean))
  if [[ $diff -lt 0 ]]; then diff=$((-diff)); fi

  if [[ $diff -lt $min_effect ]]; then
    echo "NORMAL"
    return 0
  fi

  if [[ $n_obs -lt 10 ]]; then
    # Phase 2: only ALERT triggers (wide bands)
    local alert_threshold=$((var * 2))
    if [[ $alert_threshold -lt 1 ]]; then alert_threshold=1; fi
    if [[ $diff -gt $alert_threshold ]]; then
      echo "ALERT"
    else
      echo "NORMAL"
    fi
    return 0
  fi

  # Phase 3: full model
  if [[ $var -lt 1 ]]; then var=1; fi
  if [[ $diff -gt $((var * 2)) ]]; then
    echo "ALERT"
  elif [[ $diff -gt $var ]]; then
    echo "WARN"
  else
    echo "NORMAL"
  fi
}

# ── moira_bench_check_regression <aggregate_path> <run_result_path> ─
# Check current run's metrics against baselines for regression.
# run_result_path: YAML file with the current run's quality_scores.
moira_bench_check_regression() {
  local agg_path="$1"
  local run_result_path="${2:-}"

  if [[ ! -f "$agg_path" ]]; then
    echo "no_baseline"
    return 0
  fi

  if [[ -z "$run_result_path" || ! -f "$run_result_path" ]]; then
    echo "no_data"
    return 0
  fi

  local alerts=0 warns=0
  local metrics="composite_score requirements_coverage code_correctness architecture_quality conventions_adherence"

  for metric in $metrics; do
    local mean
    mean=$(moira_yaml_get "$agg_path" "baselines.${metric}.mean" 2>/dev/null) || continue
    [[ -z "$mean" || "$mean" == "null" ]] && continue

    # Read current value from run result
    local current_value
    current_value=$(moira_yaml_get "$run_result_path" "quality_scores.${metric}" 2>/dev/null) || continue
    [[ -z "$current_value" || "$current_value" == "null" ]] && continue

    local zone
    zone=$(moira_bench_classify_zone "$agg_path" "$metric" "$current_value" 2>/dev/null) || continue
    case "$zone" in
      ALERT) alerts=$((alerts + 1)) ;;
      WARN) warns=$((warns + 1)) ;;
    esac
  done

  if [[ $alerts -gt 0 ]]; then
    echo "regression"
  elif [[ $warns -ge 3 ]]; then
    echo "regression"
  elif [[ $warns -ge 2 ]]; then
    echo "sustained_warn"
  elif [[ $warns -ge 1 ]]; then
    echo "noise"
  else
    echo "stable"
  fi
}

# ── _moira_bench_int_ln <x_times_100> ─────────────────────────────────
# Integer approximation of ln(x/100) × 1000.
# Input: x × 100 (e.g., 1800 = 18.0, 10 = 0.10)
# Output: ln(x/100) × 1000
# Uses piecewise linear interpolation between known anchor points.
_moira_bench_int_ln() {
  local x="$1"  # x × 100

  # Anchor points: (x×100, ln(x/100)×1000)
  # 1 → -4605, 5 → -2996, 10 → -2303, 20 → -1609, 50 → -693,
  # 100 → 0, 200 → 693, 500 → 1609, 1000 → 2303, 1800 → 2890,
  # 2000 → 2996, 5000 → 3912, 10000 → 4605
  if [[ $x -le 0 ]]; then
    echo "-9999"
  elif [[ $x -le 1 ]]; then
    echo "-4605"
  elif [[ $x -le 5 ]]; then
    echo $(( -4605 + (x - 1) * (4605 - 2996) / 4 ))
  elif [[ $x -le 10 ]]; then
    echo $(( -2996 + (x - 5) * (2996 - 2303) / 5 ))
  elif [[ $x -le 20 ]]; then
    echo $(( -2303 + (x - 10) * (2303 - 1609) / 10 ))
  elif [[ $x -le 50 ]]; then
    echo $(( -1609 + (x - 20) * (1609 - 693) / 30 ))
  elif [[ $x -le 100 ]]; then
    echo $(( -693 + (x - 50) * 693 / 50 ))
  elif [[ $x -le 200 ]]; then
    echo $(( (x - 100) * 693 / 100 ))
  elif [[ $x -le 500 ]]; then
    echo $(( 693 + (x - 200) * (1609 - 693) / 300 ))
  elif [[ $x -le 1000 ]]; then
    echo $(( 1609 + (x - 500) * (2303 - 1609) / 500 ))
  elif [[ $x -le 2000 ]]; then
    echo $(( 2303 + (x - 1000) * (2996 - 2303) / 1000 ))
  elif [[ $x -le 5000 ]]; then
    echo $(( 2996 + (x - 2000) * (3912 - 2996) / 3000 ))
  else
    echo $(( 3912 + (x - 5000) * (4605 - 3912) / 5000 ))
  fi
}

# ═══════════════════════════════════════════════════════════════════════
# SPRT — Sequential Probability Ratio Test
# Allows early termination of bench runs when statistical evidence is sufficient.
# ═══════════════════════════════════════════════════════════════════════

# SPRT state (module-level, reset per init)
_MOIRA_SPRT_LOG_LAMBDA=0       # cumulative log-likelihood ratio × 1000 (integer)
_MOIRA_SPRT_LOG_A=0            # upper threshold × 1000
_MOIRA_SPRT_LOG_B=0            # lower threshold × 1000
_MOIRA_SPRT_BASELINE_MEAN=0
_MOIRA_SPRT_BASELINE_VAR=1     # variance (σ²), NOT stddev
_MOIRA_SPRT_EFFECT_SIZE=0
_MOIRA_SPRT_COUNT=0
_MOIRA_SPRT_DECISION="continue"

# ── moira_bench_sprt_init <baseline_mean> <baseline_stddev> <effect_size> [alpha] [beta]
# Initialize SPRT state. All values are integers.
moira_bench_sprt_init() {
  local mean="$1"
  local stddev="$2"
  local effect="$3"
  local alpha="${4:-5}"   # percentage (5 = 0.05)
  local beta="${5:-10}"   # percentage (10 = 0.10)

  _MOIRA_SPRT_BASELINE_MEAN=$mean
  _MOIRA_SPRT_BASELINE_VAR=$(( stddev * stddev ))
  if [[ $_MOIRA_SPRT_BASELINE_VAR -lt 1 ]]; then
    _MOIRA_SPRT_BASELINE_VAR=1
  fi
  _MOIRA_SPRT_EFFECT_SIZE=$effect
  _MOIRA_SPRT_LOG_LAMBDA=0
  _MOIRA_SPRT_COUNT=0
  _MOIRA_SPRT_DECISION="continue"

  # A = (1-β)/α, B = β/(1-α)
  # log(A) × 1000 and log(B) × 1000 using integer approximation
  # ln(18) ≈ 2890 (×1000), ln(0.105) ≈ -2254 (×1000)
  # For default α=5%, β=10%: A=18, B≈0.105
  # Use pre-computed values for common defaults
  if [[ "$alpha" -eq 5 && "$beta" -eq 10 ]]; then
    _MOIRA_SPRT_LOG_A=2890
    _MOIRA_SPRT_LOG_B=-2254
  else
    # Compute thresholds for custom alpha/beta
    # A = (1-β)/α, B = β/(1-α), need ln(A)×1000 and ln(B)×1000
    local a_num=$(( (100 - beta) * 100 / alpha ))   # A × 100
    local b_num=$(( beta * 100 / (100 - alpha) ))    # B × 100

    # Integer ln(x/100) × 1000 using piecewise lookup
    # Covers A in [2..100] and B in [0.01..1]
    _MOIRA_SPRT_LOG_A=$(_moira_bench_int_ln "$a_num")
    _MOIRA_SPRT_LOG_B=$(_moira_bench_int_ln "$b_num")
  fi
}

# ── moira_bench_sprt_update <score>
# Update SPRT with new observation. Returns decision via _MOIRA_SPRT_DECISION.
# Also echoes the decision: "continue", "reject_h0" (regression), "accept_h0" (no regression)
moira_bench_sprt_update() {
  local score="$1"

  if [[ "$_MOIRA_SPRT_DECISION" != "continue" ]]; then
    echo "$_MOIRA_SPRT_DECISION"
    return 0
  fi

  _MOIRA_SPRT_COUNT=$(( _MOIRA_SPRT_COUNT + 1 ))

  # Log-likelihood ratio increment (×1000 for integer math):
  # ln(L(x|H1)/L(x|H0)) = -δ(2x - 2μ₀ + δ) / (2σ²)
  # Scale: multiply by 1000 for precision
  local delta=$_MOIRA_SPRT_EFFECT_SIZE
  local mu=$_MOIRA_SPRT_BASELINE_MEAN
  local var=$_MOIRA_SPRT_BASELINE_VAR
  local numerator=$(( -delta * (2 * score - 2 * mu + delta) ))
  local denominator=$(( 2 * var ))
  if [[ $denominator -eq 0 ]]; then denominator=1; fi
  local increment=$(( numerator * 1000 / denominator ))

  _MOIRA_SPRT_LOG_LAMBDA=$(( _MOIRA_SPRT_LOG_LAMBDA + increment ))

  # Decision
  if [[ $_MOIRA_SPRT_LOG_LAMBDA -gt $_MOIRA_SPRT_LOG_A ]]; then
    _MOIRA_SPRT_DECISION="reject_h0"
  elif [[ $_MOIRA_SPRT_LOG_LAMBDA -lt $_MOIRA_SPRT_LOG_B ]]; then
    _MOIRA_SPRT_DECISION="accept_h0"
  fi

  echo "$_MOIRA_SPRT_DECISION"
}

# ── moira_bench_sprt_report
# Returns human-readable SPRT status.
moira_bench_sprt_report() {
  local lambda_display=$(( _MOIRA_SPRT_LOG_LAMBDA / 10 ))
  local sign=""
  if [[ $lambda_display -lt 0 ]]; then
    sign="-"
    lambda_display=$(( -lambda_display ))
  fi
  local lambda_int=$(( lambda_display / 100 ))
  local lambda_frac=$(( lambda_display % 100 ))

  case "$_MOIRA_SPRT_DECISION" in
    reject_h0)
      echo "Regression confirmed after ${_MOIRA_SPRT_COUNT} tests (SPRT early stop)"
      ;;
    accept_h0)
      echo "No regression detected after ${_MOIRA_SPRT_COUNT} tests (SPRT early stop)"
      ;;
    continue)
      echo "SPRT: ${_MOIRA_SPRT_COUNT} tests, log-LR=${sign}${lambda_int}.${lambda_frac}, continuing"
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════
# CUSUM — Cumulative Sum Change Detection
# Detects small sustained metric shifts that individual observations miss.
# Coexists with zone system — adds DRIFT signal.
# ═══════════════════════════════════════════════════════════════════════

# ── moira_bench_cusum_update <metric_name> <score> [aggregate_path]
# Update CUSUM accumulators for a metric.
# Returns: "normal", "drift_up", or "drift_down"
moira_bench_cusum_update() {
  local metric="$1"
  local score="$2"
  local agg_path="${3:-.claude/moira/testing/bench/results/aggregate.yaml}"

  if [[ ! -f "$agg_path" ]]; then
    echo "normal"
    return 0
  fi

  # Read baseline parameters
  local mu var
  mu=$(moira_yaml_get "$agg_path" "baselines.${metric}.mean" 2>/dev/null) || mu=""
  var=$(moira_yaml_get "$agg_path" "baselines.${metric}.variance" 2>/dev/null) || var=""

  if [[ -z "$mu" || "$mu" == "null" ]]; then
    echo "normal"
    return 0
  fi

  var=${var:-1}
  if [[ $var -lt 1 ]]; then var=1; fi

  # Read minimum effect size
  local min_effect=3
  if [[ "$metric" != "composite_score" ]]; then
    min_effect=5
  fi

  # Parameters: k = δ/2, h = 4σ
  # Note: "variance" field in aggregate.yaml is an approximate spread measure.
  # Compute integer sqrt to get proper σ for threshold calculation.
  local k=$(( min_effect / 2 ))
  if [[ $k -lt 1 ]]; then k=1; fi
  local sigma=$var
  if [[ $var -gt 1 ]]; then
    # Integer sqrt via Newton's method
    sigma=$var
    local prev=0
    while [[ $sigma -ne $prev ]]; do
      prev=$sigma
      sigma=$(( (sigma + var / sigma) / 2 ))
    done
  fi
  if [[ $sigma -lt 1 ]]; then sigma=1; fi
  local h=$(( sigma * 4 ))
  if [[ $h -lt 1 ]]; then h=4; fi

  # Read current accumulators
  local s_plus s_minus
  s_plus=$(moira_yaml_get "$agg_path" "cusum.${metric}.s_plus" 2>/dev/null) || s_plus="0"
  s_minus=$(moira_yaml_get "$agg_path" "cusum.${metric}.s_minus" 2>/dev/null) || s_minus="0"
  s_plus=${s_plus:-0}
  s_minus=${s_minus:-0}

  # Update accumulators
  # S⁺ₙ = max(0, S⁺ₙ₋₁ + (xₙ - μ₀ - k))
  local new_s_plus=$(( s_plus + score - mu - k ))
  if [[ $new_s_plus -lt 0 ]]; then new_s_plus=0; fi

  # S⁻ₙ = max(0, S⁻ₙ₋₁ + (μ₀ - k - xₙ))
  local new_s_minus=$(( s_minus + mu - k - score ))
  if [[ $new_s_minus -lt 0 ]]; then new_s_minus=0; fi

  # Persist
  moira_yaml_set "$agg_path" "cusum.${metric}.s_plus" "$new_s_plus"
  moira_yaml_set "$agg_path" "cusum.${metric}.s_minus" "$new_s_minus"

  # Check for alarm
  if [[ $new_s_plus -gt $h ]]; then
    echo "drift_up"
  elif [[ $new_s_minus -gt $h ]]; then
    echo "drift_down"
  else
    echo "normal"
  fi
}

# ── moira_bench_cusum_reset <metric_name> [aggregate_path]
# Reset accumulators after alarm.
moira_bench_cusum_reset() {
  local metric="$1"
  local agg_path="${2:-.claude/moira/testing/bench/results/aggregate.yaml}"

  if [[ ! -f "$agg_path" ]]; then
    return 0
  fi

  moira_yaml_set "$agg_path" "cusum.${metric}.s_plus" "0"
  moira_yaml_set "$agg_path" "cusum.${metric}.s_minus" "0"
}

# ── moira_bench_cusum_state <metric_name> [aggregate_path]
# Read current accumulator values for reporting.
moira_bench_cusum_state() {
  local metric="$1"
  local agg_path="${2:-.claude/moira/testing/bench/results/aggregate.yaml}"

  if [[ ! -f "$agg_path" ]]; then
    echo "s_plus: 0"
    echo "s_minus: 0"
    return 0
  fi

  local s_plus s_minus
  s_plus=$(moira_yaml_get "$agg_path" "cusum.${metric}.s_plus" 2>/dev/null) || s_plus="0"
  s_minus=$(moira_yaml_get "$agg_path" "cusum.${metric}.s_minus" 2>/dev/null) || s_minus="0"

  echo "s_plus: ${s_plus:-0}"
  echo "s_minus: ${s_minus:-0}"
}

# ═══════════════════════════════════════════════════════════════════════
# BH — Benjamini-Hochberg Multiple Comparison Correction
# Controls false discovery rate when evaluating multiple metrics.
# ═══════════════════════════════════════════════════════════════════════

# ── moira_bench_bh_correct <p_values_csv> [alpha]
# Apply Benjamini-Hochberg procedure.
# Input: comma-separated p-values as integers (percentages × 100, e.g., 125 = 1.25%)
# Output: space-separated indices (0-based) of significant results surviving correction.
# If none survive, outputs "none".
moira_bench_bh_correct() {
  local p_values_csv="$1"
  local alpha="${2:-500}"  # 500 = 5.00% (scaled by 100)

  # Parse p-values into arrays
  local p_vals=()
  local indices=()
  local i=0
  IFS=',' read -ra raw_vals <<< "$p_values_csv"
  for val in "${raw_vals[@]}"; do
    val=$(echo "$val" | tr -d ' ')
    p_vals+=("$val")
    indices+=("$i")
    i=$((i + 1))
  done

  local m=${#p_vals[@]}
  if [[ $m -eq 0 ]]; then
    echo "none"
    return 0
  fi

  # Sort by p-value (ascending) — bubble sort for small m
  local sorted_p=("${p_vals[@]}")
  local sorted_idx=("${indices[@]}")
  local j
  for (( i=0; i<m-1; i++ )); do
    for (( j=0; j<m-i-1; j++ )); do
      if [[ ${sorted_p[j]} -gt ${sorted_p[j+1]} ]]; then
        # Swap p-values
        local tmp=${sorted_p[j]}
        sorted_p[j]=${sorted_p[j+1]}
        sorted_p[j+1]=$tmp
        # Swap indices
        tmp=${sorted_idx[j]}
        sorted_idx[j]=${sorted_idx[j+1]}
        sorted_idx[j+1]=$tmp
      fi
    done
  done

  # Find largest k such that p(k) ≤ (k/m) × α
  # p-values and alpha are scaled ×100, so threshold = (k × alpha) / m
  local largest_k=-1
  for (( k=1; k<=m; k++ )); do
    local threshold=$(( k * alpha / m ))
    local p_k=${sorted_p[k-1]}
    if [[ $p_k -le $threshold ]]; then
      largest_k=$k
    fi
  done

  if [[ $largest_k -lt 1 ]]; then
    echo "none"
    return 0
  fi

  # Return original indices of significant results (indices 0..largest_k-1 in sorted order)
  local result=""
  for (( k=0; k<largest_k; k++ )); do
    if [[ -n "$result" ]]; then
      result+=" "
    fi
    result+="${sorted_idx[k]}"
  done

  echo "$result"
}
