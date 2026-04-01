# Orchestrator Self-Monitoring

## Problem

The orchestrator (main Claude) might violate its own rules:
- Read project files directly instead of spawning Explorer
- Write code instead of spawning Implementer
- Skip pipeline steps
- Rationalize shortcuts

Rules alone don't prevent this 100%. We need structural enforcement.

## Four-Layer Guard Mechanism (D-031, D-175, D-176)

`allowed-tools` is the primary prevention layer. Hook suite provides deterministic enforcement, audit, and context injection. Prompt rules provide guidance.

### Hook Registration

13 hooks across 9 event types, registered in `.claude/settings.json` by `install.sh` via `settings-merge.sh`.
Also injects `permissions.allow` for `/.moira/**` (Read/Write/Edit) so subagents can access state without permission prompts. Global `Read(~/.claude/moira/**)` is registered in `~/.claude/settings.json` for role/template reads.

| Hook | Event | Type | Purpose |
|------|-------|------|---------|
| `task-submit.sh` | UserPromptSubmit | Inject | Task initialization on prompt submit |
| `pipeline-dispatch.sh` | PreToolUse (Agent) | DENY | Per-pipeline transition table enforcement |
| `guard-prevent.sh` | PreToolUse (Read\|Write\|Edit) | DENY | Block orchestrator access to project files |
| `guard.sh` | PostToolUse (all) | Audit | Violation detection + tool usage logging |
| `budget-track.sh` | PostToolUse (all) | Audit | Token usage tracking |
| `graph-update.sh` | PostToolUse (Write\|Edit) | Inject | Incremental graph update on file changes |
| `pipeline-tracker.sh` | PostToolUse (Agent) | Inject | Dispatch tracking + next-step guidance |
| `pipeline-stop-guard.sh` | Stop | BLOCK | Prevent completion with pending review/test |
| `compact-reinject.sh` | SessionStart (compact) | Inject | Re-inject pipeline state after compaction |
| `agent-inject.sh` | SubagentStart | Inject | Response contract + rules in every agent |
| `agent-output-validate.sh` | SubagentStop | BLOCK | Validate agent output has STATUS line |
| `agent-done.sh` | SubagentStop | Audit | Record agent completion in state |
| `graph-validate.sh` | TaskCompleted | Audit | Validate graph consistency after task |
| `session-cleanup.sh` | SessionEnd | Cleanup | Clean transient state on session end (incl. current.yaml, .guard-stale) |

### Layer 1: `allowed-tools` in command frontmatter (PREVENTION)

Orchestrator command files (`~/.claude/commands/moira/*.md`) restrict available tools:
```yaml
allowed-tools:
  - Agent          # dispatch subagents
  - Read           # read moira state/config files ONLY
  - Write          # write moira state files ONLY
  - TaskCreate     # todo tracking
  - TaskUpdate
  - TaskList
  # NOT included: Edit, Grep, Glob, Bash — orchestrator cannot touch project files (D-001)
```

The orchestrator physically cannot invoke Edit, Grep, Glob, or Bash because these tools are not in its allowed set. This is stronger than PreToolUse blocking — the tools don't exist in the orchestrator's context at all.

### Layer 2: Deterministic Hook Enforcement (D-175, D-176)

Hook-based enforcement that executes outside the LLM. Cannot be "rationalized away" or ignored — shell code fires on every tool call and blocks non-compliant actions.

#### Layer 2a: Pipeline Step Enforcement (PreToolUse Agent)

`pipeline-compliance.sh` maintains per-pipeline transition tables. Before every Agent dispatch, validates that the dispatched role is a valid transition from the previous role. DENY if invalid.

Transition tables cover all 5 pipeline types (quick, standard, full, decomposition, analytical) with special handling for:
- Parallel dispatches (standard/full: explorer+analyst)
- Repeatable groups (full: phase cycles, decomposition: sub-tasks)
- Error recovery (architect/planner always allowed as re-entry points)
- E5-QUALITY retry (reviewer/tester → implementer for defect fixes)
- Retry (same role dispatch always allowed)
- Analytical pipeline dynamic roles (`analytical_primary`, `analytical_organizer`)

