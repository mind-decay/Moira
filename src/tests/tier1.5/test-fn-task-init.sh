#!/usr/bin/env bash
# test-fn-task-init.sh — Functional tests for task-init.sh
# Tests task initialization and project size detection.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: task-init.sh (functional)"

source "$SRC_LIB_DIR/task-init.sh"
set +e

# ── moira_preflight_project_size: small → standard ───────────────────

mkdir -p "$TEMP_DIR/small/src"
for i in $(seq 1 50); do touch "$TEMP_DIR/small/src/f$i.txt"; done
run_fn moira_preflight_project_size "$TEMP_DIR/small"
assert_output_equals "$FN_STDOUT" "standard" "project_size: 50 files → standard"

# ── moira_preflight_project_size: large → progressive ────────────────

mkdir -p "$TEMP_DIR/large/src"
for i in $(seq 1 5100); do touch "$TEMP_DIR/large/src/f$i.txt"; done
run_fn moira_preflight_project_size "$TEMP_DIR/large"
assert_output_equals "$FN_STDOUT" "progressive" "project_size: 5100 files → progressive"

# ── moira_preflight_project_size: excludes node_modules ──────────────

mkdir -p "$TEMP_DIR/excluded/src" "$TEMP_DIR/excluded/node_modules"
for i in $(seq 1 50); do touch "$TEMP_DIR/excluded/src/f$i.txt"; done
for i in $(seq 1 6000); do touch "$TEMP_DIR/excluded/node_modules/d$i.txt"; done
run_fn moira_preflight_project_size "$TEMP_DIR/excluded"
assert_output_equals "$FN_STDOUT" "standard" "project_size: node_modules excluded"

# ── moira_preflight_project_size: excludes .git ──────────────────────

mkdir -p "$TEMP_DIR/gitdir/src" "$TEMP_DIR/gitdir/.git/objects"
for i in $(seq 1 50); do touch "$TEMP_DIR/gitdir/src/f$i.txt"; done
for i in $(seq 1 6000); do touch "$TEMP_DIR/gitdir/.git/objects/o$i"; done
run_fn moira_preflight_project_size "$TEMP_DIR/gitdir"
assert_output_equals "$FN_STDOUT" "standard" "project_size: .git excluded"

# ── moira_preflight_project_size: nonexistent → standard ─────────────

run_fn moira_preflight_project_size "$TEMP_DIR/nonexistent"
assert_output_equals "$FN_STDOUT" "standard" "project_size: missing dir → standard"

# ── moira_preflight_project_size: boundary 5000 → standard ──────────

mkdir -p "$TEMP_DIR/boundary/src"
for i in $(seq 1 5000); do touch "$TEMP_DIR/boundary/src/f$i.txt"; done
run_fn moira_preflight_project_size "$TEMP_DIR/boundary"
assert_output_equals "$FN_STDOUT" "standard" "project_size: exactly 5000 → standard"

# ── moira_preflight_project_size: boundary 5001 → progressive ────────

touch "$TEMP_DIR/boundary/src/f5001.txt"
run_fn moira_preflight_project_size "$TEMP_DIR/boundary"
assert_output_equals "$FN_STDOUT" "progressive" "project_size: 5001 → progressive"

test_summary
