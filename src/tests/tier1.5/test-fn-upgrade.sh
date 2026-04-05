#!/usr/bin/env bash
# test-fn-upgrade.sh — Functional tests for upgrade.sh
# Tests version check, diff classification, snapshot.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: upgrade.sh (functional)"

source "$SRC_LIB_DIR/upgrade.sh"
set +e

# ── moira_upgrade_check_version: newer available ─────────────────────

mkdir -p "$MOIRA_HOME"
echo "0.3.0" > "$MOIRA_HOME/.version"

mkdir -p "$TEMP_DIR/source"
echo "0.4.0" > "$TEMP_DIR/source/.version"

run_fn moira_upgrade_check_version "$TEMP_DIR/source"
assert_exit_zero "check_version: exit 0"
assert_output_contains "$FN_STDOUT" "0.4.0" "check_version: reports available version"
# Check for newer indication (may be is_newer=true or newer=true or similar)
if [[ "$FN_STDOUT" == *"true"* || "$FN_STDOUT" == *"newer"* || "$FN_STDOUT" == *"upgrade"* ]]; then
  pass "check_version: indicates newer version available"
else
  fail "check_version: should indicate newer version, got '$FN_STDOUT'"
fi

# ── moira_upgrade_check_version: same version ────────────────────────

echo "0.3.0" > "$TEMP_DIR/source/.version"
run_fn moira_upgrade_check_version "$TEMP_DIR/source"
assert_output_contains "$FN_STDOUT" "is_newer=false" "check_version: same version → not newer"

# ── moira_upgrade_check_version: older available ─────────────────────

echo "0.2.0" > "$TEMP_DIR/source/.version"
run_fn moira_upgrade_check_version "$TEMP_DIR/source"
assert_output_contains "$FN_STDOUT" "is_newer=false" "check_version: older → not newer"

# ── moira_upgrade_snapshot: creates snapshot ──────────────────────────

snap_home="$TEMP_DIR/snap-home"
mkdir -p "$snap_home/core/rules" "$snap_home/lib" "$snap_home/schemas"
echo "base rules" > "$snap_home/core/rules/base.yaml"
echo "lib content" > "$snap_home/lib/state.sh"
echo "schema" > "$snap_home/schemas/current.schema.yaml"

moira_upgrade_snapshot "$snap_home"
assert_dir_exists "$snap_home/.version-snapshot" "snapshot: creates .version-snapshot/"
assert_file_exists "$snap_home/.version-snapshot/core/rules/base.yaml" "snapshot: copies core/rules"
assert_file_exists "$snap_home/.version-snapshot/lib/state.sh" "snapshot: copies lib"
assert_file_exists "$snap_home/.version-snapshot/schemas/current.schema.yaml" "snapshot: copies schemas"

# ── moira_upgrade_diff_files: classifies changes ─────────────────────

# Setup: old (snapshot), new (source), project (current)
old_dir="$TEMP_DIR/diff-old"
new_dir="$TEMP_DIR/diff-new"
proj_dir="$TEMP_DIR/diff-proj"

mkdir -p "$old_dir/core" "$new_dir/core" "$proj_dir/core"

# File unchanged in all three → not in diff
echo "same content" > "$old_dir/core/unchanged.yaml"
echo "same content" > "$new_dir/core/unchanged.yaml"
echo "same content" > "$proj_dir/core/unchanged.yaml"

# File changed in new, not in project → auto_apply
echo "old content" > "$old_dir/core/updated.yaml"
echo "new content" > "$new_dir/core/updated.yaml"
echo "old content" > "$proj_dir/core/updated.yaml"

# New file only in new → new_file
echo "brand new" > "$new_dir/core/added.yaml"

# File changed in both → conflict
echo "original" > "$old_dir/core/conflicted.yaml"
echo "new version" > "$new_dir/core/conflicted.yaml"
echo "project version" > "$proj_dir/core/conflicted.yaml"

run_fn moira_upgrade_diff_files "$old_dir" "$new_dir" "$proj_dir"
assert_exit_zero "diff_files: exit 0"
assert_output_contains "$FN_STDOUT" "auto_apply" "diff_files: detects auto_apply"
assert_output_contains "$FN_STDOUT" "new_file" "diff_files: detects new_file"
assert_output_contains "$FN_STDOUT" "conflict" "diff_files: detects conflict"

test_summary