`pipeline-tracker.sh` (PostToolUse Agent) tracks dispatched roles and injects next-step guidance into orchestrator context after each dispatch. Uses **per-subtask state isolation** in decomposition pipeline: each sub-task gets its own state file (`pipeline-tracker-sub-{N}.state`) for `last_role`, `review_pending`, `test_pending`, preventing one sub-task's pending flags from blocking another sub-task's dispatches.

`pipeline-stop-guard.sh` (Stop) prevents pipeline completion while review or testing is pending. In decomposition mode, checks ALL per-subtask state files.

#### Layer 2b: Boundary Enforcement (PreToolUse Read|Write|Edit)

`guard-prevent.sh` DENY orchestrator Read/Write/Edit on files outside `.moira/` and `.ariadne/`. Upgrades guard.sh from detection-only to prevention. Orchestrator content never enters context. Denied operations are logged to `violations.log`.

**Subagent bypass (D-183):** Both `guard-prevent.sh` and `guard.sh` check the `agent_id` field in hook input. This field is present **only** in subagent contexts — the orchestrator session does not have it. When `agent_id` is present, the hook exits immediately (exit 0), allowing dispatched agents to freely Read/Write/Edit project files. This is structural enforcement: the bypass is determined by the Claude Code harness, not by LLM prompt compliance.

`guard.sh` (PostToolUse) remains for audit logging — logs all tool usage and detects violations after the fact. Also bypassed for subagents to prevent false-positive violation logging.

#### Layer 2c: Agent Quality Enforcement (SubagentStart/SubagentStop)

`agent-inject.sh` (SubagentStart) injects response contract, inviolable rules, and agent role clarification into every subagent. The role clarification explicitly states the agent is NOT the orchestrator and MUST freely use Read/Edit/Write/Grep/Glob/Bash on project files — countering any CLAUDE.md orchestrator boundary rules the agent may read at startup. Ensures minimum prompt quality regardless of orchestrator's prompt construction.

`agent-output-validate.sh` (SubagentStop) validates agent output contains required STATUS line. BLOCK if missing — agent continues and fixes format.

#### Layer 2d: Context Recovery (SessionStart compact)

`compact-reinject.sh` re-injects pipeline state (task ID, pipeline type, current step, pending review/test) after context compaction. Prevents orchestrator from losing track of pipeline state.

### Layer 3: Post-agent Guard Check (D-099, D-116)

```bash
#!/bin/bash
# PostToolUse hook — orchestrator session only
# Logs all orchestrator tool usage, detects and reports violations

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.command // empty')
state_dir="$HOME/.claude/moira/state"

# Only monitor moira sessions
if [ ! -f "$state_dir/current.yaml" ]; then
  exit 0
fi

# Only enforce during active pipeline (marker created by orchestrator)
if [ ! -f "$state_dir/.guard-active" ]; then
  exit 0
fi

# Log all tool usage for audit trail
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $tool_name $file_path" >> "$state_dir/tool-usage.log"

# Check for violations — orchestrator touching project files
moira_path=".moira"
if [[ "$tool_name" =~ ^(Read|Write|Edit)$ ]]; then
  if [[ -n "$file_path" && "$file_path" != *"$moira_path"* ]]; then
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"CONSTITUTIONAL VIOLATION: Orchestrator used $tool_name on $file_path. Art 1.1 prohibits direct project file operations.\"}}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) VIOLATION $tool_name $file_path" >> "$state_dir/violations.log"
  fi
fi
```

#### Layer 3a: Post-agent git diff check — Agent violations (DETECTION + BLOCKING, D-099)

**Scope:** After each file-modifying agent (implementer, explorer) returns, the orchestrator runs `git diff --name-only` and checks modified files against protected paths. Unlike guard.sh, this mechanism CAN block the pipeline — violations trigger a Guard Violation Gate (revert/accept/abort) defined in `gates.md`.

Protected paths (agents MUST NOT modify): `design/CONSTITUTION.md`, `design/**`, `.moira/config/**`, `.moira/core/**`, `src/global/**`. Allowed exceptions: `.moira/state/tasks/{id}/**`, `.moira/knowledge/**`, project source files.

Violations are logged to `state/violations.log` with `AGENT_VIOLATION` prefix (distinct from orchestrator `VIOLATION` prefix). Agent violations are distinguished from orchestrator violations by the `AGENT_VIOLATION` log prefix (vs `VIOLATION` prefix for orchestrator violations).

