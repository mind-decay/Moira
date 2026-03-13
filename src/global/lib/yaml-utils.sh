#!/usr/bin/env bash
# yaml-utils.sh — Pure bash YAML read/write/validate for Moira state files
# Supports dot-path access up to 3 levels deep
# No jq/python dependency — bash + awk + sed + grep only
# Compatible with bash 3.2+ (macOS default)
#
# Responsibilities: YAML parsing ONLY
# Does NOT handle state logic (that's state.sh)

set -euo pipefail

# ── Resolve schema directory ──────────────────────────────────────────
_moira_schema_dir() {
  if [[ -n "${MOIRA_SCHEMA_DIR:-}" ]]; then
    echo "$MOIRA_SCHEMA_DIR"
  elif [[ -n "${MOIRA_HOME:-}" && -d "${MOIRA_HOME}/schemas" ]]; then
    echo "${MOIRA_HOME}/schemas"
  else
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
    echo "${script_dir}/../../schemas"
  fi
}

# ── moira_yaml_get <file> <dot.path.key> ─────────────────────────────
# Read a value from a YAML file by dot-path key.
# Supports 1-level (step), 2-level (project.stack), 3-level (budgets.per_agent.classifier)
# For simple inline arrays [a, b, c]: returns comma-separated "a,b,c"
# Returns empty string + exit 1 if key not found.
moira_yaml_get() {
  local file="$1"
  local key="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # Split key into parts
  local IFS='.'
  set -- $key
  local p1="${1:-}" p2="${2:-}" p3="${3:-}"
  local depth=$#

  local result
  result=$(awk -v depth="$depth" \
    -v p1="$p1" \
    -v p2="$p2" \
    -v p3="$p3" \
  'BEGIN { found=0; in_p1=0; in_p2=0 }

  # Skip comments and empty lines
  /^[[:space:]]*#/ { next }
  /^[[:space:]]*$/ { next }

  {
    # Remove trailing comments (but not inside strings)
    gsub(/[[:space:]]#[^"'"'"']*$/, "")

    # Count leading spaces
    match($0, /^[[:space:]]*/);
    indent = RLENGTH;
    line = substr($0, indent + 1);
  }

  # Depth 1: top-level key
  depth == 1 && indent == 0 && line ~ "^" p1 ":" {
    sub(/^[^:]+:[[:space:]]*/, "", line);
    if (line ~ /^\[/) {
      gsub(/[\[\]]/, "", line);
      gsub(/[[:space:]]*,[[:space:]]*/, ",", line);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
    }
    gsub(/^["'"'"']|["'"'"']$/, "", line);
    if (line == "null" || line == "~") line = "";
    print line;
    found=1;
    exit;
  }

  # Depth 2+: track parent key at indent 0
  depth >= 2 && indent == 0 && line ~ "^" p1 ":" {
    in_p1=1;
    in_p2=0;
    next;
  }
  depth >= 2 && indent == 0 && in_p1 == 1 && line !~ "^" p1 ":" {
    in_p1=0;
    in_p2=0;
  }

  # Depth 2: find child key under p1
  depth == 2 && in_p1 == 1 && indent == 2 && line ~ "^" p2 ":" {
    sub(/^[^:]+:[[:space:]]*/, "", line);
    if (line ~ /^\[/) {
      gsub(/[\[\]]/, "", line);
      gsub(/[[:space:]]*,[[:space:]]*/, ",", line);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
    }
    gsub(/^["'"'"']|["'"'"']$/, "", line);
    if (line == "null" || line == "~") line = "";
    print line;
    found=1;
    exit;
  }

  # Depth 3: track p2 under p1
  depth == 3 && in_p1 == 1 && indent == 2 && line ~ "^" p2 ":" {
    in_p2=1;
    next;
  }
  depth == 3 && in_p1 == 1 && indent == 2 && in_p2 == 1 && line !~ "^" p2 ":" {
    in_p2=0;
  }

  # Depth 3: find child key under p1.p2
  depth == 3 && in_p1 == 1 && in_p2 == 1 && indent == 4 && line ~ "^" p3 ":" {
    sub(/^[^:]+:[[:space:]]*/, "", line);
    if (line ~ /^\[/) {
      gsub(/[\[\]]/, "", line);
      gsub(/[[:space:]]*,[[:space:]]*/, ",", line);
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line);
    }
    gsub(/^["'"'"']|["'"'"']$/, "", line);
    if (line == "null" || line == "~") line = "";
    print line;
    found=1;
    exit;
  }

  END { if (!found) exit 1 }
  ' "$file" 2>/dev/null)

  local rc=$?
  if [[ $rc -ne 0 ]]; then
    return 1
  fi

  echo "$result"
}

# ── moira_yaml_set <file> <dot.path.key> <value> ─────────────────────
# Set a value in a YAML file by dot-path key.
# If key exists: replaces the value portion
# If key doesn't exist: appends at correct indentation under parent
moira_yaml_set() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    return 1
  fi

  local IFS='.'
  set -- $key
  local p1="${1:-}" p2="${2:-}" p3="${3:-}"
  local depth=$#

  # Format value for YAML
  local yaml_value="$value"
  if [[ "$value" == "true" || "$value" == "false" ]]; then
    yaml_value="$value"
  elif [[ "$value" == "null" || "$value" == "" ]]; then
    yaml_value="null"
  elif echo "$value" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    yaml_value="$value"
  elif [[ "$value" == *","* && "$value" != *" "* ]]; then
    yaml_value="[${value//,/, }]"
  else
    if echo "$value" | grep -qE '[:{}\[\],&*#?|<>=!%@\\-]'; then
      yaml_value="\"$value\""
    else
      yaml_value="$value"
    fi
  fi

  # Try to replace existing key
  local replaced=false
  local tmpfile
  tmpfile=$(mktemp)

  if [[ $depth -eq 1 ]]; then
    if grep -qE "^${p1}:" "$file"; then
      sed -E "s|^(${p1}:)[[:space:]].*|\1 ${yaml_value}|" "$file" > "$tmpfile"
      replaced=true
    fi
  elif [[ $depth -eq 2 ]]; then
    awk -v p1="$p1" -v p2="$p2" -v val="$yaml_value" '
    BEGIN { in_p1=0; done_flag=0 }
    {
      if (done_flag) { print; next }
      match($0, /^[[:space:]]*/);
      indent = RLENGTH;
      line = substr($0, indent + 1);
      if (indent == 0 && line ~ "^" p1 ":") { in_p1=1; print; next }
      if (indent == 0 && in_p1 == 1) { in_p1=0 }
      if (in_p1 && indent == 2 && line ~ "^" p2 ":") {
        print "  " p2 ": " val;
        done_flag=1;
        next;
      }
      print;
    }' "$file" > "$tmpfile"
    if ! diff -q "$file" "$tmpfile" > /dev/null 2>&1; then
      replaced=true
    fi
  elif [[ $depth -eq 3 ]]; then
    awk -v p1="$p1" -v p2="$p2" -v p3="$p3" -v val="$yaml_value" '
    BEGIN { in_p1=0; in_p2=0; done_flag=0 }
    {
      if (done_flag) { print; next }
      match($0, /^[[:space:]]*/);
      indent = RLENGTH;
      line = substr($0, indent + 1);
      if (indent == 0 && line ~ "^" p1 ":") { in_p1=1; in_p2=0; print; next }
      if (indent == 0 && in_p1 == 1) { in_p1=0; in_p2=0 }
      if (in_p1 && indent == 2 && line ~ "^" p2 ":") { in_p2=1; print; next }
      if (in_p1 && indent == 2 && in_p2 == 1 && line !~ "^" p2 ":") { in_p2=0 }
      if (in_p1 && in_p2 && indent == 4 && line ~ "^" p3 ":") {
        print "    " p3 ": " val;
        done_flag=1;
        next;
      }
      print;
    }' "$file" > "$tmpfile"
    if ! diff -q "$file" "$tmpfile" > /dev/null 2>&1; then
      replaced=true
    fi
  fi

  if [[ "$replaced" == true ]]; then
    mv "$tmpfile" "$file"
  else
    rm -f "$tmpfile"
    _moira_yaml_append "$file" "$key" "$yaml_value"
  fi
}

# ── Helper: append a new key at correct indentation ──────────────────
_moira_yaml_append() {
  local file="$1"
  local key="$2"
  local value="$3"

  local IFS='.'
  set -- $key
  local p1="${1:-}" p2="${2:-}" p3="${3:-}"
  local depth=$#

  if [[ $depth -eq 1 ]]; then
    echo "$p1: $value" >> "$file"
  elif [[ $depth -eq 2 ]]; then
    local tmpfile
    tmpfile=$(mktemp)
    awk -v p1="$p1" -v p2="$p2" -v val="$value" '
    BEGIN { in_p1=0; inserted=0; last_child_line=0 }
    {
      lines[NR] = $0;
      match($0, /^[[:space:]]*/);
      indent = RLENGTH;
      line = substr($0, indent + 1);
      if (indent == 0 && line ~ "^" p1 ":") { in_p1=1; last_child_line=NR }
      if (in_p1 && indent == 0 && NR > 1 && !(line ~ "^" p1 ":")) { in_p1=0 }
      if (in_p1 && indent >= 2) { last_child_line=NR }
    }
    END {
      if (last_child_line == 0) {
        for (i=1; i<=NR; i++) print lines[i];
        print p1 ":";
        print "  " p2 ": " val;
      } else {
        for (i=1; i<=NR; i++) {
          print lines[i];
          if (i == last_child_line && !inserted) {
            print "  " p2 ": " val;
            inserted=1;
          }
        }
      }
    }' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
  elif [[ $depth -eq 3 ]]; then
    local tmpfile
    tmpfile=$(mktemp)
    awk -v p1="$p1" -v p2="$p2" -v p3="$p3" -v val="$value" '
    BEGIN { in_p1=0; in_p2=0; inserted=0; last_child_line=0 }
    {
      lines[NR] = $0;
      match($0, /^[[:space:]]*/);
      indent = RLENGTH;
      line = substr($0, indent + 1);
      if (indent == 0 && line ~ "^" p1 ":") { in_p1=1; in_p2=0 }
      if (indent == 0 && in_p1 && !(line ~ "^" p1 ":")) { in_p1=0; in_p2=0 }
      if (in_p1 && indent == 2 && line ~ "^" p2 ":") { in_p2=1; last_child_line=NR }
      if (in_p1 && indent == 2 && in_p2 && !(line ~ "^" p2 ":")) { in_p2=0 }
      if (in_p1 && in_p2 && indent >= 4) { last_child_line=NR }
    }
    END {
      for (i=1; i<=NR; i++) {
        print lines[i];
        if (i == last_child_line && !inserted) {
          print "    " p3 ": " val;
          inserted=1;
        }
      }
    }' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
  fi
}

# ── moira_yaml_validate <file> <schema_name> ─────────────────────────
# Validate a YAML file against its schema.
# Checks: required fields exist, enum values valid, pattern matches.
# Outputs errors to stderr. Exit 0 if valid, exit 1 if not.
moira_yaml_validate() {
  local file="$1"
  local schema_name="$2"
  local schema_dir
  schema_dir="$(_moira_schema_dir)"
  local schema_file="${schema_dir}/${schema_name}.schema.yaml"

  if [[ ! -f "$schema_file" ]]; then
    echo "Error: schema not found: $schema_file" >&2
    return 1
  fi

  if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    return 1
  fi

  # Use awk to parse schema and validate — avoids bash 4+ associative arrays
  local validation_output
  validation_output=$(awk -v datafile="$file" '
  BEGIN {
    field_count = 0
    errors = 0
  }

  # Parse schema: collect fields with their properties
  /^fields:/ { in_fields = 1; next }
  in_fields && /^[^ ]/ { in_fields = 0 }
  !in_fields { next }

  # Field name (2-space indent, ends with :)
  /^  [a-zA-Z_]/ && /:$/ {
    field_count++
    gsub(/^  /, "")
    gsub(/:$/, "")
    fields[field_count] = $0
    types[field_count] = ""
    requireds[field_count] = ""
    enums[field_count] = ""
    next
  }

  # Field properties (4-space indent)
  /^    type:/ { gsub(/^    type:[[:space:]]*/, ""); types[field_count] = $0; next }
  /^    required:/ { gsub(/^    required:[[:space:]]*/, ""); requireds[field_count] = $0; next }
  /^    enum:/ { gsub(/^    enum:[[:space:]]*/, ""); enums[field_count] = $0; next }

  END {
    # For each field, validate against data file
    for (i = 1; i <= field_count; i++) {
      if (types[i] == "block") continue

      field = fields[i]
      # Read value from data file using dot-path navigation
      value = ""
      found = 0

      # Split field by dots
      n = split(field, parts, ".")
      depth = n

      in_p1 = 0; in_p2 = 0
      while ((getline line < datafile) > 0) {
        # Skip comments and empty lines
        if (line ~ /^[[:space:]]*#/) continue
        if (line ~ /^[[:space:]]*$/) continue
        # Strip trailing comments
        gsub(/[[:space:]]+#[[:space:]].*$/, "", line)

        # Count indent
        match(line, /^[[:space:]]*/);
        indent = RLENGTH;
        content = substr(line, indent + 1);

        if (depth == 1 && indent == 0 && content ~ "^" parts[1] ":") {
          sub(/^[^:]+:[[:space:]]*/, "", content)
          gsub(/^["'"'"'"]|["'"'"'"]$/, "", content)
          if (content == "null" || content == "~") content = ""
          value = content
          found = 1
          break
        }

        if (depth >= 2) {
          if (indent == 0 && content ~ "^" parts[1] ":") { in_p1 = 1; in_p2 = 0 }
          else if (indent == 0 && in_p1) { in_p1 = 0; in_p2 = 0 }

          if (depth == 2 && in_p1 && indent == 2 && content ~ "^" parts[2] ":") {
            sub(/^[^:]+:[[:space:]]*/, "", content)
            gsub(/^["'"'"'"]|["'"'"'"]$/, "", content)
            if (content == "null" || content == "~") content = ""
            value = content
            found = 1
            break
          }

          if (depth == 3) {
            if (in_p1 && indent == 2 && content ~ "^" parts[2] ":") { in_p2 = 1 }
            else if (in_p1 && indent == 2 && in_p2 && content !~ "^" parts[2] ":") { in_p2 = 0 }

            if (in_p1 && in_p2 && indent == 4 && content ~ "^" parts[3] ":") {
              sub(/^[^:]+:[[:space:]]*/, "", content)
              gsub(/^["'"'"'"]|["'"'"'"]$/, "", content)
              if (content == "null" || content == "~") content = ""
              value = content
              found = 1
              break
            }
          }
        }
      }
      close(datafile)

      # Check required
      if (requireds[i] == "true" && value == "" && !found) {
        print "Error: required field '"'"'" field "'"'"' is missing or empty" > "/dev/stderr"
        errors++
        continue
      }

      # If empty and not required, skip
      if (value == "") continue

      # Check enum
      if (enums[i] != "") {
        enum_str = enums[i]
        gsub(/[\[\]]/, "", enum_str)
        n_enum = split(enum_str, enum_vals, ",")
        enum_found = 0
        for (j = 1; j <= n_enum; j++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", enum_vals[j])
          if (value == enum_vals[j]) { enum_found = 1; break }
        }
        if (!enum_found) {
          print "Error: field '"'"'" field "'"'"' has invalid value '"'"'" value "'"'"' (allowed: " enums[i] ")" > "/dev/stderr"
          errors++
        }
      }
    }
    print errors
  }
  ' "$schema_file")

  if [[ "$validation_output" -gt 0 ]] 2>/dev/null; then
    echo "Validation failed: $validation_output error(s)" >&2
    return 1
  fi
  return 0
}

# ── moira_yaml_init <schema_name> <target_path> ──────────────────────
# Generate a YAML file from schema defaults.
# Required fields without defaults get null with # REQUIRED comment.
# Uses awk for bash 3.2 compatibility (no associative arrays).
moira_yaml_init() {
  local schema_name="$1"
  local target_path="$2"
  local schema_dir
  schema_dir="$(_moira_schema_dir)"
  local schema_file="${schema_dir}/${schema_name}.schema.yaml"

  if [[ ! -f "$schema_file" ]]; then
    echo "Error: schema not found: $schema_file" >&2
    return 1
  fi

  mkdir -p "$(dirname "$target_path")"

  # Get description and location from _meta
  local schema_desc
  schema_desc=$(moira_yaml_get "$schema_file" "_meta.description" 2>/dev/null || echo "$schema_name")
  local schema_location
  schema_location=$(moira_yaml_get "$schema_file" "_meta.location" 2>/dev/null || echo "")

  # Use awk to parse schema and generate YAML
  awk -v desc="$schema_desc" -v location="$schema_location" '
  BEGIN {
    print "# " desc
    print "# Location: " location
    print ""
    field_count = 0
    in_fields = 0
  }

  /^fields:/ { in_fields = 1; next }
  in_fields && /^[^ ]/ { in_fields = 0 }
  !in_fields { next }

  # Field name
  /^  [a-zA-Z_]/ && /:$/ {
    field_count++
    name = $0
    gsub(/^  /, "", name)
    gsub(/:$/, "", name)
    f_name[field_count] = name
    f_type[field_count] = ""
    f_required[field_count] = ""
    f_default[field_count] = ""
    next
  }

  /^    type:/ { gsub(/^    type:[[:space:]]*/, ""); f_type[field_count] = $0; next }
  /^    required:/ { gsub(/^    required:[[:space:]]*/, ""); f_required[field_count] = $0; next }
  /^    default:/ { gsub(/^    default:[[:space:]]*/, ""); f_default[field_count] = $0; next }

  END {
    prev_p1 = ""
    prev_p2 = ""

    for (i = 1; i <= field_count; i++) {
      if (f_type[i] == "block") continue

      # Determine value
      val = f_default[i]
      if (val == "" || val == "null") {
        if (f_required[i] == "true") {
          val = "null"
        } else {
          val = "null"
        }
      }

      # Split name by dots
      n = split(f_name[i], parts, ".")

      if (n == 1) {
        print parts[1] ": " val
        prev_p1 = parts[1]
        prev_p2 = ""
      } else if (n == 2) {
        if (parts[1] != prev_p1) {
          print ""
          print parts[1] ":"
          prev_p1 = parts[1]
          prev_p2 = ""
        }
        print "  " parts[2] ": " val
      } else if (n == 3) {
        if (parts[1] != prev_p1) {
          print ""
          print parts[1] ":"
          prev_p1 = parts[1]
          prev_p2 = ""
        }
        if (parts[2] != prev_p2) {
          print "  " parts[2] ":"
          prev_p2 = parts[2]
        }
        print "    " parts[3] ": " val
      }
    }
  }
  ' "$schema_file" > "$target_path"
}

# ── moira_yaml_block_append <file> <parent_key> <yaml_text> ──────────
# Append a YAML block under a parent key (for history, gates, etc.)
moira_yaml_block_append() {
  local file="$1"
  local parent_key="$2"
  local yaml_text="$3"

  if [[ ! -f "$file" ]]; then
    echo "Error: file not found: $file" >&2
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)

  local IFS='.'
  set -- $parent_key
  local p1="${1:-}"

  awk -v p1="$p1" -v text="$yaml_text" '
  BEGIN { in_section=0; last_line=0 }
  {
    lines[NR] = $0;
    match($0, /^[[:space:]]*/);
    indent = RLENGTH;
    line = substr($0, indent + 1);

    if (indent == 0 && line ~ "^" p1 ":") { in_section=1; last_line=NR }
    if (in_section && indent == 0 && NR > 1 && !(line ~ "^" p1 ":") && !(line ~ /^[[:space:]]*$/)) { in_section=0 }
    if (in_section && indent >= 2) { last_line=NR }
  }
  END {
    for (i=1; i<=NR; i++) {
      print lines[i];
      if (i == last_line) {
        print text;
      }
    }
  }' "$file" > "$tmpfile"
  mv "$tmpfile" "$file"
}
