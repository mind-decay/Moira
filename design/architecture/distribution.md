# Distribution & Installation

## What Forge Actually Is (technically)

Forge has no compiled code, no runtime dependencies, no binary. It is a structured set of:

| File type | Purpose | Location |
|-----------|---------|----------|
| Markdown (.md) | Agent prompts, skills, docs | `~/.claude/forge/` and `.claude/forge/` |
| YAML (.yaml) | Rules, configs, state schemas | Same |
| Shell scripts (.sh) | Hooks (guard, budget tracker) | Same |

That's it. Forge runs entirely within Claude Code's existing infrastructure — agents, skills, hooks, CLAUDE.md. No daemon, no server, no extra processes.

This means installation = putting the right files in the right places.

---

## Distribution Model

```
┌──────────────────────────────┐
│     GitHub Repository        │
│  github.com/<org>/forge      │
│                              │
│  Contains:                   │
│  ├─ install.sh               │
│  ├─ src/                     │
│  │   ├─ global/    (→ ~/.claude/forge/)
│  │   └─ templates/ (used by /forge init)
│  ├─ design/                  │
│  └─ README.md                │
└──────────────┬───────────────┘
               │
     install.sh / forge-update
               │
┌──────────────▼───────────────┐
│    GLOBAL LAYER              │
│    ~/.claude/forge/          │
│                              │
│  Installed once per machine. │
│  Shared across all projects. │
└──────────────┬───────────────┘
               │
          /forge init
               │
┌──────────────▼───────────────┐
│    PROJECT LAYER             │
│    <project>/.claude/forge/  │
│                              │
│  Generated per project.      │
│  Committed to project repo.  │
└──────────────────────────────┘
```

---

## Installation — One Command

### Option A: curl (recommended for simplicity)

```bash
curl -fsSL https://raw.githubusercontent.com/<org>/forge/main/install.sh | bash
```

### Option B: git clone (for contributors)

```bash
git clone https://github.com/<org>/forge.git ~/.forge-source
~/.forge-source/install.sh
```

### What install.sh Does

```bash
#!/bin/bash
set -euo pipefail

FORGE_VERSION="1.0.0"
FORGE_HOME="$HOME/.claude/forge"
FORGE_SOURCE="${FORGE_SOURCE_DIR:-$(mktemp -d)}"

echo "═══════════════════════════════════════"
echo "  Installing Forge v${FORGE_VERSION}"
echo "═══════════════════════════════════════"

# ── Step 1: Check prerequisites ──────────
check_prerequisites() {
    # Claude Code must be installed
    if ! command -v claude &> /dev/null; then
        echo "Error: Claude Code CLI not found."
        echo "Install it first: https://docs.anthropic.com/claude-code"
        exit 1
    fi

    # Git must be available (Forge uses git for rollback)
    if ! command -v git &> /dev/null; then
        echo "Error: git not found."
        exit 1
    fi

    echo "✓ Prerequisites met"
}

# ── Step 2: Download or copy source ──────
fetch_source() {
    if [ -d "$FORGE_SOURCE/src" ]; then
        echo "✓ Using local source"
    else
        echo "  Downloading Forge v${FORGE_VERSION}..."
        curl -fsSL "https://github.com/<org>/forge/archive/v${FORGE_VERSION}.tar.gz" \
            | tar xz -C "$FORGE_SOURCE" --strip-components=1
        echo "✓ Downloaded"
    fi
}

# ── Step 3: Install global layer ─────────
install_global() {
    echo "  Installing global layer to $FORGE_HOME..."

    # Create directory structure
    mkdir -p "$FORGE_HOME"/{core/rules/roles,core/rules/quality,templates,skills,hooks}

    # Copy core files
    cp -r "$FORGE_SOURCE/src/global/core/"* "$FORGE_HOME/core/"
    cp -r "$FORGE_SOURCE/src/global/skills/"* "$FORGE_HOME/skills/"
    cp -r "$FORGE_SOURCE/src/global/hooks/"* "$FORGE_HOME/hooks/"
    cp -r "$FORGE_SOURCE/src/global/templates/"* "$FORGE_HOME/templates/"

    # Make hooks executable
    chmod +x "$FORGE_HOME/hooks/"*.sh

    # Write version marker
    echo "$FORGE_VERSION" > "$FORGE_HOME/.version"

    echo "✓ Global layer installed"
}

# ── Step 4: Install command files ─────────
install_commands() {
    echo "  Installing Forge commands..."

    # Native Claude Code custom commands (D-030)
    # Same file convention as GSD, zero runtime dependency
    mkdir -p "$HOME/.claude/commands/forge"
    cp -r "$FORGE_SOURCE/src/commands/forge/"* "$HOME/.claude/commands/forge/"

    echo "✓ Commands installed (/forge:init, /forge:task, etc.)"
}

# ── Step 5: Verify installation ──────────
verify() {
    local checks_passed=0
    local checks_total=5

    [ -f "$FORGE_HOME/core/rules/base.yaml" ] && ((checks_passed++))
    [ -f "$FORGE_HOME/skills/orchestrator.md" ] && ((checks_passed++))
    [ -f "$FORGE_HOME/hooks/guard.sh" ] && ((checks_passed++))
    [ -d "$FORGE_HOME/templates" ] && ((checks_passed++))
    [ -f "$FORGE_HOME/.version" ] && ((checks_passed++))

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
echo "  Forge v${FORGE_VERSION} installed ✓"
echo "═══════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "  1. Open your project directory"
echo "  2. Run Claude Code"
echo "  3. Type: /forge init"
echo ""
echo "  That's it. Forge will set up everything"
echo "  for your project automatically."
echo ""
```

