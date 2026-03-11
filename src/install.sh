#!/usr/bin/env bash
# install.sh — Moira installation script
# Copies system files to ~/.claude/moira/ and ~/.claude/commands/moira/
# No runtime dependencies beyond bash 3+, git, claude CLI.
# Idempotent — re-run overwrites core files, preserves project state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOIRA_HOME="${MOIRA_HOME:-$HOME/.claude/moira}"
MOIRA_VERSION=$(cat "$SCRIPT_DIR/.version" 2>/dev/null || echo "unknown")

# ── Banner ────────────────────────────────────────────────────────────
echo "======================================="
echo "  Installing Moira v${MOIRA_VERSION}"
echo "======================================="
echo ""

# ── Step 1: Check prerequisites ──────────────────────────────────────
check_prerequisites() {
  local errors=0

  if ! command -v claude &> /dev/null; then
    echo "[ERROR] Claude Code CLI not found."
    echo "  Install: https://docs.anthropic.com/claude-code"
    ((errors++))
  fi

  if ! command -v git &> /dev/null; then
    echo "[ERROR] git not found."
    ((errors++))
  fi

  # Check bash version >= 3
  if [[ "${BASH_VERSINFO[0]}" -lt 3 ]]; then
    echo "[ERROR] bash 3+ required (found: ${BASH_VERSION})"
    ((errors++))
  fi

  if [[ $errors -gt 0 ]]; then
    echo ""
    echo "Prerequisites not met. Fix the above errors and retry."
    exit 1
  fi

  echo "[OK] Prerequisites met"
}

# ── Step 2: Install global layer ──────────────────────────────────────
install_global() {
  echo "  Installing global layer to $MOIRA_HOME..."

  # Source scaffold to create directory structure
  source "$SCRIPT_DIR/global/lib/scaffold.sh"
  moira_scaffold_global "$MOIRA_HOME"

  # Copy lib/ utilities
  cp -f "$SCRIPT_DIR/global/lib/"*.sh "$MOIRA_HOME/lib/"

  # Copy core files (Phase 2)
  cp -f "$SCRIPT_DIR/global/core/rules/base.yaml" "$MOIRA_HOME/core/rules/"
  cp -f "$SCRIPT_DIR/global/core/knowledge-access-matrix.yaml" "$MOIRA_HOME/core/"
  cp -f "$SCRIPT_DIR/global/core/response-contract.yaml" "$MOIRA_HOME/core/"

  # Copy role and quality rules (required since Phase 2)
  cp -f "$SCRIPT_DIR/global/core/rules/roles/"*.yaml "$MOIRA_HOME/core/rules/roles/"
  cp -f "$SCRIPT_DIR/global/core/rules/quality/"*.yaml "$MOIRA_HOME/core/rules/quality/"

  # Copy optional directories (don't fail if empty — populated in later phases)
  if ls "$SCRIPT_DIR/global/skills/"* &>/dev/null; then
    cp -f "$SCRIPT_DIR/global/skills/"* "$MOIRA_HOME/skills/" 2>/dev/null || true
  fi
  if ls "$SCRIPT_DIR/global/hooks/"* &>/dev/null; then
    cp -f "$SCRIPT_DIR/global/hooks/"* "$MOIRA_HOME/hooks/" 2>/dev/null || true
  fi
  if ls "$SCRIPT_DIR/global/templates/stack-presets/"* &>/dev/null; then
    cp -f "$SCRIPT_DIR/global/templates/stack-presets/"* "$MOIRA_HOME/templates/stack-presets/" 2>/dev/null || true
  fi

  # Write version marker
  echo "$MOIRA_VERSION" > "$MOIRA_HOME/.version"

  echo "[OK] Global layer installed"
}

# ── Step 3: Install commands ──────────────────────────────────────────
install_commands() {
  echo "  Installing Moira commands..."

  mkdir -p "$HOME/.claude/commands/moira"
  cp -f "$SCRIPT_DIR/commands/moira/"*.md "$HOME/.claude/commands/moira/"

  echo "[OK] Commands installed"
}

# ── Step 4: Install schemas ──────────────────────────────────────────
install_schemas() {
  echo "  Installing schemas..."

  mkdir -p "$MOIRA_HOME/schemas"
  cp -f "$SCRIPT_DIR/schemas/"*.yaml "$MOIRA_HOME/schemas/"

  echo "[OK] Schemas installed"
}

