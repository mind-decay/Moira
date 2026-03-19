#!/usr/bin/env bash
# graph.sh — Shell library wrapping the Ariadne CLI for project graph operations.
# References: D-104 (Ariadne as separate project), D-102 (graceful degradation)
# See: design/subsystems/project-graph.md § CLI Interface
#
# Responsibilities: wrapping ariadne binary commands, freshness checks, summary extraction
# Does NOT implement graph algorithms (that's Ariadne's job)
# Bash 3.2+ compatible

set -euo pipefail

# ── Constants ────────────────────────────────────────────────────────────────

_MOIRA_GRAPH_DEFAULT_GRAPH_DIR=".ariadne/graph"
_MOIRA_GRAPH_DEFAULT_VIEWS_DIR=".ariadne/views"
_MOIRA_GRAPH_PID_FILE=".ariadne/graph/.serve.pid"

# ── moira_graph_output_dir ───────────────────────────────────────────────────
# Return the default graph output directory (relative to project root).
moira_graph_output_dir() {
  echo "${_MOIRA_GRAPH_DEFAULT_GRAPH_DIR}"
}

# ── moira_graph_views_dir ────────────────────────────────────────────────────
# Return the default views directory (relative to project root).
moira_graph_views_dir() {
  echo "${_MOIRA_GRAPH_DEFAULT_VIEWS_DIR}"
}

# ── moira_graph_check_binary ─────────────────────────────────────────────────
# Run `ariadne info` and return the version string (first line only).
# Returns empty string if ariadne is not available; never crashes.
moira_graph_check_binary() {
  if ! command -v ariadne >/dev/null 2>&1; then
    return 0
  fi

  local version
  version=$(ariadne info 2>/dev/null | head -1) || true
  echo "$version"
}

# ── moira_graph_build <project_root> [output_dir] ───────────────────────────
# Run `ariadne build` for the given project root.
# Optional output_dir overrides the default Ariadne output location.
# Passes through the exit code from ariadne.
moira_graph_build() {
  local project_root="${1:-}"
  local output_dir="${2:-}"

  if [[ -z "$project_root" ]]; then
    echo "Error: moira_graph_build requires <project_root>" >&2
    return 1
  fi

  if ! command -v ariadne >/dev/null 2>&1; then
    echo "Error: ariadne binary not found in PATH" >&2
    return 1
  fi

  if [[ -n "$output_dir" ]]; then
    ariadne build "$project_root" --output "$output_dir"
  else
    ariadne build "$project_root"
  fi
}

# ── moira_graph_update <project_root> [output_dir] ──────────────────────────
# Run `ariadne update` for the given project root (incremental rebuild).
# Optional output_dir overrides the default Ariadne output location.
# Passes through the exit code from ariadne.
moira_graph_update() {
  local project_root="${1:-}"
  local output_dir="${2:-}"

  if [[ -z "$project_root" ]]; then
    echo "Error: moira_graph_update requires <project_root>" >&2
    return 1
  fi

  if ! command -v ariadne >/dev/null 2>&1; then
    echo "Error: ariadne binary not found in PATH" >&2
    return 1
  fi

  if [[ -n "$output_dir" ]]; then
    ariadne update "$project_root" --output "$output_dir"
  else
    ariadne update "$project_root"
  fi
}

# ── moira_graph_query <subcommand> [args...] ─────────────────────────────────
# Run `ariadne query <subcommand> [args...]` and return stdout.
# Returns empty string if ariadne is not available; never crashes.
moira_graph_query() {
  local subcommand="${1:-}"

  if [[ -z "$subcommand" ]]; then
    echo "Error: moira_graph_query requires <subcommand>" >&2
    return 1
  fi

  if ! command -v ariadne >/dev/null 2>&1; then
    return 0
  fi

  shift
  ariadne query "$subcommand" "$@" 2>/dev/null || true
}

# ── moira_graph_views_generate [output_dir] [graph_dir] ─────────────────────
# Run `ariadne views generate` with optional output and graph-dir args.
# Returns empty string if ariadne is not available; passes through exit code.
moira_graph_views_generate() {
  local output_dir="${1:-}"
  local graph_dir="${2:-}"

  if ! command -v ariadne >/dev/null 2>&1; then
    echo "Error: ariadne binary not found in PATH" >&2
    return 1
  fi

  local args=()
  if [[ -n "$output_dir" ]]; then
    args+=("--output" "$output_dir")
  fi
  if [[ -n "$graph_dir" ]]; then
    args+=("--graph-dir" "$graph_dir")  # matches design doc CLI spec
  fi

  ariadne views generate "${args[@]+"${args[@]}"}"
}

