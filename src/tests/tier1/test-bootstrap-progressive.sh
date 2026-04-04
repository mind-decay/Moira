#!/usr/bin/env bash
# test-bootstrap-progressive.sh — Tier 1 tests for progressive bootstrap (D-223)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Progressive Bootstrap Mode (D-223)"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SRC_DIR/global/lib/task-init.sh"
set +e

# ── 1. Small project → standard ──
mkdir -p "$TEMP_DIR/small/src"
for i in $(seq 1 100); do
  touch "$TEMP_DIR/small/src/file-$i.txt"
done
result=$(moira_preflight_project_size "$TEMP_DIR/small")
assert_equals "$result" "standard" "small project: 100 files → standard"

# ── 2. Large project → progressive ──
mkdir -p "$TEMP_DIR/large/src"
for i in $(seq 1 5100); do
  touch "$TEMP_DIR/large/src/file-$i.txt"
done
result=$(moira_preflight_project_size "$TEMP_DIR/large")
assert_equals "$result" "progressive" "large project: 5100 files → progressive"

# ── 3. Excluded dirs not counted ──
mkdir -p "$TEMP_DIR/excluded/src" "$TEMP_DIR/excluded/node_modules"
for i in $(seq 1 100); do
  touch "$TEMP_DIR/excluded/src/file-$i.txt"
done
# Put 5000 files in node_modules (should be excluded)
for i in $(seq 1 5100); do
  touch "$TEMP_DIR/excluded/node_modules/dep-$i.txt"
done
result=$(moira_preflight_project_size "$TEMP_DIR/excluded")
assert_equals "$result" "standard" "excluded dirs: node_modules not counted"

# ── 4. Missing dir → standard ──
result=$(moira_preflight_project_size "$TEMP_DIR/nonexistent")
assert_equals "$result" "standard" "missing dir: returns standard"

# ── 5. Boundary: exactly 5000 → standard ──
mkdir -p "$TEMP_DIR/boundary/src"
for i in $(seq 1 5000); do
  touch "$TEMP_DIR/boundary/src/file-$i.txt"
done
result=$(moira_preflight_project_size "$TEMP_DIR/boundary")
assert_equals "$result" "standard" "boundary: exactly 5000 → standard (threshold is >5000)"

# ── 6. Boundary: 5001 → progressive ──
touch "$TEMP_DIR/boundary/src/file-5001.txt"
result=$(moira_preflight_project_size "$TEMP_DIR/boundary")
assert_equals "$result" "progressive" "boundary: 5001 → progressive"

test_summary
