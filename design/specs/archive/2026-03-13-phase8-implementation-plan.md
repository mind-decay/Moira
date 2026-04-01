# Phase 8: Implementation Plan — Hooks & Self-Monitoring

## Chunk Dependency Graph

```
         ┌──────────────────┐
         │  Chunk 0:        │
         │  Housekeeping    │
         └────────┬─────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 1:        │
         │  Hook Scripts    │
         │  (guard + budget)│
         └────────┬─────────┘
                  │
    ┌─────────────┼──────────────┐
    │             │              │
┌───▼───┐  ┌─────▼─────┐  ┌────▼────┐
│Chunk 2│  │  Chunk 3   │  │ Chunk 4 │
│Settings│  │Orchestrator│  │ CLAUDE  │
│Merge + │  │  Wiring +  │  │ .md     │
│Bootstr.│  │  E7-DRIFT  │  │ template│
└───┬───┘  └─────┬─────┘  └────┬────┘
    │             │              │
    └─────────────┼──────────────┘
                  │
         ┌────────▼─────────┐
         │  Chunk 5:        │
         │  Tests + Install │
         └──────────────────┘
```

---

## Chunk 0: Pre-Implementation Housekeeping

**Dependencies:** None

### Task 0.1: ~~Record Phase 8 architectural decisions~~ ALREADY DONE

Decisions D-072 through D-076 (corresponding to spec AD-1 through AD-5) were recorded in `design/decisions/log.md` during spec review fixes. No action needed.

Note: D-060 through D-071 in commit `876fde2` are architecture review decisions, NOT Phase 8 decisions.

### Task 0.2: Fix design doc inaccuracies discovered during Phase 8 review

- [x] **Modify** `design/subsystems/fault-tolerance.md`
- **Key points:**
  - E7-DRIFT section says "Guard hook **blocks** prohibited tool calls" — change to "Guard hook **detects** prohibited tool calls"
  - PostToolUse hooks fire after the tool call, not before. They cannot block — only detect and report (per D-031).
- [x] **Modify** `design/architecture/overview.md`
- **Key points:**
  - Add `settings-merge.sh` to the `lib/` file list in the global layer structure
  - Optionally: add other missing libs from Phases 4-7 (knowledge.sh, rules.sh, bootstrap.sh, quality.sh, bench.sh, budget.sh)
- **Commit:** `moira(design): fix fault-tolerance.md guard hook description and update overview.md file list`

---

## Chunk 1: Hook Scripts

**Dependencies:** Chunk 0

### Task 1.1: Create guard hook script

- [x] **Create** `src/global/hooks/guard.sh`
- **Source:** Spec D1
- **Key points:**
  - Shebang: `#!/usr/bin/env bash` — NO `set -euo pipefail` (hooks must not fail)
  - Read input from stdin: `input=$(cat)`
  - Parse JSON fields using `jq` if available, fallback to grep/sed:
    - `tool_name`: extract from `"tool_name"` field
    - `file_path`: extract from `"tool_input"."file_path"` or `"tool_input"."command"` field
  - Session check: look for `.moira/state/current.yaml` — if not present, `exit 0`
  - Config check: if config.yaml exists, check `hooks.guard_enabled` — if `false`, `exit 0`
  - Log ALL tool usage: append `{ISO8601} {tool_name} {file_path}` to `state/tool-usage.log`
  - Violation check: if `tool_name` is Read/Write/Edit AND `file_path` is non-empty AND does NOT contain `.moira`:
    - Note: `self-monitoring.md` example includes Grep/Glob but we omit them — `allowed-tools` blocks them so guard.sh can't observe them (see D-072)
    - Append `{ISO8601} VIOLATION {tool_name} {file_path}` to `state/violations.log`
    - Output JSON: `{"hookSpecificOutput":{"additionalContext":"CONSTITUTIONAL VIOLATION (Art 1.1): Orchestrator used {tool_name} on {file_path}. Direct project file operations are prohibited."}}`
  - On ANY error: `exit 0` (wrapped in trap or individual error guards)
  - Mark executable in git: needs `chmod +x` in install.sh
