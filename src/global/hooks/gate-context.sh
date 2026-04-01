#!/usr/bin/env bash
# Gate Context — UserPromptSubmit hook for gate data collection
# D-201: Collects artifact sections + health metrics + pre-classifies user input
# when a gate is pending. Injects via additionalContext so orchestrator
# skips manual reads and deterministic classification.
#
# Fires: UserPromptSubmit (no matcher — always fires)
# Reads: .claude/moira/state/current.yaml (gate_pending), artifacts, state files
# Outputs: GATE_DATA: block + INPUT_CLASS: classification
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Parse prompt from JSON input ---
if command -v jq &>/dev/null; then
  prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null) || prompt=""
else
  prompt=$(echo "$input" | grep -o '"prompt"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"prompt"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || prompt=""
fi

[[ -z "$prompt" ]] && exit 0

# Skip if this is a /moira:task invocation (task-submit.sh handles those)
echo "$prompt" | grep -qiE '^\s*/moira[: ]' && exit 0

# --- Find Moira state directory ---
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/moira/state/current.yaml" ]]; then
      echo "$dir/.claude/moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

state_dir=$(find_state_dir) || exit 0
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

current_file="$state_dir/current.yaml"

# --- Check gate_pending ---
_yaml_get() {
  grep "^${2}:" "$1" 2>/dev/null | sed "s/^${2}:[[:space:]]*//" | tr -d '"' | tr -d "'" 2>/dev/null
}

gate_pending=$(_yaml_get "$current_file" "gate_pending") || gate_pending=""
[[ -z "$gate_pending" || "$gate_pending" == "null" ]] && exit 0

# --- Source markdown-utils for section extraction ---
moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
if [[ -f "$moira_home/lib/markdown-utils.sh" ]]; then
  # shellcheck source=../lib/markdown-utils.sh
  source "$moira_home/lib/markdown-utils.sh" 2>/dev/null || true
fi

# --- Collect gate data ---
task_id=$(_yaml_get "$current_file" "task_id") || task_id=""
[[ -z "$task_id" || "$task_id" == "null" ]] && exit 0

task_dir="$state_dir/tasks/$task_id"
pipeline=$(_yaml_get "$current_file" "pipeline") || pipeline=""

# Artifact sections based on gate type
gate_sections=""
case "$gate_pending" in
  classification_gate|classification)
    artifact="$task_dir/classification.md"
    if [[ -f "$artifact" ]] && command -v moira_md_extract_section &>/dev/null; then
      ps=$(moira_md_extract_section "$artifact" "Problem Statement" 2>/dev/null) || ps=""
      scope=$(moira_md_extract_section "$artifact" "Scope" 2>/dev/null) || scope=""
      ac=$(moira_md_extract_section "$artifact" "Acceptance Criteria" 2>/dev/null) || ac=""

      gate_sections="artifact=$artifact
problem_statement=${ps:0:500}
scope=${scope:0:500}
acceptance_criteria=${ac:0:500}"
    fi ;;

  architecture_gate|architecture)
    artifact="$task_dir/architecture.md"
    if [[ -f "$artifact" ]] && command -v moira_md_extract_section &>/dev/null; then
      rec=$(moira_md_extract_section "$artifact" "Recommendation" 2>/dev/null) || rec=""
      alt=$(moira_md_extract_section "$artifact" "Alternatives" 2>/dev/null) || alt=""
      asm=$(moira_md_extract_section "$artifact" "Assumptions" 2>/dev/null) || asm=""

      gate_sections="artifact=$artifact
recommendation=${rec:0:500}
alternatives=${alt:0:500}
assumptions=${asm:0:500}"
    fi ;;

  plan_gate|plan)
    artifact="$task_dir/plan.md"
    if [[ -f "$artifact" ]] && command -v moira_md_extract_section &>/dev/null; then
      sc=$(moira_md_extract_section "$artifact" "Scope Check" 2>/dev/null) || sc=""
      at=$(moira_md_extract_section "$artifact" "Acceptance Test" 2>/dev/null) || at=""
      risks=$(moira_md_extract_section "$artifact" "Risks" 2>/dev/null) || risks=""

      gate_sections="artifact=$artifact
scope_check=${sc:0:500}
acceptance_test=${at:0:500}
risks=${risks:0:500}"
    fi ;;

  final_gate|final|completion)
    # Final gate uses multiple artifacts — collect what exists
    gate_sections="artifact=multiple"
    ;;
esac

