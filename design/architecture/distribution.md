# Distribution & Installation

## What Moira Actually Is (technically)

Moira has no compiled code, no runtime dependencies, no binary. It is a structured set of:

| File type | Purpose | Location |
|-----------|---------|----------|
| Markdown (.md) | Agent prompts, skills, docs | `~/.claude/moira/` and `.claude/moira/` |
| YAML (.yaml) | Rules, configs, state schemas | Same |
| Shell scripts (.sh) | Hooks (guard, budget tracker) | Same |

That's it. Moira runs entirely within Claude Code's existing infrastructure — agents, skills, hooks, CLAUDE.md. No daemon, no server, no extra processes.

This means installation = putting the right files in the right places.

---

## Distribution Model

```
┌──────────────────────────────┐
│     GitHub Repository        │
│  github.com/<org>/moira      │
│                              │
│  Contains:                   │
│  ├─ install.sh               │
│  ├─ src/                     │
│  │   ├─ global/    (→ ~/.claude/moira/)
│  │   └─ templates/ (used by /moira init)
│  ├─ design/                  │
│  └─ README.md                │
└──────────────┬───────────────┘
               │
     install.sh / moira-update
               │
┌──────────────▼───────────────┐
│    GLOBAL LAYER              │
│    ~/.claude/moira/          │
│                              │
│  Installed once per machine. │
│  Shared across all projects. │
└──────────────┬───────────────┘
               │
          /moira init
               │
┌──────────────▼───────────────┐
│    PROJECT LAYER             │
│    <project>/.claude/moira/  │
│                              │
│  Generated per project.      │
│  Committed to project repo.  │
└──────────────────────────────┘
```

---

## Installation — One Command

### Option A: curl (recommended for simplicity)

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/moira/main/src/remote-install.sh | bash
```

### Option B: git clone (for contributors)

```bash
git clone https://github.com/<org>/moira.git ~/.moira-source
~/.moira-source/install.sh
```

### What install.sh Does

```bash
#!/bin/bash
set -euo pipefail

MOIRA_VERSION="1.0.0"
MOIRA_HOME="$HOME/.claude/moira"
MOIRA_SOURCE="${MOIRA_SOURCE_DIR:-$(mktemp -d)}"

echo "═══════════════════════════════════════"
echo "  Installing Moira v${MOIRA_VERSION}"
echo "═══════════════════════════════════════"

# ── Step 1: Check prerequisites ──────────
check_prerequisites() {
    # Claude Code must be installed
    if ! command -v claude &> /dev/null; then
        echo "Error: Claude Code CLI not found."
        echo "Install it first: https://docs.anthropic.com/claude-code"
        exit 1
    fi

    # Git must be available (Moira uses git for rollback)
    if ! command -v git &> /dev/null; then
        echo "Error: git not found."
        exit 1
    fi

    echo "✓ Prerequisites met"
}

# ── Step 2: Download or copy source ──────
fetch_source() {
    if [ -d "$MOIRA_SOURCE/src" ]; then
        echo "✓ Using local source"
    else
        echo "  Downloading Moira v${MOIRA_VERSION}..."
        curl -fsSL "https://github.com/<org>/moira/archive/v${MOIRA_VERSION}.tar.gz" \
            | tar xz -C "$MOIRA_SOURCE" --strip-components=1
        echo "✓ Downloaded"
    fi
}

# ── Step 3: Install global layer ─────────
install_global() {
    echo "  Installing global layer to $MOIRA_HOME..."

    # Create directory structure
    mkdir -p "$MOIRA_HOME"/{core/rules/roles,core/rules/quality,templates,skills,hooks}

    # Copy core files
    cp -r "$MOIRA_SOURCE/src/global/core/"* "$MOIRA_HOME/core/"
    cp -r "$MOIRA_SOURCE/src/global/skills/"* "$MOIRA_HOME/skills/"
    cp -r "$MOIRA_SOURCE/src/global/hooks/"* "$MOIRA_HOME/hooks/"
    cp -r "$MOIRA_SOURCE/src/global/templates/"* "$MOIRA_HOME/templates/"

    # Make hooks executable
    chmod +x "$MOIRA_HOME/hooks/"*.sh

    # Write version marker
    echo "$MOIRA_VERSION" > "$MOIRA_HOME/.version"

    echo "✓ Global layer installed"
}

