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

# Guard: bootstrap.sh uses BASH_REMATCH and must run under bash, not zsh
if [[ -n "${ZSH_VERSION:-}" ]]; then
  echo "Error: bootstrap.sh must run under bash, not zsh. Use: bash -c 'source ...'" >&2
  return 1 2>/dev/null || exit 1
fi

# Source dependencies from the same directory
_MOIRA_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/yaml-utils.sh"
# shellcheck source=knowledge.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/knowledge.sh"
# shellcheck source=mcp.sh
source "${_MOIRA_BOOTSTRAP_LIB_DIR}/mcp.sh"

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

  local config_file="$project_root/.moira/config.yaml"
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
  standard:
    max_retries: 2
  full:
    max_retries: 2
  decomposition:
    max_retries: 2

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
  freshness_confidence_threshold: 30
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

  local rules_dir="$project_root/.moira/project/rules"
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

# ── Internal: parse frontmatter with fallback aliases ─────────────────
# Try multiple field names in order, return first match.
# Usage: _moira_parse_frontmatter_alias <file> <field1> [field2] [field3] ...
_moira_parse_frontmatter_alias() {
  local file="$1"; shift
  local result=""
  for field in "$@"; do
    result=$(_moira_parse_frontmatter "$file" "$field")
    if [[ -n "$result" ]]; then
      echo "$result"
      return 0
    fi
  done
}

