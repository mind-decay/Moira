# Phase 8: Hooks & Self-Monitoring

## Goal

Complete the three-layer guard mechanism (D-031). Layer 1 (`allowed-tools` prevention) is in place since Phase 3. This phase implements Layer 2 (PostToolUse hooks for detection/audit) and Layer 3 (CLAUDE.md prompt enforcement). After Phase 8: every tool call during a Moira session is logged, orchestrator violations are detected and reported in real-time, budget-related tool activity is tracked, and the CLAUDE.md prompt enforcement rules complete the defense-in-depth model.

**Why now:** The system has been running with `allowed-tools` as the sole structural enforcement since Phase 3. Hooks provide the audit trail needed for constitutional verification (Art 6.3) and violation trend tracking (Phase 11). Budget tracking hooks complement the budget estimation system from Phase 7 with per-tool-call runtime logging.

## Risk Classification

**YELLOW (overall)** — New hook scripts, settings.json merge logic, prompt enforcement additions, E7-DRIFT stub completion. No pipeline gate changes. No agent role boundary changes. Needs regression check + impact analysis.

**Per-deliverable:**

| Deliverable | Risk | Rationale |
|-------------|------|-----------|
| D1: Guard Hook | YELLOW | New script, constitutional violation detection logic |
| D2: Budget Hook | GREEN | New script, simple logging only |
| D3: Settings Merge | YELLOW | JSON manipulation in bash, user's settings.json at risk |
| D4: Bootstrap Integration | YELLOW | Modifies bootstrap flow, new init step |
| D5: E7-DRIFT Handler | GREEN | Replaces stub, documentation-level change in skills |
| D6: CLAUDE.md Template | GREEN | Additive prompt text, no logic changes |
| D7: Health Report Integration | GREEN | Adds data source instructions to orchestrator/gates |
| D8: Tier 1 Tests | GREEN | New test file, additive |
| D9: Install.sh Update | YELLOW | Modifies install verification, chmod for hooks |
| D11: Log File Init | GREEN | Touch empty files in bootstrap |

## Design Sources

| Document | Relevance |
|----------|-----------|
| `design/CONSTITUTION.md` | Art 1.1 (orchestrator purity — hooks detect violations), Art 3.1 (decision traceability — tool usage log), Art 3.2 (budget visibility — budget tracking hook), Art 6.3 (invariant verification — guard hook provides audit trail) |
| `design/subsystems/self-monitoring.md` | Complete guard mechanism design: hook registration JSON, guard.sh logic, budget-track.sh logic, orchestrator context monitoring thresholds, warning display, anti-rationalization rules, orchestrator health report, post-task audit checks |
| `design/subsystems/self-protection.md` | Risk classification categories (RED/ORANGE/YELLOW/GREEN), dangerous change categories, development session protocol. NOTE: self-protection.md defines a *different* three-layer system (Regression→Conformance→Constitutional) for change management. Phase 8 implements the *runtime* three-layer guard from self-monitoring.md (allowed-tools→guard.sh→CLAUDE.md). |
| `design/architecture/overview.md` | File structure showing `hooks/guard.sh` and `hooks/budget-track.sh` locations, `settings.json` merge reference |
| `design/architecture/distribution.md` | Step 8 of `/moira:init`: inject hooks configuration into `.claude/settings.json`, preserve existing hooks |
| `design/subsystems/fault-tolerance.md` | E7-DRIFT error type: guard hook detection, violation logging, reflector audit, frequency tracking |
| `design/decisions/log.md` | D-031 (three-layer guard mechanism), D-020 (file-copy distribution), D-038 (E7/E8 stubs in Phase 3), D-072–D-076 (Phase 8 architectural decisions) |

## Prerequisites (from Phase 1-7)

