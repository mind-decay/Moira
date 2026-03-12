#!/usr/bin/env bash
# bootstrap.sh — Bootstrap operations for /moira:init
# Preset matching, config generation, project rules generation,
# knowledge population, CLAUDE.md integration, gitignore setup.
# Compatible with bash 3.2+ (macOS default).
#
# Responsibilities: bootstrap file generation ONLY
# Does NOT handle scanning (that's Explorer agents' job)
# Does NOT handle scaffold creation (that's scaffold.sh)

set -euo pipefail

# Source dependencies from the same directory
_MOIRA_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/yaml-utils.sh"
# shellcheck source=knowledge.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/knowledge.sh"

# ── moira_bootstrap_match_preset <tech_scan_path> <presets_dir> ───────
# Match tech scan results to the closest stack preset.
# Returns: preset filename (e.g., nextjs.yaml) or generic.yaml if no match.
moira_bootstrap_match_preset() {
  local tech_scan_path="$1"
  local presets_dir="$2"

  if [[ ! -f "$tech_scan_path" ]]; then
    echo "generic.yaml"
    return 0
  fi

  if [[ ! -d "$presets_dir" ]]; then
    echo "generic.yaml"
    return 0
  fi

  # Read tech scan and convert to lowercase for matching
  local scan_text
  scan_text=$(tr '[:upper:]' '[:lower:]' < "$tech_scan_path")

  local best_preset="generic.yaml"
  local best_score=0

  for preset_file in "$presets_dir"/*.yaml; do
    [[ -f "$preset_file" ]] || continue

    local preset_name
    preset_name=$(basename "$preset_file")

    # Skip generic — it's the fallback
    [[ "$preset_name" == "generic.yaml" ]] && continue

    # Extract match_signals and compute score
    local score=0
    local in_signals=false

    while IFS= read -r line; do
      # Detect match_signals section
      if [[ "$line" =~ ^[[:space:]]*match_signals: ]]; then
        in_signals=true
        continue
      fi

      # Exit signals section on non-list item at same or lower indent
      if $in_signals; then
        if [[ "$line" =~ ^[[:space:]]*- ]]; then
          # Extract signal and weight from {signal: "...", ...weight: N}
          local signal weight
          signal=$(echo "$line" | sed -n 's/.*signal:[[:space:]]*"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/p' | tr '[:upper:]' '[:lower:]')
          weight=$(echo "$line" | sed -n 's/.*weight:[[:space:]]*\([0-9]*\).*/\1/p')

          if [[ -n "$signal" && -n "$weight" ]]; then
            # Check if signal appears in scan text
            if echo "$scan_text" | grep -qi "$signal" 2>/dev/null; then
              score=$((score + weight))
            fi
          fi
        elif [[ ! "$line" =~ ^[[:space:]]*$ ]]; then
          # Non-empty, non-list line = end of signals section
          in_signals=false
        fi
      fi
    done < "$preset_file"

    if [[ $score -gt $best_score ]]; then
      best_score=$score
      best_preset="$preset_name"
    fi
  done

  # Threshold: must score > 5 to beat generic
  if [[ $best_score -le 5 ]]; then
    echo "generic.yaml"
  else
    echo "$best_preset"
  fi
}