# ── moira_graph_serve_start <project_root> ───────────────────────────────────
# Start `ariadne serve` in the background and persist the PID for later stop.
# PID is written to .ariadne/graph/.serve.pid (relative to cwd / project root).
# Returns 1 if ariadne is not available or if a server is already running.
moira_graph_serve_start() {
  local project_root="${1:-}"

  if [[ -z "$project_root" ]]; then
    echo "Error: moira_graph_serve_start requires <project_root>" >&2
    return 1
  fi

  if ! command -v ariadne >/dev/null 2>&1; then
    echo "Error: ariadne binary not found in PATH" >&2
    return 1
  fi

  local pid_file="${project_root}/${_MOIRA_GRAPH_PID_FILE}"

  # Check if already running
  if [[ -f "$pid_file" ]]; then
    local existing_pid
    existing_pid=$(cat "$pid_file" 2>/dev/null) || true
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
      echo "Error: ariadne serve already running (PID ${existing_pid})" >&2
      return 1
    fi
    # Stale PID file — remove it
    rm -f "$pid_file"
  fi

  mkdir -p "$(dirname "$pid_file")"

  # Start in background, redirect stdio to avoid blocking the caller
  ariadne serve --project "$project_root" </dev/null >/dev/null 2>&1 &
  local server_pid=$!

  echo "$server_pid" > "$pid_file"
  echo "$server_pid"
}

# ── moira_graph_serve_stop [project_root] ────────────────────────────────────
# Stop the MCP server process if running.
# Reads PID from .ariadne/graph/.serve.pid relative to project_root (or cwd).
# Silent no-op if no server is running.
moira_graph_serve_stop() {
  local project_root="${1:-.}"
  local pid_file="${project_root}/${_MOIRA_GRAPH_PID_FILE}"

  if [[ ! -f "$pid_file" ]]; then
    return 0
  fi

  local pid
  pid=$(cat "$pid_file" 2>/dev/null) || true

  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
  fi

  rm -f "$pid_file"
  return 0
}

