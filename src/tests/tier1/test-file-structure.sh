#!/usr/bin/env bash
# test-file-structure.sh — Verify installed Moira file structure
# Tests global layer directories, command stubs, version file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
COMMANDS_DIR="$HOME/.claude/commands/moira"

# ── Version file ─────────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/.version" ".version exists"

if [[ -f "$MOIRA_HOME/.version" ]]; then
  ver=$(cat "$MOIRA_HOME/.version")
  if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    pass ".version contains valid semver ($ver)"
  else
    fail ".version contains invalid semver: $ver"
  fi
fi

# ── Lib files ────────────────────────────────────────────────────────
for lib in state.sh yaml-utils.sh scaffold.sh task-id.sh; do
  assert_file_exists "$MOIRA_HOME/lib/$lib" "lib/$lib exists"
  if [[ -f "$MOIRA_HOME/lib/$lib" ]]; then
    if bash -n "$MOIRA_HOME/lib/$lib" 2>/dev/null; then
      pass "lib/$lib syntax valid"
    else
      fail "lib/$lib has syntax errors"
    fi
  fi
done

# ── Global directories ──────────────────────────────────────────────
assert_dir_exists "$MOIRA_HOME/core/rules/roles" "core/rules/roles/ exists"
assert_dir_exists "$MOIRA_HOME/core/rules/quality" "core/rules/quality/ exists"
assert_dir_exists "$MOIRA_HOME/skills" "skills/ exists"
assert_dir_exists "$MOIRA_HOME/hooks" "hooks/ exists"
assert_dir_exists "$MOIRA_HOME/templates/stack-presets" "templates/stack-presets/ exists"
assert_dir_exists "$MOIRA_HOME/lib" "lib/ exists"
assert_dir_exists "$MOIRA_HOME/schemas" "schemas/ exists"

# ── Command stubs ────────────────────────────────────────────────────
commands=(task init status resume knowledge metrics audit bypass refresh help)
for cmd in "${commands[@]}"; do
  assert_file_exists "$COMMANDS_DIR/${cmd}.md" "command ${cmd}.md exists"
done

# ── Command frontmatter ──────────────────────────────────────────────
for cmd in "${commands[@]}"; do
  cmd_file="$COMMANDS_DIR/${cmd}.md"
  if [[ -f "$cmd_file" ]]; then
    assert_file_contains "$cmd_file" "^name: moira:" "${cmd}.md has name: moira:* in frontmatter"
    assert_file_contains "$cmd_file" "allowed-tools:" "${cmd}.md has allowed-tools in frontmatter"
  fi
done

test_summary