# ── Step 5: Verify installation ──────────────────────────────────────
verify() {
  echo "  Verifying installation..."

  local checks_passed=0
  local checks_total=0
  local errors=""

  # Check 1: .version exists and contains valid semver
  ((checks_total++))
  if [[ -f "$MOIRA_HOME/.version" ]]; then
    local ver
    ver=$(cat "$MOIRA_HOME/.version")
    if [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      ((checks_passed++))
    else
      errors+="  .version contains invalid semver: $ver\n"
    fi
  else
    errors+="  .version not found\n"
  fi

  # Check 2-5: lib files exist and are sourceable
  for lib_file in state.sh yaml-utils.sh scaffold.sh task-id.sh; do
    ((checks_total++))
    local lib_path="$MOIRA_HOME/lib/$lib_file"
    if [[ -f "$lib_path" ]]; then
      if bash -n "$lib_path" 2>/dev/null; then
        ((checks_passed++))
      else
        errors+="  $lib_file has syntax errors\n"
      fi
    else
      errors+="  $lib_file not found\n"
    fi
  done

  # Check 6: all 10 command stubs exist
  local commands=(task init status resume knowledge metrics audit bypass refresh help)
  for cmd in "${commands[@]}"; do
    ((checks_total++))
    local cmd_path="$HOME/.claude/commands/moira/${cmd}.md"
    if [[ -f "$cmd_path" ]]; then
      ((checks_passed++))
    else
      errors+="  command stub ${cmd}.md not found\n"
    fi
  done

  # Check 7: each stub has valid frontmatter (name + allowed-tools)
  for cmd in "${commands[@]}"; do
    ((checks_total++))
    local cmd_path="$HOME/.claude/commands/moira/${cmd}.md"
    if [[ -f "$cmd_path" ]]; then
      if grep -q "^name: moira:" "$cmd_path" && grep -q "allowed-tools:" "$cmd_path"; then
        ((checks_passed++))
      else
        errors+="  ${cmd}.md missing required frontmatter (name/allowed-tools)\n"
      fi
    fi
  done

  # Check: base.yaml exists
  ((checks_total++))
  if [[ -f "$MOIRA_HOME/core/rules/base.yaml" ]]; then
    ((checks_passed++))
  else
    errors+="  core/rules/base.yaml not found\n"
  fi

  # Check: 10 role files exist
  local role_agents=(apollo hermes athena metis daedalus hephaestus themis aletheia mnemosyne argus)
  for agent in "${role_agents[@]}"; do
    ((checks_total++))
    if [[ -f "$MOIRA_HOME/core/rules/roles/${agent}.yaml" ]]; then
      ((checks_passed++))
    else
      errors+="  core/rules/roles/${agent}.yaml not found\n"
    fi
  done

  # Check: 5 quality files exist
  local quality_files=(q1-completeness q2-soundness q3-feasibility q4-correctness q5-coverage)
  for qfile in "${quality_files[@]}"; do
    ((checks_total++))
    if [[ -f "$MOIRA_HOME/core/rules/quality/${qfile}.yaml" ]]; then
      ((checks_passed++))
    else
      errors+="  core/rules/quality/${qfile}.yaml not found\n"
    fi
  done

  # Check: knowledge-access-matrix.yaml and response-contract.yaml
  for core_file in knowledge-access-matrix.yaml response-contract.yaml; do
    ((checks_total++))
    if [[ -f "$MOIRA_HOME/core/${core_file}" ]]; then
      ((checks_passed++))
    else
      errors+="  core/${core_file} not found\n"
    fi
  done

  if [[ $checks_passed -eq $checks_total ]]; then
    echo "[OK] Verification passed ($checks_passed/$checks_total)"
  else
    echo "[WARN] Verification: $checks_passed/$checks_total checks passed"
    if [[ -n "$errors" ]]; then
      echo -e "$errors"
    fi
    return 1
  fi
}

# ── Main ──────────────────────────────────────────────────────────────
check_prerequisites
install_global
install_commands
install_schemas
verify

echo ""
echo "======================================="
echo "  Moira v${MOIRA_VERSION} installed"
echo "======================================="
echo ""
echo "  Next: cd <project> && claude && /moira:init"
echo ""
