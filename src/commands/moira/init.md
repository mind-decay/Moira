---
name: moira:init
description: Set up Moira for the current project
argument-hint: "[--force]"
allowed-tools:
  - Agent
  - Read
  - Write
  - Bash
---

# Moira — Project Initialization

This command sets up Moira for the current project. It scans the project, generates configuration and rules, populates the knowledge base, and integrates with `.claude/CLAUDE.md`.

**Important:** This is a setup command, NOT the orchestrator. It can use Bash and Write directly because it needs to run scaffold.sh, create config files, etc. It does NOT read project source code — scanners (Explorer agents) do that.

---

## Step 1: Check Global Layer

Read `~/.claude/moira/.version`.

- If file exists: store version, continue.
- If not found: display error and stop:
  ```
  Moira is not installed globally.
  Run the install script first (see Moira documentation).
  ```

## Step 2: Check Existing Init

Read `.claude/moira/config.yaml`.

- If exists AND $ARGUMENTS does **not** contain `--force`:
  Display:
  ```
  Moira is already initialized for this project.
  Use /moira:refresh to update, or /moira:init --force to reinitialize.
  ```
  Stop.
- If exists AND `--force` in arguments: continue (reinit mode)
- If not exists: continue (fresh init)

## Step 3: Create Project Scaffold

Run via Bash (always use `bash -c` to ensure bash execution — user's default shell may be zsh):
```bash
bash -c 'source ~/.claude/moira/lib/scaffold.sh && moira_scaffold_project "{project_root}"'
```

This creates all directories and copies knowledge templates. Idempotent — safe to re-run.

## Step 4: Dispatch Scanner Agents

Read scanner instruction templates and dispatch 4 Explorer agents in PARALLEL.

For each of the 4 scanners, construct the agent prompt by combining:
1. Explorer role identity from `~/.claude/moira/core/rules/roles/hermes.yaml`
2. Base inviolable rules from `~/.claude/moira/core/rules/base.yaml`
3. Scanner-specific instructions from the template

Read these files:
- `~/.claude/moira/core/rules/roles/hermes.yaml`
- `~/.claude/moira/core/rules/base.yaml`
- `~/.claude/moira/templates/scanners/tech-scan.md`
- `~/.claude/moira/templates/scanners/structure-scan.md`
- `~/.claude/moira/templates/scanners/convention-scan.md`
- `~/.claude/moira/templates/scanners/pattern-scan.md`

Dispatch ALL 4 agents simultaneously using 4 Agent tool calls in a **single message**:

**Agent 1 — Tech Scanner:**
- description: "Hermes — tech scan"
- subagent_type: general-purpose
- prompt: Combine Hermes identity + base rules + tech-scan.md instructions
  Tell the agent: "You are Hermes, the Explorer. [identity from hermes.yaml]. [base rules]. Your task: [tech-scan.md contents]. Write output to `.claude/moira/state/init/tech-scan.md`."

**Agent 2 — Structure Scanner:**
- description: "Hermes — structure scan"
- subagent_type: general-purpose
- prompt: Same pattern with structure-scan.md

**Agent 3 — Convention Scanner:**
- description: "Hermes — convention scan"
- subagent_type: general-purpose
- prompt: Same pattern with convention-scan.md

**Agent 4 — Pattern Scanner:**
- description: "Hermes — pattern scan"
- subagent_type: general-purpose
- prompt: Same pattern with pattern-scan.md

Wait for all 4 to complete. Check results:
- If any agent fails: report which scanner failed and why. Offer: **retry** / **skip** (fields will be empty) / **abort**
- If all succeed: proceed

## Step 4b: Build Project Graph

Check for the Ariadne binary and build the project graph if available.

### 4b.1: Check Binary

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_check_binary'
```

### 4b.2: If Binary Found

Run graph build and view generation via Bash (can run in parallel with Step 4 scanner agents):
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_build "{project_root}" && moira_graph_views_generate'
```

After build completes, extract summary:
```bash
bash -c 'source ~/.claude/moira/lib/graph.sh && moira_graph_summary'
```

Store the summary values (node_count, edge_count, cluster_count) for display in Step 11.

Report: "Project Graph: {node_count} files, {edge_count} edges, {cluster_count} clusters"

### 4b.3: If Binary Not Found

Display:
```
⚠ ariadne not found — Project Graph features unavailable.
  Install: cargo install ariadne-graph
  Or: curl -sSL https://raw.githubusercontent.com/anthropics/ariadne/main/install.sh | bash
```

Continue without graph (graceful degradation per D-102).

## Step 5: Generate Config and Rules

Run via Bash (always use `bash -c` — bootstrap.sh uses BASH_REMATCH which requires bash):
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_generate_config "{project_root}" ".claude/moira/state/init/tech-scan.md" && moira_bootstrap_generate_project_rules "{project_root}" ".claude/moira/state/init"'
```

## Step 6: MCP Discovery

Discover available MCP servers and generate the MCP registry.

This step runs AFTER config generation (Step 5) because MCP classification benefits from knowing the project stack.

Read the MCP scanner template and dispatch a single Explorer agent:
- `~/.claude/moira/templates/scanners/mcp-scan.md`

**Agent — MCP Scanner:**
- description: "Hermes — MCP scan"
- subagent_type: general-purpose
- prompt: Combine Hermes identity + base rules + mcp-scan.md instructions
  Tell the agent: "You are Hermes, the Explorer. [identity from hermes.yaml]. [base rules]. Your task: [mcp-scan.md contents]. Write output to `.claude/moira/state/init/mcp-scan.md`."

Wait for completion, then process results:
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_scan_mcp "{project_root}" ".claude/moira/state/init"'
```

If no MCP servers are available in the environment (agent reports none): the bootstrap function sets `mcp.enabled: false` — this is normal and expected.

## Step 7: Populate Knowledge

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_populate_knowledge "{project_root}" ".claude/moira/state/init"'
```

## Step 8: Integrate CLAUDE.md

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_inject_claude_md "{project_root}" "$HOME/.claude/moira"'
```

## Step 9: Setup Gitignore

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_setup_gitignore "{project_root}"'
```

## Step 10: Configure Hooks

Run via Bash:
```bash
bash -c 'source ~/.claude/moira/lib/bootstrap.sh && moira_bootstrap_inject_hooks "{project_root}" "$HOME/.claude/moira"'
```

This registers guard and budget-track hooks in `.claude/settings.json` and creates empty log files. If hook injection fails: display warning but continue initialization.

## Step 11: User Review Gate (REQUIRED — Art 4.2)

This is an **APPROVAL GATE**. Do NOT proceed without explicit user action.

Read key fields from generated files to populate the summary, then display:

```
═══════════════════════════════════════════
  MOIRA — Project Setup Complete
═══════════════════════════════════════════
  Detected:
  ├─ Stack: {from config.yaml project.stack}
  ├─ Testing: {from stack.yaml testing field}
  ├─ Structure: {from structure scan — source layout pattern}
  └─ CI: {from tech scan — CI platform}

  Configured:
  ├─ Config: .claude/moira/config.yaml
  ├─ Rules: .claude/moira/project/rules/ (4 files)
  ├─ Knowledge: .claude/moira/knowledge/ (3 types populated)
  ├─ CLAUDE.md: updated with Moira section
  ├─ Hooks: guard.sh + budget-track.sh registered
  ├─ MCP: {N} servers registered ({server1}, {server2}, ...) OR "no servers detected"
  └─ Graph: {node_count} files, {edge_count} edges, {cluster_count} clusters OR "not available (ariadne not installed)"

  1) review  — inspect generated files
  2) accept  — start using Moira
  3) adjust  — correct something