# ── Internal: generate stack.yaml ─────────────────────────────────────
_moira_bootstrap_gen_stack() {
  local tech_scan="$1"
  local output="$2"

  local language framework runtime styling orm testing ci
  language=$(_moira_parse_frontmatter_alias "$tech_scan" "language" "primary_language" "lang")
  framework=$(_moira_parse_frontmatter_alias "$tech_scan" "framework" "primary_framework")
  runtime=$(_moira_parse_frontmatter_alias "$tech_scan" "runtime" "runtime_environment")
  styling=$(_moira_parse_frontmatter_alias "$tech_scan" "styling" "css_framework" "css" "style_framework")
  orm=$(_moira_parse_frontmatter_alias "$tech_scan" "orm" "database_orm" "query_builder")
  testing=$(_moira_parse_frontmatter_alias "$tech_scan" "testing" "test_framework" "test_runner")
  ci=$(_moira_parse_frontmatter_alias "$tech_scan" "ci" "ci_cd" "ci_platform")

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
    :
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
    :
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
    :
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

  local knowledge_dir="$project_root/.moira/knowledge"
  local today
  today=$(date -u +%Y-%m-%d)

  # --- project-model (from structure-scan.md) ---
  if [[ -f "$scan_results_dir/structure-scan.md" ]]; then
    _write_knowledge_level "$knowledge_dir" "project-model" "L2" \
      "$scan_results_dir/structure-scan.md" "$today"

    # L1: condensed summary
    _condense_to_summary "$scan_results_dir/structure-scan.md" \
      "$knowledge_dir/project-model/summary.md" "$today" \
      "Source|Layout|Entry|Root|Pattern|Structure|Directory|Generated"

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
      "File|Function|Component|Import|Export|Naming|Convention|indent|quote|semicolon"

    _condense_to_index "$scan_results_dir/convention-scan.md" \
      "$knowledge_dir/conventions/index.md" "$today"
  fi

  # --- patterns (from pattern-scan.md) ---
  if [[ -f "$scan_results_dir/pattern-scan.md" ]]; then
    _write_knowledge_level "$knowledge_dir" "patterns" "L2" \
      "$scan_results_dir/pattern-scan.md" "$today"

    _condense_to_summary "$scan_results_dir/pattern-scan.md" \
      "$knowledge_dir/patterns/summary.md" "$today" \
      "Structure|Style|Pattern|State|Component|API|Handler|Fetch|Error"

    _condense_to_index "$scan_results_dir/pattern-scan.md" \
      "$knowledge_dir/patterns/index.md" "$today"
  fi

  # --- quality-map (from Ariadne structural data, if available) ---
  # Phase 15: replaced keyword-matching with Ariadne-to-knowledge pipeline
  source "$(dirname "${BASH_SOURCE[0]}")/graph.sh"
  moira_graph_populate_knowledge "$project_root" "$knowledge_dir"

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
    # Extract section headers, bullet lines (with optional **bold**), and table rows matching key patterns
    grep -E "^## |^- (\*\*)?[^*]*(${patterns})|^\|[[:space:]]*(${patterns})" "$scan_file" 2>/dev/null || true
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





# ── moira_bootstrap_inject_hooks <project_root> <moira_home> ───────────
# Inject hook configuration into .claude/settings.json and create log files.
# Failure does NOT block init.
moira_bootstrap_inject_hooks() {
  local project_root="$1"
  local moira_home="$2"

  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"

  if [[ -f "$lib_dir/settings-merge.sh" ]]; then
    source "$lib_dir/settings-merge.sh"
    # Guard: verify function exists after source (catches syntax errors)
    if declare -f moira_settings_merge_hooks &>/dev/null; then
      if moira_settings_merge_hooks "$project_root" "$moira_home"; then
        echo "Hooks configured in .claude/settings.json"
      else
        echo "Warning: Hook injection failed — configure manually" >&2
        echo "See: ~/.claude/moira/hooks/ for hook scripts" >&2
      fi
    else
      echo "Warning: settings-merge.sh loaded but function not found" >&2
    fi
  fi

  # Create empty log files (D-076: pre-create during bootstrap, not scaffold)
  local state_dir="$project_root/.moira/state"
  if [[ -d "$state_dir" ]]; then
    touch "$state_dir/violations.log" "$state_dir/tool-usage.log" "$state_dir/budget-tool-usage.log"
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
    ".moira/state/"
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

# ── moira_scan_precollect_tech <project_root> ─────────────────────────
# Pre-collect config files for the tech scanner to reduce agent budget.
# Output: .moira/state/init/raw-configs.md
moira_scan_precollect_tech() {
  local project_root="$1"
  local output_dir="${project_root}/.moira/state/init"
  local output_file="${output_dir}/raw-configs.md"
  local max_file_size=10240  # 10KB per file
  local max_total_size=102400  # 100KB total
  local total_size=0

  mkdir -p "$output_dir"

  echo "# Pre-Collected Config Files" > "$output_file"

  # Hardcoded config file list
  local config_files=(
    "package.json"
    "tsconfig.json"
    ".eslintrc"
    ".eslintrc.js"
    ".eslintrc.json"
    ".eslintrc.yml"
    ".eslintrc.yaml"
    ".prettierrc"
    ".prettierrc.js"
    ".prettierrc.json"
    ".prettierrc.yml"
    ".prettierrc.yaml"
    ".stylelintrc"
    ".stylelintrc.js"
    ".stylelintrc.json"
    "Dockerfile"
    ".dockerignore"
    ".env.example"
    "go.mod"
    "pyproject.toml"
    "setup.py"
    "setup.cfg"
    "requirements.txt"
    "Cargo.toml"
    "Gemfile"
    ".ruby-version"
    "Makefile"
    "justfile"
    ".nvmrc"
    ".node-version"
    ".tool-versions"
  )

  # Safety exclusion patterns
  _moira_precollect_is_safe() {
    local fname="$1"
    local base
    base=$(basename "$fname")
    # Skip .env files (except .env.example)
    if [[ "$base" == .env* ]] && [[ "$base" != ".env.example" ]]; then
      return 1
    fi
    # Skip files matching secret/credential/key/token patterns
    case "$base" in
      *secret*|*credential*|*key.json|*token*) return 1 ;;
    esac
    return 0
  }

  for cf in "${config_files[@]}"; do
    if [[ $total_size -ge $max_total_size ]]; then
      echo "" >> "$output_file"
      echo "[REMAINING FILES OMITTED -- output cap reached]" >> "$output_file"
      break
    fi

    local filepath="${project_root}/${cf}"
    if [[ -f "$filepath" ]]; then
      if ! _moira_precollect_is_safe "$cf"; then
        continue
      fi

      local ext="${cf##*.}"
      local file_size
      file_size=$(wc -c < "$filepath" | tr -d ' ')

      echo "" >> "$output_file"
      echo "## ${cf}" >> "$output_file"
      echo "\`\`\`${ext}" >> "$output_file"

      if [[ $file_size -gt $max_file_size ]]; then
        head -c "$max_file_size" "$filepath" >> "$output_file"
        echo "" >> "$output_file"
        echo "[TRUNCATED at 10KB -- read full file if needed]" >> "$output_file"
        total_size=$(( total_size + max_file_size ))
      else
        cat "$filepath" >> "$output_file"
        total_size=$(( total_size + file_size ))
      fi

      echo "\`\`\`" >> "$output_file"
    fi
  done

  # Glob patterns: tsconfig.*.json, docker-compose*, .github/workflows/*.yml, .github/workflows/*.yaml
  for pattern in "tsconfig.*.json" "docker-compose*"; do
    for filepath in "${project_root}"/${pattern}; do
      [[ -f "$filepath" ]] || continue
      if [[ $total_size -ge $max_total_size ]]; then
        echo "" >> "$output_file"
        echo "[REMAINING FILES OMITTED -- output cap reached]" >> "$output_file"
        break 2
      fi
      local fname
      fname=$(basename "$filepath")
      if ! _moira_precollect_is_safe "$fname"; then
        continue
      fi
      local ext="${fname##*.}"
      local file_size
      file_size=$(wc -c < "$filepath" | tr -d ' ')

      echo "" >> "$output_file"
      echo "## ${fname}" >> "$output_file"
      echo "\`\`\`${ext}" >> "$output_file"

      if [[ $file_size -gt $max_file_size ]]; then
        head -c "$max_file_size" "$filepath" >> "$output_file"
        echo "" >> "$output_file"
        echo "[TRUNCATED at 10KB -- read full file if needed]" >> "$output_file"
        total_size=$(( total_size + max_file_size ))
      else
        cat "$filepath" >> "$output_file"
        total_size=$(( total_size + file_size ))
      fi

      echo "\`\`\`" >> "$output_file"
    done
  done

  # GitHub workflows
  for filepath in "${project_root}"/.github/workflows/*.yml "${project_root}"/.github/workflows/*.yaml; do
    [[ -f "$filepath" ]] || continue
    if [[ $total_size -ge $max_total_size ]]; then
      echo "" >> "$output_file"
      echo "[REMAINING FILES OMITTED -- output cap reached]" >> "$output_file"
      break
    fi
    local fname
    fname=".github/workflows/$(basename "$filepath")"
    local ext="${filepath##*.}"
    local file_size
    file_size=$(wc -c < "$filepath" | tr -d ' ')

    echo "" >> "$output_file"
    echo "## ${fname}" >> "$output_file"
    echo "\`\`\`${ext}" >> "$output_file"

    if [[ $file_size -gt $max_file_size ]]; then
      head -c "$max_file_size" "$filepath" >> "$output_file"
      echo "" >> "$output_file"
      echo "[TRUNCATED at 10KB -- read full file if needed]" >> "$output_file"
      total_size=$(( total_size + max_file_size ))
    else
      cat "$filepath" >> "$output_file"
      total_size=$(( total_size + file_size ))
    fi

    echo "\`\`\`" >> "$output_file"
  done

  # Lock file detection
  echo "" >> "$output_file"
  echo "## Lock Files" >> "$output_file"
  for lockfile in package-lock.json yarn.lock pnpm-lock.yaml go.sum Cargo.lock Gemfile.lock; do
    if [[ -f "${project_root}/${lockfile}" ]]; then
      echo "- ${lockfile}: exists" >> "$output_file"
    else
      echo "- ${lockfile}: not found" >> "$output_file"
    fi
  done
}

# ── moira_scan_precollect_structure <project_root> ────────────────────
# Pre-collect project structure and Ariadne graph data for structure scanner.
# Output: .moira/state/init/raw-structure.md
moira_scan_precollect_structure() {
  local project_root="$1"
  local output_dir="${project_root}/.moira/state/init"
  local output_file="${output_dir}/raw-structure.md"

  mkdir -p "$output_dir"

  echo "# Pre-Collected Structure" > "$output_file"

  # Directory tree (maxdepth 2, excluding common noise)
  echo "" >> "$output_file"
  echo "## Directory Tree" >> "$output_file"
  echo "\`\`\`" >> "$output_file"
  (cd "$project_root" && find . -maxdepth 2 -type d \
    ! -path './.git' ! -path './.git/*' \
    ! -path './node_modules' ! -path './node_modules/*' \
    ! -path './.ariadne' ! -path './.ariadne/*' \
    ! -path './.claude' ! -path './.claude/*' \
    2>/dev/null | sort) >> "$output_file"
  echo "\`\`\`" >> "$output_file"

  # Source directories
  echo "" >> "$output_file"
  echo "## Source Directories" >> "$output_file"
  for src_dir in src lib app pkg cmd internal; do
    local full_path="${project_root}/${src_dir}"
    if [[ -d "$full_path" ]]; then
      echo "" >> "$output_file"
      echo "### ${src_dir}" >> "$output_file"
      echo "\`\`\`" >> "$output_file"
      (cd "$project_root" && find "./${src_dir}" -maxdepth 3 -type d 2>/dev/null | sort) >> "$output_file"
      echo "" >> "$output_file"
      ls -1 "$full_path" 2>/dev/null >> "$output_file"
      echo "\`\`\`" >> "$output_file"
    fi
  done

  # Ariadne clusters
  echo "" >> "$output_file"
  echo "## Ariadne Clusters" >> "$output_file"
  if command -v ariadne >/dev/null 2>&1; then
    local cluster_data
    cluster_data=$(cd "$project_root" && ariadne query clusters --format json 2>/dev/null | jq '.' 2>/dev/null) || true
    if [[ -n "$cluster_data" ]]; then
      echo "\`\`\`json" >> "$output_file"
      echo "$cluster_data" >> "$output_file"
      echo "\`\`\`" >> "$output_file"
    else
      echo "(ariadne not available)" >> "$output_file"
    fi
  else
    echo "(ariadne not available)" >> "$output_file"
  fi

  # Ariadne layers
  echo "" >> "$output_file"
  echo "## Ariadne Layers" >> "$output_file"
  if command -v ariadne >/dev/null 2>&1; then
    local layer_data
    layer_data=$(cd "$project_root" && ariadne query layers --format json 2>/dev/null | jq '.' 2>/dev/null) || true
    if [[ -n "$layer_data" ]]; then
      echo "\`\`\`json" >> "$output_file"
      echo "$layer_data" >> "$output_file"
      echo "\`\`\`" >> "$output_file"
    else
      echo "(ariadne not available)" >> "$output_file"
    fi
  else
    echo "(ariadne not available)" >> "$output_file"
  fi
}

# ── moira_bootstrap_scan_mcp <project_root> <scan_results_dir> ──────
# Process MCP scan results and generate registry.
# Always calls moira_mcp_generate_registry which handles both:
#   - Infrastructure MCP (Ariadne, if binary available) — added automatically (D-108)
#   - External MCP (from scanner output) — parsed from mcp-scan.md frontmatter
# The generate_registry function sets mcp.enabled based on whether any servers exist.
moira_bootstrap_scan_mcp() {
  local project_root="$1"
  local scan_results_dir="$2"

  # Always generate registry — even without scan results, infrastructure MCP
  # (e.g., Ariadne) may be available and should be registered
  local result
  result=$(moira_mcp_generate_registry "$project_root" "$scan_results_dir" 2>&1) || true
  if [[ -n "$result" ]]; then
    echo "$result"
  fi
}
