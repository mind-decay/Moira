#!/usr/bin/env bash
# test-fn-preflight-assemble.sh — Functional tests for preflight-assemble.sh
# Tests instruction assembly for Apollo, Hermes, Athena with real role files.
# Validates the role→agent name mapping that was broken (D-229).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers-functional.sh"

echo "Testing: preflight-assemble.sh (functional)"

# ── Setup: create minimal MOIRA_HOME with role files and base rules ──

mkdir -p "$MOIRA_HOME/core/rules/roles"
mkdir -p "$MOIRA_HOME/core/pipelines"

# Create minimal base.yaml
cat > "$MOIRA_HOME/core/rules/base.yaml" << 'EOF'
version: "1.0"
rules:
  - "Follow design docs"
EOF

# Create minimal knowledge-matrix.yaml
cat > "$MOIRA_HOME/core/rules/knowledge-matrix.yaml" << 'EOF'
matrix:
  apollo: ["stack"]
  hermes: ["stack"]
  athena: ["stack"]
EOF

# Create role files (named by AGENT NAME, not role name — this is the contract)
cat > "$MOIRA_HOME/core/rules/roles/apollo.yaml" << 'EOF'
_meta:
  role: classifier
identity: |
  You are Apollo, the classifier agent.
never:
  - "Skip classification"
quality_checklist: "classification-checklist"
budget: 20000
EOF

cat > "$MOIRA_HOME/core/rules/roles/hermes.yaml" << 'EOF'
_meta:
  role: explorer
identity: |
  You are Hermes, the explorer agent.
never:
  - "Modify files"
quality_checklist: "exploration-checklist"
budget: 140000
EOF

cat > "$MOIRA_HOME/core/rules/roles/athena.yaml" << 'EOF'
_meta:
  role: analyst
identity: |
  You are Athena, the analyst agent.
never:
  - "Execute code"
quality_checklist: "analysis-checklist"
budget: 80000
EOF

# Source the library under test
source "$SRC_LIB_DIR/preflight-assemble.sh"
set +e

# ── Setup: create task state ─────────────────────────────────────────

TASK_STATE="$TEMP_DIR/state"
TASK_ID="test-task-001"
TASK_DIR="$TASK_STATE/tasks/$TASK_ID"
mkdir -p "$TASK_DIR/instructions"
mkdir -p "$TASK_STATE/../config/rules"
mkdir -p "$TASK_STATE/../knowledge"

# Create input.md (required by all assemblies)
cat > "$TASK_DIR/input.md" << 'EOF'
# Task Input
Implement user authentication for the API
EOF

# Create classification.md (used by exploration assembly)
cat > "$TASK_DIR/classification.md" << 'EOF'
# Classification
Pipeline: standard
Size: medium
EOF

# ═══════════════════════════════════════════════════════════════════════
# TEST: moira_preflight_assemble_apollo — basic assembly
# ═══════════════════════════════════════════════════════════════════════

run_fn moira_preflight_assemble_apollo "$TASK_ID" "$TASK_STATE"
assert_exit_zero "apollo: assembly succeeds"

output_file="$TASK_DIR/instructions/apollo.md"
if [[ -f "$output_file" && -s "$output_file" ]]; then
  pass "apollo: instruction file created and non-empty"
else
  fail "apollo: instruction file missing or empty at $output_file"
fi

# Verify content includes role identity
if grep -q "classifier" "$output_file" 2>/dev/null; then
  pass "apollo: instruction contains classifier identity"
else
  fail "apollo: instruction should contain classifier identity"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: moira_preflight_assemble_agent with AGENT NAME (hermes)
# ═══════════════════════════════════════════════════════════════════════

# Clean up previous output
rm -f "$TASK_DIR/instructions/hermes.md"

run_fn moira_preflight_assemble_agent "hermes" "$TASK_ID" "$TASK_STATE"
assert_exit_zero "hermes: assembly with agent name succeeds"

hermes_file="$TASK_DIR/instructions/hermes.md"
if [[ -f "$hermes_file" && -s "$hermes_file" ]]; then
  pass "hermes: instruction file created"
else
  fail "hermes: instruction file missing or empty at $hermes_file"
fi

# Verify classification context was included
if grep -q "standard" "$hermes_file" 2>/dev/null; then
  pass "hermes: instruction includes classification context"
