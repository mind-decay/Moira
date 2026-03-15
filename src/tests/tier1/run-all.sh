#!/usr/bin/env bash
# run-all.sh — Tier 1 Structural Verifier entry point
# Runs all test-*.sh files, aggregates results.
# 0 Claude tokens — pure bash, deterministic.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASSES=0
TOTAL_FAILURES=0
TOTAL_FILES=0

echo ""
echo "Moira Tier 1 — Structural Verifier"
echo "==================================="
echo ""

# Find and run all test-*.sh files (skip test-helpers.sh)
for test_file in "$SCRIPT_DIR"/test-*.sh; do
  [[ -f "$test_file" ]] || continue
  [[ "$(basename "$test_file")" == "test-helpers.sh" ]] && continue

  test_name=$(basename "$test_file" .sh)
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

# Summary
TOTAL=$((TOTAL_PASSES + TOTAL_FAILURES))
echo "==================================="
echo "Total: $TOTAL_PASSES/$TOTAL passed, $TOTAL_FAILURES failed ($TOTAL_FILES test files)"
echo "==================================="

if [[ $TOTAL_FAILURES -gt 0 ]]; then
  exit 1
fi
