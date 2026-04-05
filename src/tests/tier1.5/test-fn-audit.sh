#!/usr/bin/env bash
# test-fn-audit.sh — Functional tests for audit.sh
# Tests trigger check, template selection, findings parsing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: audit.sh (functional)"

source "$SRC_LIB_DIR/audit.sh"
set +e

# ── moira_audit_check_trigger: no tasks → none ──────���───────────────

audit_state="$TEMP_DIR/audit-empty"
mkdir -p "$audit_state"
run_fn moira_audit_check_trigger "$audit_state"
assert_exit_zero "check_trigger: no tasks → exit 0"
assert_output_contains "$FN_STDOUT" "none" "check_trigger: no tasks → none"

# ── moira_audit_check_trigger: below threshold → none ────────────────

audit_state2="$TEMP_DIR/audit-below"
mkdir -p "$audit_state2/tasks"
for i in $(seq 1 5); do mkdir -p "$audit_state2/tasks/task-2026-04-05-$(printf '%03d' $i)"; done
run_fn moira_audit_check_trigger "$audit_state2"
assert_output_contains "$FN_STDOUT" "none" "check_trigger: 5 tasks → none"

# ── moira_audit_check_trigger: with metrics ──────────────────────────

audit_state3="$TEMP_DIR/audit-metrics"
mkdir -p "$audit_state3/metrics"
month=$(date +%Y-%m)
cat > "$audit_state3/metrics/monthly-${month}.yaml" << 'EOF'
tasks:
  total: 10
EOF

run_fn moira_audit_check_trigger "$audit_state3"
# 10th task should trigger light audit
assert_output_contains "$FN_STDOUT" "light" "check_trigger: 10 tasks → light"

# ── moira_audit_select_templates: returns paths ──────────────────────

# Setup template structure matching actual convention
template_dir="$MOIRA_HOME/templates/audit"
mkdir -p "$template_dir"
echo "# Rules light audit" > "$template_dir/rules-light.md"
echo "# Rules standard audit" > "$template_dir/rules-standard.md"

# select_templates returns paths in format: ${MOIRA_HOME}/templates/audit/{domain}-{depth}.md
run_fn moira_audit_select_templates "rules" "light"
assert_exit_zero "select_templates: exit 0"
assert_output_contains "$FN_STDOUT" "rules-light.md" "select_templates: returns correct filename pattern"

# ── moira_audit_parse_findings: structured report ────────────────────

cat > "$TEMP_DIR/audit-report.md" << 'EOF'
# Audit Report

## Findings

### HIGH: Missing NEVER constraint in explorer
- Domain: agents
- Risk: high
- Description: Explorer agent lacks boundary constraint

### MEDIUM: Stale knowledge entry
- Domain: knowledge
- Risk: medium
- Description: conventions knowledge outdated

### LOW: Config default mismatch
- Domain: config
- Risk: low
- Description: config default differs from schema
EOF

run_fn moira_audit_parse_findings "$TEMP_DIR/audit-report.md"
assert_exit_zero "parse_findings: exit 0"
assert_output_contains "$FN_STDOUT" "high" "parse_findings: detects high risk"
assert_output_contains "$FN_STDOUT" "medium" "parse_findings: detects medium risk"

# ── moira_audit_parse_findings: missing file → error ─────────────────

run_fn moira_audit_parse_findings "$TEMP_DIR/nonexistent.md"
assert_exit_nonzero "parse_findings: missing file → exit 1"

test_summary
