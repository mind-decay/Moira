#!/usr/bin/env bash
# knowledge.sh — Knowledge read/write/freshness operations for Moira
# Built on yaml-utils.sh patterns (bash 3.2+ compatible, no jq/python).
#
# Responsibilities: knowledge CRUD + freshness tracking ONLY
# Does NOT handle knowledge generation (that's agents' job)

set -euo pipefail

# Source yaml-utils from the same directory
_MOIRA_KNOWLEDGE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
# shellcheck source=yaml-utils.sh
source "${_MOIRA_KNOWLEDGE_LIB_DIR}/yaml-utils.sh"

# Valid knowledge types (includes libraries for MCP documentation caching)
# libraries = per-library MCP docs cached individually, no single full.md (follows different lifecycle)
_MOIRA_KNOWLEDGE_TYPES="project-model conventions decisions patterns failures quality-map libraries"

# Level-to-file mapping
_moira_level_file() {
  local level="$1"
  case "$level" in
    L0) echo "index.md" ;;
    L1) echo "summary.md" ;;
    L2) echo "full.md" ;;
    *)
      echo "Error: invalid level '$level' (must be L0, L1, or L2)" >&2
      return 1
      ;;
  esac
}

# Validate knowledge type
_moira_valid_type() {
  local ktype="$1"
  for valid in $_MOIRA_KNOWLEDGE_TYPES; do
    if [[ "$ktype" == "$valid" ]]; then
      return 0
    fi
  done
  echo "Error: invalid knowledge type '$ktype'" >&2
  return 1
}

# ── moira_knowledge_read <knowledge_dir> <knowledge_type> <level> ────
# Read a knowledge file at a specific level.
# Returns file contents or empty string if file doesn't exist.
moira_knowledge_read() {
  local knowledge_dir="$1"
  local ktype="$2"
  local level="$3"

  _moira_valid_type "$ktype" || return 1

  # Quality-map has no L0 (AD-6)
  if [[ "$ktype" == "quality-map" && "$level" == "L0" ]]; then
    return 0
  fi

  # Libraries L2 = individual per-library files, not a single full.md
  if [[ "$ktype" == "libraries" && "$level" == "L2" ]]; then
    return 0
  fi

  local level_file
  level_file=$(_moira_level_file "$level") || return 1

  local target="${knowledge_dir}/${ktype}/${level_file}"

  if [[ -f "$target" ]]; then
    cat "$target"
  fi
  return 0
}