# ── moira_bootstrap_generate_config <project_root> <preset_path> <tech_scan_path>
# Generate config.yaml from preset + scan results.
moira_bootstrap_generate_config() {
  local project_root="$1"
  local preset_path="$2"
  local tech_scan_path="$3"

  local config_file="$project_root/.claude/moira/config.yaml"
  mkdir -p "$(dirname "$config_file")"

  # Extract stack_id from preset
  local stack_id="generic"
  if [[ -f "$preset_path" ]]; then
    stack_id=$(grep 'stack_id:' "$preset_path" | head -1 | sed 's/.*stack_id:[[:space:]]*//' | tr -d ' ')
  fi

  # Extract project name: try package.json, then go.mod, then directory name
  local project_name
  project_name=$(basename "$project_root")

  if [[ -f "$project_root/package.json" ]]; then
    local pkg_name
    pkg_name=$(grep '"name"' "$project_root/package.json" | head -1 | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -n "$pkg_name" ]]; then
      project_name="$pkg_name"
    fi
  elif [[ -f "$project_root/go.mod" ]]; then
    local mod_name
    mod_name=$(grep '^module ' "$project_root/go.mod" | head -1 | sed 's/^module[[:space:]]*//')
    if [[ -n "$mod_name" ]]; then
      # Use last path component of module path
      project_name=$(basename "$mod_name")
    fi
  elif [[ -f "$project_root/pyproject.toml" ]]; then
    local py_name
    py_name=$(grep '^name' "$project_root/pyproject.toml" | head -1 | sed 's/.*=[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -n "$py_name" ]]; then
      project_name="$py_name"
    fi
  fi

  # Get current UTC timestamp
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Write config.yaml
  cat > "$config_file" << YAML
version: "1.0"

project:
  name: "${project_name}"
  root: "${project_root}"
  stack: ${stack_id}

classification:
  default_pipeline: standard
  size_hints_override: false

pipelines:
  quick:
    max_retries: 1
    gates: [classification, final]
  standard:
    max_retries: 2
    gates: [classification, architecture, plan, final]
  full:
    max_retries: 2
    gates: [classification, architecture, plan, per-phase, final]
  decomposition:
    max_retries: 2
    gates: [classification, decomposition, per-task, final]

budgets:
  orchestrator_max_percent: 25
  agent_max_load_percent: 70
  per_agent:
    classifier: 20000
    explorer: 140000
    analyst: 80000
    architect: 100000
    planner: 70000
    implementer: 120000
    reviewer: 100000
    tester: 90000
    reflector: 80000
    auditor: 140000

quality:
  mode: conform
  evolution_threshold: 3
  review_severity_minimum: medium

knowledge:
  freshness_days: 30
  archival_max_entries: 100

audit:
  light_every_n_tasks: 10
  standard_every_n_tasks: 20
  auto_batch_apply_risk: low

mcp:
  enabled: false
  registry_path: config/mcp-registry.yaml

hooks:
  guard_enabled: true
  budget_tracking_enabled: true

bootstrap:
  quick_scan_completed: true
  quick_scan_at: "${timestamp}"
  deep_scan_completed: false
  deep_scan_pending: true
YAML
}

# ── moira_bootstrap_generate_project_rules <project_root> <preset_path> <scan_results_dir>
# Generate Layer 3 project rules from preset + scanner results.
moira_bootstrap_generate_project_rules() {
  local project_root="$1"
  local preset_path="$2"
  local scan_results_dir="$3"

  local rules_dir="$project_root/.claude/moira/project/rules"
  mkdir -p "$rules_dir"

  # --- stack.yaml ---
  _moira_bootstrap_gen_stack "$preset_path" "$scan_results_dir/tech-scan.md" "$rules_dir/stack.yaml"

  # --- conventions.yaml ---
  _moira_bootstrap_gen_conventions "$preset_path" "$scan_results_dir/convention-scan.md" "$rules_dir/conventions.yaml"

  # --- patterns.yaml ---
  _moira_bootstrap_gen_patterns "$preset_path" "$scan_results_dir/pattern-scan.md" "$rules_dir/patterns.yaml"

  # --- boundaries.yaml ---
  _moira_bootstrap_gen_boundaries "$preset_path" "$scan_results_dir/structure-scan.md" "$rules_dir/boundaries.yaml"
}

