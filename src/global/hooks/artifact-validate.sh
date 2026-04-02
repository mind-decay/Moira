#!/usr/bin/env bash
# Artifact Validate — SubagentStop hook
# Validates that agent artifacts contain required sections per role (D-184).
# BLOCK agent from stopping if artifact contract is violated.
#
# Fires: SubagentStop (matcher: empty — all agents)
# Reads: agent description (to determine role), ARTIFACTS line from output, artifact file
# Can output: decision=block to force agent to add missing sections
#
# This hook runs AFTER agent-output-validate.sh (which ensures STATUS line exists).
# By the time this hook fires, the agent has written its artifact file and produced
# a valid STATUS response. This hook validates the CONTENT of the artifact.
#
# MUST NOT fail — exits 0 silently on any error.

input=$(cat 2>/dev/null) || exit 0

# --- Prevent infinite loop ---
if command -v jq &>/dev/null; then
  stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false' 2>/dev/null) || stop_hook_active="false"
  last_msg=$(echo "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null) || last_msg=""
  agent_type=$(echo "$input" | jq -r '.agent_type // empty' 2>/dev/null) || agent_type=""
  agent_desc=$(echo "$input" | jq -r '.agent_description // empty' 2>/dev/null) || agent_desc=""
else
  stop_hook_active="false"
  echo "$input" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null && stop_hook_active="true"
  last_msg=$(echo "$input" | grep -o '"last_assistant_message"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"last_assistant_message"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || last_msg=""
  agent_type=$(echo "$input" | grep -o '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_type"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_type=""
  agent_desc=$(echo "$input" | grep -o '"agent_description"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"agent_description"[[:space:]]*:[[:space:]]*"//;s/"$//' 2>/dev/null) || agent_desc=""
fi

[[ "$stop_hook_active" == "true" ]] && exit 0

# --- Find Moira state directory ---
find_state_dir() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.moira/state/current.yaml" ]]; then
      echo "$dir/.moira/state"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

state_dir=$(find_state_dir) || exit 0
[[ ! -f "$state_dir/.guard-active" ]] && exit 0

# --- Skip non-pipeline agent types ---
case "$agent_type" in
  Explore|Plan|Bash|"") exit 0 ;;
  general-purpose|*) ;;
esac

# --- Determine role from agent description ---
# Description format: "Name (role) — task description"
role=""
case "$agent_desc" in
  *"(classifier)"*|*"Apollo"*|*"apollo"*)           role="apollo" ;;
  *"(explorer)"*|*"Hermes"*|*"hermes"*)             role="hermes" ;;
  *"(analyst)"*|*"Athena"*|*"athena"*)              role="athena" ;;
  *"(architect)"*|*"Metis"*|*"metis"*)              role="metis" ;;
  *"(planner)"*|*"Daedalus"*|*"daedalus"*)          role="daedalus" ;;
  *"(implementer)"*|*"Hephaestus"*|*"hephaestus"*)  role="hephaestus" ;;
  *"(reviewer)"*|*"Themis"*|*"themis"*)             role="themis" ;;
  *"(tester)"*|*"Aletheia"*|*"aletheia"*)           role="aletheia" ;;
  *"(scribe)"*|*"Calliope"*|*"calliope"*)           role="calliope" ;;
  *"(reflector)"*|*"Mnemosyne"*|*"mnemosyne"*)      role="mnemosyne" ;;
  *"(auditor)"*|*"Argus"*|*"argus"*)                role="argus" ;;
  *) exit 0 ;;  # Unknown role — skip validation
esac

[[ -z "$role" ]] && exit 0
[[ -z "$last_msg" ]] && exit 0

# --- Extract artifact path from ARTIFACTS line ---
artifact_line=$(echo "$last_msg" | grep -i 'ARTIFACTS:' | head -1) || exit 0
[[ -z "$artifact_line" ]] && exit 0

# Extract first file path from ARTIFACTS line
# Format: ARTIFACTS: [path1, path2] or ARTIFACTS: path1
artifact_path=$(echo "$artifact_line" | sed 's/.*ARTIFACTS:[[:space:]]*//' | sed 's/^\[//;s/\]$//' | sed 's/,.*//' | tr -d '[:space:]' | tr -d '"' | tr -d "'" 2>/dev/null) || exit 0
[[ -z "$artifact_path" ]] && exit 0

