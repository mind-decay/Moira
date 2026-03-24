# Security Surface Scan — Moira

Scan date: 2026-03-24
Prior scan: 2026-03-22
Scope: All shell libraries, hooks, install scripts, commands, configuration files, schemas, git hooks
Files examined: ~50

---

## 1. Hardcoded Secrets

**No hardcoded secrets found.** No API keys, tokens, passwords, or connection strings are present in any source file.

- `src/global/core/rules/base.yaml` (INV-006) explicitly prohibits committing secrets or credentials as an inviolable rule.
- Scanner templates (`src/global/templates/scanners/deep/deep-security-scan.md`, line 20; `src/global/templates/scanners/tech-scan.md`) include instructions to never read `.env` files.
- No `.env` files exist in the repository.
- `.githooks/pre-commit` (line 61-67) checks staged files for patterns matching `api[_-]?key|secret|password|token|credential` and blocks commits.

---

## 2. Input Validation Gaps

### 2a. Guard hook path matching uses substring match, not prefix match

- **File:** `src/global/hooks/guard.sh`, lines 75, 89
- **Observation:** The guard hook checks `$file_path != *".claude/moira"*` using a glob substring match. A path containing the substring `.claude/moira` anywhere (not necessarily as a prefix of the canonical path) would bypass the guard.
- **Evidence:** Line 75: `if [[ -n "$file_path" && "$file_path" != *".claude/moira"* && "$file_path" != *".ariadne/"* ]]; then`

### 2b. Guard hook can be disabled via config

- **File:** `src/global/hooks/guard.sh`, lines 53-61
- **Observation:** If `config.yaml` contains `guard_enabled` followed by (or containing) the string `false`, the guard hook silently exits. The check uses substring matching: `if [[ "$guard_val" == *"false"* ]]; then`.
- **Evidence:** An LLM orchestrator with Write access to `.claude/moira/config.yaml` could set `guard_enabled: false` to disable violation detection. The guard hook is the sole runtime enforcement boundary (see 3a).

### 2c. Budget tracking hook can be similarly disabled

- **File:** `src/global/hooks/budget-track.sh`, lines 44-49
- **Observation:** Same pattern as the guard hook — `budget_tracking_enabled: false` in config disables budget tracking.

### 2d. No validation of task descriptions

- **File:** `src/commands/moira/task.md`, lines 42-55
- **Observation:** Task descriptions from user input are written directly to `input.md` and `status.yaml` without sanitization. Since these are YAML/markdown files consumed by LLM agents (not executed), this is low-severity but noted for completeness.

### 2e. YAML key matching uses regex without anchoring

- **File:** `src/global/lib/yaml-utils.sh`, lines 67-79 and 93-105
- **Observation:** The awk patterns use `line ~ "^" p1 ":"` which constructs a regex from user-supplied key names. Key names containing regex metacharacters (`.`, `*`, `+`, etc.) could match unintended keys. All current callers use safe literal key names, but the interface does not sanitize inputs.

### 2f. sed replacement in yaml_set uses user values in replacement string