# ── Internal: generate stack.yaml ─────────────────────────────────────
_moira_bootstrap_gen_stack() {
  local preset_path="$1"
  local tech_scan="$2"
  local output="$3"

  # Start with preset defaults
  local language framework runtime styling orm testing ci
  language=$(_extract_preset_field "$preset_path" "stack" "language")
  framework=$(_extract_preset_field "$preset_path" "stack" "framework")
  runtime=$(_extract_preset_field "$preset_path" "stack" "runtime")
  styling=$(_extract_preset_field "$preset_path" "stack" "styling")
  orm=$(_extract_preset_field "$preset_path" "stack" "orm")
  testing=$(_extract_preset_field "$preset_path" "stack" "testing")
  ci=$(_extract_preset_field "$preset_path" "stack" "ci")

  # Override with scan results where available
  if [[ -f "$tech_scan" ]]; then
    local scan_val
    scan_val=$(_extract_scan_value "$tech_scan" "Primary:" "Language")
    [[ -n "$scan_val" ]] && language="$scan_val"

    scan_val=$(_extract_scan_value "$tech_scan" "Name:" "Framework")
    [[ -n "$scan_val" ]] && framework="$scan_val"

    scan_val=$(_extract_scan_value "$tech_scan" "Package manager:" "Build")
    # runtime can be inferred from package manager
    if [[ -n "$scan_val" ]]; then
      case "$scan_val" in
        *npm*|*yarn*|*pnpm*) runtime="Node.js" ;;
        *pip*|*poetry*) runtime="Python" ;;
        *cargo*) runtime="Rust" ;;
        *go*) runtime="Go" ;;
      esac
    fi

    scan_val=$(_extract_scan_value "$tech_scan" "Framework:" "Testing")
    [[ -n "$scan_val" ]] && testing="$scan_val"

    scan_val=$(_extract_scan_value "$tech_scan" "ORM/Query:" "Database")
    [[ -n "$scan_val" && "$scan_val" != "Not detected" ]] && orm="$scan_val"

    scan_val=$(_extract_scan_value "$tech_scan" "Platform:" "CI")
    [[ -n "$scan_val" && "$scan_val" != "Not detected" ]] && ci="$scan_val"
  fi

  cat > "$output" << YAML
# Stack configuration — generated by /moira:init
# Source: tech scanner results + ${preset_path##*/} preset

language: ${language}
framework: ${framework}
runtime: ${runtime}
styling: ${styling}
orm: ${orm}
testing: ${testing}
ci: ${ci}
YAML
}

# ── Internal: generate conventions.yaml ───────────────────────────────
_moira_bootstrap_gen_conventions() {
  local preset_path="$1"
  local convention_scan="$2"
  local output="$3"

  # Start with preset defaults
  local file_naming func_naming comp_naming const_naming type_naming
  file_naming=$(_extract_preset_field "$preset_path" "naming" "files")
  func_naming=$(_extract_preset_field "$preset_path" "naming" "functions")
  comp_naming=$(_extract_preset_field "$preset_path" "naming" "components")
  const_naming=$(_extract_preset_field "$preset_path" "naming" "constants")
  type_naming=$(_extract_preset_field "$preset_path" "naming" "types")

  local indent quotes semicolons max_line
  indent=$(_extract_preset_field "$preset_path" "formatting" "indent")
  quotes=$(_extract_preset_field "$preset_path" "formatting" "quotes")
  semicolons=$(_extract_preset_field "$preset_path" "formatting" "semicolons")
  max_line=$(_extract_preset_field "$preset_path" "formatting" "max_line_length")

  # Override with scan results where available
  if [[ -f "$convention_scan" ]]; then
    local scan_val
    # Parse naming conventions table
    scan_val=$(_extract_table_value "$convention_scan" "Files")
    [[ -n "$scan_val" ]] && file_naming="$scan_val"

    scan_val=$(_extract_table_value "$convention_scan" "Functions")
    [[ -n "$scan_val" ]] && func_naming="$scan_val"

    scan_val=$(_extract_table_value "$convention_scan" "Components")
    [[ -n "$scan_val" ]] && comp_naming="$scan_val"

    scan_val=$(_extract_table_value "$convention_scan" "Constants")
    [[ -n "$scan_val" ]] && const_naming="$scan_val"

    scan_val=$(_extract_table_value "$convention_scan" "Types")
    [[ -n "$scan_val" ]] && type_naming="$scan_val"
  fi

  cat > "$output" << YAML
# Conventions — generated by /moira:init
# Source: convention scanner results + ${preset_path##*/} preset

naming:
  files: ${file_naming}
  functions: ${func_naming}
  components: ${comp_naming}
  constants: ${const_naming}
  types: ${type_naming}

formatting:
  indent: ${indent}
  quotes: ${quotes}
  semicolons: ${semicolons}
  max_line_length: ${max_line}
YAML
}