# --- Resolve artifact path ---
# Read task_id from current.yaml to resolve relative paths
task_id=""
if [[ -f "$state_dir/current.yaml" ]]; then
  task_id=$(grep '^task_id:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^task_id:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
fi

# Try to find the artifact file
project_dir=$(dirname "$(dirname "$state_dir")")  # .moira/state -> project root
resolved_path=""

# Try direct path first
if [[ -f "$artifact_path" ]]; then
  resolved_path="$artifact_path"
# Try relative to state dir
elif [[ -f "$state_dir/$artifact_path" ]]; then
  resolved_path="$state_dir/$artifact_path"
# Try relative to task dir
elif [[ -n "$task_id" && -f "$state_dir/tasks/$task_id/$artifact_path" ]]; then
  resolved_path="$state_dir/tasks/$task_id/$artifact_path"
# Try relative to project root
elif [[ -f "$project_dir/$artifact_path" ]]; then
  resolved_path="$project_dir/$artifact_path"
# Try stripping common prefixes
elif [[ -f "$project_dir/.moira/$artifact_path" ]]; then
  resolved_path="$project_dir/.moira/$artifact_path"
fi

# If artifact file not found, skip validation (agent may not have written it yet)
[[ -z "$resolved_path" || ! -f "$resolved_path" ]] && exit 0

# --- Define required sections per role ---
missing=()

check_section() {
  local file="$1"
  local section="$2"
  if ! grep -q "^## ${section}$\|^## ${section} " "$file" 2>/dev/null; then
    # Also try with trailing whitespace or different formatting
    if ! grep -q "^##[[:space:]]*${section}" "$file" 2>/dev/null; then
      missing+=("## $section")
    fi
  fi
}

check_subsection() {
  local file="$1"
  local section="$2"
  if ! grep -q "^### ${section}$\|^### ${section} " "$file" 2>/dev/null; then
    if ! grep -q "^###[[:space:]]*${section}" "$file" 2>/dev/null; then
      missing+=("### $section")
    fi
  fi
}

case "$role" in
  apollo)
    check_section "$resolved_path" "Problem Statement"
    check_section "$resolved_path" "Scope"
    check_subsection "$resolved_path" "In Scope"
    check_subsection "$resolved_path" "Out of Scope"
    check_section "$resolved_path" "Acceptance Criteria"
    ;;
  hermes)
    # Check which artifact type based on filename
    case "$artifact_path" in
      *context.md)
        # Quick pipeline variant
        check_section "$resolved_path" "Context Summary"
        check_section "$resolved_path" "Key Files"
        ;;
      *)
        # Standard/Full exploration
        check_section "$resolved_path" "Relevant Files"
        check_section "$resolved_path" "Key Findings"
        # Gap Analysis required in Standard/Full pipelines
        # Read pipeline type from current.yaml
        pipeline_type=""
        if [[ -f "$state_dir/current.yaml" ]]; then
          pipeline_type=$(grep '^pipeline:' "$state_dir/current.yaml" 2>/dev/null | sed 's/^pipeline:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
        fi
        case "$pipeline_type" in
          standard|full|decomposition|analytical)
            check_section "$resolved_path" "Gap Analysis"
            ;;
        esac
        ;;
    esac
    ;;
  athena)
    check_section "$resolved_path" "Requirements"
    check_section "$resolved_path" "Constraints"
    check_section "$resolved_path" "Dependencies"
    ;;
  metis)
    check_section "$resolved_path" "Alternatives"
    check_section "$resolved_path" "Recommendation"
    check_section "$resolved_path" "Assumptions"
    check_subsection "$resolved_path" "Unverified"

    # Structural check: ## Alternatives must contain >= 2 ### Alternative subsections
    alt_count=$(grep -c '^###[[:space:]]*Alternative' "$resolved_path" 2>/dev/null) || alt_count=0
    if [[ "$alt_count" -lt 2 ]]; then
      missing+=("## Alternatives must contain at least 2 ### Alternative subsections (found $alt_count)")
    fi
    ;;
  daedalus)
    check_section "$resolved_path" "Scope Check"
    check_section "$resolved_path" "Acceptance Test"
    check_section "$resolved_path" "Risks"

    # Conditional check: ## Unverified Dependencies required when architecture has UNVERIFIED items
    if [[ -n "$task_id" ]]; then
      arch_path="$state_dir/tasks/$task_id/architecture.md"
      if [[ -f "$arch_path" ]]; then
        unverified_count=$(grep -ci 'UNVERIFIED' "$arch_path" 2>/dev/null) || unverified_count=0
        if [[ "$unverified_count" -gt 0 ]]; then
          check_section "$resolved_path" "Unverified Dependencies"
          # Amend last missing entry with context if it was added
          last_idx=$(( ${#missing[@]} - 1 ))
          if [[ "${missing[$last_idx]:-}" == "## Unverified Dependencies" ]]; then
            missing[$last_idx]="## Unverified Dependencies (required: architecture has $unverified_count UNVERIFIED claims)"
          fi
        fi
      fi
    fi
    ;;
  hephaestus)
    check_section "$resolved_path" "Changes Made"
    check_section "$resolved_path" "Verification Results"
    ;;
  themis)
    # Check which artifact type based on filename
    case "$artifact_path" in
      *plan-check.md)
        check_section "$resolved_path" "Plan Check Findings"
        check_section "$resolved_path" "Verdict"
        ;;
      *)
        check_section "$resolved_path" "Review Findings"
        check_section "$resolved_path" "Verdict"
        ;;
    esac
    ;;
  aletheia)
    check_section "$resolved_path" "Test Cases"
    check_section "$resolved_path" "Results Summary"
    ;;
  calliope)
    check_section "$resolved_path" "Sources"
    check_section "$resolved_path" "Content"
    ;;
  mnemosyne)
    check_section "$resolved_path" "Analysis"
    check_section "$resolved_path" "Recommendations"
    ;;
  argus)
    check_section "$resolved_path" "Findings"
    check_section "$resolved_path" "Risk Assessment"
    ;;
