#!/usr/bin/env bash
# test-fn-yaml-utils.sh — Functional tests for yaml-utils.sh
# Tests moira_yaml_get, moira_yaml_set, moira_yaml_validate,
# moira_yaml_init, moira_yaml_block_append with real data.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: yaml-utils.sh (functional)"

# Source the library under test
source "$SRC_LIB_DIR/yaml-utils.sh"
set +e

# ── moira_yaml_get: depth 1 ─────────────────────────────────────────

cat > "$TEMP_DIR/simple.yaml" << 'EOF'
name: moira
version: 1.0
enabled: true
count: 42
empty_val: null
tilde_val: ~
EOF

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "name"
assert_exit_zero "get depth-1: exit 0"
assert_output_equals "$FN_STDOUT" "moira" "get depth-1: string value"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "version"
assert_output_equals "$FN_STDOUT" "1.0" "get depth-1: numeric value"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "enabled"
assert_output_equals "$FN_STDOUT" "true" "get depth-1: boolean value"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "count"
assert_output_equals "$FN_STDOUT" "42" "get depth-1: integer value"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "empty_val"
assert_output_empty "$FN_STDOUT" "get depth-1: null returns empty"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "tilde_val"
assert_output_empty "$FN_STDOUT" "get depth-1: tilde returns empty"

run_fn moira_yaml_get "$TEMP_DIR/simple.yaml" "nonexistent"
assert_exit_nonzero "get depth-1: missing key returns exit 1"

# ── moira_yaml_get: depth 2 ─────────────────────────────────────────

cat > "$TEMP_DIR/nested.yaml" << 'EOF'
project:
  name: myapp
  stack: typescript
budgets:
  max_load: 70
EOF

run_fn moira_yaml_get "$TEMP_DIR/nested.yaml" "project.name"
assert_output_equals "$FN_STDOUT" "myapp" "get depth-2: nested string"

run_fn moira_yaml_get "$TEMP_DIR/nested.yaml" "project.stack"
assert_output_equals "$FN_STDOUT" "typescript" "get depth-2: nested string 2"

run_fn moira_yaml_get "$TEMP_DIR/nested.yaml" "budgets.max_load"
assert_output_equals "$FN_STDOUT" "70" "get depth-2: nested number"

run_fn moira_yaml_get "$TEMP_DIR/nested.yaml" "project.missing"
assert_exit_nonzero "get depth-2: missing child returns exit 1"

# ── moira_yaml_get: depth 3 ─────────────────────────────────────────

cat > "$TEMP_DIR/deep.yaml" << 'EOF'
budgets:
  per_agent:
    classifier: 20000
    explorer: 140000
EOF

run_fn moira_yaml_get "$TEMP_DIR/deep.yaml" "budgets.per_agent.classifier"
assert_output_equals "$FN_STDOUT" "20000" "get depth-3: deep nested value"

run_fn moira_yaml_get "$TEMP_DIR/deep.yaml" "budgets.per_agent.explorer"
assert_output_equals "$FN_STDOUT" "140000" "get depth-3: deep nested value 2"

run_fn moira_yaml_get "$TEMP_DIR/deep.yaml" "budgets.per_agent.missing"
assert_exit_nonzero "get depth-3: missing key returns exit 1"

# ── moira_yaml_get: inline arrays ────────────────────────────────────

cat > "$TEMP_DIR/arrays.yaml" << 'EOF'
tags: [alpha, beta, gamma]
EOF

run_fn moira_yaml_get "$TEMP_DIR/arrays.yaml" "tags"
assert_output_equals "$FN_STDOUT" "alpha,beta,gamma" "get: inline array returns csv"

# ── moira_yaml_get: quoted strings ───────────────────────────────────

cat > "$TEMP_DIR/quoted.yaml" << 'EOF'
message: "hello world"
single: 'test value'
EOF

run_fn moira_yaml_get "$TEMP_DIR/quoted.yaml" "message"
assert_output_equals "$FN_STDOUT" "hello world" "get: double-quoted string unquoted"

run_fn moira_yaml_get "$TEMP_DIR/quoted.yaml" "single"
assert_output_equals "$FN_STDOUT" "test value" "get: single-quoted string unquoted"

# ── moira_yaml_get: comments ─────────────────────────────────────────

cat > "$TEMP_DIR/comments.yaml" << 'EOF'
# This is a comment
name: value  # inline comment
# Another comment
count: 5
EOF

run_fn moira_yaml_get "$TEMP_DIR/comments.yaml" "name"
assert_output_equals "$FN_STDOUT" "value" "get: ignores comments"

run_fn moira_yaml_get "$TEMP_DIR/comments.yaml" "count"
assert_output_equals "$FN_STDOUT" "5" "get: reads past comment lines"

# ── moira_yaml_get: nonexistent file ─────────────────────────────────

run_fn moira_yaml_get "$TEMP_DIR/nonexistent.yaml" "key"
assert_exit_nonzero "get: nonexistent file returns exit 1"

