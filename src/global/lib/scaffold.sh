#!/usr/bin/env bash
# scaffold.sh — Directory scaffold generator for Moira
# Creates global layer and project layer directory structures.
# Idempotent — re-run does not destroy existing files (Art 4.3).
#
# Responsibilities: directory creation ONLY
# Does NOT create or populate files (install.sh / /moira:init do that)

set -euo pipefail

# ── moira_scaffold_global <target_dir> ────────────────────────────────
# Create the global layer directory structure at <target_dir>.
# Typically called with ~/.claude/moira/ as target.
moira_scaffold_global() {
  local target_dir="$1"

  if [[ -z "$target_dir" ]]; then
    echo "Error: target_dir required" >&2
    return 1
  fi

  mkdir -p "$target_dir"/core/rules/roles
  mkdir -p "$target_dir"/core/rules/quality
  mkdir -p "$target_dir"/core/pipelines
  mkdir -p "$target_dir"/skills
  mkdir -p "$target_dir"/hooks
  mkdir -p "$target_dir"/templates/stack-presets
  mkdir -p "$target_dir"/templates/scanners
  mkdir -p "$target_dir"/templates/knowledge
  mkdir -p "$target_dir"/lib
  mkdir -p "$target_dir"/schemas
}

# ── moira_scaffold_project <project_root> ─────────────────────────────
# Create the project layer directory structure at <project_root>/.claude/moira/.
# Source: overview.md project layer tree (lines 131-222).
# Does NOT create files — that's Phase 5 /moira:init.
moira_scaffold_project() {
  local project_root="$1"

  if [[ -z "$project_root" ]]; then
    echo "Error: project_root required" >&2
    return 1
  fi

  if [[ ! -d "$project_root" ]]; then
    echo "Error: project root does not exist: $project_root" >&2
    return 1
  fi

  local base="$project_root/.claude/moira"

  # Core rules (copied from global, customized by init)
  mkdir -p "$base"/core/rules/roles
  mkdir -p "$base"/core/rules/quality

  # Project-specific rules
  mkdir -p "$base"/project/rules

  # Configuration
  mkdir -p "$base"/config

  # Knowledge base
  mkdir -p "$base"/knowledge/project-model
  mkdir -p "$base"/knowledge/conventions
  mkdir -p "$base"/knowledge/decisions/archive
  mkdir -p "$base"/knowledge/patterns/archive
  mkdir -p "$base"/knowledge/failures
  mkdir -p "$base"/knowledge/quality-map

  # State
  mkdir -p "$base"/state/tasks
  mkdir -p "$base"/state/metrics
  mkdir -p "$base"/state/audits
  mkdir -p "$base"/state/init

  # Hooks
  mkdir -p "$base"/hooks

  # Copy knowledge templates if available (idempotent — only copy if target doesn't exist)
  local moira_home="${MOIRA_HOME:-$HOME/.claude/moira}"
  if [[ -d "$moira_home/templates/knowledge" ]]; then
    _moira_copy_templates "$moira_home/templates/knowledge" "$base/knowledge"
  fi

  # Copy budget configuration template (Phase 7)
  if [[ -f "$moira_home/templates/budgets.yaml.tmpl" ]]; then
    [[ -f "$base/config/budgets.yaml" ]] || cp "$moira_home/templates/budgets.yaml.tmpl" "$base/config/budgets.yaml"
  fi
}

# ── _moira_copy_templates <source_dir> <target_dir> ──────────────────
# Copy knowledge template files to project, preserving existing files.
_moira_copy_templates() {
  local src="$1"
  local dst="$2"

  for type_dir in "$src"/*/; do
    [[ -d "$type_dir" ]] || continue
    local type_name
    type_name=$(basename "$type_dir")
    mkdir -p "$dst/$type_name"

    for tmpl_file in "$type_dir"*.md; do
      [[ -f "$tmpl_file" ]] || continue
      local target_file="$dst/$type_name/$(basename "$tmpl_file")"
      # Only copy if target doesn't exist (preserve existing knowledge)
      if [[ ! -f "$target_file" ]]; then
        cp "$tmpl_file" "$target_file"
      fi
    done
  done
}