esac

# --- Findings YAML validation for gate agents (D-197) ---
# Gate agents must produce a findings YAML alongside their artifact
findings_gate=""
case "$role" in
  athena)    findings_gate="Q1" ;;
  metis)     findings_gate="Q2" ;;
  daedalus)  findings_gate="Q3" ;;
  themis)    findings_gate="Q4" ;;
  aletheia)  findings_gate="Q5" ;;
esac

if [[ -n "$findings_gate" && -n "$task_id" ]]; then
  findings_dir="$state_dir/tasks/$task_id/findings"
  # Find matching findings file (agent-gate pattern)
  # Findings filename uses lowercase role name (matches agent naming convention)
  findings_file="$findings_dir/${role}-${findings_gate}.yaml"

  if [[ -f "$findings_file" ]]; then
    # Validate required fields exist
    if ! grep -q '^_meta:' "$findings_file" 2>/dev/null; then
      missing+=("findings/${role}-${findings_gate}.yaml: missing _meta section")
    fi
    if ! grep -q 'task_id:' "$findings_file" 2>/dev/null; then
      missing+=("findings/${role}-${findings_gate}.yaml: missing _meta.task_id")
    fi
    if ! grep -q 'gate:' "$findings_file" 2>/dev/null; then
      missing+=("findings/${role}-${findings_gate}.yaml: missing _meta.gate")
    fi
    if ! grep -q 'verdict:' "$findings_file" 2>/dev/null; then
      missing+=("findings/${role}-${findings_gate}.yaml: missing summary.verdict")
    else
      # Validate verdict enum
      verdict=$(grep 'verdict:' "$findings_file" 2>/dev/null | tail -1 | sed 's/.*verdict:[[:space:]]*//' | tr -d '"' | tr -d "'" 2>/dev/null) || true
      case "$verdict" in
        pass|fail_critical|fail_warning) ;;
        *) missing+=("findings/${role}-${findings_gate}.yaml: invalid verdict '$verdict' (must be pass|fail_critical|fail_warning)") ;;
      esac

      # Cross-validate verdict derivation
      critical_count=$(grep 'critical_count:' "$findings_file" 2>/dev/null | tail -1 | sed 's/.*critical_count:[[:space:]]*//' | tr -d '"' 2>/dev/null) || critical_count="0"
      [[ "$critical_count" =~ ^[0-9]+$ ]] || critical_count="0"
      if [[ "$critical_count" -gt 0 && "$verdict" != "fail_critical" ]]; then
        missing+=("findings/${role}-${findings_gate}.yaml: verdict=$verdict but critical_count=$critical_count (should be fail_critical)")
      fi
    fi
  fi
  # Note: findings file not existing is OK — agent may not have written it yet,
  # or this role doesn't produce findings in all pipelines (e.g., Athena on-demand)
fi

# --- Report results ---
if [[ ${#missing[@]} -eq 0 ]]; then
  exit 0  # All sections present
fi

# Build block message with real newlines (no echo -e dependency)
missing_list=""
for m in "${missing[@]}"; do
  missing_list="${missing_list}
- ${m}"
done

reason="ARTIFACT CONTRACT VIOLATION (D-184): Your artifact is missing required sections. Add these sections to your artifact file (${artifact_path}) before completing:${missing_list}

These sections are required by your role's output contract. Each section must have real content -- the validation checks for section headers, but your output must contain substantive analysis in each section."

# Escape for JSON: backslashes, quotes, tabs, then collapse newlines to \n
reason_escaped=$(printf '%s' "$reason" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//' 2>/dev/null) || exit 0

echo "{\"decision\":\"block\",\"reason\":\"$reason_escaped\"}"
exit 0