### Installation time: <30 seconds

No build step. No compilation. No package manager resolution. Just file copy + verify.

---

## Global Layer File Map

After installation, `~/.claude/forge/` contains:

```
~/.claude/forge/
├── .version                          # "1.0.0"
├── core/
│   └── rules/
│       ├── base.yaml                 # Layer 1: inviolable + overridable rules
│       ├── roles/
│       │   ├── classifier.yaml       # Layer 2: agent role rules
│       │   ├── explorer.yaml
│       │   ├── analyst.yaml
│       │   ├── architect.yaml
│       │   ├── planner.yaml
│       │   ├── implementer.yaml
│       │   ├── reviewer.yaml
│       │   ├── tester.yaml
│       │   ├── reflector.yaml
│       │   └── auditor.yaml
│       └── quality/
│           ├── correctness.yaml
│           ├── performance.yaml
│           ├── security.yaml
│           └── standards.yaml        # SOLID, KISS, DRY
│
├── skills/
│   └── orchestrator.md               # Main orchestrator skill (referenced by commands)
│
├── commands/forge/                   # User-facing slash commands (D-030)
│   ├── init.md                      # /forge:init
│   ├── task.md                      # /forge:task — main entry point
│   ├── status.md                    # /forge:status
│   ├── metrics.md                   # /forge:metrics
│   ├── audit.md                     # /forge:audit
│   ├── knowledge.md                 # /forge:knowledge
│   ├── bypass.md                    # /forge:bypass
│   ├── resume.md                    # /forge:resume
│   ├── refresh.md                   # /forge:refresh
│   └── help.md                      # /forge:help
│
├── hooks/
│   ├── guard.sh                      # Orchestrator tool restriction
│   └── budget-track.sh              # Context usage logging
│
└── templates/
    ├── project-claude-md.tmpl        # CLAUDE.md template for projects
    ├── project-agents-md.tmpl        # AGENTS.md template for projects
    ├── project-config.tmpl           # config.yaml template
    ├── project-model.tmpl            # project-model skeleton
    ├── conventions.tmpl              # conventions.yaml skeleton
    ├── patterns.tmpl                 # patterns.yaml skeleton
    ├── quality-map.tmpl              # quality-map skeleton
    └── stack-presets/
        ├── nextjs.yaml               # Preset: Next.js project
        ├── react-vite.yaml           # Preset: React + Vite
        ├── express.yaml              # Preset: Express.js API
        ├── nestjs.yaml               # Preset: NestJS
        ├── fastapi.yaml              # Preset: Python FastAPI
        ├── django.yaml               # Preset: Python Django
        ├── go-api.yaml               # Preset: Go API
        ├── vue-nuxt.yaml             # Preset: Vue/Nuxt
        └── generic.yaml              # Fallback: unknown stack
```

---

## Project Setup — /forge init

After global installation, for each project:

```bash
cd /path/to/my-project
claude                    # start Claude Code
> /forge init             # that's it
```

### What /forge init does internally

```
/forge init
  │
  ├─ 1. CHECK: Is global layer installed?
  │    ├─ YES → continue
  │    └─ NO → "Forge not installed. Run: curl ... | bash"
  │
  ├─ 2. CHECK: Is project already initialized?
  │    ├─ YES → "Already initialized. Use /forge refresh to update."
  │    └─ NO → continue
  │
  ├─ 3. SCAN: Quick project analysis (4 parallel agents)
  │    ├─ Tech scanner → detects stack from package.json, configs, etc.
  │    ├─ Structure scanner → maps directory layout
  │    ├─ Convention scanner → reads linter configs + sample files
  │    └─ Pattern scanner → reads representative files per layer
  │
  ├─ 4. MATCH: Find closest stack preset
  │    Tech scanner found: Next.js 14, TypeScript, Tailwind, Prisma
  │    Closest preset: nextjs.yaml
  │    Augmented with: Prisma-specific patterns, Tailwind conventions
  │
  ├─ 5. GENERATE: Create project layer
  │    .claude/forge/
  │    ├─ config.yaml              (from preset + scan results)
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
  ├─ 6. INJECT: Project CLAUDE.md integration
  │    ├─ If .claude/CLAUDE.md exists → append Forge section
  │    └─ If not → create with Forge configuration
  │    (Never overwrites existing CLAUDE.md content)
  │
  ├─ 7. INJECT: Project AGENTS.md
  │    ├─ Generate project-adapted agent definitions
  │    └─ Stack-specific implementer, reviewer, tester prompts
  │
  ├─ 8. INJECT: Hooks configuration
  │    ├─ Add guard.sh and budget-track.sh to .claude/settings.json
  │    └─ Preserve existing hooks (append, don't overwrite)
  │
  ├─ 9. GATE: User reviews generated config
  │    ═══════════════════════════════════════════
  │     FORGE — Project Setup Complete
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
  │     ▸ accept  — start using Forge
  │     ▸ adjust  — correct something
  │    ═══════════════════════════════════════════
  │
  └─ 10. ONBOARDING: If first time → offer walkthrough
         (see onboarding.md)
```

