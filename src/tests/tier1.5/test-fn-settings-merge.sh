#!/usr/bin/env bash
# test-fn-settings-merge.sh — Functional tests for settings-merge.sh
# Tests hooks merge, MCP registration, statusline.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: settings-merge.sh (functional)"

source "$SRC_LIB_DIR/settings-merge.sh"
set +e

# ── moira_settings_merge_hooks: creates settings.json ────────────────

proj_root="$TEMP_DIR/merge-project"
mkdir -p "$proj_root/.claude"

# Create minimal moira home with hooks
merge_home="$TEMP_DIR/merge-moira-home"
mkdir -p "$merge_home/hooks"
echo '#!/bin/bash' > "$merge_home/hooks/guard.sh"
echo '#!/bin/bash' > "$merge_home/hooks/budget-track.sh"

run_fn moira_settings_merge_hooks "$proj_root" "$merge_home"
assert_exit_zero "merge_hooks: exit 0"
assert_file_exists "$proj_root/.claude/settings.json" "merge_hooks: creates settings.json"
assert_file_contains "$proj_root/.claude/settings.json" "hooks" "merge_hooks: includes hooks section"

# ── moira_settings_merge_hooks: idempotent ───────────────────────────

# Run again — should not duplicate entries
moira_settings_merge_hooks "$proj_root" "$merge_home"
# Count occurrences of guard.sh — should be exactly once
# guard.sh may appear in multiple matcher groups (intentional: always-on + agent-specific)
# Idempotency means running merge twice doesn't add MORE entries
first_count=$(grep -c "guard.sh" "$proj_root/.claude/settings.json" 2>/dev/null || echo "0")
moira_settings_merge_hooks "$proj_root" "$merge_home"
second_count=$(grep -c "guard.sh" "$proj_root/.claude/settings.json" 2>/dev/null || echo "0")
if [[ "$first_count" -eq "$second_count" ]]; then
  pass "merge_hooks: idempotent (count stable: $first_count)"
else
  fail "merge_hooks: not idempotent ($first_count → $second_count)"
fi

# ── moira_settings_merge_mcp: creates .mcp.json ─────────────────────

mcp_proj="$TEMP_DIR/mcp-merge-project"
mkdir -p "$mcp_proj"

run_fn moira_settings_merge_mcp "$mcp_proj" "test-server" "npx" "-y" "test-mcp"
assert_exit_zero "merge_mcp: exit 0"
assert_file_exists "$mcp_proj/.mcp.json" "merge_mcp: creates .mcp.json"
assert_file_contains "$mcp_proj/.mcp.json" "test-server" "merge_mcp: includes server name"

# ── moira_settings_merge_mcp: idempotent ─────────────────────────────

moira_settings_merge_mcp "$mcp_proj" "test-server" "npx" "-y" "test-mcp"
server_count=$(grep -c "test-server" "$mcp_proj/.mcp.json" 2>/dev/null || echo "0")
if [[ "$server_count" -le 1 ]]; then
  pass "merge_mcp: idempotent (no duplicates)"
else
  fail "merge_mcp: server duplicated ($server_count occurrences)"
fi

# ── moira_settings_remove_mcp: removes server ────────────────────────

moira_settings_merge_mcp "$mcp_proj" "to-remove" "npx" "-y" "remove-me"
assert_file_contains "$mcp_proj/.mcp.json" "to-remove" "remove_mcp: server exists before removal"
moira_settings_remove_mcp "$mcp_proj" "to-remove"
if ! grep -q "to-remove" "$mcp_proj/.mcp.json" 2>/dev/null; then
  pass "remove_mcp: server removed"
else
  fail "remove_mcp: server should be removed"
fi

# ── moira_settings_remove_hooks: removes hook entries ────────────────

hooks_proj="$TEMP_DIR/hooks-remove-project"
mkdir -p "$hooks_proj/.claude"
moira_settings_merge_hooks "$hooks_proj" "$merge_home"
assert_file_contains "$hooks_proj/.claude/settings.json" "hooks" "remove_hooks: hooks exist before"
moira_settings_remove_hooks "$hooks_proj"
# After removal, hooks section should be empty or missing
run_fn moira_settings_remove_hooks "$hooks_proj"
assert_exit_zero "remove_hooks: exit 0"

test_summary