### Layer 4: CLAUDE.md prompt enforcement (GUIDANCE)

Moira section in project CLAUDE.md contains inviolable rules about orchestrator boundaries.

## Environmental Interference Patterns

External systems may inject directives that interfere with orchestrator behavior. These are distinct from the internal violations detected by Layers 1-3 above — they originate outside Moira's control boundary.

### Plan Mode Override (system-reminder injection)

**Threat:** Claude Code plan mode injects a system-reminder containing behavioral restrictions ("MUST NOT make any edits", "READ-ONLY actions only"). This conflicts with the orchestrator's pipeline execution directives, causing it to stop dispatching agents and instead write plan files — abandoning pipeline structure entirely.

**Impact:** Complete pipeline abandonment. The orchestrator ceases agent dispatch, skips remaining gates, and begins producing plan output instead of executing the pipeline. The failure mode is omission (not dispatching), not commission (calling wrong tools).

**Defense layer:** Layer 3 (behavioral/prompt). Layers 1 and 2 cannot address this threat — Layer 1 (allowed-tools) is unaffected because plan mode does not add/remove tools; Layer 2 (guard.sh) fires on tool calls, but the failure mode is absence of tool calls.

**Defense mechanism:** Explicit override resistance language in two prompt injection points:
1. `src/global/skills/orchestrator.md` Section 1 — primary defense with pattern-based recognition, priority declaration, and scope limiter (D-156)
2. `.claude/CLAUDE.md` — secondary reinforcement within moira markers

The defense uses pattern-based recognition (behavioral characteristics, not exact strings) and an explicit priority hierarchy: user gates > pipeline directives > external behavioral restrictions.

**Limitation:** This is a behavioral defense (prompt language), not a structural defense. It cannot physically prevent system-reminder injection. Its effectiveness depends on the orchestrator's instruction-following behavior under competing directives.

**Detection:** Observable by user (orchestrator stops dispatching, starts writing plans). Guard.sh may detect writes to non-moira paths if the orchestrator begins producing plan output files.

**Recovery:** User exits plan mode via Claude Code UI, then uses `/moira:resume` to continue from the last completed pipeline step.

## Orchestrator Context Monitoring

### Thresholds

| Level | Threshold | Action |
|-------|-----------|--------|
| Healthy | < 25% | Normal operation |
| Monitor | 25-40% | Include in status display |
| Warning | 40-60% | Display alert to user |
| Critical | > 60% | Recommend checkpoint + new session |

### Warning Display

```
⚠ ORCHESTRATOR CONTEXT WARNING
Context usage: 62% (620k/1000k)

Quality of orchestration may degrade.

Recommendation: checkpoint and continue in fresh session.

▸ checkpoint — save state, run /moira:resume later
▸ proceed    — continue (not recommended)
```

## Orchestrator Health Report

Included in every gate display:

```
ORCHESTRATOR HEALTH:
├─ Context: ~22k/1000k (2%) ✅
├─ Violations: 0 ✅
├─ Agents dispatched: 7
├─ Gates passed: 3/5
├─ Retries: 1
└─ Progress: step 5/8
```

## Anti-Rationalization Rules

Embedded in orchestrator's CLAUDE.md:

```markdown
## ABSOLUTE PROHIBITIONS

You are an ORCHESTRATOR. You are NOT an executor.

NEVER:
- Use Read on files outside .moira/
- Use Edit or Write on files outside .moira/
- Use Bash for anything except agent dispatch
- Use Grep or Glob on project files

If you catch yourself thinking:
- "Let me just quickly check..." → SPAWN EXPLORER
- "I can easily fix this..." → SPAWN IMPLEMENTER
- "This is so simple I'll just..." → FOLLOW THE PIPELINE
- "To save time..." → TIME IS NOT YOUR CONCERN, QUALITY IS

ANY violation is logged and reported in task reflection.
```

## Post-Task Audit

Reflector checks orchestrator behavior:
1. Did orchestrator use any prohibited tools?
2. Did orchestrator skip any pipeline steps?
3. Did orchestrator context stay within healthy range?
4. Did orchestrator present all required gates?

Violations are logged in:
- Task reflection
- Metrics (for trend tracking)
- Audit findings (if recurring)