- **Phase 1:** State management (`state.sh`, `yaml-utils.sh`), scaffold (`scaffold.sh`), directory structure with `hooks/` directory
- **Phase 2:** Agent role definitions with NEVER constraints
- **Phase 3:** Orchestrator skill with `allowed-tools` restriction in `task.md` frontmatter (Layer 1 — PREVENTION), E7-DRIFT stub in `errors.md`, pipeline definitions with all gates
- **Phase 5:** Bootstrap engine (`bootstrap.sh`), CLAUDE.md injection system (`moira_bootstrap_inject_claude_md`)
- **Phase 6:** Quality system, findings format
- **Phase 7:** Budget library (`budget.sh`), budget estimation/tracking functions, orchestrator health check

## Existing Infrastructure Audit

### Already Implemented (no changes needed)

1. **`allowed-tools` in `task.md`** (Layer 1): Edit, Bash, Grep, Glob are physically unavailable to the orchestrator — primary enforcement
2. **Hooks directory structure**: `src/global/hooks/.gitkeep` exists, `install.sh` copies `global/hooks/*` if present
3. **Config schema**: `hooks.guard_enabled` (default: true), `hooks.budget_tracking_enabled` (default: true) — already defined
4. **E7-DRIFT stub**: `errors.md` has E7-DRIFT section with "Phase 3 stub per D-038. Full detection in Phase 8" marker
5. **Bootstrap gitignore**: `state/` has specific file entries gitignored (tasks/, bypass-log.yaml, current.yaml, init/). New log files (violations.log, tool-usage.log, budget-tool-usage.log) need to be added to the gitignore setup.
6. **Orchestrator health report template**: `gates.md` has the health report section with violations count placeholder
7. **Budget library functions**: `moira_budget_orchestrator_check`, `moira_budget_record_agent` — provide budget data hooks can reference
8. **Anti-rationalization rules**: Already in `orchestrator.md` Section 1 — Identity and Boundaries
9. **CLAUDE.md injection system**: `moira_bootstrap_inject_claude_md` with marker-based idempotent injection

### Not Yet Implemented (Phase 8 scope)

1. **`guard.sh`**: PostToolUse hook script for violation detection and audit logging
2. **`budget-track.sh`**: PostToolUse hook script for per-tool-call token usage logging
3. **Settings.json merge**: Logic to inject hook configuration into `.claude/settings.json`
4. **E7-DRIFT full handler**: Replace stub with concrete detection/reporting using guard hook data
5. **CLAUDE.md prompt enforcement rules**: The anti-rationalization and boundary rules for project CLAUDE.md template (Layer 3)
6. **Violation log management**: Log format, rotation, health report integration
7. **Tool usage log management**: Log format for audit trail
8. **Orchestrator health report — violations data source**: Currently placeholder, needs to read from `violations.log`

## Deliverables

### D1: Guard Hook (`src/global/hooks/guard.sh`)

PostToolUse hook that fires after every tool call during a Moira session. Provides detection + audit logging (Layer 2 of D-031).

**Hook input format** (from Claude Code PostToolUse):
```json
{
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/path/to/file"
  }
}
```

**Responsibilities:**
1. Parse hook input JSON (tool_name, tool_input)
2. Log ALL tool usage to `tool-usage.log` for audit trail (Art 3.1)
3. Detect violations: orchestrator accessing project files outside `.moira/`
4. On violation: write to `violations.log` AND inject warning into Claude context via `hookSpecificOutput`

**Violation detection logic:**
- Only active during Moira sessions (check: `current.yaml` exists in state directory)
- Check `hooks.guard_enabled` in config (if available, default: true)
- Violation condition: tool_name is Read/Write/Edit AND file_path does NOT contain `.moira`
  - **Design deviation (intentional):** `self-monitoring.md` guard.sh example includes Grep/Glob in the check. We omit them because `allowed-tools` in `task.md` physically prevents the orchestrator from using Grep/Glob — guard.sh cannot detect what `allowed-tools` already blocks. Guard only checks Read/Write/Edit because these are the tools the orchestrator legitimately has access to (for reading `.moira/` state). See D-072 rationale.
  - Agent tool calls are NOT violations — agents SHOULD use all tools
  - The guard cannot distinguish orchestrator vs. agent calls (both fire PostToolUse) — but `allowed-tools` prevents the orchestrator from even having these tools. Guard catches edge cases only.

