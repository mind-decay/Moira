#!/usr/bin/env bash
# test-fn-quality.sh — Functional tests for quality.sh
# Tests verdict parsing, mode management, cooldown, findings validation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: quality.sh (functional)"

source "$SRC_LIB_DIR/quality.sh"
set +e

# ── moira_quality_get_mode: default → conform ───────────────────────

# quality functions take config FILE path (not directory)
QCONFIG="$TEMP_DIR/qconfig.yaml"
cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
EOF

run_fn moira_quality_get_mode "$QCONFIG"
assert_output_equals "$FN_STDOUT" "conform" "get_mode: default → conform"

# ── moira_quality_get_mode: evolve ───────────────────────────────────

moira_yaml_set "$QCONFIG" "quality.mode" "evolve"
run_fn moira_quality_get_mode "$QCONFIG"
assert_output_equals "$FN_STDOUT" "evolve" "get_mode: reads evolve"

# ── moira_quality_get_mode: no config → conform ─────────────────────

run_fn moira_quality_get_mode "$TEMP_DIR/nonexistent.yaml"
assert_output_equals "$FN_STDOUT" "conform" "get_mode: missing config → conform"

# ── moira_quality_check_cooldown: ready when no cooldown ─────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
EOF

run_fn moira_quality_check_cooldown "$QCONFIG"
assert_output_contains "$FN_STDOUT" "ready" "check_cooldown: no cooldown field → ready"

# ── moira_quality_check_cooldown: active cooldown ────────────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
  evolution:
    cooldown_remaining: 3
EOF

run_fn moira_quality_check_cooldown "$QCONFIG"
assert_output_contains "$FN_STDOUT" "cooldown" "check_cooldown: 3 → cooldown"

# ── moira_quality_start_evolve: activates ────────────────────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
  evolution:
    cooldown_remaining: 0
EOF

run_fn moira_quality_start_evolve "$QCONFIG" "naming-conventions"
assert_exit_zero "start_evolve: exit 0 when no cooldown"

mode_val=$(moira_yaml_get "$QCONFIG" "quality.mode" 2>/dev/null) || mode_val=""
assert_equals "$mode_val" "evolve" "start_evolve: sets mode to evolve"

# ── moira_quality_start_evolve: blocked during cooldown ──────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
  evolution:
    cooldown_remaining: 3
EOF

run_fn moira_quality_start_evolve "$QCONFIG" "naming-conventions"
assert_exit_nonzero "start_evolve: blocked during cooldown"

# ── moira_quality_complete_evolve: resets to conform ─────────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: evolve
  evolution:
    cooldown_remaining: 0
EOF

moira_quality_complete_evolve "$QCONFIG"
mode_val=$(moira_yaml_get "$QCONFIG" "quality.mode" 2>/dev/null) || mode_val=""
assert_equals "$mode_val" "conform" "complete_evolve: resets to conform"

# ── moira_quality_tick_cooldown: decrements ──────────────────────────

cat > "$QCONFIG" << 'EOF'
version: 1.0
quality:
  mode: conform
  evolution:
    cooldown_remaining: 3
EOF

moira_quality_tick_cooldown "$QCONFIG"
run_fn moira_quality_check_cooldown "$QCONFIG"
assert_output_contains "$FN_STDOUT" "cooldown" "tick_cooldown: still in cooldown after one tick"

# ── moira_quality_parse_verdict: pass ────────────────────────────────

cat > "$TEMP_DIR/findings-pass.yaml" << 'EOF'
summary:
  critical_count: 0
  warning_count: 0
  suggestion_count: 2
EOF

run_fn moira_quality_parse_verdict "$TEMP_DIR/findings-pass.yaml"
assert_exit_zero "parse_verdict: exit 0"
assert_output_equals "$FN_STDOUT" "pass" "parse_verdict: no criticals/warnings → pass"

# ── moira_quality_parse_verdict: fail on critical ────────────────────

cat > "$TEMP_DIR/findings-fail.yaml" << 'EOF'
summary:
  critical_count: 1
  warning_count: 0
  suggestion_count: 0
EOF

run_fn moira_quality_parse_verdict "$TEMP_DIR/findings-fail.yaml"
assert_output_equals "$FN_STDOUT" "fail_critical" "parse_verdict: critical → fail_critical"

# ── moira_quality_parse_verdict: fail on warnings ────────────────────

cat > "$TEMP_DIR/findings-warn.yaml" << 'EOF'
summary:
  critical_count: 0
  warning_count: 2
  suggestion_count: 1
findings:
  - id: check-1
    severity: warning
    description: "code smell"
  - id: check-2
    severity: warning
    description: "missing test"
EOF

run_fn moira_quality_parse_verdict "$TEMP_DIR/findings-warn.yaml"
assert_output_equals "$FN_STDOUT" "fail_warning" "parse_verdict: warnings → fail_warning"

# ── moira_quality_parse_verdict: missing file → error ────────────────

run_fn moira_quality_parse_verdict "$TEMP_DIR/nonexistent.yaml"
assert_exit_nonzero "parse_verdict: missing file → exit 1"

# ── moira_quality_format_warnings: formats output ────────────────────

# format_warnings expects items: block with severity: warning
cat > "$TEMP_DIR/findings-items.yaml" << 'EOF'
summary:
  critical_count: 0
  warning_count: 1
items:
  - id: W1
    check: "naming convention"
    severity: warning
    detail: "code smell in module"
    evidence: "found in 3 files"
EOF

run_fn moira_quality_format_warnings "$TEMP_DIR/findings-items.yaml"
assert_exit_zero "format_warnings: exit 0"
assert_output_contains "$FN_STDOUT" "naming convention" "format_warnings: includes check description"

test_summary
