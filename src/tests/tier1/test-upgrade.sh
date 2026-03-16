#!/usr/bin/env bash
# test-upgrade.sh — Verify upgrade system artifacts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"

# ── upgrade.sh existence ─────────────────────────────────────────────
assert_file_exists "$SRC_DIR/global/lib/upgrade.sh" "upgrade.sh exists in src"
assert_file_exists "$MOIRA_HOME/lib/upgrade.sh" "upgrade.sh exists in MOIRA_HOME"

# ── upgrade.sh functions ─────────────────────────────────────────────
for func in moira_upgrade_check_version moira_upgrade_diff_files moira_upgrade_apply moira_upgrade_snapshot; do
  if grep -q "$func" "$SRC_DIR/global/lib/upgrade.sh" 2>/dev/null; then
    pass "upgrade.sh defines $func"
  else
    fail "upgrade.sh missing function: $func"
  fi
done

# ── upgrade.sh syntax ───────────────────────────────────────────────
if bash -n "$SRC_DIR/global/lib/upgrade.sh" 2>/dev/null; then
  pass "upgrade.sh has valid bash syntax"
else
  fail "upgrade.sh has syntax errors"
fi

# ── upgrade.md command ───────────────────────────────────────────────
upgrade_cmd="$SRC_DIR/commands/moira/upgrade.md"
assert_file_exists "$upgrade_cmd" "upgrade.md command exists"

# ── upgrade.md is not a placeholder ──────────────────────────────────
if grep -qi "placeholder\|will be implemented\|TODO" "$upgrade_cmd" 2>/dev/null; then
  fail "upgrade.md appears to be a placeholder"
else
  pass "upgrade.md is not a placeholder"
fi

# ── upgrade.md allowed-tools ─────────────────────────────────────────
assert_file_contains "$upgrade_cmd" "Agent" "upgrade.md has Agent in allowed-tools"
assert_file_contains "$upgrade_cmd" "Read" "upgrade.md has Read in allowed-tools"
assert_file_contains "$upgrade_cmd" "Write" "upgrade.md has Write in allowed-tools"
assert_file_contains "$upgrade_cmd" "Bash" "upgrade.md has Bash in allowed-tools"

# ── scaffold.sh creates .version-snapshot ────────────────────────────
scaffold="$SRC_DIR/global/lib/scaffold.sh"
if [[ ! -f "$scaffold" ]]; then
  scaffold="$MOIRA_HOME/lib/scaffold.sh"
fi
assert_file_exists "$scaffold" "scaffold.sh exists"
assert_file_contains "$scaffold" "version-snapshot" "scaffold.sh creates .version-snapshot directory"

test_summary
