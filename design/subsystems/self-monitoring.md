# Orchestrator Self-Monitoring

## Problem

The orchestrator (main Claude) might violate its own rules:
- Read project files directly instead of spawning Explorer
- Write code instead of spawning Implementer
- Skip pipeline steps
- Rationalize shortcuts

Rules alone don't prevent this 100%. We need structural enforcement.

## Three-Layer Guard Mechanism (D-031)

`allowed-tools` is the primary enforcement layer. Hooks provide audit and detection. Prompt rules provide guidance.

### Hook Registration

```jsonc
// .claude/settings.json (merged by install.sh)
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

### Layer 2: Two-Tier Violation Detection (D-031, D-099, D-116)

Layer 2 has two sub-mechanisms. Claude Code supports hooks in subagent frontmatter, but Moira agents use dynamic prompt construction (not static `.claude/agents/` definitions with frontmatter), so `settings.json` hooks don't reach agent sessions. Post-agent git diff verification handles agent-level guard checks instead (D-099). See D-116 for future migration path to subagent frontmatter hooks.

#### Layer 2a: PostToolUse `guard.sh` hook — Orchestrator violations (DETECTION + AUDIT)

**Scope:** guard.sh is registered in `settings.json` and fires only in the orchestrator session (settings.json hooks do not propagate to subagent sessions). It detects orchestrator-level Art 1.1 violations (orchestrator touching project files). It cannot block — PostToolUse fires after the tool call (D-075). It logs violations and injects context warnings via hookSpecificOutput.

**Activation:** Guard enforcement requires a `.guard-active` marker file in the state directory. The orchestrator creates this marker at pipeline start (Pre-Pipeline Setup, step 0) and deletes it on pipeline end (completion, abort, or failure). Without the marker, guard.sh exits silently — preventing false positives in normal Claude Code sessions and when a pipeline is interrupted awaiting `/moira:resume`.

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
moira_path=".claude/moira"
if [[ "$tool_name" =~ ^(Read|Write|Edit)$ ]]; then
  if [[ -n "$file_path" && "$file_path" != *"$moira_path"* ]]; then
    echo "{\"hookSpecificOutput\":{\"additionalContext\":\"CONSTITUTIONAL VIOLATION: Orchestrator used $tool_name on $file_path. Art 1.1 prohibits direct project file operations.\"}}"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) VIOLATION $tool_name $file_path" >> "$state_dir/violations.log"
  fi
fi
```

#### Layer 2b: Post-agent git diff check — Agent violations (DETECTION + BLOCKING, D-099)

**Scope:** After each file-modifying agent (implementer, explorer) returns, the orchestrator runs `git diff --name-only` and checks modified files against protected paths. Unlike guard.sh, this mechanism CAN block the pipeline — violations trigger a Guard Violation Gate (revert/accept/abort) defined in `gates.md`.

Protected paths (agents MUST NOT modify): `design/CONSTITUTION.md`, `design/**`, `.claude/moira/config/**`, `.claude/moira/core/**`, `src/global/**`. Allowed exceptions: `.claude/moira/state/tasks/{id}/**`, `.claude/moira/knowledge/**`, project source files.

Violations are logged to `state/violations.log` with `AGENT_VIOLATION` prefix (distinct from orchestrator `VIOLATION` prefix). Agent violations are distinguished from orchestrator violations by the `AGENT_VIOLATION` log prefix (vs `VIOLATION` prefix for orchestrator violations).

### Layer 3: CLAUDE.md prompt enforcement (GUIDANCE)

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
- Use Read on files outside .claude/moira/
- Use Edit or Write on files outside .claude/moira/
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