**Output on violation:**
```json
{"hookSpecificOutput":{"additionalContext":"CONSTITUTIONAL VIOLATION (Art 1.1): Orchestrator used {tool_name} on {file_path}. Direct project file operations are prohibited."}}
```

**Log format — `tool-usage.log`:**
```
{ISO8601} {tool_name} {file_path_or_command}
```

**Log format — `violations.log`:**
```
{ISO8601} VIOLATION {tool_name} {file_path}
```

**Log location:** Both logs in the project's `.moira/state/` directory (gitignored, per-developer).

**Error handling:**
- If `jq` is not available: fall back to grep-based JSON extraction
- If state directory doesn't exist: exit 0 silently (not a Moira session)
- If any error occurs: exit 0 (hooks MUST NOT break Claude Code operation)
- Script must be fast: < 50ms execution time (avoid expensive operations)

**Critical design constraint:**
- Hook scripts execute in a SEPARATE process, not in the orchestrator context
- They cannot call `budget.sh` or `state.sh` functions directly
- All state interaction is via direct file reads/writes using `grep`/`sed`/basic bash
- No `source` of Moira library files (too slow for PostToolUse frequency)

### D2: Budget Tracking Hook (`src/global/hooks/budget-track.sh`)

PostToolUse hook that logs tool-level activity for budget analysis.

**Responsibilities:**
1. Log tool calls with timestamps for post-task budget analysis
2. Track Read operations with file sizes for token estimation
3. Provide data source for budget trend analysis (Phase 11)

**What it logs — `budget-tool-usage.log`:**
```
{ISO8601} {tool_name} {file_path} {file_size_bytes}
```

Where:
- `file_size_bytes` is populated for Read/Write/Edit calls (get file size via `wc -c`)
- For Agent calls: log `agent` as the file_path, `0` as size
- For other tools: log the relevant parameter, `0` as size

**Activation check:**
- Only active during Moira sessions (check: `current.yaml` exists)
- Check `hooks.budget_tracking_enabled` in config (if available, default: true)

**Performance:**
- Must be fast: file size via `wc -c` is cheap
- Write to log file via simple append (no locking needed — single process)
- Exit 0 on any error

**Log location:** `.moira/state/budget-tool-usage.log` (gitignored)

### D3: Settings.json Merge Logic (`src/global/lib/settings-merge.sh`)

Shell library for merging Moira hook configuration into `.claude/settings.json`.

**Challenge:** Claude Code's `.claude/settings.json` may:
- Not exist yet
- Exist with no hooks section
- Exist with existing hooks (from user or other tools)
- Have Moira hooks already registered (idempotent re-init)

**Strategy: additive merge, never overwrite existing hooks.**

#### `moira_settings_merge_hooks <project_root> <moira_home>`

1. Read existing `.claude/settings.json` (or create empty `{}` if missing)
2. Parse `hooks.PostToolUse` array (or create empty if missing)
3. Check if Moira guard hook is already registered:
   - Search for command containing `moira/hooks/guard.sh`
   - If found: skip (idempotent)
   - If not found: append Moira hook entry
4. Check if Moira budget-track hook is already registered:
   - Search for command containing `moira/hooks/budget-track.sh`
   - If found: skip
   - If not found: append Moira hook entry
5. Write updated `.claude/settings.json`

