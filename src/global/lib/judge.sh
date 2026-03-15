#!/usr/bin/env bash
# judge.sh — LLM-Judge prompt assembly and scoring for Moira
# Constructs evaluation prompts, calculates composite scores, runs calibration.
#
# Responsibilities: judge prompt assembly + score calculation ONLY
# Does NOT dispatch the judge (that's the orchestrator/bench caller via Agent tool)
# Does NOT decide pass/fail (that's the bench runner or health command)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_JUDGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_JUDGE_LIB_DIR}/yaml-utils.sh"

# ── moira_judge_invoke <task_dir> <rubric_path> [model_tier] ─────────
# Assemble a judge evaluation prompt from template + task artifacts + rubric.
# Outputs the assembled prompt to stdout for the caller to dispatch via Agent tool.
# Returns 0 on success.
moira_judge_invoke() {
  local task_dir="$1"
  local rubric_path="$2"
  local model_tier="${3:-}"

  local moira_home="${MOIRA_HOME:-${HOME}/.claude/moira}"
  local template_path="${moira_home}/templates/judge/judge-prompt.md"

  if [[ ! -f "$template_path" ]]; then
    echo "Error: judge prompt template not found: $template_path" >&2
    return 1
  fi

  if [[ ! -f "$rubric_path" ]]; then
    echo "Error: rubric file not found: $rubric_path" >&2
    return 1
  fi

  # Read template
  local template
  template=$(cat "$template_path")

  # Read task artifacts (skip missing ones gracefully)
  local task_description="" requirements="" architecture="" implementation=""
  local review_findings="" test_results=""

  if [[ -f "${task_dir}/input.md" ]]; then
    task_description=$(cat "${task_dir}/input.md")
  fi
  if [[ -f "${task_dir}/requirements.md" ]]; then
    requirements=$(cat "${task_dir}/requirements.md")
  fi
  if [[ -f "${task_dir}/architecture.md" ]]; then
    architecture=$(cat "${task_dir}/architecture.md")
  fi
  if [[ -f "${task_dir}/implementation.md" ]]; then
    implementation=$(cat "${task_dir}/implementation.md")
  fi
  if [[ -f "${task_dir}/review.md" ]]; then
    review_findings=$(cat "${task_dir}/review.md")
  fi
  if [[ -f "${task_dir}/test-results.md" ]]; then
    test_results=$(cat "${task_dir}/test-results.md")
  fi

  # Read rubric criteria
  local rubric_criteria
  rubric_criteria=$(cat "$rubric_path")

  # Substitute placeholders in template
  # Use awk for multi-line substitution safety
  local output="$template"
  output=$(echo "$output" | awk -v val="$task_description" '{gsub(/\{task_description\}/, val); print}')
  output=$(echo "$output" | awk -v val="$requirements" '{gsub(/\{requirements\}/, val); print}')
  output=$(echo "$output" | awk -v val="$architecture" '{gsub(/\{architecture\}/, val); print}')
  output=$(echo "$output" | awk -v val="$implementation" '{gsub(/\{implementation\}/, val); print}')
  output=$(echo "$output" | awk -v val="$review_findings" '{gsub(/\{review_findings\}/, val); print}')
  output=$(echo "$output" | awk -v val="$test_results" '{gsub(/\{test_results\}/, val); print}')
  output=$(echo "$output" | awk -v val="$rubric_criteria" '{gsub(/\{rubric_criteria\}/, val); print}')

  echo "$output"
  return 0
}

