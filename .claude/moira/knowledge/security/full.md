# Security Surface Scan — Moira

Scan date: 2026-03-22
Scope: All shell libraries, hooks, install scripts, commands, configuration files, schemas
Files examined: ~45

---

## 1. Hardcoded Secrets

**No hardcoded secrets found.** No API keys, tokens, passwords, or connection strings are present in any source file.

- `src/global/core/rules/base.yaml` (INV-006) explicitly prohibits committing secrets or credentials as an inviolable rule.
- Scanner templates (`src/global/templates/scanners/deep/deep-security-scan.md`, line 99; `src/global/templates/scanners/tech-scan.md`, line 32) include instructions to never read `.env` files.
- No `.env` files exist in the repository.

---

## 2. Input Validation Gaps

### 2a. Guard hook path matching uses substring match, not prefix match

- **File:** `src/global/hooks/guard.sh`, lines 69-86
- **Observation:** The guard hook checks `$file_path != *".claude/moira"*` using a glob substring match. A path like `/tmp/evil/.claude/moira/../../etc/passwd` would pass the guard check because it contains the substring `.claude/moira`.
- **Evidence:** Line 69: `if [[ -n "$file_path" && "$file_path" != *".claude/moira"* && "$file_path" != *".ariadne/"* ]]; then`

### 2b. Guard hook can be disabled via config

- **File:** `src/global/hooks/guard.sh`, lines 46-55
- **Observation:** If `config.yaml` contains `guard_enabled: false` (or any line where `guard_enabled` and `false` appear on the same line), the guard hook silently exits. The check uses substring matching on the line content: `if [[ "$guard_val" == *"false"* ]]; then`.
- **Evidence:** An LLM orchestrator with Write access to `.claude/moira/config.yaml` could set `guard_enabled: false` to disable violation detection.

### 2c. Budget tracking hook can be similarly disabled

- **File:** `src/global/hooks/budget-track.sh`, lines 42-49
- **Observation:** Same pattern as the guard hook — `budget_tracking_enabled: false` in config disables budget tracking.

### 2d. No validation of task descriptions

- **File:** `src/commands/moira/task.md`, lines 20-27
- **Observation:** Task descriptions from user input are written directly to `input.md` and `status.yaml` without sanitization. Since these are YAML/markdown files consumed by LLM agents (not executed), this is low-severity but noted for completeness.

### 2e. YAML key matching uses regex without anchoring

- **File:** `src/global/lib/yaml-utils.sh`, lines 67-79 and 93-105
- **Observation:** The awk patterns use `line ~ "^" p1 ":"` which constructs a regex from user-supplied key names. Key names containing regex metacharacters (`.`, `*`, `+`, etc.) could match unintended keys. All current callers use safe literal key names, but the interface does not sanitize inputs.

### 2f. sed replacement in yaml_set uses user values in replacement string

