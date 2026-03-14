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

### Layer 2: PostToolUse `guard.sh` hook (DETECTION + AUDIT)

**Scope:** guard.sh runs as a PostToolUse hook in the orchestrator session. Claude Code hooks fire for ALL tool uses in the session, including those made by dispatched subagents. Since agents are expected to read/write project files (that's their job), guard.sh must distinguish orchestrator tool calls from agent tool calls. Platform constraint: Claude Code does not currently expose whether a tool call originates from the main session or a subagent. Guard.sh should log all tool calls but only flag violations from orchestrator-context operations (non-agent file operations targeting project paths).

```bash
#!/bin/bash
# PostToolUse hook — fires AFTER every tool call
# Logs all tool usage, detects and reports violations

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.command // empty')
state_dir="$HOME/.claude/moira/state"

# Only monitor moira sessions
if [ ! -f "$state_dir/current.yaml" ]; then
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

### Layer 3: CLAUDE.md prompt enforcement (GUIDANCE)

Moira section in project CLAUDE.md contains inviolable rules about orchestrator boundaries.

## Orchestrator Context Monitoring

### Thresholds

| Level | Threshold | Action |
|-------|-----------|--------|
| Healthy | < 25% | Normal operation |
| Monitor | 25-40% | Include in status display |
| Warning | 40-60% | Display alert to user |
| Critical | > 60% | Recommend checkpoint |

### Warning Display

```
⚠ ORCHESTRATOR CONTEXT WARNING
Context usage: 62% (620k/1000k)

Quality of orchestration may degrade.

Recommendation: checkpoint and continue in fresh session.

▸ checkpoint — save state, run /moira continue later
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