- **File:** `src/global/lib/yaml-utils.sh` (yaml_set function)
- **Observation:** `sed -E "s|^(${p1}:)[[:space:]].*|\1 ${yaml_value}|"` — the `yaml_value` is interpolated into a sed replacement string. Values containing `|` (the sed delimiter) or `&` or `\` could produce unexpected results. The yaml_value quoting logic adds quotes for values containing special YAML chars, which partially mitigates this.

### 2g. Frontmatter parser uses unsanitized field names as regex

- **File:** `src/global/lib/bootstrap.sh`, lines 50, 90
- **Observation:** `_moira_parse_frontmatter` uses `[[ "$line" =~ ^${field}:[[:space:]]+(.*) ]]` where `$field` is interpolated directly into the regex. All current callers pass safe literal field names, but the interface does not sanitize inputs.

### 2h. State transition validation allows backward transitions with only a log note

- **File:** `src/global/lib/state.sh`, lines 125-127
- **Observation:** When `moira_state_transition()` detects a backward pipeline transition (new step index < current step index), it emits a note to stderr but does not block the transition. This is by design (for rearchitect/retry flows), but there is no validation that the caller is legitimately in a rearchitect/retry flow.

---

## 3. Auth Middleware Coverage

### 3a. Guard hook is the sole enforcement boundary

- **File:** `src/global/hooks/guard.sh`
- **Observation:** The guard hook is the only runtime enforcement of Art 1.1 (orchestrator must not directly access project files). It runs as a PostToolUse hook on Read/Write/Edit operations. It logs violations and injects context warnings but does not block the operation.
- **Evidence:** Line 84: outputs JSON with `additionalContext` warning but always exits 0. There is no mechanism to reject or undo the tool call.

### 3b. Grep and Glob are not monitored by guard hook

- **File:** `src/global/hooks/guard.sh`, line 70
- **Observation:** Comment on line 70 states: "D-072: Grep/Glob blocked by allowed-tools, unobservable here." The guard hook only checks Read, Write, and Edit. Grep and Glob violations rely entirely on the `allowed-tools` frontmatter in command files.
- **Evidence:** The `task.md` allowed-tools list (lines 6-11) includes Agent, Read, Write, TaskCreate, TaskUpdate, TaskList but not Grep or Glob. However, the `.claude/CLAUDE.md` orchestrator boundary section is a prompt-level control, not a system-enforced one.

### 3c. Knowledge access matrix is prompt-enforced, not system-enforced

- **File:** `src/global/core/knowledge-access-matrix.yaml`
- **Observation:** The access matrix defines which agents can read/write which knowledge types at which levels. Enforcement depends on the orchestrator skill correctly assembling agent instructions per the matrix. There is no runtime enforcement preventing an agent from reading files outside its authorized scope.

### 3d. Bypass command has strict confirmation gate

- **File:** `src/commands/moira/bypass.md`, lines 46-54
- **Observation:** The bypass command requires the user to enter exactly "2" to confirm. Natural language confirmations are explicitly rejected. This is a well-designed anti-manipulation gate, but it is prompt-enforced rather than system-enforced.

### 3e. Hook matcher applies to all tools, not just Moira sessions

- **File:** `.claude/settings.json`
- **Observation:** The PostToolUse hooks use `"matcher": ""` (empty string), which matches all tool calls in all sessions, not just Moira sessions. The hooks are designed to be safe (exit 0 on any error, fast path when no current.yaml found) but execute on every tool call across all projects in this Claude Code instance.

### 3f. Init command has broader tool access than task command

- **File:** `src/commands/moira/init.md`, lines 5-9
- **Observation:** The init command's `allowed-tools` includes `Bash` in addition to Agent, Read, and Write. This is by design (it needs to run scaffold.sh, bootstrap.sh, etc.), but it creates a broader attack surface during initialization than during normal task execution.

### 3g. Pre-commit hook not installed in .git/hooks

- **File:** `.git/hooks/pre-commit` — not present
- **Observation:** The `.githooks/pre-commit` script exists in the repository source but is not installed at `.git/hooks/pre-commit`. The `src/global/hooks/pre-commit.sh` (constitutional verification hook) is also not installed. The pre-commit checks documented in the codebase are not active for this project's git operations.
- **Evidence:** `ls .git/hooks/pre-commit` returns "No pre-commit hook installed". The `.githooks/` directory contains the hook file but Git must be configured to use it (e.g., via `core.hooksPath`).

---

## 4. Unsafe Patterns

### 4a. Temporary files created without restrictive permissions

- **Files:** `src/global/lib/yaml-utils.sh`, `src/global/lib/knowledge.sh`, `src/global/lib/settings-merge.sh`, `src/global/lib/bootstrap.sh`, `src/global/lib/reflection.sh`, `src/global/lib/judge.sh`
- **Observation:** All temp files use `mktemp` (which creates files with 0600 on most systems), then `mv` to overwrite the target. This is a standard safe pattern. However, the temp files are in the default system temp directory, which on macOS is typically `/var/folders/...` with per-user isolation.

### 4b. remote-install.sh pipes from curl to bash

- **File:** `src/remote-install.sh`, line 3
- **Observation:** The documented usage is `curl -fsSL ... | bash`. This is a common install pattern but inherently trusts the remote source. The script itself clones the repo and delegates to `install.sh`, which is a mitigating factor (the cloned repo can be inspected before install runs, but the pipe pattern does not allow this).

### 4c. install.sh sources external scripts during execution

- **File:** `src/install.sh`, lines 54, 185, 495
- **Observation:** `install.sh` sources `scaffold.sh`, `settings-merge.sh`, and `upgrade.sh` from the same directory. Since these come from the same repo checkout, this is expected behavior, but the `source` calls do not verify file integrity.

### 4d. Hook scripts read from stdin without size limits

- **Files:** `src/global/hooks/guard.sh` (line 8), `src/global/hooks/budget-track.sh` (line 8)
- **Observation:** Both hooks read all of stdin with `input=$(cat 2>/dev/null)`. If Claude provides extremely large tool input JSON, these hooks will consume it entirely into a shell variable. Both hooks are designed to be fast and never fail (exit 0 on any error), which limits the blast radius.

### 4e. bench.sh uses eval on reset_command from fixture YAML

- **File:** `src/global/lib/bench.sh`, line 66
- **Observation:** `(cd "$fixture_dir" && eval "$reset_cmd" 2>/dev/null) || true` — the `reset_cmd` value is read from `.moira-fixture.yaml` via `moira_yaml_get`. The eval executes arbitrary shell commands from the fixture YAML. Fixture files are part of the Moira repository (not user-supplied), and eval runs in a subshell. However, if a malicious fixture YAML were introduced, it could execute arbitrary commands.

### 4f. test-pipeline-graph.sh uses eval for variable indirection

- **File:** `src/tests/tier1/test-pipeline-graph.sh`, line 288
- **Observation:** `eval "required_gates_csv=\$REQUIRED_GATES_${pipeline}"` — uses eval for variable indirection. The `$pipeline` value is derived from pipeline YAML filenames in the Moira codebase. In tests only, not production code.

### 4g. Indirect variable expansion in budget.sh and knowledge.sh

- **Files:** `src/global/lib/budget.sh` (line 66), `src/global/lib/knowledge.sh` (line 212)
- **Observation:** Both use `${!var_name}` for indirect variable expansion. In budget.sh, `var_name` is constructed from agent role names; in knowledge.sh, from knowledge type names. Both are derived from YAML keys in Moira's own configuration files, not from external input.

### 4h. Pre-commit hook uses -P (PCRE) flag

- **File:** `.githooks/pre-commit`, lines 27, 63
- **Observation:** The pre-commit hook uses `grep -oP` for Perl-compatible regex. The macOS built-in grep does not support `-P`. If `core.hooksPath` is set to `.githooks/`, the pre-commit hook would fail on macOS without GNU grep installed. The `src/global/hooks/pre-commit.sh` (a separate hook) does not use `-P`.

---

## 5. Sensitive Data Handling

### 5a. Tool usage logs contain file paths

- **File:** `src/global/hooks/guard.sh`, line 67
- **Observation:** `tool-usage.log` records timestamps, tool names, and file paths for every tool call. `violations.log` records the same for violations. These logs are in `.claude/moira/state/` which is gitignored. File paths could reveal project structure to anyone with access to the state directory.
- **Evidence:** `.gitignore` entry: `.claude/moira/state/`

### 5b. Task descriptions stored in plaintext

- **File:** `src/commands/moira/task.md`, lines 42-55
- **Observation:** User task descriptions are written verbatim to `input.md` and the first 100 characters to `status.yaml`. These are in per-task directories under `.claude/moira/state/tasks/` which is gitignored.

### 5c. Bypass log records file changes

- **File:** `src/commands/moira/bypass.md`, lines 92-102
- **Observation:** The bypass log at `.claude/moira/state/bypass-log.yaml` records timestamps, task descriptions, and lists of changed files. This file is gitignored (via the `state/` parent directory exclusion).

### 5d. .gitignore covers state but not all Moira runtime data

- **File:** `.gitignore`, lines 15-26
- **Observation:** The `.gitignore` excludes `.claude/moira/state/` and `*.log`. However, `.claude/moira/config.yaml`, `.claude/moira/config/budgets.yaml`, `.claude/moira/config/mcp-registry.yaml`, and `.claude/moira/knowledge/` are NOT gitignored. Knowledge files may contain project-specific information derived from scans. The MCP registry reveals which external services are configured.
- **Evidence:** `.claude/moira/config.yaml` contains `project.root: "/Users/minddecay/Documents/Projects/Moira"` — an absolute path that reveals the developer's username and directory structure.

### 5e. Config.yaml contains absolute filesystem paths

- **File:** `.claude/moira/config.yaml`, line 5
- **Observation:** `root: "/Users/minddecay/Documents/Projects/Moira"` — the project root path is stored as an absolute path in a file that is not gitignored. This reveals the developer's username and directory structure to anyone with repository access.

### 5f. .mcp.json contains absolute filesystem paths

- **File:** `.mcp.json`, line 8
- **Observation:** `"--project", "/Users/minddecay/Documents/Projects/Moira"` — the Ariadne MCP server configuration contains the absolute project root path. This file is tracked in git.

### 5g. Global settings.json contains absolute paths

- **File:** `~/.claude/settings.json`
- **Observation:** The statusLine command references the absolute path `/Users/minddecay/.claude/moira/statusline/context-status.sh`. This is a per-user file and not committed to any repository.

---

## 6. Configuration Security

### 6a. Global settings allow dangerous mode without prompts

- **File:** `~/.claude/settings.json`
- **Observation:** `"skipDangerousModePermissionPrompt": true` is set in the global Claude settings. This means Claude Code will not prompt for confirmation when performing potentially dangerous operations. This is a user-level setting, not set by Moira.

### 6b. Hook empty matcher matches all tools globally

- **File:** `.claude/settings.json`
- **Observation:** The PostToolUse hook matcher is `""` (empty string). Both guard.sh and budget-track.sh execute on every tool call in any Claude Code session using this project. The hooks find Moira state by walking up from CWD, and exit early (exit 0) if no state is found. This means the hooks fire but have no effect in non-Moira sessions.

### 6c. Log rotation archive path is configurable

- **File:** `src/global/lib/log-rotation.sh`, lines 23-31
- **Observation:** The `archive_dir` config value from `config.yaml` is used to construct an archive path relative to the Moira directory. There is no path traversal validation on the `archive_dir` value. A value like `../../` could write archives outside the expected location.

---

## Summary

| Category | Count | Severity |
|---|---|---|
| Hardcoded secrets | 0 | N/A |
| Input validation gaps | 8 | Low to Medium |
| Auth gaps (prompt-enforced only) | 7 | Medium (by design) |
| Unsafe patterns | 8 | Low |
| Sensitive data exposure | 7 | Low |
| Configuration security | 3 | Low to Medium |

The system's security model is primarily prompt-enforced (LLM instruction compliance) rather than system-enforced (hard technical controls). The guard hook provides detection and logging but not prevention. This is consistent with the system's architecture as a meta-orchestration layer for Claude Code, where the LLM itself is both the enforcement target and the execution engine.

### Changes Since Prior Scan (2026-03-22)

New findings in this scan:

- **2g**: Frontmatter parser regex injection surface (bootstrap.sh)
- **2h**: Backward state transitions allowed without caller validation (state.sh)
- **3e**: Hook matcher scope (all sessions, not just Moira)
- **3f**: Init command has broader tool access than task command
- **3g**: Pre-commit hook not installed in .git/hooks
- **4e**: bench.sh eval on fixture YAML reset_command
- **4f**: test eval for variable indirection
- **4g**: Indirect variable expansion in budget.sh and knowledge.sh
- **4h**: Pre-commit hook uses macOS-incompatible grep -P flag
- **5e**: config.yaml absolute path exposure
- **5f**: .mcp.json absolute path exposure
- **5g**: Global settings absolute path exposure
- **6a**: skipDangerousModePermissionPrompt enabled
- **6b**: Hook empty matcher scope
- **6c**: Log rotation archive path traversal
