#!/usr/bin/env bash
# remote-install.sh — Bootstrap Moira from a remote curl invocation.
# Usage: curl -fsSL https://raw.githubusercontent.com/mind-decay/Moira/master/src/remote-install.sh | bash
#
# Clones the repo into a temp directory, runs the real install.sh, then cleans up.

set -euo pipefail

REPO_URL="https://github.com/mind-decay/Moira.git"
BRANCH="master"

# Allow override via env var
MOIRA_REPO_URL="${MOIRA_REPO_URL:-$REPO_URL}"
MOIRA_BRANCH="${MOIRA_BRANCH:-$BRANCH}"

# ── Prerequisite: git ─────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "[ERROR] git is required to install Moira."
  exit 1
fi

# ── Clone into temp directory ─────────────────────────────────────────
TMPDIR_MOIRA="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_MOIRA"' EXIT

echo "Cloning Moira..."
git clone --depth 1 --branch "$MOIRA_BRANCH" "$MOIRA_REPO_URL" "$TMPDIR_MOIRA" 2>&1 | tail -1

# ── Delegate to real installer ────────────────────────────────────────
exec bash "$TMPDIR_MOIRA/src/install.sh"