# ── Step 4: Install command files ─────────
install_commands() {
    echo "  Installing Moira commands..."

    # Native Claude Code custom commands (D-030)
    # Same file convention as GSD, zero runtime dependency
    mkdir -p "$HOME/.claude/commands/moira"
    cp -r "$MOIRA_SOURCE/src/commands/moira/"* "$HOME/.claude/commands/moira/"

    echo "✓ Commands installed (/moira:init, /moira:task, etc.)"
}

# ── Step 5: Verify installation ──────────
verify() {
    local checks_passed=0
    local checks_total=5

    [ -f "$MOIRA_HOME/core/rules/base.yaml" ] && ((checks_passed++))
    [ -f "$MOIRA_HOME/skills/orchestrator.md" ] && ((checks_passed++))
    [ -f "$MOIRA_HOME/hooks/guard.sh" ] && ((checks_passed++))
    [ -d "$MOIRA_HOME/templates" ] && ((checks_passed++))
    [ -f "$MOIRA_HOME/.version" ] && ((checks_passed++))

    if [ "$checks_passed" -eq "$checks_total" ]; then
        echo "✓ Verification passed ($checks_passed/$checks_total)"
    else
        echo "⚠ Verification: $checks_passed/$checks_total checks passed"
        echo "  Some components may be missing. Try reinstalling."
        exit 1
    fi
}

# ── Run ──────────────────────────────────
check_prerequisites
fetch_source
install_global
install_commands
verify