# ── Internal: generate patterns.yaml ──────────────────────────────────
_moira_bootstrap_gen_patterns() {
  local preset_path="$1"
  local pattern_scan="$2"
  local output="$3"

  # Start with preset defaults
  local data_fetching validation error_handling api_style
  data_fetching=$(_extract_preset_field "$preset_path" "patterns" "data_fetching")
  validation=$(_extract_preset_field "$preset_path" "patterns" "validation")
  error_handling=$(_extract_preset_field "$preset_path" "patterns" "error_handling")
  api_style=$(_extract_preset_field "$preset_path" "patterns" "api_style")

  # Override with scan results
  if [[ -f "$pattern_scan" ]]; then
    local scan_val
    scan_val=$(_extract_scan_value "$pattern_scan" "Style:" "API Pattern")
    [[ -n "$scan_val" && "$scan_val" != "Not detected" ]] && api_style="$scan_val"

    scan_val=$(_extract_scan_value "$pattern_scan" "Request validation:" "API Pattern")
    [[ -n "$scan_val" && "$scan_val" != "Not detected" ]] && validation="$scan_val"
  fi

  cat > "$output" << YAML
# Patterns — generated by /moira:init
# Source: pattern scanner results + ${preset_path##*/} preset

data_fetching: ${data_fetching:-unknown}
validation: ${validation:-unknown}
error_handling: ${error_handling:-unknown}
api_style: ${api_style:-unknown}
YAML
}

# ── Internal: generate boundaries.yaml ────────────────────────────────
_moira_bootstrap_gen_boundaries() {
  local preset_path="$1"
  local structure_scan="$2"
  local output="$3"

  # Collect do_not_modify from preset
  local do_not_modify=""
  if [[ -f "$preset_path" ]]; then
    local in_dnm=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*do_not_modify: ]]; then
        in_dnm=true
        continue
      fi
      if $in_dnm; then
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
          local entry
          entry=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
          if [[ -n "$do_not_modify" ]]; then
            do_not_modify="$do_not_modify"$'\n'"  - $entry"
          else
            do_not_modify="  - $entry"
          fi
        else
          in_dnm=false
        fi
      fi
    done < "$preset_path"
  fi

  # Add generated dirs from structure scan
  if [[ -f "$structure_scan" ]]; then
    local in_generated=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]*Generated ]]; then
        in_generated=true
        continue
      fi
      if $in_generated; then
        if [[ "$line" =~ ^## ]]; then
          break
        fi
        # Extract directory names from bullet points
        if [[ "$line" =~ ^[[:space:]]*[-*][[:space:]] ]]; then
          local dir_entry
          dir_entry=$(echo "$line" | sed 's/^[[:space:]]*[-*][[:space:]]*//' | sed 's/[[:space:]].*//')
          # Check if already in list
          if [[ -n "$dir_entry" ]] && ! echo "$do_not_modify" | grep -q "$dir_entry"; then
            if [[ -n "$do_not_modify" ]]; then
              do_not_modify="$do_not_modify"$'\n'"  - $dir_entry"
            else
              do_not_modify="  - $dir_entry"
            fi
          fi
        fi
      fi
    done < "$structure_scan"
  fi

  # Collect modify_with_caution from preset
  local modify_with_caution=""
  if [[ -f "$preset_path" ]]; then
    local in_mwc=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*modify_with_caution: ]]; then
        in_mwc=true
        continue
      fi
      if $in_mwc; then
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
          local entry
          entry=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*//')
          if [[ -n "$modify_with_caution" ]]; then
            modify_with_caution="$modify_with_caution"$'\n'"  - $entry"
          else
            modify_with_caution="  - $entry"
          fi
        else
          in_mwc=false
        fi
      fi
    done < "$preset_path"
  fi

  cat > "$output" << YAML
# Boundaries — generated by /moira:init
# Source: structure scanner results + ${preset_path##*/} preset

