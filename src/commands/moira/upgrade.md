---
name: moira:upgrade
description: Upgrade Moira to a newer version
argument-hint: "[source_path]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---

# Moira — Upgrade

Upgrade the Moira installation to a newer version using three-way diff classification for safe, conflict-aware file updates.

## Setup

- **MOIRA_HOME:** `~/.claude/moira/`
- **Version file:** `~/.claude/moira/.version`
- **Version snapshot:** `~/.claude/moira/.version-snapshot/`
- **Upgrade library:** `~/.claude/moira/lib/upgrade.sh`
- **Config:** `.moira/config.yaml`
- **Write scope:** `~/.claude/moira/` paths ONLY

## Step 1: Read Current Version

Read `~/.claude/moira/.version` to get the current installed version.

If the file does not exist:

```
Moira is not installed. Run the install script first.
```

Stop execution.

## Step 2: Determine Upgrade Source

Check for the new version source in this order:

1. **Command argument**: if user passed a path (e.g., `/moira:upgrade /path/to/new/moira`), use that as the source directory.
2. **Environment variable**: check `$MOIRA_SOURCE` via Bash: `echo "$MOIRA_SOURCE"`.
3. **No source found**: display instructions and stop:

```
═══════════════════════════════════════════
 MOIRA — Upgrade
═══════════════════════════════════════════
 Current version: v{current}

 No upgrade source specified.

 Usage:
   /moira:upgrade /path/to/moira-source

 Or set the MOIRA_SOURCE environment variable:
   export MOIRA_SOURCE=/path/to/moira-source
═══════════════════════════════════════════
```

## Step 3: Compare Versions

Read the `.version` file from the source directory.

Run via Bash:
```bash
source ~/.claude/moira/lib/upgrade.sh && moira_upgrade_check_version "{source_dir}"
```

Parse the output: `current={X} available={Y} is_newer={true|false}`.

If `is_newer` is `false`:

```
Moira is up to date (v{current}).
```

Stop execution.

## Step 4: Check Version Pinning

Read `.moira/config.yaml` and check for `moira.version` field.

If `moira.version` is set and differs from the available version:

```
═══════════════════════════════════════════
 VERSION PIN DETECTED
═══════════════════════════════════════════
 Config pins Moira to v{pinned_version}.
 Available version: v{available}.

 ▸ override — upgrade anyway (removes pin)
 ▸ skip     — stay on v{current}
═══════════════════════════════════════════
```

On `skip` → stop execution.
On `override` → continue (and remove the pin in Step 8).

## Step 5: Classify Changes

Run three-way diff classification via Bash:

```bash
source ~/.claude/moira/lib/upgrade.sh && moira_upgrade_diff_files ~/.claude/moira/.version-snapshot "{source_dir}" ~/.claude/moira
```

Parse the output. Each line has format: `{classification}\t{relative_path}`.

Count files per category:
- `auto_apply` — safe to update (project unchanged, source updated)
- `keep_project` — user customized, source unchanged
- `conflict` — both user and source changed
- `new_file` — new in source
- `removed` — removed in source

## Step 6: Present Upgrade Gate

```
═══════════════════════════════════════════
 MOIRA UPGRADE — v{current} → v{available}
═══════════════════════════════════════════
 Changes:
 ├─ {N} files auto-apply (safe)
 ├─ {N} files keep project version (customized)
 ├─ {N} conflicts (both changed)
 └─ {N} new files

 ▸ apply  — upgrade (safe changes only)
 ▸ diff   — show detailed file changes
 ▸ skip   — stay on current version
═══════════════════════════════════════════
```

If there are `removed` files, also show:
```
 ├─ {N} files removed in new version
```

## Step 7: Handle User Choice

### Choice: `diff`

Show per-file details for all categories:

**auto_apply files:**
```
AUTO-APPLY (safe — your copy unchanged):
  {path1}
  {path2}
  ...
```

For each auto_apply file, optionally run `diff` between old snapshot and new source to show what changed:
```bash
diff ~/.claude/moira/.version-snapshot/{path} {source_dir}/{path}
```

**keep_project files:**
```
KEEP PROJECT (you customized these):
  {path1}
  {path2}
  ...
```

**conflict files:**
```
CONFLICTS (both you and upstream changed):
  {path1}
  {path2}
  ...
```

For each conflict, show both diffs (user changes vs upstream changes).

**new_file files:**
```
NEW FILES:
  {path1}
  {path2}
  ...
```

**removed files:**
```
REMOVED IN NEW VERSION:
  {path1}
  {path2}
  ...
```

After showing diff, re-present the gate (go back to Step 6).

### Choice: `skip`

```
Staying on v{current}.
```

Stop execution.

### Choice: `apply`

Proceed to Step 8.

## Step 8: Apply Upgrade

### 8a. Write Change List

Write the classification output to a temporary file via Bash:

```bash
source ~/.claude/moira/lib/upgrade.sh && moira_upgrade_diff_files ~/.claude/moira/.version-snapshot "{source_dir}" ~/.claude/moira > /tmp/moira-upgrade-changes.txt
```

### 8b. Apply Safe Changes

Run via Bash:

```bash
source ~/.claude/moira/lib/upgrade.sh && moira_upgrade_apply /tmp/moira-upgrade-changes.txt "{source_dir}" ~/.claude/moira
```

Parse output: `applied={N}`, `skipped={N}`, and any `conflicts:` list.

### 8c. Create New Version Snapshot

Run via Bash:

```bash
source ~/.claude/moira/lib/upgrade.sh && moira_upgrade_snapshot ~/.claude/moira
```

### 8d. Update Version File

Write the new version to `~/.claude/moira/.version` (copy from source):

```bash
cp "{source_dir}/.version" ~/.claude/moira/.version
```

### 8e. Remove Version Pin (if overridden in Step 4)

If the user chose `override` in Step 4, update `.moira/config.yaml` to remove or clear the `moira.version` field.

### 8f. Cleanup

```bash
rm -f /tmp/moira-upgrade-changes.txt
```

## Step 9: Display Summary

```
═══════════════════════════════════════════
 MOIRA — Upgrade Complete
═══════════════════════════════════════════
 Version: v{old} → v{new}
 ├─ Applied: {N} files
 ├─ Skipped: {N} files (customized/conflicts)
 └─ New:     {N} files added
═══════════════════════════════════════════
```

If there were conflicts:

```
 Unresolved conflicts ({N} files):
   {conflict file list}
 Review these files manually and merge changes.
```

Always end with:

```
 Recommended: run /moira:audit to verify system health.
```

## Constitutional Compliance

- **Art 4.2:** User must approve the upgrade before any files are modified. The gate in Step 6 ensures explicit consent.
- **Art 5.2:** Customized files (keep_project) are never overwritten without explicit user action.
- **Write scope:** This command writes ONLY to `~/.claude/moira/` paths (global Moira install). NEVER to project source files.