- **Performance considerations:**
  - No `source` of any library files
  - No subshell spawns beyond necessary `jq` or `grep`
  - Date via `date -u +%Y-%m-%dT%H:%M:%SZ` (one fork)
  - State directory path: check `.moira/state/` relative to git root or home
    - Use heuristic: walk up from CWD looking for `.moira/state/current.yaml`
    - Fallback: check `$HOME/.claude/moira/state/current.yaml`
- **Commit:** `moira(hooks): create guard hook for violation detection and audit logging`

### Task 1.2: Create budget tracking hook script

- [x] **Create** `src/global/hooks/budget-track.sh`
- **Source:** Spec D2
- **Key points:**
  - Same structure as guard.sh: read stdin, parse JSON, session check, config check
  - Config check: `hooks.budget_tracking_enabled` — if `false`, `exit 0`
  - Log format: `{ISO8601} {tool_name} {file_path} {file_size_bytes}`
  - For Read/Write/Edit calls with `file_path`: get file size via `wc -c < "$file_path" 2>/dev/null || echo 0`
  - For Agent calls: log `agent` as file_path, `0` as size
  - For other tools: log the first relevant parameter, `0` as size
  - Append to `state/budget-tool-usage.log`
  - Same error handling as guard.sh: `exit 0` on any failure
  - Same performance constraints: no library sourcing, minimal forks
- **Commit:** `moira(hooks): create budget tracking hook for per-tool-call logging`

### Task 1.3: Remove `.gitkeep` from hooks directory

- [x] **Delete** `src/global/hooks/.gitkeep`
- **Key points:**
  - With actual hook files now in the directory, `.gitkeep` is no longer needed
  - `git rm src/global/hooks/.gitkeep`
- **Commit:** (combine with Task 1.2 commit)

---

## Chunk 2: Settings Merge + Bootstrap Integration

**Dependencies:** Chunk 1 (hook scripts exist)

### Task 2.1: Create settings merge library

- [x] **Create** `src/global/lib/settings-merge.sh`
- **Source:** Spec D3
- **Key points:**
  - Preamble: `#!/usr/bin/env bash`, `set -euo pipefail`
  - No Moira library dependencies (does not source yaml-utils.sh or others)
  - Two public functions:
    - `moira_settings_merge_hooks <project_root> <moira_home>`
    - `moira_settings_remove_hooks <project_root>`

  - **`moira_settings_merge_hooks` logic:**
    - `settings_file="$project_root/.claude/settings.json"`
    - `mkdir -p "$project_root/.claude"`
    - If `jq` is available (`command -v jq`): use jq path
    - Else: use fallback path

  - **jq path:**
    - If file doesn't exist: write Moira hooks JSON directly
    - If file exists: read existing JSON
      - Check if Moira guard hook already registered: `jq '.hooks.PostToolUse[]?.hooks[]? | select(.command | contains("moira/hooks/guard.sh"))' < settings`
      - If not found: merge using `jq`:
        ```
        jq '.hooks.PostToolUse = (.hooks.PostToolUse // []) + [{moira_entry}]'
        ```
        But must be more careful — need to add to existing matcher's hooks array or create new matcher entry
      - Actually simpler approach: Moira adds ONE matcher entry with BOTH hooks. Check if any matcher contains `moira/hooks/guard.sh`. If not, append the entire matcher block.
    - Write result atomically (write to temp file, mv)

  - **Fallback path (no jq):**
    - If file doesn't exist or is empty: write complete JSON with hooks
    - If file exists and already contains `moira/hooks/guard.sh`: skip (idempotent)
    - If file exists but no Moira hooks:
      - If file contains `"PostToolUse"`: warn user "Cannot safely merge — please add manually" + provide the JSON snippet
      - If file does NOT contain `"PostToolUse"`: simple insertion before the final `}`
    - This covers ~90% of cases. The remaining 10% (complex settings.json without jq) gets a clear manual instruction.

  - **`moira_settings_remove_hooks` logic:**
    - If `jq` available: filter out entries containing `moira/hooks/`
    - If no `jq`: warn user "Cannot safely remove — please edit manually"

- **Commit:** `moira(hooks): create settings.json merge library`

### Task 2.2: Update bootstrap.sh for hook injection

