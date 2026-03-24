#!/usr/bin/env bash
# rules.sh — Rule layer loading, conflict detection, and instruction file assembly
# Built on yaml-utils.sh and knowledge.sh (bash 3.2+ compatible, no jq/python).
#
# Responsibilities: rule assembly ONLY
# Does NOT handle pipeline logic or agent dispatch

set -euo pipefail

# Source dependencies from the same directory
_MOIRA_RULES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_RULES_LIB_DIR}/yaml-utils.sh"
# shellcheck source=knowledge.sh
source "${_MOIRA_RULES_LIB_DIR}/knowledge.sh"

# ── moira_rules_load_layer <layer_number> <source_path> ──────────────
# Load a single rule layer from file. Outputs structured content to stdout.
moira_rules_load_layer() {
  local layer="$1"
  local source_path="$2"

  case "$layer" in
    1)
      # L1: base.yaml — extract inviolable + overridable
      if [[ ! -f "$source_path" ]]; then
        echo "Error: base rules not found: $source_path" >&2
        return 1
      fi

      echo "=== LAYER 1: BASE RULES ==="
      echo ""
      echo "--- INVIOLABLE ---"
      # Extract inviolable rule texts
      awk '
        /^inviolable:/ { in_inv=1; next }
        /^[a-z]/ && in_inv { in_inv=0 }
        in_inv && /rule:/ {
          sub(/.*rule:[[:space:]]*"?/, "")
          sub(/"[[:space:]]*$/, "")
          print "- " $0
        }
      ' "$source_path"
      echo ""
      echo "--- OVERRIDABLE ---"
      awk '
        /^overridable:/ { in_over=1; next }
        /^[a-z]/ && in_over { in_over=0 }
        in_over && /^  [a-z]/ {
          sub(/^  /, "")
          print $0
        }
      ' "$source_path"
      ;;

    2)
      # L2: role yaml — extract identity, never, quality_checklist
      if [[ ! -f "$source_path" ]]; then
        echo "Error: role file not found: $source_path" >&2
        return 1
      fi

      echo "=== LAYER 2: ROLE RULES ==="
      echo ""
      echo "--- IDENTITY ---"
      # Extract multiline identity field
      awk '
        /^identity: \|/ { in_id=1; next }
        in_id && /^[a-z_]/ { in_id=0 }
        in_id { print }
      ' "$source_path"
      echo ""
      echo "--- NEVER ---"
      awk '
        /^never:/ { in_never=1; next }
        /^[a-z_]/ && in_never { in_never=0 }
        in_never && /^[[:space:]]*- / {
          sub(/^[[:space:]]*- /, "- ")
          gsub(/^- ["'\''"]|["'\''"]$/, "")
          if (/^[^-]/) $0 = "- " $0
          print
        }
      ' "$source_path"
      echo ""
      echo "--- QUALITY_CHECKLIST ---"
      local qc
      qc=$(moira_yaml_get "$source_path" "quality_checklist" 2>/dev/null) || true
      echo "${qc:-null}"
      ;;

    3)
      # L3: project rules directory — extract all yaml key-values
      if [[ ! -d "$source_path" ]]; then
        echo "Error: project rules directory not found: $source_path" >&2
        return 1
      fi

      echo "=== LAYER 3: PROJECT RULES ==="
      for rule_file in "$source_path"/*.yaml; do
        [[ -f "$rule_file" ]] || continue
        local fname
        fname=$(basename "$rule_file" .yaml)
        echo ""
        echo "--- ${fname^^} ---"
        cat "$rule_file"
      done
      ;;

    4)
      # L4: task-specific content — output as-is
      if [[ ! -f "$source_path" ]]; then
        echo "Error: task context file not found: $source_path" >&2
        return 1
      fi

      echo "=== LAYER 4: TASK CONTEXT ==="
      echo ""
      cat "$source_path"
      ;;

    *)
      echo "Error: invalid layer number '$layer' (must be 1-4)" >&2
      return 1
      ;;
  esac

  return 0
}

# ── moira_rules_detect_conflicts <base_file> <project_rules_dir> ─────
# Detect conflicts between L1 overridable/inviolable and L3 project rules.
# Returns exit code 1 if inviolable conflict detected.
moira_rules_detect_conflicts() {
  local base_file="$1"
  local project_rules_dir="$2"

  if [[ ! -f "$base_file" ]]; then
    echo "Error: base rules not found: $base_file" >&2
    return 1
  fi

  if [[ ! -d "$project_rules_dir" ]]; then
    # No project rules = no conflicts
    return 0
  fi

  local has_inviolable_conflict=false

  # Extract L1 overridable keys and values
  local overridable_keys
  overridable_keys=$(awk '
    /^overridable:/ { in_over=1; next }
    /^[a-z]/ && in_over { in_over=0 }
    in_over && /^  [a-z]/ {
      sub(/^  /, "")
      print
    }
  ' "$base_file")

  # Extract L1 inviolable rule texts for checking
  local inviolable_rules
  inviolable_rules=$(awk '
    /^inviolable:/ { in_inv=1; next }
    /^[a-z]/ && in_inv { in_inv=0 }
    in_inv && /rule:/ {
      sub(/.*rule:[[:space:]]*"?/, "")
      sub(/"[[:space:]]*$/, "")
      print
    }
  ' "$base_file")

  # Check each L1 overridable key against L3 project rules
  while IFS= read -r overridable_line; do
    [[ -z "$overridable_line" ]] && continue
    local l1_key="${overridable_line%%:*}"
    local l1_val="${overridable_line#*: }"
    l1_key=$(echo "$l1_key" | tr -d ' ')
    l1_val=$(echo "$l1_val" | tr -d ' ')

    # Check for direct key match in project rules
    for rule_file in "$project_rules_dir"/*.yaml; do
      [[ -f "$rule_file" ]] || continue

      local l3_val=""

      # Direct key match
      l3_val=$(grep "^${l1_key}:" "$rule_file" 2>/dev/null | head -1 | sed "s/^${l1_key}:[[:space:]]*//" || true)

      # Nested key match for specific mappings
      if [[ -z "$l3_val" ]]; then
        case "$l1_key" in
          naming_convention)
            # Check for any naming: sub-key
            if grep -q "^naming:" "$rule_file" 2>/dev/null; then
              l3_val="(project-specific naming rules)"
            fi
            ;;
          indent)
            l3_val=$(grep "indent:" "$rule_file" 2>/dev/null | head -1 | sed 's/.*indent:[[:space:]]*//' || true)
            ;;
          test_framework)
            l3_val=$(grep "testing:" "$rule_file" 2>/dev/null | head -1 | sed 's/.*testing:[[:space:]]*//' || true)
            ;;
        esac
      fi

      if [[ -n "$l3_val" ]]; then
        l3_val=$(echo "$l3_val" | tr -d ' ')
        if [[ "$l1_val" != "$l3_val" ]]; then
          local fname
          fname=$(basename "$rule_file")
          echo "CONFLICT: ${l1_key}"
          echo "  L1 (base): ${l1_val}"
          echo "  L3 (${fname}): ${l3_val}"
          echo "  RESOLUTION: L3 wins (project override)"
          echo ""
        fi
      fi
    done
  done <<< "$overridable_keys"

  # Check if any L3 keys attempt to override inviolable rules
  # Keyword heuristic: look for project rule KEYS (not comments) that contradict inviolable constraints
  # Only matches key-value lines (key: value or key = value), ignoring comments (#)
  for rule_file in "$project_rules_dir"/*.yaml; do
    [[ -f "$rule_file" ]] || continue

    # Strip comments before checking — only match actual rule keys/values
    local rule_content
    rule_content=$(sed 's/#.*$//' "$rule_file")

    if echo "$rule_content" | grep -qiE '^[[:space:]]*[a-z_]*fabricat[a-z_]*[[:space:]]*[:=]' 2>/dev/null; then
      echo "INVIOLABLE CONFLICT: project rules attempt to override fabrication prohibition" >&2
      has_inviolable_conflict=true
    fi
    if echo "$rule_content" | grep -qiE '^[[:space:]]*(suppress_error|ignore_error|skip_error)[[:space:]]*[:=]' 2>/dev/null; then
      echo "INVIOLABLE CONFLICT: project rules attempt to override error suppression prohibition" >&2
      has_inviolable_conflict=true
    fi
  done

  if $has_inviolable_conflict; then
    return 1
  fi

  return 0
}

# ── moira_rules_project_rules_for_agent <agent_name> <project_rules_dir>
# Returns list of relevant project rule files for a given agent (space-separated paths).
moira_rules_project_rules_for_agent() {
  local agent_name="$1"
  local project_rules_dir="$2"

  if [[ ! -d "$project_rules_dir" ]]; then
    return 0
  fi

  local relevant_files=""

  case "$agent_name" in
    hephaestus|themis|aletheia|mnemosyne|argus)
      # Full access: stack, conventions, patterns, boundaries
      for f in stack.yaml conventions.yaml patterns.yaml boundaries.yaml; do
        [[ -f "$project_rules_dir/$f" ]] && relevant_files+="$project_rules_dir/$f "
      done
      ;;
    metis)
      # stack, patterns, boundaries (no conventions)
      for f in stack.yaml patterns.yaml boundaries.yaml; do
        [[ -f "$project_rules_dir/$f" ]] && relevant_files+="$project_rules_dir/$f "
      done
      ;;
    daedalus)
      # stack, conventions
      for f in stack.yaml conventions.yaml; do
        [[ -f "$project_rules_dir/$f" ]] && relevant_files+="$project_rules_dir/$f "
      done
      ;;
    hermes|apollo|athena)
      # stack only (minimal context)
      [[ -f "$project_rules_dir/stack.yaml" ]] && relevant_files+="$project_rules_dir/stack.yaml "
      ;;
    *)
      # Unknown agent — stack only as safe default
      [[ -f "$project_rules_dir/stack.yaml" ]] && relevant_files+="$project_rules_dir/stack.yaml "
      ;;
  esac

  echo "$relevant_files" | sed 's/[[:space:]]*$//'
  return 0
}

# ── moira_rules_assemble_instruction <output_path> <agent_name> <base_file> <role_file> <project_rules_dir> <knowledge_dir> <task_context_file> <matrix_file>
# Assemble a complete agent instruction file.
moira_rules_assemble_instruction() {
  local output_path="$1"
  local agent_name="$2"
  local base_file="$3"
  local role_file="$4"
  local project_rules_dir="$5"
  local knowledge_dir="$6"
  local task_context_file="$7"
  local matrix_file="$8"

  # Validate inputs
  if [[ ! -f "$base_file" ]]; then
    echo "Error: base rules not found: $base_file" >&2
    return 1
  fi
  if [[ ! -f "$role_file" ]]; then
    echo "Error: role file not found: $role_file" >&2
    return 1
  fi
  if [[ ! -f "$task_context_file" ]]; then
    echo "Error: task context file not found: $task_context_file" >&2
    return 1
  fi

  # Create output directory
  mkdir -p "$(dirname "$output_path")"

  # Run conflict detection (non-fatal for missing project rules dir)
  if [[ -d "$project_rules_dir" ]]; then
    local conflict_output
    conflict_output=$(moira_rules_detect_conflicts "$base_file" "$project_rules_dir" 2>&1)
    local conflict_rc=$?
    if [[ $conflict_rc -ne 0 ]]; then
      echo "Error: inviolable rule conflict detected — cannot assemble instruction" >&2
      echo "$conflict_output" >&2
      return 1
    fi
  fi

  # Extract display name and role from role file
  local display_name role_name identity
  display_name=$(moira_yaml_get "$role_file" "_meta.name" 2>/dev/null || echo "$agent_name")
  role_name=$(moira_yaml_get "$role_file" "_meta.role" 2>/dev/null || echo "agent")

  # Capitalize display name
  display_name="$(echo "${display_name:0:1}" | tr '[:lower:]' '[:upper:]')${display_name:1}"

  # Extract identity (multiline)
  identity=$(awk '
    /^identity: \|/ { in_id=1; next }
    in_id && /^[a-z_]/ { in_id=0 }
    in_id { print }
  ' "$role_file")

  # Extract inviolable rules
  local inviolable_rules
  inviolable_rules=$(awk '
    /^inviolable:/ { in_inv=1; next }
    /^[a-z]/ && in_inv { in_inv=0 }
    in_inv && /rule:/ {
      sub(/.*rule:[[:space:]]*"?/, "")
      sub(/"[[:space:]]*$/, "")
      print "- " $0
    }
  ' "$base_file")

  # Extract role constraints (never)
  local role_constraints
  role_constraints=$(awk '
    /^never:/ { in_never=1; next }
    /^[a-z_]/ && in_never { in_never=0 }
    in_never && /^[[:space:]]*- / {
      sub(/^[[:space:]]*- /, "- ")
      gsub(/^- ["'\''"]|["'\''"]$/, "")
      if (/^[^-]/) $0 = "- " $0
      print
    }
  ' "$role_file")

  # Assemble project rules section
  local project_rules_section=""
  if [[ -d "$project_rules_dir" ]]; then
    local relevant_files
    relevant_files=$(moira_rules_project_rules_for_agent "$agent_name" "$project_rules_dir")
    if [[ -n "$relevant_files" ]]; then
      for rf in $relevant_files; do
        [[ -f "$rf" ]] || continue
        local section_name
        section_name=$(basename "$rf" .yaml)
        section_name="$(echo "${section_name:0:1}" | tr '[:lower:]' '[:upper:]')${section_name:1}"
        project_rules_section+="### ${section_name}"$'\n'
        project_rules_section+=$'\n'
        project_rules_section+="$(cat "$rf")"$'\n'
        project_rules_section+=$'\n'
      done
    fi
  fi

  # Read knowledge for this agent
  local knowledge_section=""
  if [[ -d "$knowledge_dir" ]] && [[ -f "$matrix_file" ]]; then
    knowledge_section=$(moira_knowledge_read_for_agent "$knowledge_dir" "$agent_name" "$matrix_file" 2>/dev/null) || true
  fi

  # Read quality checklist
  local quality_section=""
  local qc_ref
  qc_ref=$(moira_yaml_get "$role_file" "quality_checklist" 2>/dev/null) || true
  if [[ -n "$qc_ref" && "$qc_ref" != "null" ]]; then
    local qc_file="${MOIRA_HOME:-$HOME/.claude/moira}/core/rules/quality/${qc_ref}.yaml"
    if [[ -f "$qc_file" ]]; then
      # Format checklist items as markdown
      quality_section=$(awk '
        /^items:/ { in_items=1; next }
        /^[a-z]/ && in_items { in_items=0 }
        in_items && /check:/ {
          sub(/.*check:[[:space:]]*"?/, "")
          sub(/"[[:space:]]*$/, "")
          print "- [ ] " $0
        }
      ' "$qc_file")
      if [[ -z "$quality_section" ]]; then
        # Fallback: include entire file
        quality_section=$(cat "$qc_file")
      fi
    fi
  fi

  # Determine artifact output path
  local task_dir
  task_dir="$(dirname "$(dirname "$output_path")")"
  local artifact_path="${task_dir}/${agent_name}.md"

  # Write the assembled instruction file
  {
    echo "# Instructions for ${display_name} (${role_name})"
    echo ""
    echo "## Identity"
    echo ""
    echo "$identity"
    echo ""
    echo "## Rules"
    echo ""
    echo "### Inviolable (NEVER violate -- Constitution enforced)"
    echo ""
    echo "$inviolable_rules"
    echo ""
    echo "### Role Constraints"
    echo ""
    echo "$role_constraints"

    if [[ -n "$project_rules_section" ]]; then
      echo ""
      echo "### Project Rules"
      echo ""
      echo "$project_rules_section"
    fi

    if [[ -n "$knowledge_section" ]]; then
      echo ""
      echo "## Knowledge"
      echo ""
      echo "$knowledge_section"
    fi

    if [[ -n "$quality_section" ]]; then
      echo ""
      echo "## Quality Checklist"
      echo ""
      echo "$quality_section"
    fi

    # D-115: Infrastructure MCP injection — all agents, all pipelines
    local infra_mcp_section
    infra_mcp_section=$(moira_mcp_format_infrastructure_section "$project_root" 2>/dev/null)
    if [[ -n "$infra_mcp_section" ]]; then
      echo ""
      echo "$infra_mcp_section"
    fi

    echo ""
    echo "## Response Contract"
    echo ""
    echo "STATUS: success|failure|blocked|budget_exceeded"
    echo "SUMMARY: <1-2 sentences, factual>"
    echo "ARTIFACTS: [<list of file paths written>]"
    echo "NEXT: <recommended next pipeline step>"
    echo "QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)  [only if quality gate assigned]"
    echo ""
    echo "Write all detailed output to artifact files. Return ONLY the status summary above."
    echo ""
    echo "## Task"
    echo ""
    cat "$task_context_file"
    echo ""
    echo "## Output"
    echo ""
    echo "Write your detailed results to: ${artifact_path}"
  } > "$output_path"

  # D-113: Instruction size validation
  # Estimate token count (file_size_bytes / 4, per D-056)
  local file_size instruction_tokens
  file_size=$(wc -c < "$output_path" 2>/dev/null || echo 0)
  instruction_tokens=$(( file_size / 4 ))

  if [[ $instruction_tokens -gt 50000 ]]; then
    echo "Warning: instruction size ~${instruction_tokens} tokens exceeds 50k threshold for ${agent_name}" >&2
    echo "INSTRUCTION_SIZE_WARNING: ${instruction_tokens}" >&2
  fi

  return 0
}

# ── CPM (Critical Path Method) Batch Scheduling ─────────────────────
# Pure-bash DAG scheduling for Daedalus planner.
# All functions use parallel indexed arrays (bash 3.2+ compatible).

# ── moira_rules_cpm_schedule <dep_graph_yaml> ────────────────────────
# Takes a dependency graph YAML file (nodes + dependencies).
# Outputs phase assignments as "node_id: phase_N" lines.
# Algorithm: topological sort -> forward pass (earliest_start) -> group by phase.
moira_rules_cpm_schedule() {
  local dep_graph_yaml="$1"

  if [[ ! -f "$dep_graph_yaml" ]]; then
    echo "Error: dependency graph not found: $dep_graph_yaml" >&2
    return 1
  fi

  # Parse nodes: extract id and estimated_tokens into parallel arrays
  local node_ids=()
  local node_tokens=()
  local _id _tokens
  while IFS= read -r _id; do
    node_ids+=("$_id")
  done < <(awk '
    /^nodes:/ { in_nodes=1; next }
    /^[a-z]/ && in_nodes { in_nodes=0 }
    in_nodes && /id:/ {
      sub(/.*id:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  while IFS= read -r _tokens; do
    node_tokens+=("$_tokens")
  done < <(awk '
    /^nodes:/ { in_nodes=1; next }
    /^[a-z]/ && in_nodes { in_nodes=0 }
    in_nodes && /estimated_tokens:/ {
      sub(/.*estimated_tokens:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  local node_count=${#node_ids[@]}
  if [[ $node_count -eq 0 ]]; then
    echo "Error: no nodes found in dependency graph" >&2
    return 1
  fi

  # Parse dependencies: from -> to edges
  local dep_from=()
  local dep_to=()
  while IFS= read -r _id; do
    dep_from+=("$_id")
  done < <(awk '
    /^dependencies:/ { in_deps=1; next }
    /^[a-z]/ && !/^[[:space:]]/ && in_deps { in_deps=0 }
    in_deps && /from:/ {
      sub(/.*from:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  while IFS= read -r _id; do
    dep_to+=("$_id")
  done < <(awk '
    /^dependencies:/ { in_deps=1; next }
    /^[a-z]/ && !/^[[:space:]]/ && in_deps { in_deps=0 }
    in_deps && /to:/ {
      sub(/.*to:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  local dep_count=${#dep_from[@]}

  # Helper: find index of node_id in node_ids array
  _moira_cpm_node_index() {
    local target="$1"
    local i
    for (( i=0; i<node_count; i++ )); do
      if [[ "${node_ids[$i]}" == "$target" ]]; then
        echo "$i"
        return 0
      fi
    done
    return 1
  }

  # Compute in-degree for each node
  local in_degree=()
  for (( i=0; i<node_count; i++ )); do
    in_degree+=( 0 )
  done
  for (( e=0; e<dep_count; e++ )); do
    local to_idx
    to_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
    in_degree[$to_idx]=$(( ${in_degree[$to_idx]} + 1 ))
  done

  # Topological sort (Kahn's algorithm)
  local topo_order=()
  local queue=()
  for (( i=0; i<node_count; i++ )); do
    if [[ ${in_degree[$i]} -eq 0 ]]; then
      queue+=( "$i" )
    fi
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    topo_order+=( "$current" )

    # For each edge from current
    for (( e=0; e<dep_count; e++ )); do
      local from_idx
      from_idx=$(_moira_cpm_node_index "${dep_from[$e]}") || continue
      if [[ $from_idx -eq $current ]]; then
        local to_idx
        to_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
        in_degree[$to_idx]=$(( ${in_degree[$to_idx]} - 1 ))
        if [[ ${in_degree[$to_idx]} -eq 0 ]]; then
          queue+=( "$to_idx" )
        fi
      fi
    done
  done

  if [[ ${#topo_order[@]} -ne $node_count ]]; then
    echo "Error: cycle detected in dependency graph" >&2
    return 1
  fi

  # Forward pass: earliest_start[v] = max(earliest_finish[u]) for predecessors u
  # earliest_finish[u] = earliest_start[u] + estimated_tokens[u]
  local earliest_start=()
  local earliest_finish=()
  for (( i=0; i<node_count; i++ )); do
    earliest_start+=( 0 )
    earliest_finish+=( 0 )
  done

  for idx in "${topo_order[@]}"; do
    local max_pred_finish=0
    # Check all edges where dep_to == node_ids[idx]
    for (( e=0; e<dep_count; e++ )); do
      if [[ "${dep_to[$e]}" == "${node_ids[$idx]}" ]]; then
        local pred_idx
        pred_idx=$(_moira_cpm_node_index "${dep_from[$e]}") || continue
        if [[ ${earliest_finish[$pred_idx]} -gt $max_pred_finish ]]; then
          max_pred_finish=${earliest_finish[$pred_idx]}
        fi
      fi
    done
    earliest_start[$idx]=$max_pred_finish
    earliest_finish[$idx]=$(( max_pred_finish + ${node_tokens[$idx]} ))
  done

  # Backward pass: latest_finish[v] = min(latest_start[succ]) for successors
  # latest_start[v] = latest_finish[v] - estimated_tokens[v]
  # Terminal nodes: latest_finish = project_end (max of all earliest_finish)
  local project_end=0
  for (( i=0; i<node_count; i++ )); do
    if [[ ${earliest_finish[$i]} -gt $project_end ]]; then
      project_end=${earliest_finish[$i]}
    fi
  done

  local latest_start=()
  local latest_finish=()
  for (( i=0; i<node_count; i++ )); do
    latest_finish+=( $project_end )
    latest_start+=( $(( project_end - ${node_tokens[$i]} )) )
  done

  # Reverse topological order
  local rev_count=${#topo_order[@]}
  for (( r=rev_count-1; r>=0; r-- )); do
    local idx="${topo_order[$r]}"
    local min_succ_start=$project_end
    # Check all edges where dep_from == node_ids[idx]
    for (( e=0; e<dep_count; e++ )); do
      if [[ "${dep_from[$e]}" == "${node_ids[$idx]}" ]]; then
        local succ_idx
        succ_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
        if [[ ${latest_start[$succ_idx]} -lt $min_succ_start ]]; then
          min_succ_start=${latest_start[$succ_idx]}
        fi
      fi
    done
    latest_finish[$idx]=$min_succ_start
    latest_start[$idx]=$(( min_succ_start - ${node_tokens[$idx]} ))
  done

  # Phase assignment: group nodes by earliest_start value
  # Nodes with the same earliest_start go in the same phase
  # Collect unique earliest_start values, sorted ascending
  local unique_starts=()
  for idx in "${topo_order[@]}"; do
    local es=${earliest_start[$idx]}
    local already=false
    for us in "${unique_starts[@]+"${unique_starts[@]}"}"; do
      if [[ $us -eq $es ]]; then
        already=true
        break
      fi
    done
    if ! $already; then
      unique_starts+=( "$es" )
    fi
  done

  # Sort unique_starts numerically
  local sorted_starts=()
  while IFS= read -r val; do
    sorted_starts+=( "$val" )
  done < <(printf '%s\n' "${unique_starts[@]}" | sort -n)

  # Assign phases
  for idx in "${topo_order[@]}"; do
    local es=${earliest_start[$idx]}
    local phase_num=0
    for (( p=0; p<${#sorted_starts[@]}; p++ )); do
      if [[ ${sorted_starts[$p]} -eq $es ]]; then
        phase_num=$(( p + 1 ))
        break
      fi
    done
    echo "${node_ids[$idx]}: phase_${phase_num}"
  done

  return 0
}

# ── moira_rules_cpm_critical_path <dep_graph_yaml> ───────────────────
# Returns nodes on the critical path (zero slack).
# Slack = latest_start - earliest_start. Output: one node ID per line.
moira_rules_cpm_critical_path() {
  local dep_graph_yaml="$1"

  if [[ ! -f "$dep_graph_yaml" ]]; then
    echo "Error: dependency graph not found: $dep_graph_yaml" >&2
    return 1
  fi

  # Parse nodes
  local node_ids=()
  local node_tokens=()
  local _id _tokens
  while IFS= read -r _id; do
    node_ids+=("$_id")
  done < <(awk '
    /^nodes:/ { in_nodes=1; next }
    /^[a-z]/ && in_nodes { in_nodes=0 }
    in_nodes && /id:/ {
      sub(/.*id:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  while IFS= read -r _tokens; do
    node_tokens+=("$_tokens")
  done < <(awk '
    /^nodes:/ { in_nodes=1; next }
    /^[a-z]/ && in_nodes { in_nodes=0 }
    in_nodes && /estimated_tokens:/ {
      sub(/.*estimated_tokens:[[:space:]]*/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  local node_count=${#node_ids[@]}
  if [[ $node_count -eq 0 ]]; then
    echo "Error: no nodes found in dependency graph" >&2
    return 1
  fi

  # Parse dependencies
  local dep_from=()
  local dep_to=()
  while IFS= read -r _id; do
    dep_from+=("$_id")
  done < <(awk '
    /^dependencies:/ { in_deps=1; next }
    /^[a-z]/ && !/^[[:space:]]/ && in_deps { in_deps=0 }
    in_deps && /from:/ {
      sub(/.*from:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  while IFS= read -r _id; do
    dep_to+=("$_id")
  done < <(awk '
    /^dependencies:/ { in_deps=1; next }
    /^[a-z]/ && !/^[[:space:]]/ && in_deps { in_deps=0 }
    in_deps && /to:/ {
      sub(/.*to:[[:space:]]*/, "")
      gsub(/["'"'"']/, "")
      gsub(/[[:space:]]*$/, "")
      print
    }
  ' "$dep_graph_yaml")

  local dep_count=${#dep_from[@]}

  _moira_cpm_node_index() {
    local target="$1"
    local i
    for (( i=0; i<node_count; i++ )); do
      if [[ "${node_ids[$i]}" == "$target" ]]; then
        echo "$i"
        return 0
      fi
    done
    return 1
  }

  # In-degree + topological sort
  local in_degree=()
  for (( i=0; i<node_count; i++ )); do
    in_degree+=( 0 )
  done
  for (( e=0; e<dep_count; e++ )); do
    local to_idx
    to_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
    in_degree[$to_idx]=$(( ${in_degree[$to_idx]} + 1 ))
  done

  local topo_order=()
  local queue=()
  for (( i=0; i<node_count; i++ )); do
    if [[ ${in_degree[$i]} -eq 0 ]]; then
      queue+=( "$i" )
    fi
  done

  while [[ ${#queue[@]} -gt 0 ]]; do
    local current="${queue[0]}"
    queue=("${queue[@]:1}")
    topo_order+=( "$current" )
    for (( e=0; e<dep_count; e++ )); do
      local from_idx
      from_idx=$(_moira_cpm_node_index "${dep_from[$e]}") || continue
      if [[ $from_idx -eq $current ]]; then
        local to_idx
        to_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
        in_degree[$to_idx]=$(( ${in_degree[$to_idx]} - 1 ))
        if [[ ${in_degree[$to_idx]} -eq 0 ]]; then
          queue+=( "$to_idx" )
        fi
      fi
    done
  done

  if [[ ${#topo_order[@]} -ne $node_count ]]; then
    echo "Error: cycle detected in dependency graph" >&2
    return 1
  fi

  # Forward pass
  local earliest_start=()
  local earliest_finish=()
  for (( i=0; i<node_count; i++ )); do
    earliest_start+=( 0 )
    earliest_finish+=( 0 )
  done

  for idx in "${topo_order[@]}"; do
    local max_pred_finish=0
    for (( e=0; e<dep_count; e++ )); do
      if [[ "${dep_to[$e]}" == "${node_ids[$idx]}" ]]; then
        local pred_idx
        pred_idx=$(_moira_cpm_node_index "${dep_from[$e]}") || continue
        if [[ ${earliest_finish[$pred_idx]} -gt $max_pred_finish ]]; then
          max_pred_finish=${earliest_finish[$pred_idx]}
        fi
      fi
    done
    earliest_start[$idx]=$max_pred_finish
    earliest_finish[$idx]=$(( max_pred_finish + ${node_tokens[$idx]} ))
  done

  # Backward pass
  local project_end=0
  for (( i=0; i<node_count; i++ )); do
    if [[ ${earliest_finish[$i]} -gt $project_end ]]; then
      project_end=${earliest_finish[$i]}
    fi
  done

  local latest_start=()
  local latest_finish=()
  for (( i=0; i<node_count; i++ )); do
    latest_finish+=( $project_end )
    latest_start+=( $(( project_end - ${node_tokens[$i]} )) )
  done

  local rev_count=${#topo_order[@]}
  for (( r=rev_count-1; r>=0; r-- )); do
    local idx="${topo_order[$r]}"
    local min_succ_start=$project_end
    for (( e=0; e<dep_count; e++ )); do
      if [[ "${dep_from[$e]}" == "${node_ids[$idx]}" ]]; then
        local succ_idx
        succ_idx=$(_moira_cpm_node_index "${dep_to[$e]}") || continue
        if [[ ${latest_start[$succ_idx]} -lt $min_succ_start ]]; then
          min_succ_start=${latest_start[$succ_idx]}
        fi
      fi
    done
    latest_finish[$idx]=$min_succ_start
    latest_start[$idx]=$(( min_succ_start - ${node_tokens[$idx]} ))
  done

  # Output nodes with zero slack
  for (( i=0; i<node_count; i++ )); do
    local slack=$(( ${latest_start[$i]} - ${earliest_start[$i]} ))
    if [[ $slack -eq 0 ]]; then
      echo "${node_ids[$i]}"
    fi
  done

  return 0
}

# ── moira_rules_lpt_split <phase_files_csv> <budget_limit> ──────────
# Split a phase into sub-batches using LPT (Longest Processing Time first).
# Input: comma-separated "file:size" pairs, integer budget limit.
# Output: "batch_N: file1,file2,..." lines.
moira_rules_lpt_split() {
  local phase_files_csv="$1"
  local budget_limit="$2"

  if [[ -z "$phase_files_csv" || -z "$budget_limit" ]]; then
    echo "Error: usage: moira_rules_lpt_split <file:size,...> <budget_limit>" >&2
    return 1
  fi

  # Parse file:size pairs into parallel arrays
  local file_names=()
  local file_sizes=()
  local IFS=','
  for pair in $phase_files_csv; do
    local fname="${pair%%:*}"
    local fsize="${pair##*:}"
    file_names+=("$fname")
    file_sizes+=("$fsize")
  done
  unset IFS

  local file_count=${#file_names[@]}
  if [[ $file_count -eq 0 ]]; then
    echo "Error: no files provided" >&2
    return 1
  fi

  # Sort by size descending (insertion sort for bash 3.2 compat)
  for (( i=1; i<file_count; i++ )); do
    local j=$i
    while [[ $j -gt 0 && ${file_sizes[$((j-1))]} -lt ${file_sizes[$j]} ]]; do
      # Swap sizes
      local tmp_size="${file_sizes[$j]}"
      file_sizes[$j]="${file_sizes[$((j-1))]}"
      file_sizes[$((j-1))]="$tmp_size"
      # Swap names
      local tmp_name="${file_names[$j]}"
      file_names[$j]="${file_names[$((j-1))]}"
      file_names[$((j-1))]="$tmp_name"
      j=$((j-1))
    done
  done

  # LPT: assign each file to the batch with the smallest current total
  # Start with one batch; add new batch if all existing exceed budget
  local batch_totals=()
  local batch_files=()
  local batch_count=0

  for (( i=0; i<file_count; i++ )); do
    local fsize=${file_sizes[$i]}
    local fname="${file_names[$i]}"

    # Find batch with smallest total that can fit this file
    local best_batch=-1
    local best_total=-1

    for (( b=0; b<batch_count; b++ )); do
      local new_total=$(( ${batch_totals[$b]} + fsize ))
      if [[ $new_total -le $budget_limit ]]; then
        if [[ $best_batch -eq -1 || ${batch_totals[$b]} -lt $best_total ]]; then
          best_batch=$b
          best_total=${batch_totals[$b]}
        fi
      fi
    done

    if [[ $best_batch -eq -1 ]]; then
      # No existing batch can fit -- create new batch
      best_batch=$batch_count
      batch_totals+=( 0 )
      batch_files+=( "" )
      batch_count=$(( batch_count + 1 ))
    fi

    batch_totals[$best_batch]=$(( ${batch_totals[$best_batch]} + fsize ))
    if [[ -z "${batch_files[$best_batch]}" ]]; then
      batch_files[$best_batch]="$fname"
    else
      batch_files[$best_batch]="${batch_files[$best_batch]},${fname}"
    fi
  done

  # Output
  for (( b=0; b<batch_count; b++ )); do
    echo "batch_$(( b + 1 )): ${batch_files[$b]}"
  done

  return 0
}