**Moira hook entries to inject:**
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/moira/hooks/budget-track.sh"
          }
        ]
      }
    ]
  }
}
```

**JSON manipulation:** This is the hardest part — shell-based JSON editing. Options:
1. If `jq` available: use jq for safe merge
2. Fallback: simple string-based insertion for the common case (empty or simple settings.json)
3. If JSON is too complex to parse safely: warn user and skip hook injection, providing manual instructions

**Output:** Updated `.claude/settings.json` with Moira hooks merged alongside any existing hooks.

#### `moira_settings_remove_hooks <project_root>`

Inverse of merge — removes Moira hook entries from settings.json. Used for uninstall/cleanup.

1. Read `.claude/settings.json`
2. Remove entries containing `moira/hooks/guard.sh` and `moira/hooks/budget-track.sh`
3. If PostToolUse array is now empty, remove it
4. If hooks object is now empty, remove it
5. Write updated file

### D4: Bootstrap Integration — Hook Injection in `/moira:init`

Wire settings.json merge into the bootstrap flow (Step 8 from `distribution.md`).

#### D4a: Update `bootstrap.sh`

Add new function `moira_bootstrap_inject_hooks` that:
1. Sources `settings-merge.sh`
2. Calls `moira_settings_merge_hooks` with project root and moira home
3. Handles errors gracefully (hook injection failure should NOT block init)
4. Logs result: "Hooks configured in .claude/settings.json" or "Hooks injection skipped — configure manually"

#### D4b: Update `init.md` command

Hook injection step from `distribution.md` Step 8 is not yet implemented in `init.md`. Add it:
- Current init.md steps: 1-8 (Check → Scaffold → Scanners → Config → Knowledge → CLAUDE.md → Gitignore → Review Gate → Onboarding)
- Insert hook injection as **new Step 9** (after Step 8 Gitignore, before current Step 9 Review Gate)
- Renumber: Review Gate becomes Step 10, Onboarding becomes Step 11
- Update `--force` mode section: "Steps 7-8" becomes "Steps 7-9" (CLAUDE.md, gitignore, hooks re-injected)
- Display hook status in init gate summary (Step 10):
  ```
  Configured:
  ├─ ...existing items...
  └─ Hooks: guard.sh + budget-track.sh registered
  ```

### D5: E7-DRIFT Full Handler

Replace the Phase 3 stub in `errors.md` with concrete detection and reporting.

**Detection sources (from guard.sh):**
1. `violations.log` — direct file operation violations detected by guard hook
2. `tool-usage.log` — audit trail for pattern analysis

**Updated E7-DRIFT section in `errors.md`:**

```
## E7-DRIFT: Orchestrator Rule Violation

### Detection

Guard hook (`guard.sh`) detects violations in real-time:
- Orchestrator uses Read/Write/Edit on files outside `.moira/`
- Violation logged to `state/violations.log`
- Warning injected into orchestrator context via hookSpecificOutput

### During Pipeline

On violation detection (guard hook fires):
1. Violation is ALREADY logged (guard.sh handles this)
2. Warning message appears in orchestrator context
3. Orchestrator MUST acknowledge the violation in its next output
4. Include violation count in next health report

### Post-Task Audit

After pipeline completion, check violations:
1. Count violations: `wc -l < state/violations.log`
2. If violations > 0:
   - Include in completion summary: "{N} orchestrator violations detected"
   - Log in telemetry: `compliance.orchestrator_violation_count` (integer)
   - Flag for Reflector analysis (Phase 10)
   - If violations > 3: recommend rule strengthening

### Display

When violations exist, add to health report:

```
ORCHESTRATOR HEALTH:
├─ Context: ~22k/1M (2%) ✅
├─ Violations: {count} 🔴  ← highlighted when > 0
...
```

### State Updates

- `state/violations.log`: appended by guard.sh on each violation (ISO8601, tool_name, file_path)
- `state/tool-usage.log`: appended by guard.sh on every tool call (audit trail)
- `telemetry.yaml`: `compliance.orchestrator_violation_count` written at task completion

### Recovery

No automated recovery — violations are informational.
- `allowed-tools` prevents most violations structurally
- Guard hook catches edge cases
- Reflector tracks patterns for trend analysis (Phase 10)
- Audit recommends rule changes if violations are recurring (Phase 11)

### Escalation