- [x] **Modify** `src/global/lib/bootstrap.sh`
- **Source:** Spec D4a
- **Key points:**
  - Add new function `moira_bootstrap_inject_hooks`:
    ```bash
    moira_bootstrap_inject_hooks() {
      local project_root="$1"
      local moira_home="$2"

      local lib_dir
      lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

      if [[ -f "$lib_dir/settings-merge.sh" ]]; then
        source "$lib_dir/settings-merge.sh"
        # Guard: verify function exists after source (catches syntax errors in settings-merge.sh)
        if declare -f moira_settings_merge_hooks &>/dev/null; then
          if moira_settings_merge_hooks "$project_root" "$moira_home"; then
            echo "Hooks configured in .claude/settings.json"
          else
            echo "Warning: Hook injection failed — configure manually" >&2
            echo "See: ~/.claude/moira/hooks/ for hook scripts" >&2
          fi
        else
          echo "Warning: settings-merge.sh loaded but function not found" >&2
        fi
      fi

      # Create empty log files (D-076: pre-create during bootstrap, not scaffold)
      local state_dir="$project_root/.moira/state"
      if [[ -d "$state_dir" ]]; then
        touch "$state_dir/violations.log" "$state_dir/tool-usage.log" "$state_dir/budget-tool-usage.log"
      fi
    }
    ```
  - This function is called by the init command flow (init.md dispatches agents that call bootstrap functions)
  - The function is additive — does not break existing bootstrap flow
  - Error handling: failure to inject hooks does NOT fail init
  - Log file creation here (not in scaffold.sh) — scaffold is responsible for directories ONLY per its documented contract
  - **Also update `moira_bootstrap_setup_gitignore`** — add entries for the 3 new log files:
    ```bash
    # Add to the entries array in moira_bootstrap_setup_gitignore:
    ".moira/state/violations.log"
    ".moira/state/tool-usage.log"
    ".moira/state/budget-tool-usage.log"
    ```
    These are per-developer ephemeral data (D-074) and must not be committed.
- **Commit:** `moira(hooks): integrate hook injection into bootstrap flow`

### Task 2.3: Update init.md command for hook injection step

- [x] **Modify** `src/commands/moira/init.md`
- **Source:** Spec D4b
- **Key points:**
  - The init command currently follows steps from distribution.md
  - Current init.md steps: 1-7 (Check → Check Existing → Scaffold → Scanners → Config → Knowledge → CLAUDE.md), Step 8 (Gitignore), Step 9 (Review Gate), Step 10 (Onboarding)
  - Insert hook injection as **new Step 9**, renumber Review Gate to **Step 10** and Onboarding to **Step 11**:
    - "Step 9: Configure hooks in `.claude/settings.json`"
    - "Call `moira_bootstrap_inject_hooks` to register guard and budget-track hooks"
    - "If hook injection fails: display warning but continue initialization"
  - Update `--force` mode section at the end: "Steps 7-8" reference becomes "Steps 7-9" (CLAUDE.md, gitignore, hooks re-injected)
  - Add hook status to the init gate summary display (now in Step 10):
    ```
    Configured:
    ├─ ...existing items...
    └─ Hooks: guard.sh + budget-track.sh registered
    ```
  - Note: init.md is a command stub that provides instructions to the orchestrator/agent. The actual function call happens in the agent context.
- **Commit:** `moira(hooks): add hook injection step to init command`

---

## Chunk 3: Orchestrator Wiring + E7-DRIFT

**Dependencies:** Chunk 1 (hook scripts exist, log format defined)

### Task 3.1: Replace E7-DRIFT stub in errors.md

