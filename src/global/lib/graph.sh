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

# ── moira_graph_temporal_available <project_root> ────────────────────────────
# Check if temporal (git history) data is available via Ariadne.
# Returns 0 if temporal data is available, 1 otherwise.
# Detection: probes `ariadne query hotspots --format json --top 1` — if it
# returns a non-empty JSON array, temporal data is available.
# Reference: D-159, AD-3 (ariadne query overview does not exist as CLI subcommand)
moira_graph_temporal_available() {
  local project_root="${1:-}"

  if [[ -z "$project_root" ]]; then
    echo "Error: moira_graph_temporal_available requires <project_root>" >&2
    return 1
  fi

  if ! command -v ariadne >/dev/null 2>&1; then
    return 1
  fi

  local probe_output
  probe_output=$(ariadne query hotspots --format json --top 1 2>/dev/null) || return 1

  if [[ -z "$probe_output" ]] || [[ "$probe_output" == "[]" ]]; then
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

  # Temporal summary (if available)
  # AD-3: ariadne query overview does not exist as CLI subcommand; use hotspots + coupling instead
  if moira_graph_temporal_available "${graph_dir%/*}" 2>/dev/null; then
    local hotspot_count=0
    local hidden_dep_count=0

    if command -v jq >/dev/null 2>&1; then
      local hotspot_output
      hotspot_output=$(ariadne query hotspots --format json 2>/dev/null) || hotspot_output="[]"
      hotspot_count=$(echo "$hotspot_output" | jq 'if type == "array" then length else 0 end' 2>/dev/null) || hotspot_count=0

      local coupling_output
      coupling_output=$(ariadne query coupling --format json 2>/dev/null) || coupling_output="[]"
      hidden_dep_count=$(echo "$coupling_output" | jq '[.[] | select(.has_structural_link == false)] | length' 2>/dev/null) || hidden_dep_count=0
    fi

    hotspot_count="${hotspot_count:-0}"
    hidden_dep_count="${hidden_dep_count:-0}"
    echo "temporal_available=true"
    echo "hotspot_count=${hotspot_count}"
    echo "hidden_dep_count=${hidden_dep_count}"
  else
    echo "temporal_available=false"
  fi
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

# ── moira_graph_analytical_baseline [scope_path] ─────────────────────────────
# Run the 6 baseline Ariadne queries for the analytical pipeline gather step.
# Returns output suitable for writing to ariadne-baseline.md.
# For scoped analysis, also runs blast-radius and file-detail queries.
# If Ariadne binary not found, returns a degradation message (D-102).
moira_graph_analytical_baseline() {
  local scope_path="${1:-}"
  local project_root="${2:-.}"

  if ! command -v ariadne >/dev/null 2>&1; then
    echo "# Ariadne Baseline"
    echo ""
    echo "Ariadne not available. Structural analysis skipped."
    echo "Analysis proceeds with code-level data only."
    return 0
  fi

  echo "# Ariadne Baseline"
  echo ""
  echo "Generated at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""

  echo "## Overview"
  echo ""
  ariadne query overview 2>/dev/null || echo "(query failed)"
  echo ""

  echo "## Smells"
  echo ""
  ariadne query smells 2>/dev/null || echo "(query failed)"
  echo ""

  echo "## Metrics"
  echo ""
  ariadne query metrics 2>/dev/null || echo "(query failed)"
  echo ""

  echo "## Layers"
  echo ""
  ariadne query layers 2>/dev/null || echo "(query failed)"
  echo ""

  echo "## Cycles"
  echo ""
  ariadne query cycles 2>/dev/null || echo "(query failed)"
  echo ""

  echo "## Clusters"
  echo ""
  ariadne query clusters 2>/dev/null || echo "(query failed)"
  echo ""

  # Scoped queries (if scope path provided)
  if [[ -n "$scope_path" ]]; then
    echo "## Blast Radius (Scoped)"
    echo ""
    ariadne query blast-radius "$scope_path" 2>/dev/null || echo "(query failed)"
    echo ""

    echo "## File Detail (Scoped)"
    echo ""
    ariadne query file "$scope_path" 2>/dev/null || echo "(query failed)"
    echo ""
  fi

  # Phase 4/5 MCP tools notice (D-151r)
  echo "## Available MCP Tools (Phase 4/5)"
  echo ""
  echo "Agents dispatched during analysis have access to these additional Ariadne MCP tools:"
  echo "- ariadne_symbols: List symbols in a file (functions, classes, types)"
  echo "- ariadne_symbol_search: Search symbols by name across the project"
  echo "- ariadne_callers: Find cross-file call sites of a symbol"
  echo "- ariadne_callees: Find cross-file callees of a function"
  echo "- ariadne_symbol_blast_radius: Trace transitive callers of a symbol"
  echo "- ariadne_context: Assemble optimal file context within a token budget"
  echo "- ariadne_tests_for: Identify test files for source files"
  echo "- ariadne_reading_order: Get optimal file reading order"
  echo "- ariadne_plan_impact: Analyze impact of planned changes"
  echo ""

  # Phase 6 MCP tools notice (D-157)
  echo "## Available MCP Tools (Phase 6 — Annotations & Bookmarks)"
  echo ""
  echo "Agents dispatched during analysis have access to these Ariadne Phase 6 MCP tools:"
  echo "- ariadne_annotate: Add/update annotation on file, cluster, symbol, or edge"
  echo "- ariadne_annotations: List annotations with tag/target filter"
  echo "- ariadne_remove_annotation: Remove an annotation"
  echo "- ariadne_bookmark: Create named subgraph bookmark"
  echo "- ariadne_bookmarks: List all bookmarks"
  echo "- ariadne_remove_bookmark: Remove a bookmark"
  echo "Note: Write tools (annotate, bookmark, remove-*) are restricted by agent role."
  echo ""

  # Phase 7 MCP tools notice — conditional on temporal availability (D-161)
  if moira_graph_temporal_available "$project_root" 2>/dev/null; then
    echo "## Available MCP Tools (Phase 7 — Temporal Analysis)"
    echo ""
    echo "Temporal data is available. Agents have access to these Ariadne Phase 7 MCP tools:"
    echo "- ariadne_churn: Files by change frequency for period (30d/90d/1y)"
    echo "- ariadne_coupling: Co-change pairs above confidence threshold"
    echo "- ariadne_hotspots: Files ranked by churn x LOC x blast_radius"
    echo "- ariadne_ownership: Authors/contributors per file or project-wide"
    echo "- ariadne_hidden_deps: Co-change pairs with NO structural import link"
    echo ""
  else
    echo "## Available MCP Tools (Phase 7 — Temporal Analysis)"
    echo ""
    echo "Temporal data is NOT available (no git history or shallow clone)."
    echo "Phase 7 tools will return temporal_unavailable errors."
    echo ""
  fi

  return 0
}

# ── moira_graph_populate_knowledge <project_root> <knowledge_dir> ──────────
# Populate quality-map and project-model from Ariadne structural data.
# Queries Ariadne CLI for smells, cycles, hotspots, coupling, centrality,
# layers, metrics, and boundaries. Writes entries to quality-map/full.md
# (Problematic/Adequate) and project-model/full.md (structural sections).
# Saves graph snapshot to .moira/state/graph-snapshot.json for diff.
#
# Preconditions: ariadne + jq in PATH, knowledge_dir exists.
# Graceful degradation: returns 0 silently if ariadne absent; warns if jq absent.
# Each ariadne query wrapped in `|| true` — individual failure does not abort.
# Reference: Phase 15, AD-1 through AD-5
moira_graph_populate_knowledge() {
  local project_root="${1:-}"
  local knowledge_dir="${2:-}"

  if [[ -z "$project_root" ]] || [[ -z "$knowledge_dir" ]]; then
    echo "Error: moira_graph_populate_knowledge requires <project_root> <knowledge_dir>" >&2
    return 1
  fi

  # Precondition 1: ariadne binary
  if ! command -v ariadne >/dev/null 2>&1; then
    return 0
  fi

  # Precondition 2: jq binary
  if ! command -v jq >/dev/null 2>&1; then
    echo "Warning: jq not found — skipping Ariadne-to-knowledge pipeline" >&2
    return 0
  fi

  # Precondition 3: knowledge_dir exists
  if [[ ! -d "$knowledge_dir" ]]; then
    echo "Error: knowledge_dir does not exist: $knowledge_dir" >&2
    return 1
  fi

  # Source knowledge.sh for moira_knowledge_write
  source "$(dirname "${BASH_SOURCE[0]}")/knowledge.sh"

  local today
  today=$(date -u +%Y-%m-%d)
  local graph_dir="${project_root}/${_MOIRA_GRAPH_DEFAULT_GRAPH_DIR}"

  # ── Collect Ariadne data ──────────────────────────────────────────────

  # 1. Smells
  local smells_json
  smells_json=$(ariadne query smells --format json 2>/dev/null) || true
  local smells_valid="false"
  if [[ -n "$smells_json" ]] && echo "$smells_json" | jq type 2>/dev/null | grep -q '"array"'; then
    smells_valid="true"
  fi

  # 2. Cycles
  local cycles_json
  cycles_json=$(ariadne query cycles --format json 2>/dev/null) || true
  local cycles_valid="false"
  if [[ -n "$cycles_json" ]] && echo "$cycles_json" | jq type 2>/dev/null | grep -q '"array"'; then
    cycles_valid="true"
  fi

  # 3. Hotspots (temporal only)
  local hotspots_json="[]"
  local hotspots_valid="false"
  if moira_graph_temporal_available "$project_root" 2>/dev/null; then
    hotspots_json=$(ariadne query hotspots --format json 2>/dev/null) || true
    if [[ -n "$hotspots_json" ]] && echo "$hotspots_json" | jq type 2>/dev/null | grep -q '"array"'; then
      hotspots_valid="true"
    fi
  fi

  # 4. Coupling (temporal only, confidence >= 0.5)
  local coupling_json="[]"
  local coupling_valid="false"
  if moira_graph_temporal_available "$project_root" 2>/dev/null; then
    coupling_json=$(ariadne query coupling --format json 2>/dev/null) || true
    if [[ -n "$coupling_json" ]] && echo "$coupling_json" | jq type 2>/dev/null | grep -q '"array"'; then
      coupling_valid="true"
    fi
  fi

  # 5. Centrality
  local centrality_json
  centrality_json=$(ariadne query centrality --format json 2>/dev/null) || true
  local centrality_valid="false"
  if [[ -n "$centrality_json" ]] && echo "$centrality_json" | jq type 2>/dev/null | grep -q '"object"'; then
    centrality_valid="true"
  fi

  # 6. Layers
  local layers_json
  layers_json=$(ariadne query layers --format json 2>/dev/null) || true
  local layers_valid="false"
  if [[ -n "$layers_json" ]] && echo "$layers_json" | jq type 2>/dev/null | grep -q '"object"'; then
    layers_valid="true"
  fi

  # 7. Metrics
  local metrics_json
  metrics_json=$(ariadne query metrics --format json 2>/dev/null) || true
  local metrics_valid="false"
  if [[ -n "$metrics_json" ]] && echo "$metrics_json" | jq type 2>/dev/null | grep -q '"object"'; then
    metrics_valid="true"
  fi

  # 8. Boundaries
  local boundaries_json
  boundaries_json=$(ariadne query boundaries --format json 2>/dev/null) || true
  local boundaries_valid="false"
  if [[ -n "$boundaries_json" ]] && echo "$boundaries_json" | jq type 2>/dev/null | grep -qE '"object"|"array"'; then
    boundaries_valid="true"
  fi

  # ── Write quality-map entries ─────────────────────────────────────────

  local qm_tmp
  qm_tmp=$(mktemp)

  {
    echo "<!-- moira:freshness ariadne-init ${today} -->"
    echo "<!-- moira:mode conform -->"
    echo ""
    echo "# Quality Map"
    echo ""
    echo "## Problematic"
    echo ""

    # Smells -> Problematic
    if [[ "$smells_valid" == "true" ]]; then
      echo "$smells_json" | jq -r '.[] | "\(.smell_type)\t\(.files | join(", "))\t\(.files[0] // "unknown")"' 2>/dev/null | while IFS=$'\t' read -r smell_type file_list first_file; do
        echo "### ${smell_type}: ${first_file}"
        echo "- **Category**: ${smell_type}"
        echo "- **Evidence**: ariadne structural analysis"
        echo "- **File(s)**: ${file_list}"
        echo "- **Confidence**: high"
        echo "- **Observation count**: 1"
        echo "- **Failed observations**: 0"
        echo "- **Consecutive passes**: 0"
        echo "- **Lifecycle**: NEW"
        echo ""
      done
    fi

    # Cycles -> Problematic
    if [[ "$cycles_valid" == "true" ]]; then
      local cycle_count
      cycle_count=$(echo "$cycles_json" | jq 'length' 2>/dev/null) || cycle_count=0
      if [[ "$cycle_count" -gt 0 ]]; then
        echo "$cycles_json" | jq -r '.[] | join(", ")' 2>/dev/null | while IFS= read -r member_files; do
          echo "### Circular dependency: ${member_files}"
          echo "- **Category**: circular dependency"
          echo "- **Evidence**: ariadne structural analysis"
          echo "- **File(s)**: ${member_files}"
          echo "- **Confidence**: high"
          echo "- **Observation count**: 1"
          echo "- **Failed observations**: 0"
          echo "- **Consecutive passes**: 0"
          echo "- **Lifecycle**: NEW"
          echo ""
        done
      fi
    fi

    # Hotspots -> Problematic (temporal only)
    if [[ "$hotspots_valid" == "true" ]]; then
      echo "$hotspots_json" | jq -r '.[0:20] | .[] | .path' 2>/dev/null | while IFS= read -r hotspot_path; do
        echo "### Hotspot: ${hotspot_path}"
        echo "- **Category**: churn hotspot"
        echo "- **Evidence**: ariadne temporal analysis"
        echo "- **File(s)**: ${hotspot_path}"
        echo "- **Confidence**: high"
        echo "- **Observation count**: 1"
        echo "- **Failed observations**: 0"
        echo "- **Consecutive passes**: 0"
        echo "- **Lifecycle**: NEW"
        echo ""
      done
    fi

    echo "## Adequate"
    echo ""

    # Coupling -> Adequate (temporal only, confidence >= 0.5)
    if [[ "$coupling_valid" == "true" ]]; then
      echo "$coupling_json" | jq -r '.[] | select(.confidence >= 0.5) | "\(.file_a)\t\(.file_b)\t\(.confidence)"' 2>/dev/null | while IFS=$'\t' read -r file_a file_b confidence; do
        echo "### Co-change coupling: ${file_a} <-> ${file_b}"
        echo "- **Category**: structural coupling"
        echo "- **Evidence**: ariadne temporal analysis (confidence: ${confidence})"
        echo "- **File(s)**: ${file_a}, ${file_b}"
        echo "- **Confidence**: high"
        echo "- **Observation count**: 1"
        echo "- **Failed observations**: 0"
        echo "- **Consecutive passes**: 0"
        echo "- **Lifecycle**: NEW"
        echo ""
      done
    fi

    echo "## Strong"
    echo ""
    echo "(populated by observation — no entries at init)"
    echo ""
  } > "$qm_tmp"

  mkdir -p "${knowledge_dir}/quality-map"
  cp "$qm_tmp" "${knowledge_dir}/quality-map/full.md"
  rm -f "$qm_tmp"

  # ── Write project-model sections ──────────────────────────────────────

  local pm_tmp
  pm_tmp=$(mktemp)

  {
    echo "## Structural Bottlenecks"
    echo ""

    # Centrality: top 15 by value
    if [[ "$centrality_valid" == "true" ]]; then
      echo "| File | Centrality Score |"
      echo "|------|-----------------|"
      echo "$centrality_json" | jq -r 'to_entries | sort_by(-.value) | .[0:15] | .[] | "| \(.key) | \(.value) |"' 2>/dev/null || true
    else
      echo "(no centrality data available)"
    fi
    echo ""

    echo "## Architectural Layers"
    echo ""

    # Layers
    if [[ "$layers_valid" == "true" ]]; then
      echo "| Layer | Files |"
      echo "|-------|-------|"
      echo "$layers_json" | jq -r 'to_entries | .[] | "| \(.key) | \(.value | join(", ") | if length > 120 then .[0:117] + "..." else . end) |"' 2>/dev/null || true
    else
      echo "(no layer data available)"
    fi
    echo ""

    echo "## Cluster Metrics"
    echo ""

    # Metrics
    if [[ "$metrics_valid" == "true" ]]; then
      echo "| Cluster | Instability | Abstractness | Distance | Zone |"
      echo "|---------|-------------|-------------|----------|------|"
      echo "$metrics_json" | jq -r 'to_entries | .[] | "| \(.value.cluster_id) | \(.value.instability) | \(.value.abstractness) | \(.value.distance) | \(.value.zone) |"' 2>/dev/null || true
    else
      echo "(no cluster metrics available)"
    fi
    echo ""

    echo "## Architectural Boundaries"
    echo ""

    # Boundaries
    if [[ "$boundaries_valid" == "true" ]]; then
      echo "$boundaries_json" | jq -r 'if type == "array" then .[] | tostring elif type == "object" then to_entries[] | "- \(.key): \(.value | tostring)" else tostring end' 2>/dev/null || true
    else
      echo "(no boundary data available)"
    fi
    echo ""

    echo "## Graph Summary"
    echo ""

    # Graph summary from files (follow existing moira_graph_summary pattern)
    local graph_file="${graph_dir}/graph.json"
    local stats_file="${graph_dir}/stats.json"
    local clusters_file="${graph_dir}/clusters.json"

    local gs_nodes=0 gs_edges=0 gs_clusters=0 gs_cycles=0 gs_smells=0 gs_monolith=0

    if [[ -f "$graph_file" ]]; then
      gs_nodes=$(jq '(.nodes // {}) | length' "$graph_file" 2>/dev/null) || gs_nodes=0
      gs_edges=$(jq '(.edges // []) | length' "$graph_file" 2>/dev/null) || gs_edges=0
    fi
    if [[ -f "$clusters_file" ]]; then
      gs_clusters=$(jq '(.clusters // {}) | length' "$clusters_file" 2>/dev/null) || gs_clusters=0
    fi
    if [[ -f "$stats_file" ]]; then
      gs_cycles=$(jq '[(.sccs // [])[] | select(length > 1)] | length' "$stats_file" 2>/dev/null) || gs_cycles=0
      gs_monolith=$(jq '.monolith_score // 0' "$stats_file" 2>/dev/null) || gs_monolith=0
    fi
    if [[ "$smells_valid" == "true" ]]; then
      gs_smells=$(echo "$smells_json" | jq 'length' 2>/dev/null) || gs_smells=0
    fi

    local temporal_status="unavailable"
    if moira_graph_temporal_available "$project_root" 2>/dev/null; then
      temporal_status="available"
    fi

    echo "- Nodes: ${gs_nodes}"
    echo "- Edges: ${gs_edges}"
    echo "- Clusters: ${gs_clusters}"
    echo "- Cycles: ${gs_cycles}"
    echo "- Smells: ${gs_smells}"
    echo "- Monolith score: ${gs_monolith}"
    echo "- Temporal: ${temporal_status}"
    echo ""
  } > "$pm_tmp"

  # Append structural sections to project-model/full.md
  local pm_full="${knowledge_dir}/project-model/full.md"
  mkdir -p "$(dirname "$pm_full")"
  if [[ -f "$pm_full" ]]; then
    # Remove existing structural sections before appending fresh data
    local pm_cleaned
    pm_cleaned=$(mktemp)
    # Use awk to strip sections we're replacing
    awk '
      /^## (Structural Bottlenecks|Architectural Layers|Cluster Metrics|Architectural Boundaries|Graph Summary)$/ { skip=1; next }
      /^## / { skip=0 }
      !skip { print }
    ' "$pm_full" > "$pm_cleaned" 2>/dev/null || cp "$pm_full" "$pm_cleaned"
    {
      cat "$pm_cleaned"
      echo ""
      cat "$pm_tmp"
    } > "$pm_full"
    rm -f "$pm_cleaned"
  else
    {
      echo "<!-- moira:freshness ariadne-init ${today} -->"
      echo ""
      echo "# Project Model"
      echo ""
      cat "$pm_tmp"
    } > "$pm_full"
  fi
  rm -f "$pm_tmp"

  # ── Snapshot persistence (AD-2) ───────────────────────────────────────

  local state_dir="${project_root}/.moira/state"
  mkdir -p "$state_dir"

  local snapshot_file="${state_dir}/graph-snapshot.json"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  local snapshot_smells="[]"
  if [[ "$smells_valid" == "true" ]]; then
    snapshot_smells="$smells_json"
  fi

  local snapshot_cycles="[]"
  if [[ "$cycles_valid" == "true" ]]; then
    snapshot_cycles="$cycles_json"
  fi

  jq -n --arg ts "$timestamp" --argjson smells "$snapshot_smells" --argjson cycles "$snapshot_cycles" \
    '{"timestamp": $ts, "smells": $smells, "cycles": $cycles}' > "$snapshot_file" 2>/dev/null || {
    # Fallback if jq construction fails
    echo "{\"timestamp\":\"${timestamp}\",\"smells\":[],\"cycles\":[]}" > "$snapshot_file"
  }

  # ── L0/L1 regeneration ───────────────────────────────────────────────

  # Generate quality-map summary (L1) and index (L0)
  local qm_full="${knowledge_dir}/quality-map/full.md"
  if [[ -f "$qm_full" ]]; then
    local qm_summary_tmp
    qm_summary_tmp=$(mktemp)
    {
      echo "# Quality Map Summary"
      echo ""
      echo "## Problematic"
      grep '^### ' "$qm_full" 2>/dev/null | sed 's/^### /- /' | head -30
      echo ""
    } > "$qm_summary_tmp"
    moira_knowledge_write "$knowledge_dir" "quality-map" "L1" "$qm_summary_tmp" "ariadne-init" 2>/dev/null || true
    rm -f "$qm_summary_tmp"

    local qm_index_tmp
    qm_index_tmp=$(mktemp)
    {
      echo "# Quality Map Index"
      echo ""
      grep '^## ' "$qm_full" 2>/dev/null || true
    } > "$qm_index_tmp"
    moira_knowledge_write "$knowledge_dir" "quality-map" "L0" "$qm_index_tmp" "ariadne-init" 2>/dev/null || true
    rm -f "$qm_index_tmp"
  fi

  # Generate project-model summary (L1) and index (L0)
  if [[ -f "$pm_full" ]]; then
    local pm_summary_tmp
    pm_summary_tmp=$(mktemp)
    {
      echo "# Project Model Summary"
      echo ""
      grep -E '^## |^- (Nodes|Edges|Clusters|Cycles|Smells|Monolith|Temporal)' "$pm_full" 2>/dev/null || true
    } > "$pm_summary_tmp"
    moira_knowledge_write "$knowledge_dir" "project-model" "L1" "$pm_summary_tmp" "ariadne-init" 2>/dev/null || true
    rm -f "$pm_summary_tmp"

    local pm_index_tmp
    pm_index_tmp=$(mktemp)
    {
      echo "# Project Model Index"
      echo ""
      grep '^## ' "$pm_full" 2>/dev/null || true
    } > "$pm_index_tmp"
    moira_knowledge_write "$knowledge_dir" "project-model" "L0" "$pm_index_tmp" "ariadne-init" 2>/dev/null || true
    rm -f "$pm_index_tmp"
  fi

  return 0
}

# ── moira_graph_diff_to_knowledge <project_root> <knowledge_dir> ─────────
# Compare current Ariadne smells/cycles against saved snapshot and update
# quality-map accordingly: new findings append, resolved findings trigger
# pass observations. Overwrites project-model structural sections with fresh data.
# Saves updated snapshot for future diffs.
#
# Preconditions: ariadne + jq in PATH, knowledge_dir exists.
# Graceful degradation: returns 0 silently if ariadne absent; warns if jq absent.
# Reference: Phase 15, AD-2 (snapshot-based diff)
moira_graph_diff_to_knowledge() {
  local project_root="${1:-}"
  local knowledge_dir="${2:-}"

  if [[ -z "$project_root" ]] || [[ -z "$knowledge_dir" ]]; then
    echo "Error: moira_graph_diff_to_knowledge requires <project_root> <knowledge_dir>" >&2
    return 1
  fi

  # Precondition 1: ariadne binary
  if ! command -v ariadne >/dev/null 2>&1; then
    return 0
  fi

  # Precondition 2: jq binary
  if ! command -v jq >/dev/null 2>&1; then
    echo "Warning: jq not found — skipping Ariadne diff-to-knowledge pipeline" >&2
    return 0
  fi

  # Precondition 3: knowledge_dir exists
  if [[ ! -d "$knowledge_dir" ]]; then
    echo "Error: knowledge_dir does not exist: $knowledge_dir" >&2
    return 1
  fi

  # Source knowledge.sh for pass_observation and write functions
  source "$(dirname "${BASH_SOURCE[0]}")/knowledge.sh"

  local today
  today=$(date -u +%Y-%m-%d)
  local state_dir="${project_root}/.moira/state"
  local snapshot_file="${state_dir}/graph-snapshot.json"

  # ── Load previous snapshot ───────────────────────────────────────────

  if [[ ! -f "$snapshot_file" ]]; then
    # No snapshot — fallback to full populate (AD-2 task 3.8)
    moira_graph_populate_knowledge "$project_root" "$knowledge_dir"
    return $?
  fi

  local snapshot_smells snapshot_cycles
  snapshot_smells=$(jq '.smells // []' "$snapshot_file" 2>/dev/null) || snapshot_smells="[]"
  snapshot_cycles=$(jq '.cycles // []' "$snapshot_file" 2>/dev/null) || snapshot_cycles="[]"

  # ── Query current data ───────────────────────────────────────────────

  local current_smells current_cycles
  current_smells=$(ariadne query smells --format json 2>/dev/null) || true
  current_cycles=$(ariadne query cycles --format json 2>/dev/null) || true

  # Validate JSON
  local smells_valid="false"
  if [[ -n "$current_smells" ]] && echo "$current_smells" | jq type 2>/dev/null | grep -q '"array"'; then
    smells_valid="true"
  else
    current_smells="[]"
  fi

  local cycles_valid="false"
  if [[ -n "$current_cycles" ]] && echo "$current_cycles" | jq type 2>/dev/null | grep -q '"array"'; then
    cycles_valid="true"
  else
    current_cycles="[]"
  fi

  # ── Compare smells: smell_type + sorted files as dedup key ───────────

  local snapshot_smell_keys current_smell_keys
  snapshot_smell_keys=$(echo "$snapshot_smells" | jq -r '[.[] | (.smell_type + ":" + (.files | sort | join(",")))] | sort | .[]' 2>/dev/null) || snapshot_smell_keys=""
  current_smell_keys=$(echo "$current_smells" | jq -r '[.[] | (.smell_type + ":" + (.files | sort | join(",")))] | sort | .[]' 2>/dev/null) || current_smell_keys=""

  # New smells = in current but not snapshot
  local new_smell_keys resolved_smell_keys
  if [[ -n "$current_smell_keys" ]] && [[ -n "$snapshot_smell_keys" ]]; then
    new_smell_keys=$(comm -23 <(echo "$current_smell_keys") <(echo "$snapshot_smell_keys")) || new_smell_keys=""
    resolved_smell_keys=$(comm -13 <(echo "$current_smell_keys") <(echo "$snapshot_smell_keys")) || resolved_smell_keys=""
  elif [[ -n "$current_smell_keys" ]]; then
    new_smell_keys="$current_smell_keys"
    resolved_smell_keys=""
  else
    new_smell_keys=""
    resolved_smell_keys="$snapshot_smell_keys"
  fi

  local qm_full="${knowledge_dir}/quality-map/full.md"
  mkdir -p "$(dirname "$qm_full")"

  # Append new smells to quality-map Problematic section
  if [[ -n "$new_smell_keys" ]]; then
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local smell_type="${key%%:*}"
      local file_list="${key#*:}"
      local first_file="${file_list%%,*}"

      local entry_block
      entry_block=$(printf '%s\n' \
        "### ${smell_type}: ${first_file}" \
        "- **Category**: ${smell_type}" \
        "- **Evidence**: ariadne-refresh ${today}" \
        "- **File(s)**: ${file_list}" \
        "- **Confidence**: high" \
        "- **Observation count**: 1" \
        "- **Failed observations**: 0" \
        "- **Consecutive passes**: 0" \
        "- **Lifecycle**: NEW" \
        "")

      if [[ -f "$qm_full" ]] && grep -q "^## Problematic" "$qm_full" 2>/dev/null; then
        local prob_line
        prob_line=$(grep -n "^## Problematic" "$qm_full" | head -1 | cut -d: -f1)
        if [[ -n "$prob_line" ]]; then
          local head_part tail_part
          head_part=$(head -n "$prob_line" "$qm_full")
          tail_part=$(tail -n +"$((prob_line + 1))" "$qm_full")
          printf '%s\n\n%s\n%s\n' "$head_part" "$entry_block" "$tail_part" > "$qm_full"
        fi
      elif [[ -f "$qm_full" ]]; then
        printf '\n%s\n' "$entry_block" >> "$qm_full"
      fi
    done <<< "$new_smell_keys"
  fi

  # Resolved smells -> pass observation
  if [[ -n "$resolved_smell_keys" ]]; then
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local smell_type="${key%%:*}"
      local file_list="${key#*:}"
      local first_file="${file_list%%,*}"
      local entry_name="${smell_type}: ${first_file}"
      moira_knowledge_quality_map_pass_observation "${knowledge_dir}/quality-map" "$entry_name" "ariadne-refresh" 2>/dev/null || true
    done <<< "$resolved_smell_keys"
  fi

  # ── Compare cycles ───────────────────────────────────────────────────

  local snapshot_cycle_keys current_cycle_keys
  snapshot_cycle_keys=$(echo "$snapshot_cycles" | jq -r '[.[] | sort | join(",")] | sort | .[]' 2>/dev/null) || snapshot_cycle_keys=""
  current_cycle_keys=$(echo "$current_cycles" | jq -r '[.[] | sort | join(",")] | sort | .[]' 2>/dev/null) || current_cycle_keys=""

  local new_cycle_keys resolved_cycle_keys
  if [[ -n "$current_cycle_keys" ]] && [[ -n "$snapshot_cycle_keys" ]]; then
    new_cycle_keys=$(comm -23 <(echo "$current_cycle_keys") <(echo "$snapshot_cycle_keys")) || new_cycle_keys=""
    resolved_cycle_keys=$(comm -13 <(echo "$current_cycle_keys") <(echo "$snapshot_cycle_keys")) || resolved_cycle_keys=""
  elif [[ -n "$current_cycle_keys" ]]; then
    new_cycle_keys="$current_cycle_keys"
    resolved_cycle_keys=""
  else
    new_cycle_keys=""
    resolved_cycle_keys="$snapshot_cycle_keys"
  fi

  # Append new cycles
  if [[ -n "$new_cycle_keys" ]]; then
    while IFS= read -r member_files; do
      [[ -z "$member_files" ]] && continue
      local display_files
      display_files=$(echo "$member_files" | sed 's/,/, /g')

      local entry_block
      entry_block=$(printf '%s\n' \
        "### Circular dependency: ${display_files}" \
        "- **Category**: circular dependency" \
        "- **Evidence**: ariadne-refresh ${today}" \
        "- **File(s)**: ${display_files}" \
        "- **Confidence**: high" \
        "- **Observation count**: 1" \
        "- **Failed observations**: 0" \
        "- **Consecutive passes**: 0" \
        "- **Lifecycle**: NEW" \
        "")

      if [[ -f "$qm_full" ]] && grep -q "^## Problematic" "$qm_full" 2>/dev/null; then
        local prob_line
        prob_line=$(grep -n "^## Problematic" "$qm_full" | head -1 | cut -d: -f1)
        if [[ -n "$prob_line" ]]; then
          local head_part tail_part
          head_part=$(head -n "$prob_line" "$qm_full")
          tail_part=$(tail -n +"$((prob_line + 1))" "$qm_full")
          printf '%s\n\n%s\n%s\n' "$head_part" "$entry_block" "$tail_part" > "$qm_full"
        fi
      elif [[ -f "$qm_full" ]]; then
        printf '\n%s\n' "$entry_block" >> "$qm_full"
      fi
    done <<< "$new_cycle_keys"
  fi

  # Resolved cycles -> pass observation
  if [[ -n "$resolved_cycle_keys" ]]; then
    while IFS= read -r member_files; do
      [[ -z "$member_files" ]] && continue
      local display_files
      display_files=$(echo "$member_files" | sed 's/,/, /g')
      local entry_name="Circular dependency: ${display_files}"
      moira_knowledge_quality_map_pass_observation "${knowledge_dir}/quality-map" "$entry_name" "ariadne-refresh" 2>/dev/null || true
    done <<< "$resolved_cycle_keys"
  fi

  # ── Overwrite project-model structural sections ──────────────────────

  local pm_full="${knowledge_dir}/project-model/full.md"

  if [[ -f "$pm_full" ]]; then
    # Re-query centrality for Structural Bottlenecks
    local centrality_json
    centrality_json=$(ariadne query centrality --format json 2>/dev/null) || true
    local centrality_valid="false"
    if [[ -n "$centrality_json" ]] && echo "$centrality_json" | jq type 2>/dev/null | grep -q '"object"'; then
      centrality_valid="true"
    fi

    # Build new Structural Bottlenecks content
    local bottleneck_content
    bottleneck_content=$(mktemp)
    {
      echo "## Structural Bottlenecks"
      echo ""
      if [[ "$centrality_valid" == "true" ]]; then
        echo "| File | Centrality Score |"
        echo "|------|-----------------|"
        echo "$centrality_json" | jq -r 'to_entries | sort_by(-.value) | .[0:15] | .[] | "| \(.key) | \(.value) |"' 2>/dev/null || true
      else
        echo "(no centrality data available)"
      fi
      echo ""
    } > "$bottleneck_content"

    # Section overwrite: find boundaries and replace
    local start_line end_line
    start_line=$(grep -n "^## Structural Bottlenecks" "$pm_full" 2>/dev/null | cut -d: -f1 | head -1)

    if [[ -n "$start_line" ]]; then
      # Find next ## section after start_line
      end_line=$(tail -n +"$((start_line + 1))" "$pm_full" | grep -n "^## " | head -1 | cut -d: -f1)

      local pm_tmp
      pm_tmp=$(mktemp)
      if [[ -n "$end_line" ]]; then
        # end_line is relative to start_line+1, convert to absolute
        local abs_end=$((start_line + end_line))
        head -n "$((start_line - 1))" "$pm_full" > "$pm_tmp"
        cat "$bottleneck_content" >> "$pm_tmp"
        tail -n +"$abs_end" "$pm_full" >> "$pm_tmp"
      else
        # Section goes to EOF — replace everything from start_line to end
        head -n "$((start_line - 1))" "$pm_full" > "$pm_tmp"
        cat "$bottleneck_content" >> "$pm_tmp"
      fi
      cp "$pm_tmp" "$pm_full"
      rm -f "$pm_tmp"
    else
      # Section doesn't exist — append at end
      echo "" >> "$pm_full"
      cat "$bottleneck_content" >> "$pm_full"
    fi
    rm -f "$bottleneck_content"
  fi

  # ── Save new snapshot ────────────────────────────────────────────────

  mkdir -p "$state_dir"
  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  jq -n --arg ts "$timestamp" --argjson smells "$current_smells" --argjson cycles "$current_cycles" \
    '{"timestamp": $ts, "smells": $smells, "cycles": $cycles}' > "$snapshot_file" 2>/dev/null || {
    echo "{\"timestamp\":\"${timestamp}\",\"smells\":[],\"cycles\":[]}" > "$snapshot_file"
  }

  # ── L0/L1 regeneration ──────────────────────────────────────────────

  local qm_regen="${knowledge_dir}/quality-map/full.md"
  if [[ -f "$qm_regen" ]]; then
    local qm_summary_tmp
    qm_summary_tmp=$(mktemp)
    {
      echo "# Quality Map Summary"
      echo ""
      echo "## Problematic"
      grep '^### ' "$qm_regen" 2>/dev/null | sed 's/^### /- /' | head -30
      echo ""
    } > "$qm_summary_tmp"
    moira_knowledge_write "$knowledge_dir" "quality-map" "L1" "$qm_summary_tmp" "ariadne-refresh" 2>/dev/null || true
    rm -f "$qm_summary_tmp"

    local qm_index_tmp
    qm_index_tmp=$(mktemp)
    {
      echo "# Quality Map Index"
      echo ""
      grep '^## ' "$qm_regen" 2>/dev/null || true
    } > "$qm_index_tmp"
    moira_knowledge_write "$knowledge_dir" "quality-map" "L0" "$qm_index_tmp" "ariadne-refresh" 2>/dev/null || true
    rm -f "$qm_index_tmp"
  fi

  if [[ -f "$pm_full" ]]; then
    local pm_summary_tmp
    pm_summary_tmp=$(mktemp)
    {
      echo "# Project Model Summary"
      echo ""
      grep -E '^## |^- (Nodes|Edges|Clusters|Cycles|Smells|Monolith|Temporal)' "$pm_full" 2>/dev/null || true
    } > "$pm_summary_tmp"
    moira_knowledge_write "$knowledge_dir" "project-model" "L1" "$pm_summary_tmp" "ariadne-refresh" 2>/dev/null || true
    rm -f "$pm_summary_tmp"

    local pm_index_tmp
    pm_index_tmp=$(mktemp)
    {
      echo "# Project Model Index"
      echo ""
      grep '^## ' "$pm_full" 2>/dev/null || true
    } > "$pm_index_tmp"
    moira_knowledge_write "$knowledge_dir" "project-model" "L0" "$pm_index_tmp" "ariadne-refresh" 2>/dev/null || true
    rm -f "$pm_index_tmp"
  fi

  return 0
}

# ── moira_deepscan_prepare_context <project_root> ────────────────────────
# Generate Ariadne pre-context file for deep scanner agents.
# Queries Ariadne for clusters, cycles, boundaries, layers, centrality, and smells.
# Writes structured markdown to .moira/state/init/ariadne-context.md.
#
# Preconditions: ariadne + jq in PATH. If absent, writes placeholder.
# Each ariadne query wrapped in `|| true`.
# Reference: Phase 15, architecture.md section 3.5
moira_deepscan_prepare_context() {
  local project_root="${1:-}"

  if [[ -z "$project_root" ]]; then
    echo "Error: moira_deepscan_prepare_context requires <project_root>" >&2
    return 1
  fi

  local output_dir="${project_root}/.moira/state/init"
  local output_file="${output_dir}/ariadne-context.md"
  mkdir -p "$output_dir"

  # Precondition: ariadne + jq required
  if ! command -v ariadne >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    printf '%s\n%s\n' "# Ariadne Pre-Context" "(not available -- proceed with full manual scanning)" > "$output_file"
    return 0
  fi

  local timestamp
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local graph_dir="${project_root}/${_MOIRA_GRAPH_DEFAULT_GRAPH_DIR}"

  {
    echo "# Ariadne Pre-Context"
    echo "Generated: ${timestamp}"
    echo ""

    # ── Clusters (from file) ──────────────────────────────────────────
    echo "## Clusters"
    echo ""
    local clusters_file="${graph_dir}/clusters.json"
    if [[ -f "$clusters_file" ]]; then
      jq -r '
        .clusters // {} | to_entries | .[] |
        "- **\(.key)**: \(.value.files // [] | length) files, \(.value.internal_edges // 0) internal edges"
      ' "$clusters_file" 2>/dev/null || echo "(failed to parse clusters)"
    else
      echo "(clusters.json not found)"
    fi
    echo ""

    # ── Cycles ────────────────────────────────────────────────────────
    echo "## Cycles"
    echo ""
    local cycles_output
    cycles_output=$(ariadne query cycles --format json 2>/dev/null) || true
    if [[ -n "$cycles_output" ]] && echo "$cycles_output" | jq type 2>/dev/null | grep -q '"array"'; then
      local cycle_count
      cycle_count=$(echo "$cycles_output" | jq 'length' 2>/dev/null) || cycle_count=0
      if [[ "$cycle_count" -gt 0 ]]; then
        echo "$cycles_output" | jq -r '.[] | "- " + join(" → ")' 2>/dev/null || echo "(failed to parse cycles)"
      else
        echo "None detected"
      fi
    else
      echo "None detected"
    fi
    echo ""

    # ── Boundaries ────────────────────────────────────────────────────
    echo "## Boundaries"
    echo ""
    local boundaries_output
    boundaries_output=$(ariadne query boundaries --format json 2>/dev/null) || true
    if [[ -n "$boundaries_output" ]] && echo "$boundaries_output" | jq type 2>/dev/null | grep -qE '"object"|"array"'; then
      echo "$boundaries_output" | jq -r '
        if type == "array" then
          .[] | if type == "object" then to_entries[] | "- \(.key): \(.value)" else tostring end
        elif type == "object" then
          to_entries[] | "- \(.key): \(.value | tostring)"
        else
          tostring
        end
      ' 2>/dev/null || echo "(not available)"
    else
      echo "(not available)"
    fi
    echo ""

    # ── Layers ────────────────────────────────────────────────────────
    echo "## Layers"
    echo ""
    local layers_output
    layers_output=$(ariadne query layers --format json 2>/dev/null) || true
    if [[ -n "$layers_output" ]] && echo "$layers_output" | jq type 2>/dev/null | grep -q '"object"'; then
      echo "$layers_output" | jq -r 'to_entries | .[] | "- **\(.key)**: \(.value | join(", ") | if length > 150 then .[0:147] + "..." else . end)"' 2>/dev/null || echo "(failed to parse layers)"
    else
      echo "(no layer data available)"
    fi
    echo ""

    # ── High-Centrality Files (Top 20) ────────────────────────────────
    echo "## High-Centrality Files (Top 20)"
    echo ""
    local centrality_output
    centrality_output=$(ariadne query centrality --format json 2>/dev/null) || true
    if [[ -n "$centrality_output" ]] && echo "$centrality_output" | jq type 2>/dev/null | grep -q '"object"'; then
      echo "| File | Score |"
      echo "|------|-------|"
      echo "$centrality_output" | jq -r 'to_entries | sort_by(-.value) | .[:20] | .[] | "| \(.key) | \(.value) |"' 2>/dev/null || echo "(failed to parse centrality)"
    else
      echo "(no centrality data available)"
    fi
    echo ""

    # ── Architectural Smells ──────────────────────────────────────────
    echo "## Architectural Smells"
    echo ""
    local smells_output
    smells_output=$(ariadne query smells --format json 2>/dev/null) || true
    if [[ -n "$smells_output" ]] && echo "$smells_output" | jq type 2>/dev/null | grep -q '"array"'; then
      local smell_count
      smell_count=$(echo "$smells_output" | jq 'length' 2>/dev/null) || smell_count=0
      if [[ "$smell_count" -gt 0 ]]; then
        echo "$smells_output" | jq -r '.[] | "- **\(.smell_type)** (\(.severity // "unknown")): \(.files | join(", "))"' 2>/dev/null || echo "(failed to parse smells)"
      else
        echo "None detected"
      fi
    else
      echo "None detected"
    fi
    echo ""
  } > "$output_file"

  return 0
}
