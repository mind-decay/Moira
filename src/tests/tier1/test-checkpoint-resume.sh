#!/usr/bin/env bash
# test-checkpoint-resume.sh — Verify checkpoint/resume system artifacts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
SRC_DIR="$(cd "$SCRIPT_DIR/../../" && pwd)"

# ── checkpoint.sh existence ──────────────────────────────────────────
assert_file_exists "$SRC_DIR/global/lib/checkpoint.sh" "checkpoint.sh exists in src"
assert_file_exists "$MOIRA_HOME/lib/checkpoint.sh" "checkpoint.sh exists in MOIRA_HOME"

# ── checkpoint.sh functions ──────────────────────────────────────────
for func in moira_checkpoint_create moira_checkpoint_validate moira_checkpoint_build_resume_context moira_checkpoint_cleanup; do
  if grep -q "$func" "$SRC_DIR/global/lib/checkpoint.sh" 2>/dev/null; then
    pass "checkpoint.sh defines $func"
  else
    fail "checkpoint.sh missing function: $func"
  fi
done

# ── checkpoint.sh syntax ────────────────────────────────────────────
if bash -n "$SRC_DIR/global/lib/checkpoint.sh" 2>/dev/null; then
  pass "checkpoint.sh has valid bash syntax"
else
  fail "checkpoint.sh has syntax errors"
fi

# ── manifest.schema.yaml checkpoint fields ───────────────────────────
manifest_schema="$MOIRA_HOME/schemas/manifest.schema.yaml"
if [[ ! -f "$manifest_schema" ]]; then
  manifest_schema="$SRC_DIR/global/schemas/manifest.schema.yaml"
fi
assert_file_exists "$manifest_schema" "manifest.schema.yaml exists"
assert_file_contains "$manifest_schema" "checkpoint.step" "manifest schema has checkpoint.step"
assert_file_contains "$manifest_schema" "checkpoint.reason" "manifest schema has checkpoint.reason"
assert_file_contains "$manifest_schema" "validation.git_branch" "manifest schema has validation.git_branch"

# ── resume.md is not a placeholder ──────────────────────────────────
resume_cmd="$HOME/.claude/commands/moira/resume.md"
if [[ ! -f "$resume_cmd" ]]; then
  resume_cmd="$SRC_DIR/commands/moira/resume.md"
fi
assert_file_exists "$resume_cmd" "resume.md command exists"
if grep -qi "Phase 12" "$resume_cmd" 2>/dev/null || grep -qi "will be implemented" "$resume_cmd" 2>/dev/null; then
  fail "resume.md appears to be a placeholder"
else
  pass "resume.md is not a placeholder"
fi

# ── resume.md allowed-tools ──────────────────────────────────────────
assert_file_contains "$resume_cmd" "Agent" "resume.md has Agent in allowed-tools"
assert_file_contains "$resume_cmd" "Read" "resume.md has Read in allowed-tools"
assert_file_contains "$resume_cmd" "Write" "resume.md has Write in allowed-tools"

# ── current.schema.yaml step_status includes checkpointed ───────────
current_schema="$MOIRA_HOME/schemas/current.schema.yaml"
if [[ ! -f "$current_schema" ]]; then
  current_schema="$SRC_DIR/global/schemas/current.schema.yaml"
fi
assert_file_exists "$current_schema" "current.schema.yaml exists"
assert_file_contains "$current_schema" "checkpointed" "current.schema.yaml step_status includes checkpointed"

# ── state.sh valid_statuses includes checkpointed ───────────────────
state_lib="$MOIRA_HOME/lib/state.sh"
if [[ ! -f "$state_lib" ]]; then
  state_lib="$SRC_DIR/global/lib/state.sh"
fi
assert_file_exists "$state_lib" "state.sh exists"
assert_file_contains "$state_lib" "checkpointed" "state.sh valid_statuses includes checkpointed"

test_summary
