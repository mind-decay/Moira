#!/usr/bin/env bash
# test-metrics-audit.sh — Tier 1: Metrics and audit system structural tests
# Source: Phase 11 spec D9

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"

# Derive SRC_DIR: if MOIRA_HOME points to src/global, SRC_DIR is src/
if [[ -d "$MOIRA_HOME/lib" && ! -d "$MOIRA_HOME/schemas" && -d "$(dirname "$MOIRA_HOME")/schemas" ]]; then
  SRC_DIR="$(dirname "$MOIRA_HOME")"
else
  SRC_DIR="$MOIRA_HOME"
fi

echo "=== Metrics & Audit System ==="

# ── Metrics schema ────────────────────────────────────────────────────
assert_file_exists "$SRC_DIR/schemas/metrics.schema.yaml" "metrics.schema.yaml exists"
assert_file_contains "$SRC_DIR/schemas/metrics.schema.yaml" "_meta:" "metrics schema has _meta block"
assert_file_contains "$SRC_DIR/schemas/metrics.schema.yaml" "name: metrics" "metrics schema has correct name"

# ── Audit schema ──────────────────────────────────────────────────────
assert_file_exists "$SRC_DIR/schemas/audit.schema.yaml" "audit.schema.yaml exists"
assert_file_contains "$SRC_DIR/schemas/audit.schema.yaml" "_meta:" "audit schema has _meta block"
assert_file_contains "$SRC_DIR/schemas/audit.schema.yaml" "name: audit" "audit schema has correct name"

# ── Audit templates ───────────────────────────────────────────────────
TEMPLATE_DIR="$MOIRA_HOME/templates/audit"
assert_dir_exists "$TEMPLATE_DIR" "audit templates directory exists"

# All 12 templates
for template in rules-light rules-standard rules-deep \
                knowledge-light knowledge-standard knowledge-deep \
                agents-standard agents-deep \
                config-standard config-deep \
                consistency-standard consistency-deep; do
  assert_file_exists "$TEMPLATE_DIR/${template}.md" "template ${template}.md exists"
done

# ── Metrics command is not a placeholder ──────────────────────────────
CMD_DIR="$HOME/.claude/commands/moira"
if [[ -f "$CMD_DIR/metrics.md" ]]; then
  if grep -q "will be implemented in Phase 11" "$CMD_DIR/metrics.md" 2>/dev/null; then
    fail "metrics.md is still a placeholder"
  else
    pass "metrics.md is not a placeholder"
  fi
else
  fail "metrics.md command not found"
fi

# ── Audit command is not a placeholder ────────────────────────────────
if [[ -f "$CMD_DIR/audit.md" ]]; then
  if grep -q "will be implemented in Phase 11" "$CMD_DIR/audit.md" 2>/dev/null; then
    fail "audit.md is still a placeholder"
  else
    pass "audit.md is not a placeholder"
  fi
else
  fail "audit.md command not found"
fi

# ── metrics.sh library ────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/metrics.sh" "lib/metrics.sh exists"
if [[ -f "$MOIRA_HOME/lib/metrics.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/metrics.sh" 2>/dev/null; then
    pass "metrics.sh has valid bash syntax"
  else
    fail "metrics.sh has syntax errors"
  fi

  # Check expected functions
  for func in moira_metrics_collect_task moira_metrics_aggregate_monthly moira_metrics_dashboard moira_metrics_drilldown moira_metrics_compare moira_metrics_export; do
    assert_file_contains "$MOIRA_HOME/lib/metrics.sh" "$func" "metrics.sh defines $func"
  done

  # Check sources yaml-utils.sh
  assert_file_contains "$MOIRA_HOME/lib/metrics.sh" "yaml-utils.sh" "metrics.sh sources yaml-utils.sh"
fi

# ── audit.sh library ─────────────────────────────────────────────────
assert_file_exists "$MOIRA_HOME/lib/audit.sh" "lib/audit.sh exists"
if [[ -f "$MOIRA_HOME/lib/audit.sh" ]]; then
  if bash -n "$MOIRA_HOME/lib/audit.sh" 2>/dev/null; then
    pass "audit.sh has valid bash syntax"
  else
    fail "audit.sh has syntax errors"
  fi

  # Check expected functions
  for func in moira_audit_check_trigger moira_audit_select_templates moira_audit_parse_findings moira_audit_generate_report moira_audit_format_recommendations; do
    assert_file_contains "$MOIRA_HOME/lib/audit.sh" "$func" "audit.sh defines $func"
  done

  # Check sources yaml-utils.sh
  assert_file_contains "$MOIRA_HOME/lib/audit.sh" "yaml-utils.sh" "audit.sh sources yaml-utils.sh"
fi

test_summary
