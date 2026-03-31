#!/usr/bin/env bash
# audit.sh — Audit dispatch support, finding parsing, report generation for Moira
# Provides finding parsing, report generation, recommendation formatting,
# and audit trigger detection. Does NOT dispatch agents (shell cannot invoke
# the Agent tool — that's done by the audit.md command skill).
#
# Source: design/subsystems/audit.md, design/specs/2026-03-15-phase11-metrics-audit.md D4

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_AUDIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_AUDIT_LIB_DIR}/yaml-utils.sh"

# ── moira_audit_check_trigger [state_dir] ─────────────────────────────
# Check if automatic audit is due based on completed task count.
# Returns "light" (every 10th task), "standard" (every 20th), or "none".
# Writes audit_pending flag to state if due.
moira_audit_check_trigger() {
  local state_dir="${1:-.claude/moira/state}"

  local month
  month=$(date +%Y-%m)
  local monthly_file="${state_dir}/metrics/monthly-${month}.yaml"

  if [[ ! -f "$monthly_file" ]]; then
    echo "none"
    return 0
  fi

  local total
  total=$(moira_yaml_get "$monthly_file" "tasks.total" 2>/dev/null) || true
  total=${total:-0}

  if [[ "$total" -eq 0 ]]; then
    echo "none"
    return 0
  fi

  local config_path="${state_dir}/config.yaml"
  local light_n=10
  local standard_n=20
  if [[ -f "$config_path" ]]; then
    light_n=$(moira_yaml_get "$config_path" "audit.light_every_n_tasks" 2>/dev/null) || light_n=10
    standard_n=$(moira_yaml_get "$config_path" "audit.standard_every_n_tasks" 2>/dev/null) || standard_n=20
  fi

  local depth="none"
  if (( total % standard_n == 0 )); then
    depth="standard"
  elif (( total % light_n == 0 )); then
    depth="light"
  fi

  if [[ "$depth" != "none" ]]; then
    mkdir -p "$state_dir"
    cat > "${state_dir}/audit-pending.yaml" << EOF
audit_pending: ${depth}
triggered_at: $(date +%Y-%m-%dT%H:%M:%S)
task_count: ${total}
EOF
    echo "$depth"
  else
    echo "none"
  fi
}

# ── moira_audit_select_templates <domain|"all"> <depth> ──────────────
# Return list of template file paths for the given domain and depth.
# Template dir: ~/.claude/moira/templates/audit/
moira_audit_select_templates() {
  local domain="$1"
  local depth="$2"
  local template_dir="${MOIRA_HOME:-$HOME/.claude/moira}/templates/audit"

  local templates=""

  if [[ "$domain" == "all" ]]; then
    # Return all templates for the given depth
    case "$depth" in
      light)
        # Only rules-light and knowledge-light exist (D-093c)
        templates="${template_dir}/rules-light.md
${template_dir}/knowledge-light.md"
        ;;
      standard)
        templates="${template_dir}/rules-standard.md
${template_dir}/knowledge-standard.md
${template_dir}/agents-standard.md
${template_dir}/config-standard.md
${template_dir}/consistency-standard.md"
        ;;
      deep)
        templates="${template_dir}/rules-deep.md
${template_dir}/knowledge-deep.md
${template_dir}/agents-deep.md
${template_dir}/config-deep.md
${template_dir}/consistency-deep.md"
        ;;
    esac
  else
    # Single domain
    local file="${template_dir}/${domain}-${depth}.md"
    if [[ -f "$file" ]]; then
      templates="$file"
    else
      # Fallback: try standard depth if requested depth doesn't exist
      file="${template_dir}/${domain}-standard.md"
      if [[ -f "$file" ]]; then
        templates="$file"
      fi
    fi
  fi

  echo "$templates"
}

# ── moira_audit_parse_findings <audit_file> ───────────────────────────
# Parse structured findings from audit report markdown.
# Extracts the YAML findings block and counts by risk level and domain.
# Output: structured summary (key-value pairs).
moira_audit_parse_findings() {
  local audit_file="$1"

  if [[ ! -f "$audit_file" ]]; then
    echo "error: audit file not found: ${audit_file}" >&2
    return 1
  fi

  local total=0
  local low=0 medium=0 high=0
  local rules=0 knowledge=0 agents=0 config=0 consistency=0

  # Parse findings from YAML block in audit report
  local in_findings=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^findings: ]]; then
      in_findings=true
      continue
    fi
    # End of findings block: next top-level key
    if $in_findings && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    if $in_findings; then
      if [[ "$line" =~ "- id:" ]]; then
        total=$(( total + 1 ))
      elif [[ "$line" =~ "risk: low" ]]; then
        low=$(( low + 1 ))
      elif [[ "$line" =~ "risk: medium" ]]; then
        medium=$(( medium + 1 ))
      elif [[ "$line" =~ "risk: high" ]]; then
        high=$(( high + 1 ))
      elif [[ "$line" =~ "domain: rules" ]]; then
        rules=$(( rules + 1 ))
      elif [[ "$line" =~ "domain: knowledge" ]]; then
        knowledge=$(( knowledge + 1 ))
      elif [[ "$line" =~ "domain: agents" ]]; then
        agents=$(( agents + 1 ))
      elif [[ "$line" =~ "domain: config" ]]; then
        config=$(( config + 1 ))
      elif [[ "$line" =~ "domain: consistency" ]]; then
        consistency=$(( consistency + 1 ))
      fi
    fi
  done < "$audit_file"

  echo "total: ${total}"
  echo "by_risk:"
  echo "  low: ${low}"
  echo "  medium: ${medium}"
  echo "  high: ${high}"
  echo "by_domain:"
  echo "  rules: ${rules}"
  echo "  knowledge: ${knowledge}"
  echo "  agents: ${agents}"
  echo "  config: ${config}"
  echo "  consistency: ${consistency}"
}