# ── moira_yaml_set: depth 1 replace ─────────────────────────────────

cat > "$TEMP_DIR/set-test.yaml" << 'EOF'
name: old
count: 10
EOF

moira_yaml_set "$TEMP_DIR/set-test.yaml" "name" "new"
run_fn moira_yaml_get "$TEMP_DIR/set-test.yaml" "name"
assert_output_equals "$FN_STDOUT" "new" "set depth-1: replace string"

moira_yaml_set "$TEMP_DIR/set-test.yaml" "count" "99"
run_fn moira_yaml_get "$TEMP_DIR/set-test.yaml" "count"
assert_output_equals "$FN_STDOUT" "99" "set depth-1: replace number"

# ── moira_yaml_set: depth 1 append ──────────────────────────────────

moira_yaml_set "$TEMP_DIR/set-test.yaml" "new_key" "appended"
run_fn moira_yaml_get "$TEMP_DIR/set-test.yaml" "new_key"
assert_output_equals "$FN_STDOUT" "appended" "set depth-1: append new key"

# ── moira_yaml_set: depth 2 ─────────────────────────────────────────

cat > "$TEMP_DIR/set-nested.yaml" << 'EOF'
project:
  name: old
  stack: generic
EOF

moira_yaml_set "$TEMP_DIR/set-nested.yaml" "project.name" "updated"
run_fn moira_yaml_get "$TEMP_DIR/set-nested.yaml" "project.name"
assert_output_equals "$FN_STDOUT" "updated" "set depth-2: replace nested value"

moira_yaml_set "$TEMP_DIR/set-nested.yaml" "project.version" "2.0"
run_fn moira_yaml_get "$TEMP_DIR/set-nested.yaml" "project.version"
assert_output_equals "$FN_STDOUT" "2.0" "set depth-2: append new nested key"

# ── moira_yaml_set: depth 3 ─────────────────────────────────────────

cat > "$TEMP_DIR/set-deep.yaml" << 'EOF'
budgets:
  per_agent:
    classifier: 20000
EOF

moira_yaml_set "$TEMP_DIR/set-deep.yaml" "budgets.per_agent.classifier" "30000"
run_fn moira_yaml_get "$TEMP_DIR/set-deep.yaml" "budgets.per_agent.classifier"
assert_output_equals "$FN_STDOUT" "30000" "set depth-3: replace deep value"

moira_yaml_set "$TEMP_DIR/set-deep.yaml" "budgets.per_agent.explorer" "140000"
run_fn moira_yaml_get "$TEMP_DIR/set-deep.yaml" "budgets.per_agent.explorer"
assert_output_equals "$FN_STDOUT" "140000" "set depth-3: append new deep key"

# ── moira_yaml_set: value formatting ─────────────────────────────────

cat > "$TEMP_DIR/format.yaml" << 'EOF'
a: placeholder
EOF

moira_yaml_set "$TEMP_DIR/format.yaml" "bool_true" "true"
run_fn moira_yaml_get "$TEMP_DIR/format.yaml" "bool_true"
assert_output_equals "$FN_STDOUT" "true" "set: boolean true preserved"

moira_yaml_set "$TEMP_DIR/format.yaml" "bool_false" "false"
run_fn moira_yaml_get "$TEMP_DIR/format.yaml" "bool_false"
assert_output_equals "$FN_STDOUT" "false" "set: boolean false preserved"

moira_yaml_set "$TEMP_DIR/format.yaml" "null_val" "null"
run_fn moira_yaml_get "$TEMP_DIR/format.yaml" "null_val"
assert_output_empty "$FN_STDOUT" "set: null value roundtrips to empty"

moira_yaml_set "$TEMP_DIR/format.yaml" "special" "value:with:colons"
run_fn moira_yaml_get "$TEMP_DIR/format.yaml" "special"
assert_output_equals "$FN_STDOUT" "value:with:colons" "set: special chars auto-quoted roundtrip"

# ── moira_yaml_set: nonexistent file ─────────────────────────────────

run_fn moira_yaml_set "$TEMP_DIR/no-such-file.yaml" "key" "val"
assert_exit_nonzero "set: nonexistent file returns exit 1"

# ── moira_yaml_validate: valid file ──────────────────────────────────

moira_yaml_init "current" "$TEMP_DIR/valid-current.yaml" 2>/dev/null
run_fn moira_yaml_validate "$TEMP_DIR/valid-current.yaml" "current"
assert_exit_zero "validate: valid file passes"

# ── moira_yaml_validate: missing schema ──────────────────────────────

run_fn moira_yaml_validate "$TEMP_DIR/valid-current.yaml" "nonexistent-schema"
assert_exit_nonzero "validate: missing schema returns exit 1"

# ── moira_yaml_validate: missing file ────────────────────────────────

run_fn moira_yaml_validate "$TEMP_DIR/no-such-file.yaml" "current"
assert_exit_nonzero "validate: missing file returns exit 1"

