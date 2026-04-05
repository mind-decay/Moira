#!/usr/bin/env bash
# upgrade.sh — Version upgrade with three-way conflict classification
# Provides semver comparison, three-way diff classification for safe upgrades,
# auto-apply of non-conflicting changes, and version snapshot management.
#
# Source: design/specs/2026-03-16-phase12-implementation-plan.md Task 4.1

set -euo pipefail

# ── moira_upgrade_check_version [source_dir] ─────────────────────────
# Compare installed version against new source version.
# Reads ~/.claude/moira/.version (installed) and $MOIRA_SOURCE/.version
# (or first arg). Compares semver numerically.
# Output: current={X} available={Y} is_newer={true|false}
moira_upgrade_check_version() {
  local source_dir="${1:-${MOIRA_SOURCE:-}}"

  if [[ -z "$source_dir" ]]; then
    echo "Error: no source directory (pass arg or set MOIRA_SOURCE)" >&2
    return 1
  fi

  local installed_file="$HOME/.claude/moira/.version"
  local source_file="${source_dir}/.version"

  if [[ ! -f "$installed_file" ]]; then
    echo "Error: installed version file not found: $installed_file" >&2
    return 1
  fi

  if [[ ! -f "$source_file" ]]; then
    echo "Error: source version file not found: $source_file" >&2
    return 1
  fi

  local current available
  current=$(< "$installed_file")
  available=$(< "$source_file")

  # Strip leading/trailing whitespace
  current="${current#"${current%%[![:space:]]*}"}"
  current="${current%"${current##*[![:space:]]}"}"
  available="${available#"${available%%[![:space:]]*}"}"
  available="${available%"${available##*[![:space:]]}"}"

  local is_newer
  is_newer=$(_moira_upgrade_semver_gt "$available" "$current")

  echo "current=${current} available=${available} is_newer=${is_newer}"
}

# ── moira_upgrade_diff_files <old_dir> <new_dir> ─────────────────────
# Three-way diff classification between base snapshot, new source, and
# current project files.
# old_dir  = base snapshot (what was installed before user changes)
# new_dir  = new source directory
# project_dir = ~/.claude/moira/ (current installed, with user changes)
#
# Per-file classification:
#   auto_apply  — project == old AND old != new (safe to update)
#   keep_project — project != old AND old == new (user customized, update unchanged)
#   conflict    — project != old AND old != new (both changed)
#   new_file    — file in new_dir but not old_dir
#   removed     — file in old_dir but not new_dir
#
# Output: one line per file: {classification}\t{relative_path}
moira_upgrade_diff_files() {
  local old_dir="$1"
  local new_dir="$2"
  local project_dir="${3:-$HOME/.claude/moira}"

  if [[ ! -d "$old_dir" ]]; then
    echo "Error: old_dir not found: $old_dir" >&2
    return 1
  fi

  if [[ ! -d "$new_dir" ]]; then
    echo "Error: new_dir not found: $new_dir" >&2
    return 1
  fi

  # Collect all relative paths from all three directories
  local all_paths
  all_paths=$(_moira_upgrade_collect_paths "$old_dir" "$new_dir" "$project_dir")

  if [[ -z "$all_paths" ]]; then
    return 0
  fi

  local path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue

    local old_file="${old_dir}/${path}"
    local new_file="${new_dir}/${path}"
    local project_file="${project_dir}/${path}"

    local in_old=false in_new=false in_project=false
    [[ -f "$old_file" ]] && in_old=true
    [[ -f "$new_file" ]] && in_new=true
    [[ -f "$project_file" ]] && in_project=true

    # new_file: exists in new but not in old
    if ! $in_old && $in_new; then
      printf "new_file\t%s\n" "$path"
      continue
    fi

    # removed: exists in old but not in new
    if $in_old && ! $in_new; then
      printf "removed\t%s\n" "$path"
      continue
    fi

    # File exists in both old and new — three-way compare
    if $in_old && $in_new; then
      local old_changed=false project_changed=false

      # Did the update change this file? (old != new)
      if ! diff -q "$old_file" "$new_file" > /dev/null 2>&1; then
        old_changed=true
      fi

      # Did the user change this file? (project != old)
      if $in_project && ! diff -q "$project_file" "$old_file" > /dev/null 2>&1; then
        project_changed=true
      fi
      # If project file doesn't exist, treat as user-removed (project changed)
      if ! $in_project; then
        project_changed=true
      fi

      if ! $project_changed && $old_changed; then
        printf "auto_apply\t%s\n" "$path"
      elif $project_changed && ! $old_changed; then
        printf "keep_project\t%s\n" "$path"
      elif $project_changed && $old_changed; then
        printf "conflict\t%s\n" "$path"
      fi
      # If neither changed, skip (no action needed)
    fi
  done <<< "$all_paths"
}

# ── moira_upgrade_apply <change_list_file> <new_dir> <project_dir> ───
# Apply safe changes from a classification file.
# Processes auto_apply and new_file entries; skips keep_project,
# conflict, and removed.
# Output: count applied, count skipped, list of conflicts
moira_upgrade_apply() {
  local change_list_file="$1"
  local new_dir="$2"
  local project_dir="$3"

  if [[ ! -f "$change_list_file" ]]; then
    echo "Error: change list file not found: $change_list_file" >&2
    return 1
  fi

  if [[ ! -d "$new_dir" ]]; then
    echo "Error: new_dir not found: $new_dir" >&2
    return 1
  fi

  local applied=0
  local skipped=0
  local conflicts=""

  local classification path
  while IFS=$'\t' read -r classification path; do
    [[ -z "$classification" ]] && continue

    case "$classification" in
      auto_apply|new_file)
        local target="${project_dir}/${path}"
        local target_dir
        target_dir="$(dirname "$target")"
        mkdir -p "$target_dir"
        cp -f "${new_dir}/${path}" "$target"
        applied=$(( applied + 1 ))
        ;;
      conflict)
        skipped=$(( skipped + 1 ))
        if [[ -n "$conflicts" ]]; then
          conflicts="${conflicts}"$'\n'"  ${path}"
        else
          conflicts="  ${path}"
        fi
        ;;
      keep_project|removed)
        skipped=$(( skipped + 1 ))
        ;;
      *)
        echo "Warning: unknown classification '${classification}' for ${path}" >&2
        skipped=$(( skipped + 1 ))
        ;;
    esac
  done < "$change_list_file"

  echo "applied=${applied}"
  echo "skipped=${skipped}"
  if [[ -n "$conflicts" ]]; then
    echo "conflicts:"
    echo "$conflicts"
  fi
}

