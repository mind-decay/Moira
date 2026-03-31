#!/usr/bin/env bash
# quality.sh — Quality gate operations for Moira
# Handles findings parsing, validation, aggregation, and formatting.
# Also handles CONFORM/EVOLVE mode management.
#
# Responsibilities: quality findings processing and mode management ONLY
# Does NOT handle pipeline routing (that's the orchestrator skill)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_LIB_DIR}/yaml-utils.sh"

# ── moira_quality_parse_verdict <findings_path> ──────────────────────
# Parse a findings YAML file and return the verdict.
# Outputs: pass | fail_critical | fail_warning
# Returns 0 on success, 1 if file not found or parse error.
moira_quality_parse_verdict() {
  local findings_path="$1"

  if [[ ! -f "$findings_path" ]]; then
    echo "Error: findings file not found: $findings_path" >&2
    return 1
  fi

  local critical_count warning_count
  critical_count=$(moira_yaml_get "$findings_path" "summary.critical_count" 2>/dev/null) || {
    echo "Error: cannot read summary.critical_count from $findings_path" >&2
    return 1
  }
  warning_count=$(moira_yaml_get "$findings_path" "summary.warning_count" 2>/dev/null) || {
    echo "Error: cannot read summary.warning_count from $findings_path" >&2
    return 1
  }

  if [[ "$critical_count" -gt 0 ]] 2>/dev/null; then
    echo "fail_critical"
  elif [[ "$warning_count" -gt 0 ]] 2>/dev/null; then
    echo "fail_warning"
  else
    echo "pass"
  fi
}

