#!/usr/bin/env bash
# test-gate-context.sh — Tier 1 tests for gate input pre-classification (D-201)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "Testing: Gate Input Pre-classification (D-201)"

# We test the classification logic inline (extracted from gate-context.sh)
# since the full hook needs JSON stdin which is harder to test directly.

classify_input() {
  local prompt="$1"
  local option_count="${2:-5}"

  local trimmed lower input_class
  trimmed=$(echo "$prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null) || trimmed="$prompt"
  lower=$(echo "$trimmed" | tr '[:upper:]' '[:lower:]' 2>/dev/null) || lower="$trimmed"

  input_class="needs_llm"

  if [[ "$lower" == "clear feedback" ]]; then
    input_class="clear_feedback"
  elif echo "$trimmed" | grep -qE '^[0-9]+$' 2>/dev/null; then
    local num="$trimmed"
    if [[ "$num" -ge 1 && "$num" -le "$option_count" ]] 2>/dev/null; then
      input_class="menu_selection:${num}"
    fi
  elif echo ",$lower," | grep -qE ',(proceed|abort|details|modify|checkpoint|rearchitect|done|tweak|redo|diff|test),' 2>/dev/null; then
    input_class="menu_selection:${lower}"
  elif echo "$lower" | grep -qE '\?$' 2>/dev/null; then
    input_class="question"
  elif echo "$lower" | grep -qE '^(what|how|why|when|where|which|can|will|does|is|are|should|would|could) ' 2>/dev/null; then
    input_class="question"
  fi

  echo "$input_class"
}

# ── Numeric inputs ──
assert_equals "menu_selection:1" "$(classify_input "1")" "numeric 1 → menu_selection:1"
assert_equals "menu_selection:3" "$(classify_input "3")" "numeric 3 → menu_selection:3"
assert_equals "menu_selection:5" "$(classify_input "5")" "numeric 5 → menu_selection:5"
assert_equals "needs_llm" "$(classify_input "0")" "numeric 0 (out of range) → needs_llm"
assert_equals "needs_llm" "$(classify_input "6")" "numeric 6 (out of range for 5 options) → needs_llm"
assert_equals "menu_selection:2" "$(classify_input "  2  ")" "numeric with whitespace → menu_selection:2"

# ── Keyword exact matches ──
assert_equals "menu_selection:proceed" "$(classify_input "proceed")" "proceed → menu_selection"
assert_equals "menu_selection:abort" "$(classify_input "abort")" "abort → menu_selection"
assert_equals "menu_selection:details" "$(classify_input "details")" "details → menu_selection"
assert_equals "menu_selection:modify" "$(classify_input "modify")" "modify → menu_selection"
assert_equals "menu_selection:proceed" "$(classify_input "Proceed")" "Proceed (capitalized) → menu_selection"
assert_equals "menu_selection:abort" "$(classify_input "ABORT")" "ABORT (uppercase) → menu_selection"
assert_equals "menu_selection:checkpoint" "$(classify_input "checkpoint")" "checkpoint → menu_selection"
assert_equals "menu_selection:rearchitect" "$(classify_input "rearchitect")" "rearchitect → menu_selection"
assert_equals "menu_selection:done" "$(classify_input "done")" "done → menu_selection"
assert_equals "menu_selection:tweak" "$(classify_input "tweak")" "tweak → menu_selection"
assert_equals "menu_selection:redo" "$(classify_input "redo")" "redo → menu_selection"

# ── Clear feedback ──
assert_equals "clear_feedback" "$(classify_input "clear feedback")" "clear feedback → clear_feedback"
assert_equals "clear_feedback" "$(classify_input "Clear Feedback")" "Clear Feedback → clear_feedback"

# ── Questions ──
assert_equals "question" "$(classify_input "what does this do?")" "what...? → question"
assert_equals "question" "$(classify_input "how does the architecture work?")" "how...? → question"
assert_equals "question" "$(classify_input "why not use option 2?")" "why...? → question"
assert_equals "question" "$(classify_input "Is this correct?")" "Is...? → question"
assert_equals "question" "$(classify_input "can we change this?")" "can...? → question"

# ── Free text (needs LLM) ──
assert_equals "needs_llm" "$(classify_input "I think we should use approach B instead")" "free text → needs_llm"
assert_equals "needs_llm" "$(classify_input "the scope looks too wide")" "feedback text → needs_llm"
assert_equals "needs_llm" "$(classify_input "yes")" "yes → needs_llm"
assert_equals "needs_llm" "$(classify_input "no")" "no → needs_llm"

# ── Edge cases ──
assert_equals "needs_llm" "$(classify_input "")" "empty input → needs_llm"
assert_equals "menu_selection:3" "$(classify_input "3" 3)" "numeric at max option count → menu_selection"
assert_equals "needs_llm" "$(classify_input "4" 3)" "numeric above max → needs_llm"

test_summary