# ── moira_upgrade_snapshot <dir> ─────────────────────────────────────
# Create a version snapshot of the current installation for future
# three-way diffs. Copies known subdirectories into .version-snapshot/.
moira_upgrade_snapshot() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    echo "Error: directory not found: $dir" >&2
    return 1
  fi

  local snapshot_dir="${dir}/.version-snapshot"

  rm -rf "$snapshot_dir"
  mkdir -p "$snapshot_dir"

  local subdir
  for subdir in core skills templates schemas lib hooks; do
    if [[ -d "${dir}/${subdir}" ]]; then
      cp -r "${dir}/${subdir}" "${snapshot_dir}/${subdir}"
    fi
  done

  echo "snapshot_created: ${snapshot_dir}"
}

# ── Helper functions ──────────────────────────────────────────────────

# _moira_upgrade_semver_gt <a> <b>
# Returns "true" if version a is strictly greater than version b.
# Compares major.minor.patch numerically.
_moira_upgrade_semver_gt() {
  local a="$1"
  local b="$2"

  local a_major a_minor a_patch
  local b_major b_minor b_patch

  IFS='.' read -r a_major a_minor a_patch <<< "$a"
  IFS='.' read -r b_major b_minor b_patch <<< "$b"

  # Default missing components to 0
  a_major=${a_major:-0}; a_minor=${a_minor:-0}; a_patch=${a_patch:-0}
  b_major=${b_major:-0}; b_minor=${b_minor:-0}; b_patch=${b_patch:-0}

  if (( a_major > b_major )); then
    echo "true"
  elif (( a_major < b_major )); then
    echo "false"
  elif (( a_minor > b_minor )); then
    echo "true"
  elif (( a_minor < b_minor )); then
    echo "false"
  elif (( a_patch > b_patch )); then
    echo "true"
  else
    echo "false"
  fi
}

# _moira_upgrade_collect_paths <dir1> <dir2> <dir3>
# Collect all unique relative file paths across up to three directories.
# Outputs sorted, deduplicated list.
_moira_upgrade_collect_paths() {
  local dir1="$1"
  local dir2="$2"
  local dir3="${3:-}"

  {
    if [[ -d "$dir1" ]]; then
      (cd "$dir1" && find . -type f 2>/dev/null) || true
    fi
    if [[ -d "$dir2" ]]; then
      (cd "$dir2" && find . -type f 2>/dev/null) || true
    fi
    if [[ -n "$dir3" && -d "$dir3" ]]; then
      (cd "$dir3" && find . -type f 2>/dev/null) || true
    fi
  } | sed 's|^\./||' | sort -u
}