# ── moira_graph_is_fresh <graph_dir> ────────────────────────────────────────
# Return 0 if graph.json exists and is newer than all project source files.
# Return 1 otherwise (graph is absent or stale).
# Heuristic: checks if any source file (*.ts, *.tsx, *.js, *.jsx, *.go,
#   *.py, *.rs, *.cs, *.java) is newer than graph.json.
moira_graph_is_fresh() {
  local graph_dir="${1:-${_MOIRA_GRAPH_DEFAULT_GRAPH_DIR}}"
  local graph_file="${graph_dir}/graph.json"

  if [[ ! -f "$graph_file" ]]; then
    return 1
  fi

  # Find any source file newer than graph.json (heuristic — samples top 4 levels)
  local newer_files
  newer_files=$(find . -maxdepth 4 \
    \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" \
       -o -name "*.go" -o -name "*.py" -o -name "*.rs" \
       -o -name "*.cs" -o -name "*.java" \) \
    -newer "$graph_file" \
    -not -path "./.ariadne/*" \
    -not -path "./node_modules/*" \
    2>/dev/null | head -1)

  if [[ -n "$newer_files" ]]; then
    return 1
  fi

  return 0
}

# ── moira_graph_summary <graph_dir> ─────────────────────────────────────────
# Extract key metrics from graph.json, stats.json, and clusters.json.
# Outputs key=value pairs, one per line:
#   node_count=<N>
#   edge_count=<N>
#   cluster_count=<N>
#   cycle_count=<N>
#   smell_count=<N>
#   monolith_score=<V>
# Uses jq when available, falls back to grep/sed.
moira_graph_summary() {
  local graph_dir="${1:-${_MOIRA_GRAPH_DEFAULT_GRAPH_DIR}}"
  local graph_file="${graph_dir}/graph.json"
  local stats_file="${graph_dir}/stats.json"
  local clusters_file="${graph_dir}/clusters.json"

  local node_count=0
  local edge_count=0
  local cluster_count=0
  local cycle_count=0
  local smell_count=0
  local bottleneck_count=0
  local monolith_score=0

  if command -v jq >/dev/null 2>&1; then
    # ── jq path ──────────────────────────────────────────────────────────────
    if [[ -f "$graph_file" ]]; then
      node_count=$(jq '(.nodes // {}) | length' "$graph_file" 2>/dev/null) || node_count=0
      edge_count=$(jq '(.edges // []) | length' "$graph_file" 2>/dev/null) || edge_count=0
    fi

    if [[ -f "$clusters_file" ]]; then
      cluster_count=$(jq '(.clusters // {}) | length' "$clusters_file" 2>/dev/null) || cluster_count=0
    fi

    if [[ -f "$stats_file" ]]; then
      # cycles = number of SCCs with size > 1
      cycle_count=$(jq '[(.sccs // [])[] | select(length > 1)] | length' "$stats_file" 2>/dev/null) || cycle_count=0
      # monolith_score from spectral analysis (field may not exist yet)
      monolith_score=$(jq '.monolith_score // 0' "$stats_file" 2>/dev/null) || monolith_score=0
    fi

  else
    # ── grep/sed fallback ────────────────────────────────────────────────────
    if [[ -f "$graph_file" ]]; then
      # Count node keys: lines like "  \"src/...\": {" at depth 1 inside "nodes"
      # Use a simple heuristic: count lines that start a file entry
      node_count=$(grep -c '"file_type"' "$graph_file" 2>/dev/null) || node_count=0
      # Count edge objects: lines with "from":
      edge_count=$(grep -c '"from"' "$graph_file" 2>/dev/null) || edge_count=0
    fi

    if [[ -f "$clusters_file" ]]; then
      # Count cluster entries: lines with "internal_edges"
      cluster_count=$(grep -c '"internal_edges"' "$clusters_file" 2>/dev/null) || cluster_count=0
    fi

    if [[ -f "$stats_file" ]]; then
      # Count SCCs with >1 element — look for arrays with commas (multi-element)
      # inside the "sccs" field. Best-effort without jq.
      cycle_count=$(sed -n '/"sccs"/,/\]/p' "$stats_file" 2>/dev/null | \
        grep -c '.*,.*' 2>/dev/null) || cycle_count=0
      # monolith_score: extract numeric value
      monolith_score=$(grep '"monolith_score"' "$stats_file" 2>/dev/null | \
        sed 's/.*"monolith_score"[[:space:]]*:[[:space:]]*\([0-9.]*\).*/\1/' | \
        head -1) || monolith_score=0
      monolith_score="${monolith_score:-0}"
    fi
  fi

  # bottleneck_count: files with centrality > 0.9 (from stats.json)
  if command -v jq >/dev/null 2>&1 && [[ -f "$stats_file" ]]; then
    bottleneck_count=$(jq '[(.centrality // {}) | to_entries[] | select(.value > 0.9)] | length' "$stats_file" 2>/dev/null) || bottleneck_count=0
  fi

  # smell_count: attempt a query; fall back to 0 if unavailable
  if command -v ariadne >/dev/null 2>&1; then
    local smell_output
    smell_output=$(ariadne query smells 2>/dev/null) || smell_output=""
    if [[ -n "$smell_output" ]]; then
      smell_count=$(echo "$smell_output" | grep -c '"type"' 2>/dev/null) || smell_count=0
    fi
  fi

  echo "node_count=${node_count}"
  echo "edge_count=${edge_count}"
  echo "cluster_count=${cluster_count}"
  echo "cycle_count=${cycle_count}"
  echo "bottleneck_count=${bottleneck_count}"
  echo "smell_count=${smell_count}"
  echo "monolith_score=${monolith_score}"
}

# ── moira_graph_read_view <level> [cluster_name] [graph_dir] ────────────────
# Return the contents of the L0 index.md or an L1 cluster view.
# level: L0 → views/index.md
#        L1 → views/clusters/<cluster_name>.md  (cluster_name required)
# Returns empty string if the file does not exist; never crashes.
moira_graph_read_view() {
  local level="${1:-}"
  local cluster_name="${2:-}"
  local views_dir="${3:-${_MOIRA_GRAPH_DEFAULT_VIEWS_DIR}}"

  if [[ -z "$level" ]]; then
    echo "Error: moira_graph_read_view requires <level> (L0 or L1)" >&2
    return 1
  fi

  local target=""

  case "$level" in
    L0)
      target="${views_dir}/index.md"
      ;;
    L1)
      if [[ -z "$cluster_name" ]]; then
        echo "Error: moira_graph_read_view L1 requires <cluster_name>" >&2
        return 1
      fi
      target="${views_dir}/clusters/${cluster_name}.md"
      ;;
    *)
      echo "Error: moira_graph_read_view level must be L0 or L1, got '${level}'" >&2
      return 1
      ;;
  esac

  if [[ -f "$target" ]]; then
    cat "$target"
  fi

  return 0
}