- **File:** `src/global/lib/yaml-utils.sh`, line 186
- **Observation:** `sed -E "s|^(${p1}:)[[:space:]].*|\1 ${yaml_value}|"` — the `yaml_value` is interpolated into a sed replacement string. Values containing `|` (the sed delimiter) or `&` or `\` could produce unexpected results. The yaml_value quoting logic (lines 162-177) adds quotes for values containing special YAML chars, which partially mitigates this.

---

## 3. Auth Middleware Coverage

### 3a. Guard hook is the sole enforcement boundary

- **File:** `src/global/hooks/guard.sh`
- **Observation:** The guard hook is the only runtime enforcement of Art 1.1 (orchestrator must not directly access project files). It runs as a PostToolUse hook on Read/Write/Edit operations. It logs violations and injects context warnings but does not block the operation.
- **Evidence:** Line 74: outputs JSON with `additionalContext` warning but always exits 0. There is no mechanism to reject or undo the tool call.

### 3b. Grep and Glob are not monitored by guard hook

- **File:** `src/global/hooks/guard.sh`, line 64
- **Observation:** Comment on line 64 states: "D-072: Grep/Glob blocked by allowed-tools, unobservable here." The guard hook only checks Read, Write, and Edit. Grep and Glob violations rely entirely on the `allowed-tools` frontmatter in command files (e.g., `task.md` does not list Grep or Glob).
- **Evidence:** The `task.md` allowed-tools list (line 6-11) includes Agent, Read, Write, TaskCreate, TaskUpdate, TaskList but not Grep or Glob. However, the `.claude/CLAUDE.md` orchestrator boundary section is a prompt-level control, not a system-enforced one.

### 3c. Knowledge access matrix is prompt-enforced, not system-enforced

- **File:** `src/global/core/knowledge-access-matrix.yaml`
- **Observation:** The access matrix defines which agents can read/write which knowledge types at which levels. Enforcement depends on the orchestrator skill correctly assembling agent instructions per the matrix. There is no runtime enforcement preventing an agent from reading files outside its authorized scope.

### 3d. Bypass command has strict confirmation gate

- **File:** `src/commands/moira/bypass.md`, lines 46-54
- **Observation:** The bypass command requires the user to enter exactly "2" to confirm. Natural language confirmations are explicitly rejected. This is a well-designed anti-manipulation gate, but it is prompt-enforced rather than system-enforced.

---

## 4. Unsafe Patterns

### 4a. Temporary files created without restrictive permissions

- **Files:** `src/global/lib/yaml-utils.sh` (lines 182, 256, 286, 588), `src/global/lib/knowledge.sh` (lines 384, 389, 551, 700), `src/global/lib/settings-merge.sh` (lines 90, 136, 195, 230), `src/global/lib/bootstrap.sh` (lines 573-574, 817-818), `src/global/lib/reflection.sh` (lines 155, 310), `src/global/lib/judge.sh` (line 73)
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

---

## 5. Sensitive Data Handling

### 5a. Tool usage logs contain file paths

- **File:** `src/global/hooks/guard.sh`, line 61
- **Observation:** `tool-usage.log` records timestamps, tool names, and file paths for every tool call. `violations.log` records the same for violations. These logs are in `.claude/moira/state/` which is gitignored. File paths could reveal project structure to anyone with access to the state directory.
- **Evidence:** `.gitignore` includes entries for `.claude/moira/state/violations.log`, `.claude/moira/state/tool-usage.log`, and `.claude/moira/state/budget-tool-usage.log`.

### 5b. Task descriptions stored in plaintext

- **File:** `src/commands/moira/task.md`, lines 42-55
- **Observation:** User task descriptions are written verbatim to `input.md` and the first 100 characters to `status.yaml`. These are in per-task directories under `.claude/moira/state/tasks/` which is gitignored.

### 5c. Bypass log records file changes

- **File:** `src/commands/moira/bypass.md`, lines 92-102
- **Observation:** The bypass log at `.claude/moira/state/bypass-log.yaml` records timestamps, task descriptions, and lists of changed files. This file is gitignored (via the `state/` parent directory exclusion).

### 5d. .gitignore covers state but not all Moira runtime data

- **File:** `.gitignore`, lines 15-37
- **Observation:** The `.gitignore` excludes task directories, lock files, bypass logs, current state, queue, and various log files. However, `.claude/moira/config.yaml`, `.claude/moira/config/budgets.yaml`, `.claude/moira/config/mcp-registry.yaml`, and `.claude/moira/knowledge/` are NOT gitignored. Knowledge files may contain project-specific information derived from scans. The MCP registry reveals which external services are configured.
- **Evidence:** `.claude/moira/config/mcp-registry.yaml` is tracked (visible in git status of the project), as is `.claude/moira/project/rules/`.

---

## Summary

| Category | Count | Severity |
|---|---|---|
| Hardcoded secrets | 0 | N/A |
| Input validation gaps | 6 | Low to Medium |
| Auth gaps (prompt-enforced only) | 4 | Medium (by design) |
| Unsafe patterns | 4 | Low |
| Sensitive data exposure | 4 | Low |

The system's security model is primarily prompt-enforced (LLM instruction compliance) rather than system-enforced (hard technical controls). The guard hook provides detection and logging but not prevention. This is consistent with the system's architecture as a meta-orchestration layer for Claude Code, where the LLM itself is both the enforcement target and the execution engine.