echo ""
echo "═══════════════════════════════════════"
echo "  Moira v${MOIRA_VERSION} installed ✓"
echo "═══════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. Open your project directory"
echo "  2. Run Claude Code"
echo "  3. Type: /moira init"
echo ""
echo "  That's it. Moira will set up everything"
echo "  for your project automatically."
echo ""
```

### Installation time: <30 seconds

No build step. No compilation. No package manager resolution. Just file copy + verify.

---

## Global Layer File Map

After installation, `~/.claude/` contains:

```
~/.claude/
├── moira/                                # Core system (global layer)
│   ├── .version                          # "1.0.0"
│   ├── core/
│   │   ├── rules/
│   │   │   ├── base.yaml                 # Layer 1: inviolable + overridable rules
│   │   │   ├── roles/
│   │   │   │   ├── apollo.yaml           # Layer 2: Classifier
│   │   │   │   ├── hermes.yaml           # Explorer
│   │   │   │   ├── athena.yaml           # Analyst
│   │   │   │   ├── metis.yaml            # Architect
│   │   │   │   ├── daedalus.yaml         # Planner
│   │   │   │   ├── hephaestus.yaml       # Implementer
│   │   │   │   ├── themis.yaml           # Reviewer
│   │   │   │   ├── aletheia.yaml         # Tester
│   │   │   │   ├── mnemosyne.yaml        # Reflector
│   │   │   │   └── argus.yaml            # Auditor
│   │   │   └── quality/
│   │   │       ├── q1-completeness.yaml
│   │   │       ├── q2-soundness.yaml
│   │   │       ├── q3-feasibility.yaml
│   │   │       ├── q4-correctness.yaml
│   │   │       └── q5-coverage.yaml
│   │   ├── response-contract.yaml
│   │   ├── knowledge-access-matrix.yaml
│   │   ├── pipelines/                    # Pipeline definitions (D-035)
│   │   │   ├── quick.yaml
│   │   │   ├── standard.yaml
│   │   │   ├── full.yaml
│   │   │   └── decomposition.yaml
│   │   └── xref-manifest.yaml           # Cross-reference dependency map (D-077)
│   ├── skills/
│   │   ├── orchestrator.md               # Main orchestrator skill
│   │   ├── gates.md                      # Gate presentation templates
│   │   ├── dispatch.md                   # Agent dispatch instructions
│   │   ├── reflection.md                 # Reflection dispatch skill
│   │   └── errors.md                     # Error handling procedures
│   ├── statusline/
│   │   └── context-status.sh             # Claude Code status line (context tracking)
│   ├── hooks/
│   │   ├── guard.sh                      # Orchestrator tool restriction
│   │   └── budget-track.sh              # Context usage logging
│   ├── templates/
│   │   ├── project-claude-md.tmpl        # CLAUDE.md template for projects
│   │   ├── budgets.yaml.tmpl             # Budget configuration template
│   │   ├── scanners/                     # Scanner instruction templates
│   │   │   └── deep/                     # Deep scan templates
│   │   ├── reflection/                   # Reflection prompt templates
│   │   ├── judge/                        # LLM-judge prompt templates
│   │   └── audit/                        # Audit instruction templates
│   ├── schemas/                          # YAML schema definitions
│   │   ├── budgets.schema.yaml
│   │   ├── config.schema.yaml
│   │   ├── current.schema.yaml
│   │   ├── findings.schema.yaml
│   │   ├── locks.schema.yaml
│   │   ├── manifest.schema.yaml
│   │   ├── queue.schema.yaml
│   │   ├── status.schema.yaml
│   │   ├── telemetry.schema.yaml
│   │   ├── mcp-registry.schema.yaml
│   │   ├── metrics.schema.yaml
│   │   └── audit.schema.yaml
│   └── lib/
│       ├── bootstrap.sh                  # Project bootstrap logic
│       ├── bench.sh                      # Behavioral test runner
│       ├── budget.sh                     # Budget tracking utilities
│       ├── knowledge.sh                  # Knowledge read/write utilities
│       ├── quality.sh                    # Quality criteria utilities
│       ├── reflection.sh                 # Reflection dispatch utilities
│       ├── judge.sh                      # LLM-judge invocation utilities
│       ├── rules.sh                      # Rule assembly utilities
│       ├── scaffold.sh                   # Directory scaffold generator
│       ├── settings-merge.sh             # Settings.json merge utility
│       ├── state.sh                      # State management utilities
│       ├── task-id.sh                    # Task ID generation
│       ├── yaml-utils.sh                # YAML read/write/validate (pure bash)
│       ├── mcp.sh                        # MCP integration utilities
│       ├── retry.sh                      # Retry logic utilities
│       ├── audit.sh                      # Audit engine utilities
│       └── metrics.sh                    # Metrics collection utilities
│
├── commands/moira/                       # User-facing slash commands (D-030)
│   ├── init.md                           # /moira:init
│   ├── task.md                           # /moira:task — main entry point
│   ├── status.md                         # /moira:status
│   ├── metrics.md                        # /moira:metrics
│   ├── audit.md                          # /moira:audit
│   ├── bench.md                          # /moira:bench
│   ├── health.md                         # /moira:health
│   ├── knowledge.md                      # /moira:knowledge
│   ├── bypass.md                         # /moira:bypass
│   ├── resume.md                         # /moira:resume
│   ├── refresh.md                        # /moira:refresh
│   ├── upgrade.md                        # /moira:upgrade
│   └── help.md                           # /moira:help
│
└── settings.json                         # Hooks + statusline registration (merge)
```

---

## Project Setup — /moira init

After global installation, for each project:

```bash
cd /path/to/my-project
claude                    # start Claude Code
> /moira init             # that's it
```

### What /moira init does internally

```
/moira init
  │
  ├─ 1. CHECK: Is global layer installed?
  │    ├─ YES → continue
  │    └─ NO → "Moira not installed. Run: curl ... | bash"
  │
  ├─ 2. CHECK: Is project already initialized?
  │    ├─ YES → "Already initialized. Use /moira refresh to update."
  │    └─ NO → continue
  │
  ├─ 3. SCAN: Quick project analysis (4 parallel agents)
  │    ├─ Tech scanner → detects stack from package.json, configs, etc.
  │    ├─ Structure scanner → maps directory layout
  │    ├─ Convention scanner → reads linter configs + sample files
  │    └─ Pattern scanner → reads representative files per layer
  │
  ├─ 4. GENERATE: Create project layer
  │    .claude/moira/
  │    ├─ config.yaml              (from scan results)
  │    ├─ project/rules/
  │    │   ├─ stack.yaml           (detected stack)
  │    │   ├─ conventions.yaml     (detected conventions)
  │    │   ├─ patterns.yaml        (detected patterns)
  │    │   └─ boundaries.yaml      (detected off-limits areas)
  │    ├─ config/
  │    │   ├─ mcp-registry.yaml    (from available MCP servers)
  │    │   └─ budgets.yaml         (defaults, adjustable)
  │    ├─ knowledge/
  │    │   ├─ project-model/       (from structure scan)
  │    │   ├─ conventions/         (from convention scan)
  │    │   ├─ decisions/           (empty, will grow)
  │    │   ├─ patterns/            (from pattern scan)
  │    │   ├─ failures/            (empty, will grow)
  │    │   └─ quality-map/         (preliminary, from pattern scan)
  │    ├─ state/                   (empty, ready for tasks)
  │    └─ hooks/                   (linked from global)
  │
  ├─ 5. INJECT: Project CLAUDE.md integration
  │    ├─ If .claude/CLAUDE.md exists → append Moira section
  │    └─ If not → create with Moira configuration
  │    (Never overwrites existing CLAUDE.md content)
  │
  ├─ 6. INJECT: Project AGENTS.md
  │    ├─ Generate project-adapted agent definitions
  │    └─ Stack-specific implementer, reviewer, tester prompts
  │
  ├─ 7. INJECT: Hooks configuration
  │    ├─ Add guard.sh and budget-track.sh to .claude/settings.json
  │    └─ Preserve existing hooks (append, don't overwrite)
  │
  ├─ 8. GATE: User reviews generated config
  │    ═══════════════════════════════════════════
  │     MOIRA — Project Setup Complete
  │    ═══════════════════════════════════════════
  │     Detected:
  │     ├─ Stack: Next.js 14, TypeScript, Tailwind, Prisma
  │     ├─ Testing: Jest + React Testing Library
  │     ├─ Structure: App Router, feature-based components
  │     └─ CI: GitHub Actions
  │
  │     Generated: rules, agents, knowledge base
  │
  │     ▸ review  — inspect generated files
  │     ▸ accept  — start using Moira
  │     ▸ adjust  — correct something
  │    ═══════════════════════════════════════════
  │
  └─ 9. ONBOARDING: If first time → offer walkthrough
         (see onboarding.md)
```

### What gets committed to project repo

```
# .gitignore additions by Moira
.claude/moira/state/tasks/     # task execution state (per-developer)
.claude/moira/state/bypass-log.yaml

# These ARE committed (shared with team):
.claude/moira/config.yaml
.claude/moira/project/rules/
.claude/moira/config/
.claude/moira/knowledge/
.claude/moira/state/metrics/   # team-visible metrics
```

### Existing `.claude/` Compatibility

1. **`.claude/` already exists** — Moira creates only `.claude/moira/` subdirectory. Does not touch anything outside `moira/`.
2. **`.claude/CLAUDE.md` already exists** — Moira appends its section wrapped in markers:
   ```markdown
   <!-- moira:start -->
   ## Moira Orchestration System
   ...orchestrator instructions...
   <!-- moira:end -->
   ```
   On re-init or refresh — replaces only content between markers.
3. **`.claude/CLAUDE.md` does not exist** — Creates file with Moira section.
4. **`.claude/commands/` already exists** (GSD or other) — Moira uses its own `commands/moira/` namespace, no conflicts.
5. **Repeated `/moira:init`** — Idempotent. No duplicate sections, preserves knowledge.
6. **`/moira:init --force`** — Full reinitialization: recreates config, reruns scanners, preserves accumulated knowledge.

This means: when another developer clones the repo and runs `/moira init`, they get:
- All project-specific rules (already configured)
- All accumulated knowledge (team-shared)
- All metrics history
- Fresh state for their own tasks

---

## Update — /moira upgrade

(Phase 12 deliverable — not yet implemented)

```bash
> /moira upgrade
```

Or from terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/<org>/moira/main/src/remote-install.sh | bash
```

### Upgrade process

```
/moira upgrade
  │
  ├─ 1. Fetch latest version info
  │    Current: 1.0.0
  │    Latest: 1.1.0
  │    Changelog: [displayed]
  │
  ├─ 2. Download new global layer
  │
  ├─ 3. Diff analysis: what changed?
  │    ├─ New: auditor.yaml updated (added 2 checks)
  │    ├─ Changed: implementer.yaml (prompt improvement)
  │    ├─ Changed: base.yaml (new inviolable rule added)
  │    └─ New: rust-api.yaml preset added
  │
  ├─ 4. Compatibility check against project
  │    ├─ COMPATIBLE: base.yaml change — no project override
  │    ├─ COMPATIBLE: new preset — doesn't affect existing
  │    ├─ OVERRIDE: implementer.yaml — project has custom implementer
  │    │   → Keep project version, mark for review
  │    └─ No BREAKING changes
  │
  ├─ 5. GATE: User approves
  │    ═══════════════════════════════════════════
  │     MOIRA UPGRADE — v1.0.0 → v1.1.0
  │    ═══════════════════════════════════════════
  │     Changes:
  │     ├─ Auditor checks expanded
  │     ├─ Implementer prompt improved
  │     ├─ New inviolable rule: no eval()
  │     └─ New preset: Rust API
  │
  │     Compatibility:
  │     ├─ 3 changes apply cleanly
  │     └─ 1 conflict: your project has custom implementer
  │        → Your version kept. Review later with /moira audit
  │
  │     ▸ apply  — upgrade
  │     ▸ diff   — show detailed changes
  │     ▸ skip   — stay on current version
  │    ═══════════════════════════════════════════
  │
  └─ 6. Apply + verify
```

### Version pinning

Projects can pin Moira version:

```yaml
# .claude/moira/config.yaml
moira:
  version: "1.0.0"          # pinned
  auto_upgrade: false        # don't prompt for upgrades
```

This prevents surprise breakage on shared projects.

---

## Uninstall

### Global (remove Moira entirely)

```bash
rm -rf ~/.claude/moira
# Then manually remove Moira sections from ~/.claude/ configs
```

### Per-project (remove Moira from one project)

```bash
rm -rf .claude/moira
# Remove Moira sections from .claude/CLAUDE.md and .claude/AGENTS.md
# Remove hook entries from .claude/settings.json
```

No cleanup daemon needed. Delete files = uninstalled.

---

## Dependency Map

```
Moira requires:
├─ Claude Code CLI (claude)     # The runtime
├─ git                          # For rollback capability
└─ bash                         # For hooks (guard.sh, budget-track.sh)

Moira does NOT require:
├─ Node.js / npm                # No JS runtime needed
├─ Python / pip                 # No Python needed
├─ Docker                       # No containers
├─ Any database                 # State is files
├─ Any cloud service            # Fully local
├─ Any MCP server               # MCP is optional, not required
└─ Internet (after install)     # Works fully offline
```

---

## Team Adoption Flow

### First developer (sets up Moira for project)

```
1. Install Moira globally (curl | bash)                    # 30 sec
2. cd project && claude                                     # open project
3. /moira init                                              # bootstrap
4. Review generated config                                  # 1-2 min
5. git add .claude/moira && git commit                      # commit config
6. Push branch → merge PR                                   # team review
```

### Every other developer (joins existing Moira project)

```
1. Install Moira globally (curl | bash)                    # 30 sec (one-time)
2. git pull                                                 # get project config
3. cd project && claude                                     # open project
4. /moira init                                              # detects existing config
   → "Moira already configured for this project.
      Global layer ready. You're good to go."
5. /moira status                                            # verify
6. /moira <task>                                            # start working
```

No per-developer configuration needed. Project config is shared via git.

---

## Troubleshooting

### "Moira not found" when running /moira

```
Global layer not installed or skills not registered.
Fix: curl -fsSL https://...install.sh | bash
```

### "Version mismatch" warning

```
Global Moira: v1.1.0
Project expects: v1.0.0

This usually works fine (backward compatible).
To match exactly: check project's config.yaml for pinned version.
```

### "Hooks not working"

```
Check .claude/settings.json for hook entries.
Verify hook files are executable: chmod +x .claude/moira/hooks/*.sh
```

### "/moira init says already initialized but nothing works"

```
Config files exist but may be corrupted or from old version.
Fix: /moira init --force (regenerates config, preserves knowledge)
```

### "Agent errors about missing rules"

```
Global layer may be incomplete.
Fix: reinstall — curl ... | bash
```
