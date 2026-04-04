#!/usr/bin/env bash
# test-metrics-retention.sh — Tier 1 tests for metrics retention (D-222)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
SRC_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Testing: Metrics Retention (D-222)"

MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

source "$SRC_DIR/global/lib/completion.sh"
set +e

# ── Setup: create 15 monthly files ──
METRICS_DIR="$TEMP_DIR/metrics"
mkdir -p "$METRICS_DIR"

for m in 01 02 03 04 05 06 07 08 09 10 11 12; do
  cat > "$METRICS_DIR/monthly-2025-${m}.yaml" << EOF
period: "2025-${m}"
tasks:
  total: $((10#$m * 3))
quality:
  first_pass_accepted: $((10#$m * 2))
EOF
done
for m in 01 02 03; do
  cat > "$METRICS_DIR/monthly-2026-${m}.yaml" << EOF
period: "2026-${m}"
tasks:
  total: $((10#$m * 5))
quality:
  first_pass_accepted: $((10#$m * 4))
EOF
done

# ── 1. Aggregation: 15 files, retention=12 → 3 oldest aggregated ──
moira_metrics_retention "$METRICS_DIR" 12

remaining=$(ls "$METRICS_DIR"/monthly-*.yaml 2>/dev/null | wc -l | tr -d ' ')
assert_equals "$remaining" "12" "retention: 12 monthly files remain after aggregation"

assert_file_exists "$METRICS_DIR/annual-2025.yaml" "retention: annual-2025.yaml created"

# ── 2. Annual file format correct ──
assert_file_contains "$METRICS_DIR/annual-2025.yaml" "year: 2025" "annual format: year header"
assert_file_contains "$METRICS_DIR/annual-2025.yaml" 'period: "2025-01"' "annual format: first period present"
assert_file_contains "$METRICS_DIR/annual-2025.yaml" "tasks_total:" "annual format: tasks_total field"
assert_file_contains "$METRICS_DIR/annual-2025.yaml" "composite_score:" "annual format: composite_score field"

# ── 3. Oldest files deleted ──
if [[ ! -f "$METRICS_DIR/monthly-2025-01.yaml" ]]; then
  pass "aggregation: oldest monthly file deleted"
else
  fail "aggregation: monthly-2025-01.yaml should be deleted"
fi

# ── 4. Recent files preserved ──
assert_file_exists "$METRICS_DIR/monthly-2026-03.yaml" "aggregation: recent file preserved"

# ── 5. Idempotency: double-aggregate same month ──
moira_metrics_retention "$METRICS_DIR" 12
# Count period entries in annual file — should not have duplicates
period_count=$(grep -c 'period:' "$METRICS_DIR/annual-2025.yaml" 2>/dev/null) || period_count=0
assert_equals "$period_count" "3" "idempotency: no duplicate periods after double aggregation"

# ── 6. Count ≤ retention → no-op ──
METRICS2="$TEMP_DIR/metrics2"
mkdir -p "$METRICS2"
for m in 01 02 03; do
  echo "period: 2026-${m}" > "$METRICS2/monthly-2026-${m}.yaml"
done
moira_metrics_retention "$METRICS2" 12
if [[ ! -f "$METRICS2/annual-2026.yaml" ]]; then
  pass "no-op: count ≤ retention, no annual file created"
else
  fail "no-op: should not aggregate when count <= retention"
fi

# ── 7. Partial year append ──
# Create situation: annual-2025 already has Jan-Mar, now aggregate Apr
METRICS3="$TEMP_DIR/metrics3"
mkdir -p "$METRICS3"
cat > "$METRICS3/annual-2025.yaml" << 'EOF'
year: 2025
months:
  - period: "2025-01"
    tasks_total: 3
    composite_score: 66
  - period: "2025-02"
    tasks_total: 6
    composite_score: 66
  - period: "2025-03"
    tasks_total: 9
    composite_score: 66
EOF
# Create 13 monthly files (retention=12 means 1 needs aggregation)
for m in 04 05 06 07 08 09 10 11 12; do
  echo -e "period: \"2025-${m}\"\ntasks:\n  total: 10\nquality:\n  first_pass_accepted: 8" > "$METRICS3/monthly-2025-${m}.yaml"
done
for m in 01 02 03 04; do
  echo -e "period: \"2026-${m}\"\ntasks:\n  total: 10\nquality:\n  first_pass_accepted: 8" > "$METRICS3/monthly-2026-${m}.yaml"
done
moira_metrics_retention "$METRICS3" 12
assert_file_contains "$METRICS3/annual-2025.yaml" 'period: "2025-04"' "partial year: April appended to existing annual"

test_summary