No automated escalation. Violations are informational only.
- If violations > 3 in a single task: recommend rule strengthening in completion summary
- Reflector (Phase 10) analyzes patterns across tasks
- Audit (Phase 11) tracks frequency trends
```

### D6: CLAUDE.md Prompt Enforcement (Layer 3)

Update the project CLAUDE.md template with explicit orchestrator boundary rules.

#### D6a: Update `project-claude-md.tmpl`

**Merge strategy:** The template already has an "Orchestrator Rules (Inviolable)" section with basic NEVER rules. REPLACE that section with the expanded version below, which is a superset (adds anti-rationalization patterns, guard.sh reference). Do NOT add a duplicate section alongside the existing one.

This is the third defense layer — it operates at the prompt level, reinforcing what `allowed-tools` enforces structurally.

**Replacement section in template (within `<!-- moira:start -->` markers, replacing existing "Orchestrator Rules" section):**

```markdown
## Moira — Orchestrator Boundaries

When executing through the Moira pipeline (`/moira:task`):

### ABSOLUTE PROHIBITIONS

You are an ORCHESTRATOR. You are NOT an executor.

ALL project interaction happens through dispatched agents.

NEVER:
- Use Read on files outside .moira/
- Use Edit or Write on files outside .moira/
- Use Bash for anything except agent dispatch
- Use Grep or Glob on project files

### Anti-Rationalization

If you catch yourself thinking:
- "Let me just quickly check..." → DISPATCH Hermes (explorer)
- "I can easily fix this..." → DISPATCH Hephaestus (implementer)
- "This is so simple I'll just..." → FOLLOW THE PIPELINE
- "To save time..." → TIME IS NOT YOUR CONCERN, QUALITY IS
- "The user said to skip..." → ONLY /moira:bypass can skip pipeline