# ── moira_knowledge_read_for_agent <knowledge_dir> <agent_name> [matrix_file]
# Read all knowledge an agent is authorized to access per the access matrix.
# Returns concatenated content with section headers.
moira_knowledge_read_for_agent() {
  local knowledge_dir="$1"
  local agent_name="$2"
  local matrix_file="${3:-${MOIRA_HOME:-$HOME/.claude/moira}/core/knowledge-access-matrix.yaml}"

  if [[ ! -f "$matrix_file" ]]; then
    echo "Error: knowledge access matrix not found: $matrix_file" >&2
    return 1
  fi

  # Knowledge dimensions in matrix (underscore) → knowledge type (hyphen)
  local dimensions="project_model conventions decisions patterns quality_map failures libraries"
  local output=""
  local has_content=false

  for dim in $dimensions; do
    # Convert dimension name to knowledge type (underscore → hyphen)
    local ktype="${dim//_/-}"

    # Extract level from read_access section only (not write_access)
    # Use sed to print only lines between read_access: and write_access:, then grep agent
    local level
    level=$(sed -n '/^read_access:/,/^write_access:/p' "$matrix_file" 2>/dev/null | \
      grep "^[[:space:]]*${agent_name}:" | head -1 | \
      sed -n "s/.*${dim}: *\([^ ,}]*\).*/\1/p" | tr -d ' ')

    # Skip null or empty access
    if [[ -z "$level" || "$level" == "null" ]]; then
      continue
    fi

    # Quality-map L0 doesn't exist (AD-6) — skip silently
    if [[ "$ktype" == "quality-map" && "$level" == "L0" ]]; then
      continue
    fi

    # Libraries at L2: load L1 (summary.md) as best available aggregate
    local content
    if [[ "$ktype" == "libraries" && "$level" == "L2" ]]; then
      content=$(moira_knowledge_read "$knowledge_dir" "$ktype" "L1" 2>/dev/null) || true
    else
      content=$(moira_knowledge_read "$knowledge_dir" "$ktype" "$level" 2>/dev/null) || true
    fi

    if [[ -n "$content" ]]; then
      # Convert type name for display (hyphen → space, capitalize)
      local display_name
      display_name=$(echo "$ktype" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')

      if $has_content; then
        output+=$'\n\n'
      fi
      output+="## Knowledge: ${display_name} (${level})"
      output+=$'\n'
      output+="$content"
      has_content=true
    fi
  done

  if $has_content; then
    echo "$output"
  fi
  return 0
}

# ── moira_knowledge_write <knowledge_dir> <knowledge_type> <level> <content_file> <task_id>
# Write content to a knowledge file with freshness marker.
moira_knowledge_write() {
  local knowledge_dir="$1"
  local ktype="$2"
  local level="$3"
  local content_file="$4"
  local task_id="$5"

  _moira_valid_type "$ktype" || return 1

  local level_file
  level_file=$(_moira_level_file "$level") || return 1

  local target="${knowledge_dir}/${ktype}/${level_file}"
  local today
  today=$(date -u +%Y-%m-%d)
  # Include λ in freshness tag for exponential decay
  local lambda_x100
  lambda_x100=$(_moira_knowledge_get_lambda "$ktype")
  local lambda_str
  printf -v lambda_str "0.%02d" "$lambda_x100"
  local freshness_tag="<!-- moira:freshness ${task_id} ${today} λ=${lambda_str} -->"

  # Ensure directory exists
  mkdir -p "$(dirname "$target")"

  # If target exists, preserve old freshness tag
  local old_freshness=""
  if [[ -f "$target" ]]; then
    old_freshness=$(grep -m1 '^<!-- moira:freshness ' "$target" 2>/dev/null || true)
  fi

  # Write: freshness tag + blank line + content
  {
    echo "$freshness_tag"
    echo ""
    cat "$content_file"
    if [[ -n "$old_freshness" ]]; then
      echo ""
      echo "${old_freshness/moira:freshness/moira:freshness:previous}"
    fi
  } > "$target"

  return 0
}

# ═══════════════════════════════════════════════════════════════════════
# Exponential Knowledge Decay
# Replaces discrete 3-tier freshness with continuous confidence scores.
# confidence(entry) = e^(-λ × tasks_since_verified)
# ═══════════════════════════════════════════════════════════════════════

# Per-knowledge-type decay rates (× 100 for integer math)
_MOIRA_KNOWLEDGE_LAMBDA_conventions=2       # 0.02
_MOIRA_KNOWLEDGE_LAMBDA_patterns=5          # 0.05
_MOIRA_KNOWLEDGE_LAMBDA_project_model=8     # 0.08
_MOIRA_KNOWLEDGE_LAMBDA_decisions=1          # 0.01
_MOIRA_KNOWLEDGE_LAMBDA_failures=3           # 0.03
_MOIRA_KNOWLEDGE_LAMBDA_quality_map=7        # 0.07
_MOIRA_KNOWLEDGE_LAMBDA_libraries=5          # 0.05 (default)

# ── _moira_knowledge_get_lambda <knowledge_type>
# Return λ × 100 for a knowledge type.
_moira_knowledge_get_lambda() {
  local ktype="$1"
  # Convert hyphen to underscore for variable lookup
  local var_name="_MOIRA_KNOWLEDGE_LAMBDA_${ktype//-/_}"
  eval "echo \"\${${var_name}:-5}\""
}

# ── _moira_knowledge_exp_decay <lambda_x100> <distance>
# Compute e^(-λ × d) × 100 using integer approximation.
# Returns confidence as integer 0-100.
_moira_knowledge_exp_decay() {
  local lambda="$1"   # λ × 100
  local distance="$2" # tasks since verified

  if [[ $distance -le 0 ]]; then
    echo "100"
    return 0
  fi

  # Use repeated multiplication approach:
  # e^(-λd) = (e^(-λ))^d
  # For each unit distance, multiply by decay factor.
  # Decay factor per step = (100 - λ) / 100 (first-order approx of e^(-λ/100))
  # Work in scale of 10000 for precision.
  local confidence=10000  # starts at 100.00%
  local decay_factor=$(( 100 - lambda ))  # per-step multiplier (×100)

  local i
  for (( i=0; i<distance; i++ )); do
    confidence=$(( confidence * decay_factor / 100 ))
    # Early exit if already zero
    if [[ $confidence -le 0 ]]; then
      echo "0"
      return 0
    fi
  done

  # Convert from ×10000 to ×100
  local result=$(( confidence / 100 ))
  if [[ $result -lt 0 ]]; then result=0; fi
  if [[ $result -gt 100 ]]; then result=100; fi

  echo "$result"
}

# ── moira_knowledge_freshness_score <knowledge_dir> <knowledge_type> [current_task_count]
# Compute confidence score for a knowledge entry.
# Returns numeric score 0-100 (100 = fully trusted, 0 = needs verification).
moira_knowledge_freshness_score() {
  local knowledge_dir="$1"
  local ktype="$2"
  local current_task_count="${3:-0}"

  _moira_valid_type "$ktype" || return 1

  local target="${knowledge_dir}/${ktype}/summary.md"

  if [[ ! -f "$target" ]]; then
    echo "0"
    return 0
  fi

  # Extract freshness tag
  local tag
  tag=$(grep -m1 '^<!-- moira:freshness ' "$target" 2>/dev/null || true)

  if [[ -z "$tag" ]]; then
    echo "0"
    return 0
  fi

  # Parse task number
  local entry_task_id
  entry_task_id=$(echo "$tag" | sed 's/<!-- moira:freshness \([^ ]*\) .*/\1/')
  local entry_task_number
  entry_task_number=$(echo "$entry_task_id" | grep -o '[0-9]*$')

  if [[ -z "$entry_task_number" ]]; then
    echo "0"
    return 0
  fi

  entry_task_number=$((10#$entry_task_number))
  current_task_count=$((10#$current_task_count))

  local distance=$(( current_task_count - entry_task_number ))
  if [[ $distance -lt 0 ]]; then distance=0; fi

  # Check for λ in tag: <!-- moira:freshness task-078 2024-01-20 λ=0.05 -->
  local lambda
  local tag_lambda
  tag_lambda=$(echo "$tag" | sed -n 's/.*λ=\([0-9.]*\).*/\1/p')
  if [[ -n "$tag_lambda" ]]; then
    # Convert decimal λ to × 100 integer (e.g. 0.05 → 5, 0.10 → 10)
    lambda=$(awk -F'.' '{printf "%d", $2 + 0}' <<< "$tag_lambda")
    lambda=${lambda:-5}
  else
    lambda=$(_moira_knowledge_get_lambda "$ktype")
  fi

  _moira_knowledge_exp_decay "$lambda" "$distance"
}

# ── moira_knowledge_freshness_category <score>
# Map numeric score to human-readable category.
# Returns: trusted, usable, needs-verification
moira_knowledge_freshness_category() {
  local score="$1"

  if [[ $score -gt 70 ]]; then
    echo "trusted"
  elif [[ $score -gt 30 ]]; then
    echo "usable"
  else
    echo "needs-verification"
  fi
}

# ── moira_knowledge_freshness <knowledge_dir> <knowledge_type> <current_task_number>
# Check freshness of a knowledge entry.
# Backward compatible: returns fresh, aging, stale, or unknown (mapped from confidence).
moira_knowledge_freshness() {
  local knowledge_dir="$1"
  local ktype="$2"
  local current_task_number="$3"

  _moira_valid_type "$ktype" || return 1

  local target="${knowledge_dir}/${ktype}/summary.md"

  if [[ ! -f "$target" ]]; then
    echo "unknown"
    return 0
  fi

  local tag
  tag=$(grep -m1 '^<!-- moira:freshness ' "$target" 2>/dev/null || true)
  if [[ -z "$tag" ]]; then
    echo "unknown"
    return 0
  fi

  local score
  score=$(moira_knowledge_freshness_score "$knowledge_dir" "$ktype" "$current_task_number")

  local category
  category=$(moira_knowledge_freshness_category "$score")

  case "$category" in
    trusted) echo "fresh" ;;
    usable) echo "aging" ;;
    needs-verification) echo "stale" ;;
    *) echo "unknown" ;;
  esac
}

# ── moira_knowledge_freshness_marker_write <entry_path> <task_id> <date> <knowledge_type>
# Write freshness marker with λ parameter.
moira_knowledge_freshness_marker_write() {
  local entry_path="$1"
  local task_id="$2"
  local date="$3"
  local ktype="$4"

  local lambda_x100
  lambda_x100=$(_moira_knowledge_get_lambda "$ktype")
  # Convert to decimal string: 5 → 0.05, 2 → 0.02
  local lambda_str
  printf -v lambda_str "0.%02d" "$lambda_x100"

  local marker="<!-- moira:freshness ${task_id} ${date} λ=${lambda_str} -->"

  if [[ -f "$entry_path" ]]; then
    # Replace existing marker or prepend
    if grep -q '^<!-- moira:freshness ' "$entry_path" 2>/dev/null; then
      local tmpfile
      tmpfile=$(mktemp)
      sed "s|^<!-- moira:freshness [^>]* -->|${marker}|" "$entry_path" > "$tmpfile"
      mv "$tmpfile" "$entry_path"
    else
      local tmpfile
      tmpfile=$(mktemp)
      { echo "$marker"; echo ""; cat "$entry_path"; } > "$tmpfile"
      mv "$tmpfile" "$entry_path"
    fi
  else
    echo "$marker" > "$entry_path"
  fi
}

# ── moira_knowledge_freshness_marker_read <entry_path>
# Parse freshness marker. Handle both old and new format.
# Output: task_id, date, lambda (as key: value lines)
moira_knowledge_freshness_marker_read() {
  local entry_path="$1"

  if [[ ! -f "$entry_path" ]]; then
    return 0
  fi

  local tag
  tag=$(grep -m1 '^<!-- moira:freshness ' "$entry_path" 2>/dev/null || true)

  if [[ -z "$tag" ]]; then
    return 0
  fi

  local task_id date_val lambda_val
  task_id=$(echo "$tag" | sed 's/<!-- moira:freshness \([^ ]*\) .*/\1/')
  date_val=$(echo "$tag" | sed 's/<!-- moira:freshness [^ ]* \([^ ]*\).*/\1/')
  lambda_val=$(echo "$tag" | sed -n 's/.*λ=\([0-9.]*\).*/\1/p')

  echo "task_id: ${task_id}"
  echo "date: ${date_val}"
  echo "lambda: ${lambda_val:-default}"
}

# ── moira_knowledge_verification_priority <knowledge_dir> [current_task_count]
# Return entries sorted by confidence score ascending (lowest first = highest priority).
# Output: one line per entry: {type} confidence={score} category={category}
moira_knowledge_verification_priority() {
  local knowledge_dir="$1"
  local current_task_count="${2:-0}"

  # Collect scores
  local entries=""
  for ktype in $_MOIRA_KNOWLEDGE_TYPES; do
    local target="${knowledge_dir}/${ktype}/summary.md"
    [[ -f "$target" ]] || continue

    local score
    score=$(moira_knowledge_freshness_score "$knowledge_dir" "$ktype" "$current_task_count" 2>/dev/null) || continue

    local category
    category=$(moira_knowledge_freshness_category "$score")

    entries+="${score}|${ktype}|${category}"$'\n'
  done

  # Sort by score ascending (numeric)
  echo "$entries" | sort -t'|' -k1 -n | while IFS='|' read -r score ktype category; do
    [[ -z "$score" ]] && continue
    echo "${ktype} confidence=${score} category=${category}"
  done
}

# ── moira_knowledge_stale_entries <knowledge_dir> <current_task_number>
# List all knowledge entries needing verification (confidence ≤ 30).
# Output: one line per entry: {type} last_task={task_id} distance={N} confidence={score}
moira_knowledge_stale_entries() {
  local knowledge_dir="$1"
  local current_task_number="$2"

  for ktype in $_MOIRA_KNOWLEDGE_TYPES; do
    local target="${knowledge_dir}/${ktype}/summary.md"

    if [[ ! -f "$target" ]]; then
      continue
    fi

    local tag
    tag=$(grep -m1 '^<!-- moira:freshness ' "$target" 2>/dev/null || true)

    if [[ -z "$tag" ]]; then
      continue
    fi

    local entry_task_id
    entry_task_id=$(echo "$tag" | sed 's/<!-- moira:freshness \([^ ]*\) .*/\1/')

    local entry_task_number
    entry_task_number=$(echo "$entry_task_id" | grep -o '[0-9]*$')

    if [[ -z "$entry_task_number" ]]; then
      continue
    fi

    entry_task_number=$((10#$entry_task_number))
    local distance=$(( 10#$current_task_number - entry_task_number ))

    # Use confidence score for stale detection
    local score
    score=$(moira_knowledge_freshness_score "$knowledge_dir" "$ktype" "$current_task_number" 2>/dev/null) || score="0"

    if [[ $score -le 30 ]]; then
      echo "${ktype} last_task=${entry_task_id} distance=${distance} confidence=${score}"
    fi
  done

  return 0
}

# ── moira_knowledge_archive_rotate <knowledge_dir> <knowledge_type> [max_entries]
# Rotate old entries to archive (for decisions and patterns).
moira_knowledge_archive_rotate() {
  local knowledge_dir="$1"
  local ktype="$2"
  local max_entries="${3:-20}"

  # Only applies to types with archive dirs
  if [[ "$ktype" != "decisions" && "$ktype" != "patterns" ]]; then
    echo "Error: archive rotation only applies to decisions and patterns" >&2
    return 1
  fi

  local full_file="${knowledge_dir}/${ktype}/full.md"
  local archive_dir="${knowledge_dir}/${ktype}/archive"

  if [[ ! -f "$full_file" ]]; then
    return 0
  fi

  # Count entries (## headers at start of line, not ### or deeper)
  local count
  count=$(grep -c '^## ' "$full_file" 2>/dev/null || echo "0")

  if [[ "$count" -le "$max_entries" ]]; then
    return 0
  fi

  local to_move=$(( count - max_entries ))

  mkdir -p "$archive_dir"

  # Find next batch number
  local last_batch
  last_batch=$(ls "$archive_dir"/batch-*.md 2>/dev/null | sort | tail -1 | sed 's/.*batch-\([0-9]*\)\.md/\1/' || echo "0")
  last_batch=${last_batch:-0}
  local next_batch
  next_batch=$(printf "%03d" $(( 10#$last_batch + 1 )))

  # Extract oldest entries (from top of file)
  # Find the line number of the (to_move+1)th ## header — that's where we split
  local split_line
  split_line=$(grep -n '^## ' "$full_file" | sed -n "$((to_move + 1))p" | cut -d: -f1)

  if [[ -z "$split_line" ]]; then
    # All entries need to move (shouldn't happen given count > max)
    return 0
  fi

  # Extract lines before split point (oldest entries) to archive
  local tmpfile
  tmpfile=$(mktemp)

  # Get any file header (lines before first ## )
  local first_entry_line
  first_entry_line=$(grep -n '^## ' "$full_file" | head -1 | cut -d: -f1)

  # Archive: entries from first ## to just before split_line
  sed -n "${first_entry_line},$((split_line - 1))p" "$full_file" > "$archive_dir/batch-${next_batch}.md"

  # Keep: file header (if any) + entries from split_line onward
  {
    if [[ "$first_entry_line" -gt 1 ]]; then
      sed -n "1,$((first_entry_line - 1))p" "$full_file"
    fi
    sed -n "${split_line},\$p" "$full_file"
  } > "$tmpfile"

  mv "$tmpfile" "$full_file"

  return 0
}

# ── moira_knowledge_validate_consistency <knowledge_dir> <knowledge_type> <new_content_file>
# Check new knowledge against existing for contradictions.
# Returns: confirm, extend, or conflict (to stdout)
# On conflict: outputs details to stderr
moira_knowledge_validate_consistency() {
  local knowledge_dir="$1"
  local ktype="$2"
  local new_content_file="$3"

  _moira_valid_type "$ktype" || return 1

  local existing_file="${knowledge_dir}/${ktype}/summary.md"

  # If no existing content, new content is always an extension
  if [[ ! -f "$existing_file" ]] || [[ ! -s "$existing_file" ]]; then
    echo "extend"
    return 0
  fi

  # Extract key-value pairs from existing and new content
  # Matches patterns: "key: value", "key = value", "**key**: value"
  local existing_kvs new_kvs
  existing_kvs=$(grep -E '^\*?\*?[a-zA-Z_][a-zA-Z0-9_ -]*\*?\*?\s*[:=]\s*.+' "$existing_file" 2>/dev/null | \
    sed 's/^\*\*//;s/\*\*//;s/^[[:space:]]*//;s/[[:space:]]*[:=][[:space:]]*/=/;s/[[:space:]]*$//' || true)
  new_kvs=$(grep -E '^\*?\*?[a-zA-Z_][a-zA-Z0-9_ -]*\*?\*?\s*[:=]\s*.+' "$new_content_file" 2>/dev/null | \
    sed 's/^\*\*//;s/\*\*//;s/^[[:space:]]*//;s/[[:space:]]*[:=][[:space:]]*/=/;s/[[:space:]]*$//' || true)

  # If no structured content in either, can't compare structurally
  if [[ -z "$existing_kvs" ]] || [[ -z "$new_kvs" ]]; then
    echo "extend"
    return 0
  fi

  local has_conflict=false
  local has_new_key=false

  # Check each new key-value pair against existing
  while IFS= read -r new_kv; do
    [[ -z "$new_kv" ]] && continue
    local new_key="${new_kv%%=*}"
    local new_val="${new_kv#*=}"

    # Look for this key in existing
    local existing_val
    existing_val=$(echo "$existing_kvs" | grep "^${new_key}=" 2>/dev/null | head -1 | sed 's/^[^=]*=//' || true)

    if [[ -z "$existing_val" ]]; then
      has_new_key=true
    elif [[ "$existing_val" != "$new_val" ]]; then
      has_conflict=true
      echo "CONFLICT: key='${new_key}' existing='${existing_val}' new='${new_val}'" >&2
    fi
  done <<< "$new_kvs"

  if $has_conflict; then
    echo "conflict"
  elif $has_new_key; then
    echo "extend"
  else
    echo "confirm"
  fi

  return 0
}

# ── moira_knowledge_read_library <knowledge_dir> <library_name> ──
# Read individual cached library documentation.
moira_knowledge_read_library() {
  local knowledge_dir="$1"
  local library_name="$2"
  local target="${knowledge_dir}/libraries/${library_name}.md"
  if [[ -f "$target" ]]; then
    cat "$target"
  fi
  return 0
}

# ── moira_knowledge_update_quality_map <task_dir> <quality_map_dir> ───
# Update quality map based on Reviewer (Themis) findings from a completed task.
# Uses structural keyword matching — NOT semantic analysis.
# Called after task completion, before reflection.
moira_knowledge_update_quality_map() {
  local task_dir="$1"
  local quality_map_dir="$2"

  local findings_file="${task_dir}/findings/themis-Q4.yaml"
  local full_map="${quality_map_dir}/full.md"
  local summary_map="${quality_map_dir}/summary.md"

  # If no Themis findings, nothing to update
  if [[ ! -f "$findings_file" ]]; then
    return 0
  fi

  # Ensure quality map exists
  if [[ ! -f "$full_map" ]]; then
    return 0
  fi

  local today
  today=$(date -u +%Y-%m-%d)

  # Extract failed finding IDs and their check descriptions
  local finding_details
  finding_details=$(awk '
    /^[[:space:]]*- id:/ {
      gsub(/^[[:space:]]*- id:[[:space:]]*/, "")
      gsub(/["\047]/, "")
      current_id=$0; is_fail=0
    }
    /^[[:space:]]*result:[[:space:]]*fail/ { is_fail=1 }
    /^[[:space:]]*check:/ {
      if (is_fail) {
        check=$0
        gsub(/^[[:space:]]*check:[[:space:]]*/, "", check)
        gsub(/["\047]/, "", check)
        print current_id "|" check
      }
    }
  ' "$findings_file")

  # If no failed findings, nothing to update
  if [[ -z "$finding_details" ]]; then
    return 0
  fi

  local tmpfile
  tmpfile=$(mktemp)
  cp "$full_map" "$tmpfile"

  local map_updated=false

  while IFS='|' read -r fid fcheck; do
    [[ -z "$fid" ]] && continue

    # Extract keywords from the check for matching (words >= 4 chars)
    local keywords
    keywords=$(echo "$fcheck" | tr '[:upper:]' '[:lower:]' | \
      sed 's/[^a-z0-9 ]/ /g' | tr -s ' ')

    # Search for matching pattern in quality map
    local match_found=false
    local match_pattern=""

    while IFS= read -r line; do
      if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
        match_pattern="${BASH_REMATCH[1]}"
      fi
      if [[ -n "$match_pattern" ]]; then
        local line_lower
        line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        for kw in $keywords; do
          [[ ${#kw} -lt 4 ]] && continue
          if echo "$line_lower" | grep -q "$kw" 2>/dev/null; then
            match_found=true
            break
          fi
        done
        if $match_found; then break; fi
      fi
    done < "$tmpfile"

    if ! $match_found; then
      # New finding — append as new entry
      echo "" >> "$tmpfile"
      echo "### ${fcheck}" >> "$tmpfile"
      echo "- **Category**: detected" >> "$tmpfile"
      echo "- **Evidence**: task finding ${fid}" >> "$tmpfile"
      echo "- **Confidence**: medium" >> "$tmpfile"
      echo "- **Observation count**: 1" >> "$tmpfile"
      printf '- **Lifecycle**: \xF0\x9F\x86\x95 NEW\n' >> "$tmpfile"
      echo "" >> "$tmpfile"
      map_updated=true
    fi
  done <<< "$finding_details"

  if $map_updated; then
    # Update freshness marker
    sed "s/<!-- moira:freshness [^>]* -->/<!-- moira:freshness task ${today} -->/" "$tmpfile" > "$full_map"

    # Regenerate summary
    _moira_knowledge_regen_quality_summary "$full_map" "$summary_map" "$today"
  fi

  rm -f "$tmpfile"
  return 0
}

# ── Internal: regenerate quality map summary from full map ─────────────
_moira_knowledge_regen_quality_summary() {
  local full_map="$1"
  local summary_map="$2"
  local today="$3"

  local strong="" adequate="" problematic=""
  local current_section=""

  while IFS= read -r line; do
    if echo "$line" | grep -q "Strong Patterns" 2>/dev/null; then
      current_section="strong"
      continue
    elif echo "$line" | grep -q "Adequate Patterns" 2>/dev/null; then
      current_section="adequate"
      continue
    elif echo "$line" | grep -q "Problematic Patterns" 2>/dev/null; then
      current_section="problematic"
      continue
    fi

    if [[ "$line" =~ ^###[[:space:]]+(.*) ]]; then
      local name="${BASH_REMATCH[1]}"
      case "$current_section" in
        strong) [[ -n "$strong" ]] && strong+=", "; strong+="$name" ;;
        adequate) [[ -n "$adequate" ]] && adequate+=", "; adequate+="$name" ;;
        problematic) [[ -n "$problematic" ]] && problematic+=", "; problematic+="$name" ;;
      esac
    fi
  done < "$full_map"

  {
    echo "<!-- moira:freshness task ${today} -->"
    echo ""
    echo "# Quality Map Summary"
    echo ""
    echo "## Strong (follow): ${strong:-None detected yet}"
    echo "## Adequate (follow with notes): ${adequate:-None detected yet}"
    echo "## Problematic (don't extend): ${problematic:-None detected yet}"
  } > "$summary_map"
}