# --- Collect health metrics ---
# Context budget
orch_pct=$(_yaml_get "$current_file" "  orchestrator_percent") || orch_pct="0"
# Trim indent from nested YAML value
orch_pct=$(echo "$orch_pct" | sed 's/^[[:space:]]*//' 2>/dev/null) || orch_pct="0"
warning_level=$(_yaml_get "$current_file" "  warning_level") || warning_level="normal"
warning_level=$(echo "$warning_level" | sed 's/^[[:space:]]*//' 2>/dev/null) || warning_level="normal"

# Violations count
violations=0
if [[ -f "$state_dir/violations.log" ]]; then
  violations=$(wc -l < "$state_dir/violations.log" 2>/dev/null | tr -d ' ') || violations=0
fi

# Agents dispatched (count history entries)
agents_dispatched=0
if [[ -f "$current_file" ]]; then
  agents_dispatched=$(grep -c '  - step:' "$current_file" 2>/dev/null) || agents_dispatched=0
fi

# Gates passed
gates_passed=0
status_file="$task_dir/status.yaml"
if [[ -f "$status_file" ]]; then
  gates_passed=$(grep -c '  - gate:' "$status_file" 2>/dev/null) || gates_passed=0
fi

# Retries
retries=0
if [[ -f "$status_file" ]]; then
  retries=$(_yaml_get "$status_file" "  total") || retries=0
  retries=$(echo "$retries" | sed 's/^[[:space:]]*//' 2>/dev/null) || retries=0
fi

# Step progress
current_step=$(_yaml_get "$current_file" "step") || current_step=""
# Count total steps from pipeline definition (best effort)
total_steps="?"
if [[ -n "$pipeline" && "$pipeline" != "null" && -f "$moira_home/core/pipelines/${pipeline}.yaml" ]]; then
  total_steps=$(grep -c '  - id:' "$moira_home/core/pipelines/${pipeline}.yaml" 2>/dev/null) || total_steps="?"
fi

health="context_percent=${orch_pct}
warning_level=${warning_level}
violations=${violations}
agents_dispatched=${agents_dispatched}
gates_passed=${gates_passed}
retries=${retries}
current_step=${current_step}
total_steps=${total_steps}"

# --- Pre-classify user input (D-201) ---
# Trim whitespace
trimmed=$(echo "$prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null) || trimmed="$prompt"
# Lowercase for matching
lower=$(echo "$trimmed" | tr '[:upper:]' '[:lower:]' 2>/dev/null) || lower="$trimmed"

input_class="needs_llm"

# Read gate_options count from current.yaml for numeric validation
option_count=0
# Count option lines (gate_options is a YAML array)
if [[ -f "$current_file" ]]; then
  option_count=$(grep -c '^  - ' <(sed -n '/^gate_options:/,/^[^ ]/p' "$current_file" 2>/dev/null) 2>/dev/null) || option_count=0
fi
# Fallback: use common gate option counts
[[ "$option_count" -eq 0 ]] && option_count=5

# Classification rules (ordered, first match wins):

# 1. "clear feedback" exact match
if [[ "$lower" == "clear feedback" ]]; then
  input_class="clear_feedback"

# 2. Numeric input — check if within option range
elif echo "$trimmed" | grep -qE '^[0-9]+$' 2>/dev/null; then
  num="$trimmed"
  if [[ "$num" -ge 1 && "$num" -le "$option_count" ]] 2>/dev/null; then
    input_class="menu_selection:${num}"
  else
    input_class="needs_llm"
  fi

# 3. Keyword exact match (common gate options)
elif echo ",$lower," | grep -qE ',(proceed|abort|details|modify|checkpoint|rearchitect|done|tweak|redo|diff|test),' 2>/dev/null; then
  input_class="menu_selection:${lower}"

# 4. Question detection
elif echo "$lower" | grep -qE '\?$' 2>/dev/null; then
  input_class="question"
elif echo "$lower" | grep -qE '^(what|how|why|when|where|which|can|will|does|is|are|should|would|could) ' 2>/dev/null; then
  input_class="question"
fi

# --- Assemble and inject ---
gate_data="gate=${gate_pending}
pipeline=${pipeline}
task_id=${task_id}
${gate_sections:+$gate_sections
}${health}"

# Escape for JSON
inject="GATE_DATA:
${gate_data}
INPUT_CLASS: ${input_class}"

escaped=$(printf '%s' "$inject" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//' 2>/dev/null) || exit 0

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"$escaped\"}}"

exit 0