- [x] **Modify** `src/global/skills/errors.md`
- **Source:** Spec D5
- **Key points:**
  - Replace the current E7-DRIFT section (lines 358-373) entirely
  - Remove "Phase 3 stub per D-038" marker
  - New section structure (consistent with all other E* sections):
    - **Detection:** Guard hook detects violations in real-time via PostToolUse
    - **During Pipeline:** violation logged, warning injected, orchestrator must acknowledge, include in health report
    - **Post-Task Audit:** count violations from `violations.log`, include in completion summary, log in telemetry
    - **Display:** updated health report with violations highlighted when > 0
    - **State Updates:** `violations.log` appended by guard.sh; `tool-usage.log` appended per call; `telemetry.yaml compliance.orchestrator_violation_count` at completion
    - **Recovery:** No automated recovery — informational. `allowed-tools` provides prevention. References Phase 10 (Reflector) and Phase 11 (Audit) for pattern analysis.
    - **Escalation:** No automated escalation — informational. If violations > 3: recommend rule strengthening. Reflector (Phase 10) analyzes patterns.
- **Commit:** `moira(hooks): implement full E7-DRIFT handler with guard hook integration`

### Task 3.2: Update orchestrator.md for violation data integration

- [x] **Modify** `src/global/skills/orchestrator.md`
- **Source:** Spec D7a
- **Key points:**
  - **Section 1 (Identity and Boundaries):** Update the enforcement note:
    - Change: "PostToolUse `guard.sh` (Phase 8) provides audit logging"
    - To: "PostToolUse `guard.sh` provides audit logging and violation detection"
    - (Remove "Phase 8" reference since Phase 8 is now implemented)
  - **Section 6 (Budget Monitoring):** Add violation monitoring subsection:
    - After "Budget Monitoring After Each Agent" add:
    - "### Violation Monitoring"
    - "After each agent returns:"
    - "1. Check for violation warnings in context (guard.sh injects via hookSpecificOutput)"
    - "2. Read violation count: use Read tool on `.moira/state/violations.log`, count lines (0 if file empty or missing). The orchestrator CAN read `.moira/` files — this is within its allowed scope."
    - "3. Include violation count in health report at every gate"
    - "4. If violation count > 0: add 🔴 indicator in health report"
  - **Section 7 (Completion Flow):** In the `done` action:
    - After budget report display, add:
    - "Check `state/violations.log` line count. If > 0: include violation count in completion summary ('{N} orchestrator violations detected')."
    - "Write violation count to telemetry.yaml `compliance.orchestrator_violation_count` field."
- **Commit:** `moira(hooks): wire violation monitoring into orchestrator flow`

### Task 3.3: Update gates.md health report data source documentation

- [x] **Modify** `src/global/skills/gates.md`
- **Source:** Spec D7b
- **Key points:**
  - In the Health Report Section, add data source clarification after the template:
    ```
    Data sources:
    - Context: from `current.yaml` → `context_budget.orchestrator_percent` (updated by moira_budget_orchestrator_check)
    - Violations: line count of `.moira/state/violations.log` (0 if file doesn't exist or is empty)
    - Agents dispatched: count of entries in `current.yaml` → `history[]`
    - Gates passed: count of entries in task's `status.yaml` → `gates[]`
    - Retries: sum of `status.yaml` → `retries.total`
    - Progress: current step index / total steps from pipeline definition
    ```
  - This is documentation for the orchestrator — tells it WHERE to read each field
- **Commit:** `moira(hooks): document health report data sources in gates skill`

---

## Chunk 4: CLAUDE.md Template + Scaffold Updates

**Dependencies:** Chunk 1 (hook scripts exist, log files defined)

### Task 4.1: Update project CLAUDE.md template with enforcement rules