═══════════════════════════════════════════
```

Wait for user response.

### On "review":
Read and display:
- `.claude/moira/config.yaml` (full)
- `.claude/moira/project/rules/stack.yaml` (full)
- `.claude/moira/project/rules/conventions.yaml` (summary)

Then re-present the gate (review/accept/adjust).

### On "accept":
Display: "Moira is ready. Use `/moira:task <description>` to start."
Proceed to Step 12.

### On "adjust":
Ask user what needs correction. Apply changes to the relevant files.
Then re-present the gate.

## Step 12: Micro-Onboarding (conditional)

Check if this appears to be the user's first time with Moira (e.g., no completed tasks in any project, or global install is recent).

If first time:
```
═══════════════════════════════════════════
  MOIRA — First time setup
═══════════════════════════════════════════

  1) start — 3-minute walkthrough of how Moira works
  2) skip  — I'll figure it out (tip: /moira:help)
═══════════════════════════════════════════
```

### On "start":

Display Core Concept:
```
═══════════════════════════════════════════
  HOW MOIRA WORKS
═══════════════════════════════════════════

  You describe a task → Moira orchestrates agents:

  You ──→ Classify ──→ Analyze ──→ Plan ──→ Build ──→ Review
             │           │          │         │         │
          "how big?"  "what's    "how?"   "write    "check
                       needed?"            code"    quality"

  You approve at key checkpoints (numbered prompts).
  You never need to manage agents directly.

  1) next
═══════════════════════════════════════════
```

Then display Commands:
```
═══════════════════════════════════════════
  COMMANDS — just 5 to remember
═══════════════════════════════════════════

  /moira:task <task>     — do a task
  /moira:resume          — resume interrupted work
  /moira:status          — where am I?
  /moira:knowledge       — what does the system know?
  /moira:metrics         — how well is it working?

  Everything else happens through prompts.

  1) done — you're all set!
═══════════════════════════════════════════
```

Then: "Try `/moira:task` with a small task when ready."

### On "skip":
Display: "Quick reference: `/moira:task <task>`, `/moira:status`, `/moira:help`"
Done.

---

## --force Mode Differences

When `--force` is passed:
- Step 3: scaffold is re-run (idempotent — no data loss)
- Step 4: all 4 scanners run again (full rescan)
- Step 6: MCP scanner re-runs (full MCP re-scan)
- Step 7: knowledge update behavior:
  - **project-model, conventions, patterns**: overwritten with new scan data
  - **quality-map**: regenerated as preliminary
  - **decisions**: PRESERVED (organic growth — not scanner-sourced)
  - **failures**: PRESERVED (organic growth — not scanner-sourced)
- Steps 8-10: CLAUDE.md re-injected (replaces between markers), gitignore rechecked, hooks re-injected
- Steps 11-12: same review gate