ANY violation is logged by guard.sh and reported in task metrics.
```

This mirrors the anti-rationalization rules already in `orchestrator.md` Section 1 — the CLAUDE.md version ensures the rules are in the system prompt context even if the orchestrator skill is not fully loaded.

### D7: Orchestrator Health Report — Violation Integration

Wire violation count into the orchestrator's health report display.

#### D7a: Update `orchestrator.md` Sections 1, 6, and 7

**Section 1 (Identity and Boundaries):**
- Update Layer 2 enforcement note: remove "Phase 8" reference (now implemented), clarify guard.sh provides detection + audit logging

**Section 6 (Budget Monitoring) — add violation monitoring subsection:**
- After each agent returns, orchestrator reads violation count
- **Mechanism:** Use Read tool on `.moira/state/violations.log`, count lines (the orchestrator CAN read `.moira/` files — this is within its allowed scope)
- Include in health report: `Violations: {count} {emoji}`
- Emoji: ✅ if 0, 🔴 if > 0
- If guard.sh injected a warning via hookSpecificOutput: acknowledge it in next output

**Section 7 (Completion Flow) — add violation telemetry:**
- After budget report display: check `state/violations.log` line count
- If violations > 0: include count in completion summary ("{N} orchestrator violations detected")
- Write violation count to `telemetry.yaml` field `compliance.orchestrator_violation_count`

#### D7b: Update `gates.md` Health Report Section

Clarify data source for violations field:
- Source: line count of `.moira/state/violations.log` (0 if file doesn't exist)
- This is already in the template — Phase 8 provides the actual log file

### D8: Tier 1 Tests (`src/tests/tier1/test-hooks-system.sh`)

New test file for hooks system structural verification.

**Guard hook tests:**
- `guard.sh` exists in `hooks/`
- `guard.sh` has valid bash syntax (`bash -n`)
- `guard.sh` contains `hookSpecificOutput` (violation output mechanism)
- `guard.sh` contains `CONSTITUTIONAL VIOLATION` (violation message — must be exact string, not just `VIOLATION` which appears in log file names)
- `guard.sh` contains `violations.log` (log file reference)
- `guard.sh` contains `tool-usage.log` (audit log reference)
- `guard.sh` checks for `current.yaml` (session detection)

**Budget tracking hook tests:**
- `budget-track.sh` exists in `hooks/`
- `budget-track.sh` has valid bash syntax
- `budget-track.sh` contains `budget-tool-usage.log` (log file reference)
- `budget-track.sh` checks for `current.yaml` (session detection)

**Settings merge tests:**
- `settings-merge.sh` exists in `lib/`
- `settings-merge.sh` has valid bash syntax
- Functions exist: `moira_settings_merge_hooks`, `moira_settings_remove_hooks`

**Integration tests:**
- `orchestrator.md` mentions `guard.sh` or "guard hook" (Layer 2 reference)
- `orchestrator.md` mentions `violations.log` or "violation" (health report data)
- `errors.md` E7-DRIFT section is NOT a stub (check: does NOT contain "stub" or "Phase 3 stub")
- `project-claude-md.tmpl` contains "ORCHESTRATOR" and "NEVER" (Layer 3 enforcement)
- `project-claude-md.tmpl` contains "anti-rationalization" or "rationalization" (defense-in-depth)
- `install.sh` copies hook files
- `config.schema.yaml` has `hooks.guard_enabled` and `hooks.budget_tracking_enabled`

**Hook script functional tests (basic):**
- `guard.sh` exits 0 when no state directory exists (non-Moira session)
- `budget-track.sh` exits 0 when no state directory exists

### D9: Updated `install.sh`

Phase 8 introduces actual hook files. Verify install.sh handles them correctly.

**What to verify/update:**
- The existing `global/hooks/*` copy block already handles this — BUT it copies `.gitkeep` too
- Ensure hook scripts are copied with executable permission: `chmod +x "$MOIRA_HOME/hooks/"*.sh`
- The existing install.sh line `cp -f "$SCRIPT_DIR/global/hooks/"* "$MOIRA_HOME/hooks/"` already does the copy
- Add verification: `guard.sh` exists and has valid syntax, `budget-track.sh` exists and has valid syntax

**New copy operation:**
- `settings-merge.sh` → `$MOIRA_HOME/lib/settings-merge.sh` (already covered by `cp -f "$SCRIPT_DIR/global/lib/"*.sh`)

**New verification checks:**
- `guard.sh` exists in hooks/ and has valid syntax
- `budget-track.sh` exists in hooks/ and has valid syntax
- Both are executable (`-x` check)

### D10: ~~Updated `run-all.sh`~~ NOT NEEDED

`run-all.sh` uses glob `test-*.sh` for auto-discovery. No update required — naming convention is sufficient.

### D11: Log File Initialization in Bootstrap

Create empty log files during bootstrap (not scaffold — `scaffold.sh` is responsible for directory creation ONLY per its documented contract).

Add to `moira_bootstrap_inject_hooks` (after settings merge, before returning):
- `state/violations.log` — empty, created during bootstrap
- `state/tool-usage.log` — empty, created during bootstrap
- `state/budget-tool-usage.log` — empty, created during bootstrap

This ensures the log files exist before the first hook fires (hooks check file existence before writing).

Note: `scaffold.sh` creates `state/` directories. Bootstrap creates initial files within them. This maintains the existing responsibility split.

### D12: Gitignore Entries for Log Files

Update `moira_bootstrap_setup_gitignore` in `bootstrap.sh` to add entries for the new log files. Current gitignore entries cover specific `state/` files but NOT a `state/` wildcard — the new log files need explicit entries:

- `.moira/state/violations.log`
- `.moira/state/tool-usage.log`
- `.moira/state/budget-tool-usage.log`

These are per-developer ephemeral data (D-074) and must not be committed.

## Design Doc Corrections (incidental fixes during Phase 8)

1. **`design/subsystems/fault-tolerance.md`** E7-DRIFT section says "Guard hook **blocks** prohibited tool calls" — factually wrong per D-031 (PostToolUse = detection only, not blocking). Fix to: "Guard hook **detects** prohibited tool calls."
2. **`design/architecture/overview.md`** file structure is outdated — `lib/` section does not list `settings-merge.sh` (or other libs from Phases 4-7). Add `settings-merge.sh` at minimum; optionally update the full lib list.

## Non-Deliverables (explicitly deferred)

- **PreToolUse hooks** (does not exist): Claude Code only supports PostToolUse. D-031 explicitly addresses this — `allowed-tools` replaces the need for PreToolUse.
- **Hook-based budget estimation** (not designed): `budget-track.sh` logs data for analysis. Actual budget estimation remains in `budget.sh` library (Phase 7). The hook provides raw data; the library provides the interpretation.
- **Violation trend analysis** (Phase 11): Metrics aggregation across tasks. Phase 8 provides the data; Phase 11 provides the analysis.
- **Reflector integration** (Phase 10): The Reflector auditing orchestrator violations is Phase 10 scope. Phase 8 provides the violation log that the Reflector reads.
- **Log rotation** (Phase 11): Log files grow indefinitely in Phase 8. Rotation/archival is Phase 11 (Metrics & Audit).
- **Hook enable/disable CLI** (Phase 12): No command to toggle hooks at runtime. Users can edit config.yaml `hooks.*` fields directly.
- **Agent-level tool tracking** (not designed): Guard.sh cannot reliably distinguish orchestrator vs. agent tool calls. D-031 acknowledges this: `allowed-tools` is the primary enforcement, guard.sh is defense-in-depth audit.

## Architectural Decisions

### AD-1 (D-072): Hooks as Lightweight Scripts (No Library Dependencies)

Guard.sh and budget-track.sh do NOT source any Moira library files. They use only basic bash, `grep`, `sed`, and optionally `jq`.

Guard.sh checks only Read/Write/Edit (not Grep/Glob as in `self-monitoring.md` example). This is an intentional narrowing: `allowed-tools` physically prevents the orchestrator from using Grep/Glob, so guard.sh cannot observe these calls. Guard only monitors tools the orchestrator legitimately has access to for reading `.moira/` state.

**Rationale:**
1. PostToolUse hooks fire after EVERY tool call — performance is critical (< 50ms)
2. Sourcing `yaml-utils.sh` + `budget.sh` would add ~100ms+ startup time
3. Hooks are separate processes — they cannot share state with the orchestrator
4. Simple log file appends are sufficient for detection and audit
5. Complex analysis happens post-task (by Reflector) or post-pipeline (by budget report), not per-call
6. Grep/Glob omitted from guard.sh: `allowed-tools` makes them unobservable — guard checks only what it can actually see

### AD-2 (D-073): JSON Settings Merge with jq Fallback

Settings.json manipulation requires JSON editing. We use `jq` when available, with a grep-based fallback for simple cases.

**Rationale:**
1. `jq` is widely available but not universal (not on fresh macOS without Homebrew)
2. The fallback handles the common case: empty or simple settings.json
3. For complex settings.json (multiple tools, nested hooks): we warn and provide manual instructions
4. This matches D-020 philosophy: minimal dependencies, works on any OS with Claude Code

### AD-3 (D-074): Violation Log in State Directory (Gitignored)

Violation and tool-usage logs go in `state/` (gitignored), not `config/` (committed).

**Rationale:**
1. Violations are per-developer, per-session — not team-shared state
2. Git-tracking violations creates noise in PRs
3. Reflector (Phase 10) and Audit (Phase 11) analyze violations and produce COMMITTED reports
4. Raw logs are ephemeral; aggregated insights are permanent

### AD-4 (D-075): Guard Hook Cannot Block (PostToolUse Limitation)

Guard.sh fires AFTER the tool call, not before. It cannot prevent the action — only detect and report.

**Rationale:**
1. Claude Code does not support PreToolUse hooks (D-031)
2. `allowed-tools` provides true prevention — tools are not available to the orchestrator
3. Guard.sh provides audit trail for Art 6.3 (invariant verification)
4. The warning injected via `hookSpecificOutput` influences the orchestrator's subsequent behavior
5. This is explicitly documented as defense-in-depth, not primary enforcement

### AD-5 (D-076): Empty Log File Initialization

Log files are created empty during bootstrap (via `moira_bootstrap_inject_hooks`), not lazily on first write. Scaffold creates directories only; bootstrap creates initial files — maintaining existing responsibility split.

**Rationale:**
1. Guard.sh appends with `>>` — file must exist or be created atomically
2. Pre-creating avoids race conditions if multiple hooks fire simultaneously
3. `wc -l` on empty file returns 0 (correct baseline for violation count)
4. Simple existence check in guard.sh: if log dir doesn't exist → not a Moira project

## Success Criteria

1. **Guard hook exists and passes syntax:** `guard.sh` is valid bash, executable
2. **Guard hook detects violations:** When fed test input with non-moira file_path, outputs `hookSpecificOutput` JSON
3. **Guard hook is silent for valid operations:** When fed test input with moira file_path, exits 0 with no output
4. **Guard hook is inactive without session:** When `current.yaml` doesn't exist, exits 0 immediately
5. **Budget tracking hook exists and passes syntax:** `budget-track.sh` is valid bash, executable
6. **Settings merge works:** `moira_settings_merge_hooks` produces valid JSON with hook entries
7. **Settings merge is idempotent:** Running twice produces same result
8. **Settings merge preserves existing hooks:** User's existing hooks are not removed
9. **E7-DRIFT is fully implemented:** `errors.md` section contains concrete detection/reporting (no "stub" marker)
10. **CLAUDE.md template has enforcement rules:** Template contains anti-rationalization rules and boundary constraints
11. **Orchestrator references violation data:** `orchestrator.md` references `violations.log` for health report
12. **Tier 1 tests pass:** All existing + new Phase 8 structural tests pass
13. **Constitutional compliance:** All 19 invariants satisfied

## Constitutional Compliance Checklist

```
ARTICLE 1: Separation of Concerns
[✓] 1.1 — Guard hook detects orchestrator violations but does not prevent
         them (prevention is by allowed-tools). Hook operates on log files
         in .moira/state/ ONLY. Never reads project source.
[✓] 1.2 — Hooks do not expand agent roles. Guard hook is infrastructure,
         not an agent. No new agent responsibilities.
[✓] 1.3 — Hooks are separate scripts, not merged into existing libraries.
         settings-merge.sh is a new focused library (one responsibility).

ARTICLE 2: Determinism
[✓] 2.1 — Hooks do not affect pipeline selection. No hook output influences
         which pipeline runs.
[✓] 2.2 — Hooks do not affect gate definitions. Hook-injected warnings
         are informational context, not gate decisions.
[✓] 2.3 — Violation detection follows explicit rules: file_path outside
         .moira/ = violation. No heuristics, no judgment.

ARTICLE 3: Transparency
[✓] 3.1 — All tool usage logged to tool-usage.log. All violations logged
         to violations.log. Full audit trail for every session.
[✓] 3.2 — Budget tracking hook provides per-tool-call data. Complements
         budget.sh estimation with runtime observation.
[✓] 3.3 — Violations reported to user via hookSpecificOutput AND health
         report at every gate. No silent failures.

ARTICLE 4: Safety
[✓] 4.1 — N/A (hooks don't generate content, only log)
[✓] 4.2 — Hook-injected warnings are informational. User is not forced
         to act on them. Gates remain user-driven.
[✓] 4.3 — Hooks don't modify files. Log files can be deleted/reset
         without consequence.
[✓] 4.4 — N/A (hooks don't interact with bypass mechanism)

ARTICLE 5: Knowledge Integrity
[✓] 5.1 — N/A (hooks don't write knowledge entries)
[✓] 5.2 — N/A (hooks don't propose rule changes)
[✓] 5.3 — N/A (hooks don't modify knowledge)

ARTICLE 6: Self-Protection
[✓] 6.1 — No code path modifies CONSTITUTION.md
[✓] 6.2 — This spec written before implementation (D-018)
[✓] 6.3 — Guard hook provides the audit trail for invariant verification.
         Tier 1 tests validate hook system artifacts.
```