- [x] **Modify** `src/global/templates/project-claude-md.tmpl`
- **Source:** Spec D6a
- **Key points:**
  - Read current template content first
  - **Merge strategy: REPLACE** the existing "### Orchestrator Rules (Inviolable)" section (lines 17-22 of current template) with the expanded version below. The new section is a superset — do NOT add alongside the existing one.
  - The replacement section stays INSIDE the `<!-- moira:start -->` / `<!-- moira:end -->` markers
  - The section should come AFTER the general Moira description and BEFORE `<!-- moira:end -->`
  - Content (adapted from self-monitoring.md and orchestrator.md Section 1):
    ```markdown
    ## Moira — Orchestrator Boundaries

    When executing through the Moira pipeline (/moira:task):

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
  - This mirrors `orchestrator.md` Section 1 — intentional redundancy for defense-in-depth (Layer 3)
  - Do NOT duplicate content that's already in the template — check what exists first
- **Commit:** `moira(hooks): add orchestrator enforcement rules to CLAUDE.md template`

### Task 4.2: ~~Update scaffold.sh for log file initialization~~ MOVED to Task 2.2

Log file creation moved to `moira_bootstrap_inject_hooks` in `bootstrap.sh` (Task 2.2). `scaffold.sh` is responsible for directory creation ONLY per its documented contract (`scaffold.sh` lines 5-7). No changes to `scaffold.sh` needed.

---

## Chunk 5: Tests + Install

**Dependencies:** Chunks 1-4 (all implementations complete)

### Task 5.1: Create Tier 1 hooks system tests

- [x] **Create** `src/tests/tier1/test-hooks-system.sh`
- **Source:** Spec D8
- **Key points:**
  - Follow existing test file pattern (source test-helpers.sh, use pass/fail functions)

  - **Guard hook tests:**
    - `guard.sh` exists in hooks/ directory
    - `guard.sh` has valid bash syntax (`bash -n`)
    - `guard.sh` contains `hookSpecificOutput` string (violation output mechanism)
    - `guard.sh` contains `CONSTITUTIONAL VIOLATION` string (must be exact — just `VIOLATION` would false-match on `violations.log` filename)
    - `guard.sh` contains `violations.log` string (log file reference)
    - `guard.sh` contains `tool-usage.log` string (audit log reference)
    - `guard.sh` contains `current.yaml` string (session detection)

  - **Budget tracking hook tests:**
    - `budget-track.sh` exists in hooks/ directory
    - `budget-track.sh` has valid bash syntax
    - `budget-track.sh` contains `budget-tool-usage.log` string
    - `budget-track.sh` contains `current.yaml` string

  - **Settings merge tests:**
    - `settings-merge.sh` exists in lib/ directory
    - `settings-merge.sh` has valid bash syntax
    - Source `settings-merge.sh` and check: `moira_settings_merge_hooks` function exists (via `declare -f`)
    - Source `settings-merge.sh` and check: `moira_settings_remove_hooks` function exists

  - **Integration tests:**
    - `orchestrator.md` contains "guard" or "violations.log" (Layer 2 reference)
    - `errors.md` E7-DRIFT section does NOT contain "stub" (stub replaced)
    - `project-claude-md.tmpl` contains "ORCHESTRATOR" and "NEVER" (Layer 3)
    - `project-claude-md.tmpl` contains "rationalization" (anti-rationalization rules)
    - `config.schema.yaml` contains `hooks.guard_enabled`
    - `config.schema.yaml` contains `hooks.budget_tracking_enabled`

  - **Hook functional tests (basic):**
    - Run `guard.sh` with empty stdin and no state directory → exits 0 (non-Moira session)
    - Run `budget-track.sh` with empty stdin and no state directory → exits 0

    Test setup for functional tests:
    ```bash
    echo "" | bash "$MOIRA_HOME/hooks/guard.sh"
    # Should exit 0 without error
    ```

  - Total: ~20+ test assertions
- **Commit:** `moira(hooks): add Tier 1 hooks system tests`

### Task 5.2: ~~Update run-all.sh~~ NOT NEEDED

`run-all.sh` uses a glob pattern `test-*.sh` to auto-discover all test files (line 19). Naming the new file `test-hooks-system.sh` is sufficient — no changes to `run-all.sh` required. Verify by running tests after Task 5.1.

### Task 5.3: Update install.sh for Phase 8 artifacts

- [x] **Modify** `src/install.sh`
- **Source:** Spec D9
- **Key points:**
  - **Hook copy:** The existing line `cp -f "$SCRIPT_DIR/global/hooks/"* "$MOIRA_HOME/hooks/" 2>/dev/null || true` already copies hooks — but with `.gitkeep` removed and actual scripts present, verify it works:
    - Guard: `ls "$SCRIPT_DIR/global/hooks/"*.sh` should find `guard.sh` and `budget-track.sh`
    - The glob `*` includes `.sh` files ✅
  - **Executable permission:** After the hook copy block, ensure:
    ```bash
    chmod +x "$MOIRA_HOME/hooks/"*.sh 2>/dev/null || true
    ```
    - Check: the existing install.sh has NO `chmod +x` for hooks — this needs to be added
  - **Lib copy:** `settings-merge.sh` is already covered by the existing `cp -f "$SCRIPT_DIR/global/lib/"*.sh "$MOIRA_HOME/lib/"` glob ✅
  - **Verification additions:**
    - Add `settings-merge.sh` to the lib_file verification loop (check if it's already there — likely not since it's new)
    - Actually: the loop already uses a static list. Add `settings-merge.sh` to the list:
      ```bash
      # Current list (Phase 7): state.sh yaml-utils.sh scaffold.sh task-id.sh knowledge.sh rules.sh bootstrap.sh quality.sh bench.sh budget.sh
      # Phase 8 adds: settings-merge.sh
      for lib_file in state.sh yaml-utils.sh scaffold.sh task-id.sh knowledge.sh rules.sh bootstrap.sh quality.sh bench.sh budget.sh settings-merge.sh; do
      ```
    - Add hook file verification:
      ```bash
      # Check: hook files exist and are executable
      for hook_file in guard.sh budget-track.sh; do
        ((checks_total++))
        local hook_path="$MOIRA_HOME/hooks/$hook_file"
        if [[ -f "$hook_path" && -x "$hook_path" ]]; then
          if bash -n "$hook_path" 2>/dev/null; then
            ((checks_passed++))
          else
            errors+="  hooks/$hook_file has syntax errors\n"
          fi
        else
          errors+="  hooks/$hook_file not found or not executable\n"
        fi
      done
      ```
- **Commit:** `moira(hooks): update install and verification for Phase 8 artifacts`

### Task 5.4: Update existing test files for Phase 8

- [x] **Modify** `src/tests/tier1/test-file-structure.sh`
- **Source:** Spec D8 (extended existing tests)
- **Key points:**
  - Add check: `guard.sh` exists in hooks/
  - Add check: `budget-track.sh` exists in hooks/
  - Add check: `settings-merge.sh` exists in lib/
- [x] **Modify** `src/tests/tier1/test-bootstrap.sh`
- **Key points:**
  - Add `moira_bootstrap_inject_hooks` to the function existence check loop (lines 47-49) alongside existing `moira_bootstrap_*` functions
- [x] **Verify** `src/tests/tier1/test-install.sh` — confirm Phase 8 artifacts are covered
- **Commit:** `moira(hooks): extend file structure and bootstrap tests for Phase 8 artifacts`

---

## Summary

| Chunk | Tasks | Creates | Modifies | Depends On |
|-------|-------|---------|----------|------------|
| 0 | 1 (0.1 done) | — | fault-tolerance.md, overview.md | None |
| 1 | 3 | guard.sh, budget-track.sh | — (deletes .gitkeep) | 0 |
| 2 | 3 | settings-merge.sh | bootstrap.sh (+ log file creation + gitignore entries), init.md | 1 |
| 3 | 3 | — | errors.md, orchestrator.md, gates.md | 1 |
| 4 | 1 | — | project-claude-md.tmpl | 1 |
| 5 | 3 | test-hooks-system.sh | install.sh, test-file-structure.sh, test-bootstrap.sh | 1-4 |

**Total:** 6 chunks, 14 active tasks (Task 0.1 done, Task 4.2 moved to 2.2, Task 5.2 removed)

**Parallelism:** Chunks 2, 3, and 4 can run in parallel after Chunk 1 completes. They have no cross-dependencies.

**Risk assessment:** YELLOW — all changes are additive to existing code (new scripts, new library, updates to existing skills). No pipeline gates changed. No agent role boundaries changed. Primary risks:
- **Task 2.1 (settings-merge.sh):** JSON manipulation in bash is inherently fragile. The jq/fallback approach mitigates this but needs careful testing.
- **Task 2.2 (bootstrap.sh):** Now also creates log files — `declare -f` guard and defensive `[[ -d ]]` check mitigate source failures.
- **Task 3.1 (E7-DRIFT):** Replacing a stub — must include all standard E* sections (Detection through Escalation).
- **Task 5.3 (install.sh):** Adding to the verification loop — must match the existing pattern exactly.
