#!/usr/bin/env bash
# test-fn-scaffold.sh — Functional tests for scaffold.sh
# Tests global and project directory scaffold creation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: scaffold.sh (functional)"

source "$SRC_LIB_DIR/scaffold.sh"
set +e

# ── moira_scaffold_global: creates directory structure ───────────────

global_dir="$TEMP_DIR/global-scaffold"
moira_scaffold_global "$global_dir"

assert_dir_exists "$global_dir/core/rules" "scaffold_global: core/rules/"
assert_dir_exists "$global_dir/core/pipelines" "scaffold_global: core/pipelines/"
assert_dir_exists "$global_dir/skills" "scaffold_global: skills/"
assert_dir_exists "$global_dir/hooks" "scaffold_global: hooks/"
assert_dir_exists "$global_dir/templates" "scaffold_global: templates/"
assert_dir_exists "$global_dir/lib" "scaffold_global: lib/"
assert_dir_exists "$global_dir/schemas" "scaffold_global: schemas/"

# ── moira_scaffold_global: idempotent ────────────────────────────────

# Running twice should not error
run_fn moira_scaffold_global "$global_dir"
assert_exit_zero "scaffold_global: idempotent (no error on second run)"

# ── moira_scaffold_project: creates .moira structure ─────────────────

proj_dir="$TEMP_DIR/project-scaffold"
mkdir -p "$proj_dir"
moira_scaffold_project "$proj_dir"

assert_dir_exists "$proj_dir/.moira" "scaffold_project: .moira/"
assert_dir_exists "$proj_dir/.moira/state" "scaffold_project: state/"
assert_dir_exists "$proj_dir/.moira/knowledge" "scaffold_project: knowledge/"
assert_dir_exists "$proj_dir/.moira/config" "scaffold_project: config/"

# ── moira_scaffold_project: idempotent ───────────────────────────────

run_fn moira_scaffold_project "$proj_dir"
assert_exit_zero "scaffold_project: idempotent"

test_summary