do_not_modify:
${do_not_modify:-  # none detected}

modify_with_caution:
${modify_with_caution:-  # none detected}
YAML
}

# ── Internal: extract field from preset YAML ──────────────────────────
_extract_preset_field() {
  local file="$1"
  local section="$2"
  local field="$3"

  if [[ ! -f "$file" ]]; then
    echo "unknown"
    return 0
  fi

  local in_section=false
  local section_indent=-1
  local result=""
  while IFS= read -r line; do
    # Detect section start: "section:" at any indent level
    if [[ "$line" =~ ^([[:space:]]*)${section}:[[:space:]]*$ ]] || [[ "$line" =~ ^([[:space:]]*)${section}:[[:space:]]*[^[:space:]] ]]; then
      # Only match the section keyword, not a field that happens to contain it
      local matched_indent="${BASH_REMATCH[1]}"
      section_indent=${#matched_indent}
      in_section=true
      continue
    fi
    if $in_section; then
      # Calculate current line indent
      local stripped="${line#"${line%%[! ]*}"}"
      local cur_indent=$(( ${#line} - ${#stripped} ))
      # Exit section when indent returns to section level or less (sibling/parent)
      if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]] && [[ $cur_indent -le $section_indent ]]; then
        in_section=false
        continue
      fi
      if [[ "$line" =~ ^[[:space:]]*${field}:[[:space:]]*(.*) ]]; then
        result="${BASH_REMATCH[1]}"
        result=$(echo "$result" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        break
      fi
    fi
  done < "$file"

  echo "${result:-unknown}"
}

# ── Internal: extract value from scan markdown ────────────────────────
# Finds "label: value" under an optional section heading
_extract_scan_value() {
  local file="$1"
  local label="$2"
  local section="${3:-}"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local in_section=true
  if [[ -n "$section" ]]; then
    in_section=false
  fi

  while IFS= read -r line; do
    if [[ -n "$section" ]] && [[ "$line" =~ ^##[[:space:]].*${section} ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ -n "$section" ]] && [[ "$line" =~ ^## ]] && ! [[ "$line" =~ ${section} ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ${label}[[:space:]]*(.*) ]]; then
      local val="${BASH_REMATCH[1]}"
      # Clean up: remove leading dash/bullet, trim whitespace
      val=$(echo "$val" | sed 's/^[[:space:]]*-[[:space:]]*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ -n "$val" && "$val" != "Not detected" ]]; then
        echo "$val"
        return 0
      fi
    fi
  done < "$file"
}

# ── Internal: extract value from markdown table row ───────────────────
# Finds row starting with "| label |" and returns second column
_extract_table_value() {
  local file="$1"
  local label="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local result
  result=$(grep "^|[[:space:]]*${label}" "$file" 2>/dev/null | head -1 | \
    awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')

  if [[ -n "$result" && "$result" != "Not detected" ]]; then
    echo "$result"
  fi
}

# ── moira_bootstrap_populate_knowledge <project_root> <scan_results_dir>
# Populate knowledge templates with scan results.
moira_bootstrap_populate_knowledge() {
  local project_root="$1"
  local scan_results_dir="$2"

  local knowledge_dir="$project_root/.claude/moira/knowledge"
  local today
  today=$(date -u +%Y-%m-%d)

  # --- project-model (from structure-scan.md) ---
  if [[ -f "$scan_results_dir/structure-scan.md" ]]; then
    _write_knowledge_level "$knowledge_dir" "project-model" "L2" \
      "$scan_results_dir/structure-scan.md" "$today"

    # L1: condensed summary
    _condense_to_summary "$scan_results_dir/structure-scan.md" \
      "$knowledge_dir/project-model/summary.md" "$today" \
      "Source Layout|Entry points|Pattern"

    # L0: section headers only
    _condense_to_index "$scan_results_dir/structure-scan.md" \
      "$knowledge_dir/project-model/index.md" "$today"
  fi

  # --- conventions (from convention-scan.md) ---
  if [[ -f "$scan_results_dir/convention-scan.md" ]]; then
    _write_knowledge_level "$knowledge_dir" "conventions" "L2" \
      "$scan_results_dir/convention-scan.md" "$today"

    _condense_to_summary "$scan_results_dir/convention-scan.md" \
      "$knowledge_dir/conventions/summary.md" "$today" \
      "Files|Functions|Components|Module imports|Default exports|Pattern|Library"

    _condense_to_index "$scan_results_dir/convention-scan.md" \
      "$knowledge_dir/conventions/index.md" "$today"
  fi

  # --- patterns (from pattern-scan.md) ---
  if [[ -f "$scan_results_dir/pattern-scan.md" ]]; then
    _write_knowledge_level "$knowledge_dir" "patterns" "L2" \
      "$scan_results_dir/pattern-scan.md" "$today"

    _condense_to_summary "$scan_results_dir/pattern-scan.md" \
      "$knowledge_dir/patterns/summary.md" "$today" \
      "Structure:|Style:|Pattern:|Client state:|Server state:"

    _condense_to_index "$scan_results_dir/pattern-scan.md" \
      "$knowledge_dir/patterns/index.md" "$today"
  fi

  # --- quality-map (preliminary, from pattern-scan.md) ---
  if [[ -f "$scan_results_dir/pattern-scan.md" ]]; then
    local qm_tmp
    qm_tmp=$(mktemp)

    {
      echo "<!-- moira:preliminary — deep scan required -->"
      echo ""
      echo "# Quality Map (Preliminary)"
      echo ""
      echo "Generated from bootstrap pattern scan. A deep scan is required for"
      echo "comprehensive quality assessment."
      echo ""
      # Extract Common Abstractions and Recurring Structures sections
      _extract_section "$scan_results_dir/pattern-scan.md" "Common Abstractions"
      echo ""
      _extract_section "$scan_results_dir/pattern-scan.md" "Recurring Structures"
    } > "$qm_tmp"

    _write_knowledge_file "$knowledge_dir/quality-map/full.md" "$qm_tmp" "$today"

    # L1: summary
    local qm_summary_tmp
    qm_summary_tmp=$(mktemp)
    {
      echo "<!-- moira:preliminary — deep scan required -->"
      echo ""
      echo "# Quality Map Summary (Preliminary)"
      echo ""
      grep -E '^\|[^|]*\|[^|]*\|[^|]*\|' "$scan_results_dir/pattern-scan.md" 2>/dev/null | \
        grep -v '^|[[:space:]]*---' | grep -v '^|[[:space:]]*Abstraction' | \
        grep -v '^|[[:space:]]*Pattern[[:space:]]*|[[:space:]]*Frequency' || true
    } > "$qm_summary_tmp"

    _write_knowledge_file "$knowledge_dir/quality-map/summary.md" "$qm_summary_tmp" "$today"

    rm -f "$qm_tmp" "$qm_summary_tmp"
  fi

  # decisions/ and failures/ — leave as templates (no data yet)
}

# ── Internal: write knowledge level from scan file ────────────────────
_write_knowledge_level() {
  local knowledge_dir="$1"
  local ktype="$2"
  local level="$3"
  local scan_file="$4"
  local today="$5"

  local level_file
  case "$level" in
    L0) level_file="index.md" ;;
    L1) level_file="summary.md" ;;
    L2) level_file="full.md" ;;
  esac

  local target="$knowledge_dir/$ktype/$level_file"
  mkdir -p "$(dirname "$target")"

  {
    echo "<!-- moira:freshness init ${today} -->"
    echo "<!-- moira:knowledge ${ktype} ${level} -->"
    echo ""
    cat "$scan_file"
  } > "$target"
}

# ── Internal: write knowledge file with freshness ─────────────────────
_write_knowledge_file() {
  local target="$1"
  local content_file="$2"
  local today="$3"

  mkdir -p "$(dirname "$target")"

  {
    echo "<!-- moira:freshness init ${today} -->"
    echo ""
    cat "$content_file"
  } > "$target"
}

# ── Internal: condense to summary (L1) ────────────────────────────────
# Extract lines matching key patterns from scan output
_condense_to_summary() {
  local scan_file="$1"
  local target="$2"
  local today="$3"
  local patterns="$4"  # pipe-separated grep pattern

  mkdir -p "$(dirname "$target")"

  {
    echo "<!-- moira:freshness init ${today} -->"
    echo "<!-- moira:knowledge $(basename "$(dirname "$target")") L1 -->"
    echo ""
    # Extract section headers, bullet lines, and table rows matching key patterns
    grep -E "^## |^- .*(${patterns})|^\|[[:space:]]*(${patterns})" "$scan_file" 2>/dev/null || true
  } > "$target"
}

# ── Internal: condense to index (L0) ──────────────────────────────────
# Extract only section headers from scan output
_condense_to_index() {
  local scan_file="$1"
  local target="$2"
  local today="$3"

  mkdir -p "$(dirname "$target")"

  {
    echo "<!-- moira:freshness init ${today} -->"
    echo "<!-- moira:knowledge $(basename "$(dirname "$target")") L0 -->"
    echo ""
    grep '^## ' "$scan_file" 2>/dev/null || true
  } > "$target"
}

# ── Internal: extract a named section from markdown ───────────────────
_extract_section() {
  local file="$1"
  local section_name="$2"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  local in_section=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]].*${section_name} ]]; then
      in_section=true
      echo "$line"
      continue
    fi
    if $in_section; then
      if [[ "$line" =~ ^## ]]; then
        break
      fi
      echo "$line"
    fi
  done < "$file"
}

# ── moira_bootstrap_inject_claude_md <project_root> <moira_home> ──────
# Integrate Moira section into project's .claude/CLAUDE.md.
moira_bootstrap_inject_claude_md() {
  local project_root="$1"
  local moira_home="$2"

  local template="$moira_home/templates/project-claude-md.tmpl"
  local target="$project_root/.claude/CLAUDE.md"

  if [[ ! -f "$template" ]]; then
    echo "Error: CLAUDE.md template not found: $template" >&2
    return 1
  fi

  local template_content
  template_content=$(cat "$template")

  mkdir -p "$project_root/.claude"

  if [[ -f "$target" ]]; then
    # File exists — check for existing markers
    if grep -q '<!-- moira:start -->' "$target"; then
      # Replace between markers (inclusive)
      # INVARIANT: template file MUST contain both <!-- moira:start --> and <!-- moira:end --> markers
      local tmpfile tmpl_file
      tmpfile=$(mktemp)
      tmpl_file=$(mktemp)
      echo "$template_content" > "$tmpl_file"

      awk -v tmpl_path="$tmpl_file" '
      BEGIN { skip=0; printed=0 }
      /<!-- moira:start -->/ {
        skip=1;
        if (!printed) {
          while ((getline line < tmpl_path) > 0) print line;
          close(tmpl_path);
          printed=1
        }
        next
      }
      /<!-- moira:end -->/ { skip=0; next }
      !skip { print }
      ' "$target" > "$tmpfile"

      rm -f "$tmpl_file"
      mv "$tmpfile" "$target"
    else
      # No markers — append at end
      {
        echo ""
        echo "$template_content"
      } >> "$target"
    fi
  else
    # File doesn't exist — create with template content
    echo "$template_content" > "$target"
  fi
}

# ── moira_bootstrap_setup_gitignore <project_root> ────────────────────
# Ensure Moira's gitignore entries are present.
moira_bootstrap_setup_gitignore() {
  local project_root="$1"
  local gitignore="$project_root/.gitignore"

  local entries=(
    "# Moira orchestration state (per-developer)"
    ".claude/moira/state/tasks/"
    ".claude/moira/state/bypass-log.yaml"
    ".claude/moira/state/current.yaml"
    ".claude/moira/state/init/"
  )

  # If .gitignore doesn't exist, create it
  if [[ ! -f "$gitignore" ]]; then
    printf '%s\n' "${entries[@]}" > "$gitignore"
    return 0
  fi

  # Check each entry and append missing ones
  local needs_newline=false
  local to_append=""

  for entry in "${entries[@]}"; do
    # Skip comment lines for existence check
    if [[ "$entry" =~ ^# ]]; then
      continue
    fi
    if ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
      needs_newline=true
      break
    fi
  done

  if $needs_newline; then
    # Check if file ends with newline
    if [[ -s "$gitignore" ]] && [[ "$(tail -c1 "$gitignore" | xxd -p)" != "0a" ]]; then
      echo "" >> "$gitignore"
    fi

    echo "" >> "$gitignore"
    for entry in "${entries[@]}"; do
      if [[ "$entry" =~ ^# ]]; then
        # Add comment only if not already present
        if ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
          echo "$entry" >> "$gitignore"
        fi
      elif ! grep -qF "$entry" "$gitignore" 2>/dev/null; then
        echo "$entry" >> "$gitignore"
      fi
    done
  fi
}
