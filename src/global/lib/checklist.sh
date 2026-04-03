#!/usr/bin/env bash
# Pre-pipeline checklist generator (D-211 Layer 1)
# Called via !`command` preprocessing in task.md Step 3.5
#
# Mechanically checks pre-pipeline prerequisites and writes state.
# Outputs markdown block injected into skill prompt before LLM sees it.
#
# MUST be self-contained — no library sourcing (preprocessing environment is minimal).
# MUST exit 0 always — preprocessing failure = skill load failure.
# MUST produce output — empty output means invisible step.

set -o pipefail 2>/dev/null || true

# --- Inline YAML helpers (same pattern as hooks — no library dependency) ---
_yaml_get() {
  grep "^${2}:" "$1" 2>/dev/null | sed "s/^${2}:[[:space:]]*//" | tr -d '"' | tr -d "'" 2>/dev/null
}

_yaml_set() {
  local file="$1" key="$2" value="$3"
  local escaped_value
  escaped_value=$(printf '%s' "$value" | sed 's|[&/\\|]|\\&|g' 2>/dev/null) || escaped_value="$value"
  if grep -q "^${key}:" "$file" 2>/dev/null; then
    sed -i.bak "s|^${key}:.*|${key}: ${escaped_value}|" "$file" 2>/dev/null
    rm -f "${file}.bak" 2>/dev/null
  else
    printf '%s: %s\n' "$key" "$value" >> "$file" 2>/dev/null
  fi
}

# --- Find project root with .moira/ ---
find_moira_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.moira" ]]; then
      echo "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

main() {
  local project_root config_file current_file state_dir
  project_root=$(find_moira_root) || {
    echo "No Moira project found. Pre-pipeline checks skipped."
    exit 0
  }

  config_file="$project_root/.moira/config.yaml"
  state_dir="$project_root/.moira/state"
  current_file="$state_dir/current.yaml"

  if [[ ! -f "$config_file" ]]; then
    echo "No Moira config found. Pre-pipeline checks skipped."
    exit 0
  fi

  if [[ ! -f "$current_file" ]]; then
    echo "No active task state. Pre-pipeline checks skipped."
    exit 0
  fi

  # ── Read current state ────────────────────────────────────────────
  local deep_scan_pending graph_available graph_enabled audit_pending
  deep_scan_pending=$(_yaml_get "$config_file" "deep_scan_pending") || true
  # Also check nested bootstrap.deep_scan_pending (config uses flat or nested)
  if [[ -z "$deep_scan_pending" || "$deep_scan_pending" == "null" ]]; then
    deep_scan_pending=$(grep 'deep_scan_pending' "$config_file" 2>/dev/null | tail -1 | sed 's/.*deep_scan_pending:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  fi
  graph_available=$(_yaml_get "$current_file" "graph_available") || true
  graph_enabled=$(_yaml_get "$config_file" "graph_enabled") || true
  # Check nested graph.enabled
  if [[ -z "$graph_enabled" || "$graph_enabled" == "null" ]]; then
    graph_enabled=$(grep 'enabled' "$config_file" 2>/dev/null | head -1 | sed 's/.*enabled:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
  fi
  audit_pending=""
  [[ -f "$state_dir/audit-pending.yaml" ]] && audit_pending="true"

  local has_pending=false

  # ── Mechanical check: Graph Availability ──────────────────────────
  # Do this in shell — no agent involvement needed
  if [[ -z "$graph_available" || "$graph_available" == "null" ]]; then
    if [[ "$graph_enabled" == "false" ]]; then
      _yaml_set "$current_file" "graph_available" "false"
      _yaml_set "$current_file" "temporal_available" "false"
      graph_available="false"
    elif [[ -f "$project_root/.ariadne/graph/graph.json" ]]; then
      _yaml_set "$current_file" "graph_available" "true"
      graph_available="true"
    else
      _yaml_set "$current_file" "graph_available" "false"
      _yaml_set "$current_file" "temporal_available" "false"
      graph_available="false"
    fi
  fi

  # ── Output header ─────────────────────────────────────────────────
  echo "## Step 3.5: Pre-Pipeline Checks"
  echo ""

  # ── Deep Scan Pending ─────────────────────────────────────────────
  if [[ "$deep_scan_pending" == "true" ]]; then
    has_pending=true
    cat <<'DEEP_SCAN'
### Deep Scan (PENDING)

Deep scan is pending from bootstrap. Dispatch 4 background agents:

1. Hermes (explorer) — deep architecture scan (background, model: sonnet)
   Prompt from: `~/.claude/moira/templates/scanners/deep/deep-architecture-scan.md`
2. Hermes (explorer) — deep dependency scan (background, model: sonnet)
   Prompt from: `~/.claude/moira/templates/scanners/deep/deep-dependency-scan.md`
3. Hermes (explorer) — deep test coverage scan (background, model: sonnet)
   Prompt from: `~/.claude/moira/templates/scanners/deep/deep-test-coverage-scan.md`
4. Hermes (explorer) — deep security scan (background, model: sonnet)
   Prompt from: `~/.claude/moira/templates/scanners/deep/deep-security-scan.md`

All dispatches use: subagent_type: "general-purpose", run_in_background: true.
After dispatching all 4, continue immediately — do NOT wait.

DEEP_SCAN
  fi

  # ── Temporal Availability ─────────────────────────────────────────
  # Temporal requires MCP call (ariadne_overview) — cannot be done in shell.
  # Only output instruction if graph is available and temporal not yet checked.
  local temporal_available
  temporal_available=$(_yaml_get "$current_file" "temporal_available") || true
  if [[ "$graph_available" == "true" && ( -z "$temporal_available" || "$temporal_available" == "null" ) ]]; then
    has_pending=true
    cat <<'TEMPORAL'
### Temporal Availability Check (PENDING)

Graph is available. Check temporal data:
1. Call `ariadne_overview` MCP tool
2. If response contains `temporal` field: write `temporal_available: true` to `.moira/state/current.yaml`
3. If no temporal field or call fails: write `temporal_available: false`

TEMPORAL
  fi

  # ── Audit Pending ─────────────────────────────────────────────────
  if [[ "$audit_pending" == "true" ]]; then
    # Advisory only — does not block pipeline
    cat <<'AUDIT'
### Audit Pending (advisory)

A passive audit is pending from a previous session. Consider running `/moira:audit` after this task completes.

AUDIT
  fi

  # ── Graph Status Report ───────────────────────────────────────────
  echo "### Status"
  echo "- Graph: $graph_available"
  if [[ -n "$temporal_available" && "$temporal_available" != "null" ]]; then
    echo "- Temporal: $temporal_available"
  fi
  if [[ "$deep_scan_pending" == "true" ]]; then
    echo "- Deep scan: pending"
  fi
  echo ""

  # ── Verdict ───────────────────────────────────────────────────────
  if [[ "$has_pending" == "false" ]]; then
    echo "All pre-pipeline checks passed. Proceed to classification."
  else
    echo "Complete ALL pending checks above before proceeding to classification."
  fi
}

main "$@"
exit 0
