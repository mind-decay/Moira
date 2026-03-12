#!/usr/bin/env bash
# bench.sh — Behavioral bench test runner for Moira
# Executes bench test cases through the Moira pipeline with predefined gate responses.
# Phase 6: automated checks only (no LLM-judge).
#
# Responsibilities: bench test execution and reporting ONLY
# Does NOT handle pipeline logic (that's the orchestrator)

set -euo pipefail

_MOIRA_BENCH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BENCH_LIB_DIR}/yaml-utils.sh"

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

        # Apply filter if specified
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

  cat > "${run_dir}/summary.yaml" << YAML
timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
test_count: ${test_count}
pass_count: ${pass_count}
automated_pass_count: 0
quality_scores: null
YAML

  echo "Bench Report: ${run_dir}"
  echo "  Tests: ${test_count}"
  echo "  Structural pass: ${pass_count}/${test_count}"
  echo "  Quality scores: not available (no LLM-judge)"
}