else
  fail "hermes: instruction should include classification.md content"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: moira_preflight_assemble_agent with ROLE NAME (explorer) — THIS
# WAS THE BUG. Before D-229 fix, this would silently fail because it
# looked for roles/explorer.yaml which doesn't exist.
# ═══════════════════════════════════════════════════════════════════════

rm -f "$TASK_DIR/instructions/explorer.md"

run_fn moira_preflight_assemble_agent "explorer" "$TASK_ID" "$TASK_STATE"
# This SHOULD fail — role files are named by agent name, not role name.
# The caller (pipeline-dispatch.sh) is responsible for mapping role→agent.
assert_exit_nonzero "explorer: assembly with role name correctly fails"

if [[ ! -f "$TASK_DIR/instructions/explorer.md" ]] || [[ ! -s "$TASK_DIR/instructions/explorer.md" ]]; then
  pass "explorer: no instruction file created (correct — role name not valid)"
else
  fail "explorer: should NOT create instruction for role name 'explorer'"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: moira_preflight_assemble_agent with athena (agent name)
# ═══════════════════════════════════════════════════════════════════════

rm -f "$TASK_DIR/instructions/athena.md"

run_fn moira_preflight_assemble_agent "athena" "$TASK_ID" "$TASK_STATE"
assert_exit_zero "athena: assembly with agent name succeeds"

athena_file="$TASK_DIR/instructions/athena.md"
if [[ -f "$athena_file" && -s "$athena_file" ]]; then
  pass "athena: instruction file created"
else
  fail "athena: instruction file missing or empty"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: moira_preflight_assemble_exploration — assembles both
# ═══════════════════════════════════════════════════════════════════════

# Clean up
rm -f "$TASK_DIR/instructions/hermes.md"
rm -f "$TASK_DIR/instructions/athena.md"

run_fn moira_preflight_assemble_exploration "$TASK_ID" "$TASK_STATE"
assert_exit_zero "exploration: batch assembly succeeds"

if [[ -f "$TASK_DIR/instructions/hermes.md" && -s "$TASK_DIR/instructions/hermes.md" ]]; then
  pass "exploration: hermes instruction assembled"
else
  fail "exploration: hermes instruction missing"
fi

if [[ -f "$TASK_DIR/instructions/athena.md" && -s "$TASK_DIR/instructions/athena.md" ]]; then
  pass "exploration: athena instruction assembled"
else
  fail "exploration: athena instruction missing"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: assembly fails gracefully with missing input.md
# ═══════════════════════════════════════════════════════════════════════

EMPTY_TASK="test-task-empty"
mkdir -p "$TASK_STATE/tasks/$EMPTY_TASK/instructions"
# No input.md created

run_fn moira_preflight_assemble_apollo "$EMPTY_TASK" "$TASK_STATE"
assert_exit_nonzero "missing input.md: apollo fails with non-zero"

if [[ ! -f "$TASK_STATE/tasks/$EMPTY_TASK/instructions/apollo.md" ]] || [[ ! -s "$TASK_STATE/tasks/$EMPTY_TASK/instructions/apollo.md" ]]; then
  pass "missing input.md: no instruction file left behind"
else
  fail "missing input.md: should not create partial instruction"
fi

# ═══════════════════════════════════════════════════════════════════════
# TEST: assembly fails gracefully with missing role file
# ═══════════════════════════════════════════════════════════════════════

run_fn moira_preflight_assemble_agent "nonexistent_agent" "$TASK_ID" "$TASK_STATE"
assert_exit_nonzero "missing role file: fails with non-zero"

# ═══════════════════════════════════════════════════════════════════════
# TEST: tmp context file is cleaned up after assembly
# ═══════════════════════════════════════════════════════════════════════

rm -f "$TASK_DIR/instructions/hermes.md"
moira_preflight_assemble_agent "hermes" "$TASK_ID" "$TASK_STATE" >/dev/null 2>&1 || true
tmp_files=$(find "$TASK_DIR/instructions/" -name '.*.tmp' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$tmp_files" -eq 0 ]]; then
  pass "cleanup: no tmp files left after assembly"
else
  fail "cleanup: $tmp_files tmp files left in instructions/"
fi

test_summary