# ── moira_yaml_init: creates valid file ──────────────────────────────

moira_yaml_init "config" "$TEMP_DIR/init-config.yaml" 2>/dev/null
assert_file_exists "$TEMP_DIR/init-config.yaml" "init: creates config.yaml"

run_fn moira_yaml_validate "$TEMP_DIR/init-config.yaml" "config"
assert_exit_zero "init: created file validates against schema"

# ── moira_yaml_init: missing schema ──────────────────────────────────

run_fn moira_yaml_init "nonexistent-schema" "$TEMP_DIR/bad-init.yaml"
assert_exit_nonzero "init: missing schema returns exit 1"

# ── moira_yaml_block_append: depth 1 ────────────────────────────────

cat > "$TEMP_DIR/block.yaml" << 'EOF'
task_id: test-001
history:
  - step: classification
    status: completed
EOF

block_entry="  - step: exploration
    status: completed"

moira_yaml_block_append "$TEMP_DIR/block.yaml" "history" "$block_entry"
assert_file_contains "$TEMP_DIR/block.yaml" "exploration" "block_append depth-1: appends entry"
assert_file_contains "$TEMP_DIR/block.yaml" "classification" "block_append depth-1: preserves existing"

# ── moira_yaml_block_append: replaces [] ─────────────────────────────

cat > "$TEMP_DIR/empty-block.yaml" << 'EOF'
task_id: test-002
gates: []
EOF

gate_entry="  - gate: classification
    decision: proceed"

moira_yaml_block_append "$TEMP_DIR/empty-block.yaml" "gates" "$gate_entry"
assert_file_contains "$TEMP_DIR/empty-block.yaml" "classification" "block_append: replaces [] and appends"

# Verify [] is gone
run_fn grep -c '\[\]' "$TEMP_DIR/empty-block.yaml"
assert_output_equals "$FN_STDOUT" "0" "block_append: [] removed from file"

# ── moira_yaml_block_append: depth 2 ────────────────────────────────

cat > "$TEMP_DIR/nested-block.yaml" << 'EOF'
budget:
  estimated_tokens: 50000
  by_agent:
    - role: explorer
      actual: 30000
EOF

nested_entry="    - role: reviewer
      actual: 20000"

moira_yaml_block_append "$TEMP_DIR/nested-block.yaml" "budget.by_agent" "$nested_entry"
assert_file_contains "$TEMP_DIR/nested-block.yaml" "reviewer" "block_append depth-2: appends nested entry"
assert_file_contains "$TEMP_DIR/nested-block.yaml" "explorer" "block_append depth-2: preserves existing entry"

# ── moira_yaml_block_append: nonexistent file ────────────────────────

run_fn moira_yaml_block_append "$TEMP_DIR/no-file.yaml" "history" "  - step: test"
assert_exit_nonzero "block_append: nonexistent file returns exit 1"

# ── moira_yaml_set: depth 3 append when parents don't exist ──────────
# Regression: yaml_set 3-level key failed silently when parent keys absent

cat > "$TEMP_DIR/empty-parents.yaml" << 'EOF'
# Stats file
version: 1
EOF

moira_yaml_set "$TEMP_DIR/empty-parents.yaml" "E5_QUALITY.reviewer.probability" "80"
run_fn moira_yaml_get "$TEMP_DIR/empty-parents.yaml" "E5_QUALITY.reviewer.probability"
assert_output_equals "$FN_STDOUT" "80" "set depth-3: creates parent keys when absent"

# Also test: p1 exists but p2 doesn't
cat > "$TEMP_DIR/partial-parents.yaml" << 'EOF'
E5_QUALITY:
  implementer:
    probability: 50
EOF

moira_yaml_set "$TEMP_DIR/partial-parents.yaml" "E5_QUALITY.reviewer.probability" "75"
run_fn moira_yaml_get "$TEMP_DIR/partial-parents.yaml" "E5_QUALITY.reviewer.probability"
assert_output_equals "$FN_STDOUT" "75" "set depth-3: creates p2 when p1 exists but p2 absent"

# Verify existing sibling not corrupted
run_fn moira_yaml_get "$TEMP_DIR/partial-parents.yaml" "E5_QUALITY.implementer.probability"
assert_output_equals "$FN_STDOUT" "50" "set depth-3: preserves sibling keys"

# ── Roundtrip: init → set → get → validate ──────────────────────────

moira_yaml_init "status" "$TEMP_DIR/roundtrip.yaml" 2>/dev/null
moira_yaml_set "$TEMP_DIR/roundtrip.yaml" "status" "in_progress"
run_fn moira_yaml_get "$TEMP_DIR/roundtrip.yaml" "status"
assert_output_equals "$FN_STDOUT" "in_progress" "roundtrip: init→set→get preserves value"

run_fn moira_yaml_validate "$TEMP_DIR/roundtrip.yaml" "status"
assert_exit_zero "roundtrip: modified file still validates"

test_summary