# ── moira_audit_generate_report <date> [state_dir] ───────────────────
# Combine per-domain finding files into unified audit report.
# Writes to state/audits/{date}-audit.md.
# Expects per-domain results in state/audits/{date}-{domain}.yaml.
moira_audit_generate_report() {
  local audit_date="$1"
  local state_dir="${2:-.claude/moira/state}"

  local audits_dir="${state_dir}/audits"
  mkdir -p "$audits_dir"
  local report_file="${audits_dir}/${audit_date}-audit.md"

  # Read moira version
  local moira_version="unknown"
  if [[ -f "${MOIRA_HOME:-$HOME/.claude/moira}/.version" ]]; then
    moira_version=$(cat "${MOIRA_HOME:-$HOME/.claude/moira}/.version" 2>/dev/null) || true
  fi

  # Collect domains that have findings files
  local domains_found=""
  local all_findings=""
  local depth="standard"

  for domain in rules knowledge agents config consistency; do
    local domain_file="${audits_dir}/${audit_date}-${domain}.yaml"
    if [[ -f "$domain_file" ]]; then
      domains_found="${domains_found:+$domains_found, }${domain}"

      # Extract depth from first domain file found
      local d
      d=$(grep "^depth:" "$domain_file" 2>/dev/null | head -1) || true
      if [[ -n "$d" ]]; then
        depth="${d#depth: }"
        depth="${depth## }"
      fi

      # Extract findings block
      local in_findings=false
      while IFS= read -r line; do
        if [[ "$line" =~ ^findings: ]]; then
          in_findings=true
          continue
        fi
        if $in_findings && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
          break
        fi
        if $in_findings; then
          all_findings+="${line}"$'\n'
        fi
      done < "$domain_file"
    fi
  done

  # Write report
  cat > "$report_file" << EOF
# Moira System Audit Report

**Date:** ${audit_date}
**Depth:** ${depth}
**Domains:** ${domains_found:-none}
**Moira Version:** ${moira_version}

---

## Summary

$(moira_audit_parse_findings <(echo "findings:"; echo "$all_findings"))

---

## Findings

\`\`\`yaml
findings:
${all_findings}\`\`\`

---

*Generated by Moira audit system*
EOF

  echo "report: ${report_file}"
}

# ── moira_audit_format_recommendations <audit_file> ──────────────────
# Extract recommendations grouped by risk level.
# Format for batch approval presentation per audit.md spec.
moira_audit_format_recommendations() {
  local audit_file="$1"

  if [[ ! -f "$audit_file" ]]; then
    echo "error: audit file not found: ${audit_file}" >&2
    return 1
  fi

  local low_recs="" medium_recs="" high_recs=""
  local current_id="" current_risk="" current_desc="" current_rec="" current_target=""

  local in_findings=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^findings: ]]; then
      in_findings=true
      continue
    fi
    if $in_findings && [[ "$line" =~ ^[a-z] && ! "$line" =~ ^[[:space:]] ]]; then
      break
    fi
    if $in_findings; then
      if [[ "$line" =~ "- id:" ]]; then
        # Flush previous finding
        if [[ -n "$current_id" ]]; then
          _moira_audit_append_rec
        fi
        current_id="${line#*id: }"; current_id="${current_id## }"
        current_id="${current_id//\"/}"
        current_risk="" current_desc="" current_rec="" current_target=""
      elif [[ "$line" =~ "risk:" ]]; then
        current_risk="${line#*risk: }"; current_risk="${current_risk## }"
      elif [[ "$line" =~ "description:" ]]; then
        current_desc="${line#*description: }"; current_desc="${current_desc## }"
        current_desc="${current_desc//\"/}"
      elif [[ "$line" =~ "recommendation:" ]]; then
        current_rec="${line#*recommendation: }"; current_rec="${current_rec## }"
        current_rec="${current_rec//\"/}"
      elif [[ "$line" =~ "target_file:" ]]; then
        current_target="${line#*target_file: }"; current_target="${current_target## }"
        current_target="${current_target//\"/}"
      fi
    fi
  done < "$audit_file"

  # Flush last finding
  if [[ -n "$current_id" ]]; then
    _moira_audit_append_rec
  fi

  # Output formatted recommendations
  if [[ -n "$low_recs" ]]; then
    echo "═══ LOW RISK (batch apply-all available) ═══"
    echo "$low_recs"
    echo ""
  fi

  if [[ -n "$medium_recs" ]]; then
    echo "═══ MEDIUM RISK (individual approval) ═══"
    echo "$medium_recs"
    echo ""
  fi

  if [[ -n "$high_recs" ]]; then
    echo "═══ HIGH RISK (detailed review required) ═══"
    echo "$high_recs"
    echo ""
  fi

  if [[ -z "$low_recs" && -z "$medium_recs" && -z "$high_recs" ]]; then
    echo "No recommendations found."
  fi
}

# Helper to append recommendation to the appropriate risk bucket
_moira_audit_append_rec() {
  local entry="  [${current_id}] ${current_desc}
    → ${current_rec}"
  if [[ -n "$current_target" ]]; then
    entry+=$'\n'"    Target: ${current_target}"
  fi
  entry+=$'\n'

  case "$current_risk" in
    low)    low_recs+="${entry}" ;;
    medium) medium_recs+="${entry}" ;;
    high)   high_recs+="${entry}" ;;
  esac
}
