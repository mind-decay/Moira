#!/usr/bin/env bash
# markdown-utils.sh — Markdown extraction utilities for Moira
# D-201: Provides reliable section extraction from markdown artifacts.
# POSIX-compatible (no bashisms) — works in bash and zsh.

set -euo pipefail

# ── moira_md_extract_section <file> <heading> ─────────────────────────
# Extract text between a ## heading and the next ## heading (or EOF).
# Includes nested ### subsections within the section.
#
# Arguments:
#   file    — path to markdown file
#   heading — the heading text WITHOUT the ## prefix (e.g., "Scope", "Acceptance Criteria")
#
# Returns:
#   Section content on stdout (may be empty if section exists but has no content)
#   Exit 0 if section found, exit 1 if section not found
#
# Edge cases handled:
#   - Nested ### subsections included in output
#   - Empty sections (heading exists, no content before next ##) → empty stdout, exit 0
#   - Section at end of file → content until EOF
#   - Missing section → exit 1
#   - Heading with trailing whitespace → matched
moira_md_extract_section() {
  local file="$1"
  local heading="$2"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  # Use awk for reliable extraction
  # Match: line starts with "## " followed by the heading text (trim trailing whitespace)
  # Stop: next line starting with "## " (but not "### " or deeper)
  local result
  result=$(awk -v heading="$heading" '
    BEGIN { found=0; printing=0 }
    /^## / {
      if (printing) { printing=0; exit }
      # Strip "## " prefix and trailing whitespace from line
      line = $0
      sub(/^## */, "", line)
      sub(/[[:space:]]*$/, "", line)
      if (line == heading) {
        found=1
        printing=1
        next
      }
    }
    printing { print }
    END { if (!found) exit 1 }
  ' "$file" 2>/dev/null)

  local rc=$?
  if [[ $rc -ne 0 ]]; then
    return 1
  fi

  # Trim leading/trailing blank lines from result
  printf '%s' "$result" | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' 2>/dev/null
  echo  # ensure trailing newline
  return 0
}

# ── moira_md_extract_sections <file> <heading1> [heading2] ... ────────
# Extract multiple sections, each prefixed with ### heading.
# Skips sections that don't exist (no error).
# Returns combined output.
moira_md_extract_sections() {
  local file="$1"
  shift

  local output=""
  for heading in "$@"; do
    local section_content
    section_content=$(moira_md_extract_section "$file" "$heading" 2>/dev/null) || continue
    if [[ -n "$section_content" ]]; then
      output="${output}### ${heading}
${section_content}
"
    fi
  done

  if [[ -n "$output" ]]; then
    printf '%s' "$output"
    return 0
  fi
  return 1
}