# ── moira_quality_validate_findings <findings_path> <gate_checklist_path>
# Validate that a findings file covers all required checklist items.
# Outputs missing item IDs (one per line) if any.
# Returns 0 if all present, 1 if items missing or error.
moira_quality_validate_findings() {
  local findings_path="$1"
  local checklist_path="$2"

  if [[ ! -f "$findings_path" ]]; then
    echo "Error: findings file not found: $findings_path" >&2
    return 1
  fi
  if [[ ! -f "$checklist_path" ]]; then
    echo "Error: checklist file not found: $checklist_path" >&2
    return 1
  fi

  # Extract required item IDs from checklist YAML
  # Items are under items: array, each with id: and required: true
  local required_ids
  required_ids=$(awk '
    # Collect all item IDs — quality checklist items are required by default
    /^[[:space:]]*- id:/ {
      gsub(/^[[:space:]]*- id:[[:space:]]*/, "")
      gsub(/["\047]/, "")
      gsub(/[[:space:]]+$/, "")
      print
    }
  ' "$checklist_path")

  if [[ -z "$required_ids" ]]; then
    # No items found — nothing to validate
    return 0
  fi

  # Extract finding item IDs from findings YAML
  local finding_ids
  finding_ids=$(awk '
    /^[[:space:]]*- id:/ || /^[[:space:]]*id:/ {
      gsub(/^[[:space:]]*-?[[:space:]]*id:[[:space:]]*/, "")
      gsub(/["\047]/, "")
      gsub(/[[:space:]]+$/, "")
      print
    }
  ' "$findings_path")

  # Check each required ID exists in findings
  local missing=0
  local id
  while IFS= read -r id; do
    if [[ -z "$id" ]]; then continue; fi
    if ! echo "$finding_ids" | grep -qx "$id"; then
      echo "$id"
      missing=1
    fi
  done <<< "$required_ids"

  return "$missing"
}

# ── moira_quality_aggregate_task <task_dir> ──────────────────────────
# Aggregate all findings for a task into a summary.
# Scans findings/ directory for *-Q[1-5].yaml files.
# Writes findings/summary.yaml with per-gate verdicts and totals.
# Returns 0 on success, 1 if no findings found.
moira_quality_aggregate_task() {
  local task_dir="$1"
  local findings_dir="${task_dir}/findings"

  if [[ ! -d "$findings_dir" ]]; then
    echo "Error: findings directory not found: $findings_dir" >&2
    return 1
  fi

  # Find all findings files
  local findings_files
  findings_files=$(find "$findings_dir" -name '*-Q[1-5].yaml' -not -name 'summary.yaml' 2>/dev/null | sort)

  if [[ -z "$findings_files" ]]; then
    echo "Error: no findings files found in $findings_dir" >&2
    return 1
  fi

  local summary_file="${findings_dir}/summary.yaml"
  local total_critical=0 total_warning=0 total_suggestion=0
  local total_passed=0 total_failed=0 total_na=0 total_items=0
  local gate_verdicts=""
  local overall_verdict="pass"

  while IFS= read -r ffile; do
    if [[ -z "$ffile" ]]; then continue; fi

    local gate agent verdict
    gate=$(moira_yaml_get "$ffile" "_meta.gate" 2>/dev/null) || continue
    agent=$(moira_yaml_get "$ffile" "_meta.agent" 2>/dev/null) || continue

    local cc wc sc passed failed na total
    cc=$(moira_yaml_get "$ffile" "summary.critical_count" 2>/dev/null) || cc=0
    wc=$(moira_yaml_get "$ffile" "summary.warning_count" 2>/dev/null) || wc=0
    sc=$(moira_yaml_get "$ffile" "summary.suggestion_count" 2>/dev/null) || sc=0
    passed=$(moira_yaml_get "$ffile" "summary.passed" 2>/dev/null) || passed=0
    failed=$(moira_yaml_get "$ffile" "summary.failed" 2>/dev/null) || failed=0
    na=$(moira_yaml_get "$ffile" "summary.na" 2>/dev/null) || na=0
    total=$(moira_yaml_get "$ffile" "summary.total" 2>/dev/null) || total=0

    verdict=$(moira_quality_parse_verdict "$ffile" 2>/dev/null) || verdict="error"

    total_critical=$((total_critical + cc))
    total_warning=$((total_warning + wc))
    total_suggestion=$((total_suggestion + sc))
    total_passed=$((total_passed + passed))
    total_failed=$((total_failed + failed))
    total_na=$((total_na + na))
    total_items=$((total_items + total))

    gate_verdicts="${gate_verdicts}  - gate: ${gate}"$'\n'"    agent: ${agent}"$'\n'"    verdict: ${verdict}"$'\n'"    critical: ${cc}"$'\n'"    warning: ${wc}"$'\n'"    suggestion: ${sc}"$'\n'
  done <<< "$findings_files"

  # Derive overall verdict
  if [[ "$total_critical" -gt 0 ]]; then
    overall_verdict="fail_critical"
  elif [[ "$total_warning" -gt 0 ]]; then
    overall_verdict="fail_warning"
  fi

  # Write summary
  cat > "$summary_file" <<YAML
# Quality findings summary — auto-generated
# Do not edit manually

gates:
${gate_verdicts}
totals:
  items: ${total_items}
  passed: ${total_passed}
  failed: ${total_failed}
  na: ${total_na}
  critical: ${total_critical}
  warning: ${total_warning}
  suggestion: ${total_suggestion}

verdict: ${overall_verdict}
YAML
}

# ── moira_quality_format_warnings <findings_path> ────────────────────
# Format WARNING findings for gate display.
# Outputs formatted warning lines for the WARNING gate template.
moira_quality_format_warnings() {
  local findings_path="$1"

  if [[ ! -f "$findings_path" ]]; then
    echo "Error: findings file not found: $findings_path" >&2
    return 1
  fi

  # Extract warning items from findings YAML using awk
  awk '
  BEGIN { in_items=0; in_item=0; is_warning=0 }

  /^[[:space:]]*items:/ { in_items=1; next }
  in_items && /^[[:space:]]*- id:/ {
    if (in_item && is_warning) {
      printf "\342\232\240 %s: %s\n  Detail: %s\n  Evidence: %s\n\n", item_id, item_check, item_detail, item_evidence
    }
    in_item=1; is_warning=0
    gsub(/^[[:space:]]*- id:[[:space:]]*/, "")
    gsub(/["\047]/, "")
    item_id=$0; item_check=""; item_detail=""; item_evidence=""
    next
  }
  in_item && /^[[:space:]]*check:/ {
    gsub(/^[[:space:]]*check:[[:space:]]*/, "")
    gsub(/["\047]/, "")
    item_check=$0; next
  }
  in_item && /^[[:space:]]*severity:[[:space:]]*warning/ { is_warning=1; next }
  in_item && /^[[:space:]]*detail:/ {
    gsub(/^[[:space:]]*detail:[[:space:]]*/, "")
    gsub(/["\047]/, "")
    item_detail=$0; next
  }
  in_item && /^[[:space:]]*evidence:/ {
    gsub(/^[[:space:]]*evidence:[[:space:]]*/, "")
    gsub(/["\047]/, "")
    item_evidence=$0; next
  }
  # End of items section
  in_items && /^[^ ]/ && !/^[[:space:]]*-/ && !/^[[:space:]]*[a-z]/ { in_items=0 }

  END {
    if (in_item && is_warning) {
      printf "\342\232\240 %s: %s\n  Detail: %s\n  Evidence: %s\n", item_id, item_check, item_detail, item_evidence
    }
  }
  ' "$findings_path"
}

# ═══════════════════════════════════════════════════════════════════════
# CONFORM/EVOLVE Mode Management
# ═══════════════════════════════════════════════════════════════════════

# ── moira_quality_get_mode <config_path> ─────────────────────────────
# Read quality mode from config.yaml.
# Outputs: conform | evolve
# Defaults to "conform" if field not present.
moira_quality_get_mode() {
  local config_path="$1"

  if [[ ! -f "$config_path" ]]; then
    echo "conform"
    return 0
  fi

  local mode
  mode=$(moira_yaml_get "$config_path" "quality.mode" 2>/dev/null) || true

  if [[ -z "$mode" || "$mode" == "null" ]]; then
    echo "conform"
  else
    echo "$mode"
  fi
}

# ── moira_quality_check_cooldown <config_path> ───────────────────────
# Check post-evolution cooldown status.
# Outputs: "cooldown N" if in cooldown, "ready" if not.
moira_quality_check_cooldown() {
  local config_path="$1"

  if [[ ! -f "$config_path" ]]; then
    echo "ready"
    return 0
  fi

  local remaining
  remaining=$(moira_yaml_get "$config_path" "quality.evolution.cooldown_remaining" 2>/dev/null) || true

  if [[ -z "$remaining" || "$remaining" == "null" || "$remaining" == "0" ]]; then
    echo "ready"
  elif [[ "$remaining" -gt 0 ]] 2>/dev/null; then
    echo "cooldown $remaining"
  else
    echo "ready"
  fi
}

# ── moira_quality_start_evolve <config_path> <target_pattern> ────────
# Activate EVOLVE mode for a specific pattern.
# Returns 0 on success, 1 if cooldown active.
moira_quality_start_evolve() {
  local config_path="$1"
  local target_pattern="$2"

  if [[ ! -f "$config_path" ]]; then
    echo "Error: config file not found: $config_path" >&2
    return 1
  fi

  # Check cooldown
  local cooldown_status
  cooldown_status=$(moira_quality_check_cooldown "$config_path")

  if [[ "$cooldown_status" != "ready" ]]; then
    echo "Error: cannot start evolution — $cooldown_status" >&2
    return 1
  fi

  moira_yaml_set "$config_path" "quality.mode" "evolve"
  moira_yaml_set "$config_path" "quality.evolution.current_target" "$target_pattern"
}

# ── moira_quality_complete_evolve <config_path> ──────────────────────
# Complete evolution and start cooldown period.
# Sets mode back to conform, clears target, sets cooldown to 5.
moira_quality_complete_evolve() {
  local config_path="$1"

  if [[ ! -f "$config_path" ]]; then
    echo "Error: config file not found: $config_path" >&2
    return 1
  fi

  moira_yaml_set "$config_path" "quality.mode" "conform"
  moira_yaml_set "$config_path" "quality.evolution.current_target" ""
  moira_yaml_set "$config_path" "quality.evolution.cooldown_remaining" "5"
}

# ── moira_quality_tick_cooldown <config_path> ─────────────────────────
# Decrement cooldown counter by 1 (called after each task completion).
moira_quality_tick_cooldown() {
  local config_path="$1"

  if [[ ! -f "$config_path" ]]; then
    return 0
  fi

  local remaining
  remaining=$(moira_yaml_get "$config_path" "quality.evolution.cooldown_remaining" 2>/dev/null) || true

  if [[ -z "$remaining" || "$remaining" == "null" || "$remaining" == "0" ]]; then
    return 0
  fi

  if [[ "$remaining" -gt 0 ]] 2>/dev/null; then
    local new_remaining=$((remaining - 1))
    moira_yaml_set "$config_path" "quality.evolution.cooldown_remaining" "$new_remaining"
  fi
}
