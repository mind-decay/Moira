#!/usr/bin/env bash
# bootstrap.sh — Bootstrap operations for /moira:init
# Config generation, project rules generation,
# knowledge population, CLAUDE.md integration, gitignore setup.
# Compatible with bash 3.2+ (macOS default).
#
# Responsibilities: bootstrap file generation ONLY
# Does NOT handle scanning (that's Explorer agents' job)
# Does NOT handle scaffold creation (that's scaffold.sh)

set -euo pipefail

# Source dependencies from the same directory
_MOIRA_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/yaml-utils.sh"
# shellcheck source=knowledge.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/knowledge.sh"

# ── _moira_parse_frontmatter <file> <field> ────────────────────────────
# Read a scalar value from YAML frontmatter (between --- delimiters).
# Returns empty string if file missing, no frontmatter, or field not found.
_moira_parse_frontmatter() {
  local file="$1"
  local field="$2"

  [[ -f "$file" ]] || return 0

  local in_frontmatter=false
  local found_start=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if $found_start; then
        # Second --- = end of frontmatter
        return 0
      fi
      found_start=true
      in_frontmatter=true
      continue
    fi
    if $in_frontmatter; then
      if [[ "$line" =~ ^${field}:[[:space:]]+(.*) ]]; then
        local val="${BASH_REMATCH[1]}"
        # Trim trailing whitespace
        val="${val%"${val##*[! ]}"}"
        echo "$val"
        return 0
      fi
    fi
  done < "$file"
}

# ── _moira_parse_frontmatter_list <file> <field> ──────────────────────
# Read a list value from YAML frontmatter. Outputs one item per line.
# Returns empty string if file missing, no frontmatter, or field not found.
_moira_parse_frontmatter_list() {
  local file="$1"
  local field="$2"

  [[ -f "$file" ]] || return 0

  local in_frontmatter=false
  local found_start=false
  local found_field=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      if $found_start; then
        return 0
      fi
      found_start=true
      in_frontmatter=true
      continue
    fi
    if $in_frontmatter; then
      if $found_field; then
        if [[ "$line" =~ ^[[:space:]]{2}-[[:space:]]+(.*) ]]; then
          echo "${BASH_REMATCH[1]}"
        else
          # Non-list-item line = end of list
          return 0
        fi
      elif [[ "$line" =~ ^${field}:[[:space:]]*$ ]]; then
        found_field=true
      fi
    fi
  done < "$file"
}

# ── moira_bootstrap_generate_config <project_root> <tech_scan_path> ────
# Generate config.yaml from tech scan frontmatter.
moira_bootstrap_generate_config() {
  local project_root="$1"
  local tech_scan_path="$2"

  local config_file="$project_root/.claude/moira/config.yaml"
  mkdir -p "$(dirname "$config_file")"

  # Extract stack from frontmatter: framework → language → generic
  local stack_id
  stack_id=$(_moira_parse_frontmatter "$tech_scan_path" "framework")
  if [[ -z "$stack_id" ]]; then
    stack_id=$(_moira_parse_frontmatter "$tech_scan_path" "language")
  fi
  if [[ -z "$stack_id" ]]; then
    stack_id="generic"
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
  evolution:
    current_target: ""
    cooldown_remaining: 0

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

# ── moira_bootstrap_generate_project_rules <project_root> <scan_results_dir> ──
# Generate Layer 3 project rules from scanner frontmatter.
moira_bootstrap_generate_project_rules() {
  local project_root="$1"
  local scan_results_dir="$2"

  local rules_dir="$project_root/.claude/moira/project/rules"
  mkdir -p "$rules_dir"

  # --- stack.yaml ---
  _moira_bootstrap_gen_stack "$scan_results_dir/tech-scan.md" "$rules_dir/stack.yaml"

  # --- conventions.yaml ---
  _moira_bootstrap_gen_conventions "$scan_results_dir/convention-scan.md" "$scan_results_dir/structure-scan.md" "$rules_dir/conventions.yaml"

  # --- patterns.yaml ---
  _moira_bootstrap_gen_patterns "$scan_results_dir/pattern-scan.md" "$rules_dir/patterns.yaml"

  # --- boundaries.yaml ---
  _moira_bootstrap_gen_boundaries "$scan_results_dir/structure-scan.md" "$rules_dir/boundaries.yaml"
}

# ── Internal: generate stack.yaml ─────────────────────────────────────
_moira_bootstrap_gen_stack() {
  local tech_scan="$1"
  local output="$2"

  local language framework runtime styling orm testing ci
  language=$(_moira_parse_frontmatter "$tech_scan" "language")
  framework=$(_moira_parse_frontmatter "$tech_scan" "framework")
  runtime=$(_moira_parse_frontmatter "$tech_scan" "runtime")
  styling=$(_moira_parse_frontmatter "$tech_scan" "styling")
  orm=$(_moira_parse_frontmatter "$tech_scan" "orm")
  testing=$(_moira_parse_frontmatter "$tech_scan" "testing")
  ci=$(_moira_parse_frontmatter "$tech_scan" "ci")

  {
    echo "# Stack configuration — generated by /moira:init"
    echo ""
    [[ -n "$language" ]] && echo "language: ${language}"
    [[ -n "$framework" ]] && echo "framework: ${framework}"
    [[ -n "$runtime" ]] && echo "runtime: ${runtime}"
    [[ -n "$styling" ]] && echo "styling: ${styling}"
    [[ -n "$orm" ]] && echo "orm: ${orm}"
    [[ -n "$testing" ]] && echo "testing: ${testing}"
    [[ -n "$ci" ]] && echo "ci: ${ci}"
  } > "$output"
}

# ── Internal: generate conventions.yaml ───────────────────────────────
_moira_bootstrap_gen_conventions() {
  local convention_scan="$1"
  local structure_scan="$2"
  local output="$3"

  # Naming fields from convention-scan frontmatter
  local file_naming func_naming comp_naming const_naming type_naming
  file_naming=$(_moira_parse_frontmatter "$convention_scan" "naming_files")
  func_naming=$(_moira_parse_frontmatter "$convention_scan" "naming_functions")
  comp_naming=$(_moira_parse_frontmatter "$convention_scan" "naming_components")
  const_naming=$(_moira_parse_frontmatter "$convention_scan" "naming_constants")
  type_naming=$(_moira_parse_frontmatter "$convention_scan" "naming_types")

  # Formatting fields from convention-scan frontmatter
  local indent quotes semicolons max_line
  indent=$(_moira_parse_frontmatter "$convention_scan" "indent")
  quotes=$(_moira_parse_frontmatter "$convention_scan" "quotes")
  semicolons=$(_moira_parse_frontmatter "$convention_scan" "semicolons")
  max_line=$(_moira_parse_frontmatter "$convention_scan" "max_line_length")

  {
    echo "# Conventions — generated by /moira:init"
    echo ""

    # Naming section — only if at least one field detected
    local has_naming=false
    [[ -n "$file_naming" || -n "$func_naming" || -n "$comp_naming" || -n "$const_naming" || -n "$type_naming" ]] && has_naming=true
    if $has_naming; then
      echo "naming:"
      [[ -n "$file_naming" ]] && echo "  files: ${file_naming}"
      [[ -n "$func_naming" ]] && echo "  functions: ${func_naming}"
      [[ -n "$comp_naming" ]] && echo "  components: ${comp_naming}"
      [[ -n "$const_naming" ]] && echo "  constants: ${const_naming}"
      [[ -n "$type_naming" ]] && echo "  types: ${type_naming}"
      echo ""
    fi

    # Formatting section — only if at least one field detected
    local has_formatting=false
    [[ -n "$indent" || -n "$quotes" || -n "$semicolons" || -n "$max_line" ]] && has_formatting=true
    if $has_formatting; then
      echo "formatting:"
      [[ -n "$indent" ]] && echo "  indent: ${indent}"
      [[ -n "$quotes" ]] && echo "  quotes: ${quotes}"
      [[ -n "$semicolons" ]] && echo "  semicolons: ${semicolons}"
      [[ -n "$max_line" ]] && echo "  max_line_length: ${max_line}"
      echo ""
    fi

    # Structure section from structure-scan dir_* fields
    if [[ -f "$structure_scan" ]]; then
      local dir_fields=""
      local in_frontmatter=false
      local found_start=false
      while IFS= read -r line; do
        if [[ "$line" == "---" ]]; then
          if $found_start; then
            break
          fi
          found_start=true
          in_frontmatter=true
          continue
        fi
        if $in_frontmatter && [[ "$line" =~ ^dir_([^:]+):[[:space:]]+(.*) ]]; then
          local role="${BASH_REMATCH[1]}"
          local path="${BASH_REMATCH[2]}"
          path="${path%"${path##*[! ]}"}"
          dir_fields+="  ${role}: ${path}"$'\n'
        fi
      done < "$structure_scan"

      if [[ -n "$dir_fields" ]]; then
        echo "structure:"
        printf '%s' "$dir_fields"
      fi
    fi
  } > "$output"
}

# ── Internal: generate patterns.yaml ──────────────────────────────────
_moira_bootstrap_gen_patterns() {
  local pattern_scan="$1"
  local output="$2"

  local data_fetching error_handling api_style api_validation
  local component_structure component_state component_styling
  local client_state server_state
  data_fetching=$(_moira_parse_frontmatter "$pattern_scan" "data_fetching")
  error_handling=$(_moira_parse_frontmatter "$pattern_scan" "error_handling")
  api_style=$(_moira_parse_frontmatter "$pattern_scan" "api_style")
  api_validation=$(_moira_parse_frontmatter "$pattern_scan" "api_validation")
  component_structure=$(_moira_parse_frontmatter "$pattern_scan" "component_structure")
  component_state=$(_moira_parse_frontmatter "$pattern_scan" "component_state")
  component_styling=$(_moira_parse_frontmatter "$pattern_scan" "component_styling")
  client_state=$(_moira_parse_frontmatter "$pattern_scan" "client_state")
  server_state=$(_moira_parse_frontmatter "$pattern_scan" "server_state")

  {
    echo "# Patterns — generated by /moira:init"
    echo ""
    [[ -n "$data_fetching" ]] && echo "data_fetching: ${data_fetching}"
    [[ -n "$error_handling" ]] && echo "error_handling: ${error_handling}"
    [[ -n "$api_style" ]] && echo "api_style: ${api_style}"
    [[ -n "$api_validation" ]] && echo "api_validation: ${api_validation}"
    [[ -n "$component_structure" ]] && echo "component_structure: ${component_structure}"
    [[ -n "$component_state" ]] && echo "component_state: ${component_state}"
    [[ -n "$component_styling" ]] && echo "component_styling: ${component_styling}"
    [[ -n "$client_state" ]] && echo "client_state: ${client_state}"
    [[ -n "$server_state" ]] && echo "server_state: ${server_state}"
  } > "$output"
}

# ── Internal: generate boundaries.yaml ────────────────────────────────
_moira_bootstrap_gen_boundaries() {
  local structure_scan="$1"
  local output="$2"

  # Read lists from structure-scan frontmatter
  local dnm_list mwc_list
  dnm_list=$(_moira_parse_frontmatter_list "$structure_scan" "do_not_modify")
  mwc_list=$(_moira_parse_frontmatter_list "$structure_scan" "modify_with_caution")

  {
    echo "# Boundaries — generated by /moira:init"
    echo ""
    echo "do_not_modify:"
    if [[ -n "$dnm_list" ]]; then
      while IFS= read -r entry; do
        echo "  - ${entry}"
      done <<< "$dnm_list"
    else
      echo "  # none detected"
    fi
    echo ""
    echo "modify_with_caution:"
    if [[ -n "$mwc_list" ]]; then
      while IFS= read -r entry; do
        echo "  - ${entry}"
      done <<< "$mwc_list"
    else
      echo "  # none detected"
    fi
  } > "$output"
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
    _moira_bootstrap_gen_quality_map "$scan_results_dir/pattern-scan.md" \
      "$knowledge_dir" "$today"
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

# ── Internal: generate quality map from pattern scan ───────────────────
# Categorizes patterns into Strong/Adequate/Problematic based on scan observations.
# All entries are medium confidence (from scan, not task evidence).
_moira_bootstrap_gen_quality_map() {
  local pattern_scan="$1"
  local knowledge_dir="$2"
  local today="$3"

  local qm_full_tmp qm_summary_tmp
  qm_full_tmp=$(mktemp)
  qm_summary_tmp=$(mktemp)

  # Parse pattern scan for consistency signals
  # Patterns with "consistent" / "uniform" / "always" → Strong
  # Patterns with "mixed" / "inconsistent" / "varies" / "some" → Adequate
  # Patterns with "missing" / "broken" / "TODO" / "FIXME" / "deprecated" → Problematic

  local strong_patterns="" adequate_patterns="" problematic_patterns=""
  local current_pattern="" current_location="" current_evidence=""
  local in_pattern=false
  local loc_pat='Location:|Directory:|Path:'

  while IFS= read -r line; do
    # Detect pattern entries (### headers or table rows)
    if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
      # Flush previous pattern
      if [[ -n "$current_pattern" ]]; then
        _classify_pattern "$current_pattern" "$current_location" "$current_evidence" \
          "$pattern_scan" "$today"
      fi
      current_pattern="${BASH_REMATCH[1]}"
      current_location=""
      current_evidence="bootstrap scan"
      in_pattern=true
      continue
    fi
    if $in_pattern; then
      if [[ "$line" =~ $loc_pat ]]; then
        current_location=$(echo "$line" | sed 's/.*:\s*//')
      fi
    fi
  done < "$pattern_scan"

  # Flush last pattern
  if [[ -n "$current_pattern" ]]; then
    _classify_pattern "$current_pattern" "$current_location" "$current_evidence" \
      "$pattern_scan" "$today"
  fi

  # Build quality map using classified patterns (from _classify_pattern output)
  {
    echo "<!-- moira:freshness init ${today} -->"
    echo "<!-- moira:preliminary — deep scan required -->"
    echo "<!-- moira:mode conform -->"
    echo ""
    echo "# Quality Map"
    echo ""
    echo "## ✅ Strong Patterns"
    echo ""
    _build_pattern_section "$pattern_scan" "consistent|uniform|always|standard"
    echo ""
    echo "## ⚠️ Adequate Patterns"
    echo ""
    _build_pattern_section "$pattern_scan" "mixed|inconsistent|varies|some|partial"
    echo ""
    echo "## 🔴 Problematic Patterns"
    echo ""
    _build_pattern_section "$pattern_scan" "missing|broken|TODO|FIXME|deprecated|hack"
  } > "$qm_full_tmp"

  _write_knowledge_file "$knowledge_dir/quality-map/full.md" "$qm_full_tmp" "$today"

  # L1: summary
  {
    echo "<!-- moira:freshness init ${today} -->"
    echo "<!-- moira:preliminary — deep scan required -->"
    echo ""
    echo "# Quality Map Summary"
    echo ""
    echo "## Strong (follow):"
    _list_matching_patterns "$pattern_scan" "consistent|uniform|always|standard"
    echo ""
    echo "## Adequate (follow with notes):"
    _list_matching_patterns "$pattern_scan" "mixed|inconsistent|varies|some|partial"
    echo ""
    echo "## Problematic (don't extend):"
    _list_matching_patterns "$pattern_scan" "missing|broken|TODO|FIXME|deprecated|hack"
  } > "$qm_summary_tmp"

  _write_knowledge_file "$knowledge_dir/quality-map/summary.md" "$qm_summary_tmp" "$today"

  rm -f "$qm_full_tmp" "$qm_summary_tmp"
}

# ── Internal: classify a pattern based on scan text ────────────────────
_classify_pattern() {
  # Used internally by _moira_bootstrap_gen_quality_map
  # Classification happens in _build_pattern_section via grep
  :
}

# ── Internal: build pattern section by keyword matching ────────────────
_build_pattern_section() {
  local scan_file="$1"
  local keywords="$2"

  # Find ### headers whose following text matches keywords
  local current_header="" current_block="" found=false
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
      # Flush previous
      if $found && [[ -n "$current_header" ]]; then
        echo "### $current_header"
        echo "- **Category**: detected"
        echo "- **Evidence**: bootstrap scan"
        echo "- **Confidence**: medium"
        echo ""
      fi
      current_header="${BASH_REMATCH[1]}"
      current_block=""
      found=false
      continue
    fi
    if [[ -n "$current_header" ]]; then
      current_block+="$line "
      if echo "$line" | grep -qiE "$keywords" 2>/dev/null; then
        found=true
      fi
    fi
    # Stop at next ## header
    if [[ "$line" =~ ^##[[:space:]] ]] && [[ -n "$current_header" ]]; then
      if $found; then
        echo "### $current_header"
        echo "- **Category**: detected"
        echo "- **Evidence**: bootstrap scan"
        echo "- **Confidence**: medium"
        echo ""
      fi
      current_header=""
      current_block=""
      found=false
    fi
  done < "$scan_file"

  # Flush last
  if $found && [[ -n "$current_header" ]]; then
    echo "### $current_header"
    echo "- **Category**: detected"
    echo "- **Evidence**: bootstrap scan"
    echo "- **Confidence**: medium"
    echo ""
  fi
}

# ── Internal: list pattern names matching keywords ─────────────────────
_list_matching_patterns() {
  local scan_file="$1"
  local keywords="$2"

  local current_header="" current_block="" found=false
  local names=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
      if $found && [[ -n "$current_header" ]]; then
        if [[ -n "$names" ]]; then
          names+=", "
        fi
        names+="$current_header"
      fi
      current_header="${BASH_REMATCH[1]}"
      current_block=""
      found=false
      continue
    fi
    if [[ -n "$current_header" ]]; then
      if echo "$line" | grep -qiE "$keywords" 2>/dev/null; then
        found=true
      fi
    fi
  done < "$scan_file"

  # Flush last
  if $found && [[ -n "$current_header" ]]; then
    if [[ -n "$names" ]]; then
      names+=", "
    fi
    names+="$current_header"
  fi

  if [[ -n "$names" ]]; then
    echo "$names"
  else
    echo "None detected yet"
  fi
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