### What gets committed to project repo

```
# .gitignore additions by Forge
.claude/forge/state/tasks/     # task execution state (per-developer)
.claude/forge/state/bypass-log.yaml

# These ARE committed (shared with team):
.claude/forge/config.yaml
.claude/forge/project/rules/
.claude/forge/config/
.claude/forge/knowledge/
.claude/forge/state/metrics/   # team-visible metrics
```

### Existing `.claude/` Compatibility

1. **`.claude/` already exists** — Forge creates only `.claude/forge/` subdirectory. Does not touch anything outside `forge/`.
2. **`.claude/CLAUDE.md` already exists** — Forge appends its section wrapped in markers:
   ```markdown
   <!-- forge:start -->
   ## Forge Orchestration System
   ...orchestrator instructions...
   <!-- forge:end -->
   ```
   On re-init or refresh — replaces only content between markers.
3. **`.claude/CLAUDE.md` does not exist** — Creates file with Forge section.
4. **`.claude/commands/` already exists** (GSD or other) — Forge uses its own `commands/forge/` namespace, no conflicts.
5. **Repeated `/forge:init`** — Idempotent. No duplicate sections, preserves knowledge.
6. **`/forge:init --force`** — Full reinitialization: recreates config, reruns scanners, preserves accumulated knowledge.

This means: when another developer clones the repo and runs `/forge init`, they get:
- All project-specific rules (already configured)
- All accumulated knowledge (team-shared)
- All metrics history
- Fresh state for their own tasks

---

## Update — /forge upgrade

```bash
> /forge upgrade
```

Or from terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/<org>/forge/main/install.sh | bash
```

### Upgrade process

```
/forge upgrade
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
  │     FORGE UPGRADE — v1.0.0 → v1.1.0
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
  │        → Your version kept. Review later with /forge audit
  │
  │     ▸ apply  — upgrade
  │     ▸ diff   — show detailed changes
  │     ▸ skip   — stay on current version
  │    ═══════════════════════════════════════════
  │
  └─ 6. Apply + verify
```

### Version pinning

Projects can pin Forge version:

```yaml
# .claude/forge/config.yaml
forge:
  version: "1.0.0"          # pinned
  auto_upgrade: false        # don't prompt for upgrades
```

This prevents surprise breakage on shared projects.

---

## Uninstall

### Global (remove Forge entirely)

```bash
rm -rf ~/.claude/forge
# Then manually remove Forge sections from ~/.claude/ configs
```

### Per-project (remove Forge from one project)

```bash
rm -rf .claude/forge
# Remove Forge sections from .claude/CLAUDE.md and .claude/AGENTS.md
# Remove hook entries from .claude/settings.json
```

No cleanup daemon needed. Delete files = uninstalled.

---

## Dependency Map

```
Forge requires:
├─ Claude Code CLI (claude)     # The runtime
├─ git                          # For rollback capability
└─ bash                         # For hooks (guard.sh, budget-track.sh)

Forge does NOT require:
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

### First developer (sets up Forge for project)

```
1. Install Forge globally (curl | bash)                    # 30 sec
2. cd project && claude                                     # open project
3. /forge init                                              # bootstrap
4. Review generated config                                  # 1-2 min
5. git add .claude/forge && git commit                      # commit config
6. Push branch → merge PR                                   # team review
```

### Every other developer (joins existing Forge project)

```
1. Install Forge globally (curl | bash)                    # 30 sec (one-time)
2. git pull                                                 # get project config
3. cd project && claude                                     # open project
4. /forge init                                              # detects existing config
   → "Forge already configured for this project.
      Global layer ready. You're good to go."
5. /forge status                                            # verify
6. /forge <task>                                            # start working
```

No per-developer configuration needed. Project config is shared via git.

---

## Troubleshooting

### "Forge not found" when running /forge

```
Global layer not installed or skills not registered.
Fix: curl -fsSL https://...install.sh | bash
```

### "Version mismatch" warning

```
Global Forge: v1.1.0
Project expects: v1.0.0

This usually works fine (backward compatible).
To match exactly: check project's config.yaml for pinned version.
```

### "Hooks not working"

```
Check .claude/settings.json for hook entries.
Verify hook files are executable: chmod +x .claude/forge/hooks/*.sh
```

### "/forge init says already initialized but nothing works"

```
Config files exist but may be corrupted or from old version.
Fix: /forge init --force (regenerates config, preserves knowledge)
```

### "Agent errors about missing rules"

```
Global layer may be incomplete.
Fix: reinstall — curl ... | bash
```
