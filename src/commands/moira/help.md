---
name: moira:help
description: Show Moira help and documentation
argument-hint: "[<command>|concepts|agents|pipelines|troubleshooting]"
allowed-tools:
  - Read
---

# Moira — Help

Read the Moira version from `~/.claude/moira/.version` and display it.

Then show this help card:

## Available Commands

| Command | Description |
|---------|-------------|
| `/moira:task <description>` | Execute a task through the orchestration pipeline |
| `/moira:init` | Set up Moira for the current project |
| `/moira:status` | Show current system state |
| `/moira:resume` | Resume an interrupted task |
| `/moira:knowledge` | View and manage the knowledge base |
| `/moira:metrics` | View performance metrics dashboard |
| `/moira:audit` | Run system health audit |
| `/moira:bypass <description>` | Execute task without pipeline (escape hatch) |
| `/moira:refresh` | Update project model and knowledge base |
| `/moira:help` | Show this help |

## Quick Start

1. `/moira:init` — set up Moira for your project
2. `/moira:task Add pagination to users API` — execute a task
3. `/moira:status` — check progress

## More Information

See `design/` directory in the Moira source for full documentation.
