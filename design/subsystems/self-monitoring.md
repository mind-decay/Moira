# Orchestrator Self-Monitoring

## Problem

The orchestrator (main Claude) might violate its own rules:
- Read project files directly instead of spawning Explorer
- Write code instead of spawning Implementer
- Skip pipeline steps
- Rationalize shortcuts

Rules alone don't prevent this 100%. We need structural enforcement.

## Hook-Based Enforcement

### Guard Hook

```jsonc
// .claude/settings.json
{
  "hooks": {
    "on_tool_call": [
      {
        "name": "forge_orchestrator_guard",
        "command": "bash .claude/forge/hooks/guard.sh"
      }
    ],
    "on_agent_complete": [
      {
        "name": "forge_budget_tracker",
        "command": "bash .claude/forge/hooks/budget-track.sh"
      }
    ]
  }
}
```

### Guard Hook Logic

```bash
#!/bin/bash
# .claude/forge/hooks/guard.sh

TOOL_NAME="$1"
FILE_PATH="$2"
FORGE_PATH=".claude/forge/"

case "$TOOL_NAME" in
  "Agent"|"Skill")
    exit 0  # always allowed
    ;;
  "Read"|"Write"|"Edit")
    if [[ "$FILE_PATH" == *"$FORGE_PATH"* ]]; then
      exit 0  # forge files: allowed
    else
      echo "VIOLATION: Orchestrator attempted $TOOL_NAME on $FILE_PATH"
      echo "Orchestrator must delegate file operations to agents."
      exit 1  # blocks the tool call
    fi
    ;;
  "Bash"|"Grep"|"Glob")
    echo "VIOLATION: Orchestrator attempted $TOOL_NAME"
    echo "Orchestrator must not use execution tools directly."
    exit 1
    ;;
esac
```

### Budget Tracker Hook

Logs context usage after each agent completes:

```bash
#!/bin/bash
# .claude/forge/hooks/budget-track.sh

AGENT_NAME="$1"
TASK_ID="$2"

# Log agent completion and estimated context usage
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $AGENT_NAME $TASK_ID" \
  >> .claude/forge/state/budget-log.txt
```

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
Context usage: 58% (116k/200k)

Quality of orchestration may degrade.

Recommendation: checkpoint and continue in fresh session.

▸ checkpoint — save state, run /forge continue later
▸ proceed    — continue (not recommended)
```

## Orchestrator Health Report

Included in every gate display:

```
ORCHESTRATOR HEALTH:
├─ Context: ~22k/200k (11%) ✅
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
- Use Read on files outside .claude/forge/
- Use Edit or Write on files outside .claude/forge/
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
