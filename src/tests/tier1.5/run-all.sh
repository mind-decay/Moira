#!/usr/bin/env bash
# run-all.sh — Tier 1.5 Functional Test entry point
# Runs all test-fn-*.sh files, aggregates results.
# Supports optional filter: bash run-all.sh yaml-utils → runs only test-fn-yaml-utils.sh
# 0 Claude tokens — pure bash, deterministic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASSES=0
TOTAL_FAILURES=0
TOTAL_FILES=0
FILTER="${1:-}"

echo ""
echo "Moira Tier 1.5 — Functional Tests"
echo "==================================="
echo ""

for test_file in "$SCRIPT_DIR"/test-fn-*.sh; do
  [[ -f "$test_file" ]] || continue

  test_name=$(basename "$test_file" .sh)

  # Apply filter if provided
  if [[ -n "$FILTER" && "$test_name" != *"$FILTER"* ]]; then
    continue
  fi

  echo "[$test_name]"

  # Run test in subshell, capture output and exit code
  set +e
  output=$(bash "$test_file" 2>&1)
  exit_code=$?
  set -e

  echo "$output"

  # Extract pass/fail counts from output
  if [[ "$output" =~ ([0-9]+)/([0-9]+)\ passed,\ ([0-9]+)\ failed ]]; then
    TOTAL_PASSES=$((TOTAL_PASSES + ${BASH_REMATCH[1]}))
    TOTAL_FAILURES=$((TOTAL_FAILURES + ${BASH_REMATCH[3]}))
  fi

  TOTAL_FILES=$((TOTAL_FILES + 1))
  echo ""
done

if [[ $TOTAL_FILES -eq 0 ]]; then
  echo "No test files found${FILTER:+ matching filter '$FILTER'}"
  exit 1
fi

# Summary
TOTAL=$((TOTAL_PASSES + TOTAL_FAILURES))
echo "==================================="
echo "Total: $TOTAL_PASSES/$TOTAL passed, $TOTAL_FAILURES failed ($TOTAL_FILES test files)"
echo "==================================="

if [[ $TOTAL_FAILURES -gt 0 ]]; then
  exit 1
fi