# ── moira_judge_composite_score <evaluation_path> [automated_pass] ───
# Calculate weighted composite score from evaluation YAML.
# Weights: requirements_coverage=25, code_correctness=30, architecture_quality=25, conventions_adherence=20
# Uses integer arithmetic (multiply by 100 for precision).
# If automated_pass is "false", echoes "quality_capped: true".
# Echoes composite score as integer*100 (e.g., 375 for 3.75).
moira_judge_composite_score() {
  local evaluation_path="$1"
  local automated_pass="${2:-true}"

  if [[ ! -f "$evaluation_path" ]]; then
    echo "Error: evaluation file not found: $evaluation_path" >&2
    return 1
  fi

  local req code arch conv
  req=$(moira_yaml_get "$evaluation_path" "scores.requirements_coverage" 2>/dev/null) || req="0"
  code=$(moira_yaml_get "$evaluation_path" "scores.code_correctness" 2>/dev/null) || code="0"
  arch=$(moira_yaml_get "$evaluation_path" "scores.architecture_quality" 2>/dev/null) || arch="0"
  conv=$(moira_yaml_get "$evaluation_path" "scores.conventions_adherence" 2>/dev/null) || conv="0"

  # Integer arithmetic: multiply each score by weight, sum, result is score*100
  local composite=$(( req * 25 + code * 30 + arch * 25 + conv * 20 ))

  if [[ "$automated_pass" == "false" ]]; then
    echo "quality_capped: true"
  fi

  echo "$composite"
  return 0
}

# ── moira_judge_normalize_score <score_1_5> ──────────────────────────
# Convert 1-5 scale score to 0-100 integer.
# Formula: (score - 1) * 25
moira_judge_normalize_score() {
  local score="$1"
  local normalized=$(( (score - 1) * 25 ))
  echo "$normalized"
  return 0
}

# ── moira_judge_calibrate <calibration_dir> <rubric_path> ────────────
# Compare pre-existing evaluation results against expected values.
# Each subdirectory of calibration_dir has expected.yaml with expected scores.
# Returns 0 if all pass within tolerance, 1 if any fail.
moira_judge_calibrate() {
  local calibration_dir="$1"
  local rubric_path="$2"
  local all_pass=true

  if [[ ! -d "$calibration_dir" ]]; then
    echo "Error: calibration directory not found: $calibration_dir" >&2
    return 1
  fi

  echo "=== Judge Calibration Report ==="
  echo "Rubric: $rubric_path"
  echo ""

  for example_dir in "$calibration_dir"/*/; do
    [[ ! -d "$example_dir" ]] && continue

    local example_name
    example_name=$(basename "$example_dir")

    local expected_file="${example_dir}expected.yaml"
    local eval_file="${example_dir}judge-evaluation.yaml"

    if [[ ! -f "$expected_file" ]]; then
      echo "SKIP: ${example_name} — no expected.yaml"
      continue
    fi

    if [[ ! -f "$eval_file" ]]; then
      echo "SKIP: ${example_name} — no judge-evaluation.yaml (run judge first)"
      continue
    fi

    echo "--- ${example_name} ---"

    local tolerance
    tolerance=$(moira_yaml_get "$expected_file" "tolerance" 2>/dev/null) || tolerance="1"

    local pass=true
    for criterion in requirements_coverage code_correctness architecture_quality conventions_adherence; do
      local expected actual diff
      expected=$(moira_yaml_get "$expected_file" "$criterion" 2>/dev/null) || expected="0"
      actual=$(moira_yaml_get "$eval_file" "scores.${criterion}" 2>/dev/null) || actual="0"

      diff=$(( actual - expected ))
      if [[ $diff -lt 0 ]]; then
        diff=$(( -diff ))
      fi

      local status="PASS"
      if [[ $diff -gt $tolerance ]]; then
        status="FAIL"
        pass=false
        all_pass=false
      fi

      echo "  ${criterion}: expected=${expected} actual=${actual} diff=${diff} ${status}"
    done

    if $pass; then
      echo "  Result: PASS"
    else
      echo "  Result: FAIL"
    fi
    echo ""
  done

  echo "=== Overall: $(if $all_pass; then echo "PASS"; else echo "FAIL"; fi) ==="

  if $all_pass; then
    return 0
  else
    return 1
  fi
}
