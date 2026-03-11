# Decision Log

All architectural decisions made during Moira system design.

---

## D-001: Orchestrator Never Executes

**Context:** How should main Claude interact with project code?
**Decision:** Main Claude is a pure orchestrator — never reads/writes project files, never runs commands.
**Alternatives rejected:**
- Hybrid mode (orchestrator can do simple tasks) — breaks predictability, encourages rationalization
- Orchestrator reads but doesn't write — still pollutes context
**Reasoning:** Minimal orchestrator context = no hallucination. Strict boundary = predictable behavior.

## D-002: File-Based Agent Communication

**Context:** How should agents communicate results to orchestrator?
**Decision:** Agents write detailed results to files, return only status summary to orchestrator.
**Alternatives rejected:**
- Full results in return message — pollutes orchestrator context
- Shared memory/state — not available in Claude Code architecture
**Reasoning:** File-based communication keeps orchestrator context clean. Agents can produce arbitrarily detailed output without impacting orchestrator.

## D-003: Deterministic Pipelines

**Context:** Should the system dynamically decide execution flow or follow fixed pipelines?
**Decision:** Fixed pipeline per task size (Quick/Standard/Full/Decomposition).
**Alternatives rejected:**
- Dynamic planning (system decides flow per task) — unpredictable, hard to debug
- Single pipeline for all (with skip-gates) — over-engineering for small tasks
**Reasoning:** Predictability requires determinism. Same input type = same execution path. Engineer knows what to expect.

## D-004: Approval Gates at Key Decision Points

**Context:** How much autonomy should the system have?
**Decision:** Gates at classification, architecture, plan, and final review. No full autonomy.
**Alternatives rejected:**
- Full autonomy — vibe coding, unpredictable
- Gate at every step — too many interruptions, slows work
- Confidence-based auto-approval — introduces unpredictability
**Reasoning:** Engineers should focus on WHAT not HOW, but must approve KEY decisions. Gates are at points where wrong decisions are most costly to fix.

## D-005: Modular Rules System (4 layers)

**Context:** How to structure agent rules across projects?
**Decision:** 4-layer system: Base (universal) → Role (per agent) → Project → Task-specific.
**Alternatives rejected:**
- Monolithic per-agent files — duplication, hard to maintain
- 2-layer (global + project) — not granular enough
**Reasoning:** Modular system allows DRY rules, project-specific overrides, and per-task customization. Planner assembles rules for each agent invocation.

## D-006: Three-Level Knowledge Documentation

**Context:** How to make knowledge useful without consuming context budget?
**Decision:** L0 (index, ~100-200 tokens) → L1 (summary, ~500-2k) → L2 (full, ~2-10k). Each agent loads only the level it needs.
**Alternatives rejected:**
- Single-level (always full) — wastes context budget
- Two-level (summary + full) — index useful for agents that need minimal context
**Reasoning:** Different agents need different depth. Explorer needs almost nothing (unbiased). Implementer needs full conventions. This matrix optimizes budget per agent.

## D-007: Hybrid Knowledge Bootstrapping

**Context:** How to initialize knowledge for a new project?
**Decision:** Quick scan at init (~2-3 min) + deep scan in background during first tasks.
**Alternatives rejected:**
- Deep scan at init (20+ min) — too slow for first use
- No init, organic only — first tasks have no context, may go wrong
**Reasoning:** Quick scan provides enough for first tasks. Deep scan runs without blocking. Organic growth fills gaps over time.

## D-008: Smart Batching with Contract Interfaces

**Context:** How to parallelize multi-file implementation?
**Decision:** Planner builds dependency graph, clusters independent files, defines contracts between dependent batches.
**Alternatives rejected:**
- One agent for all files — context budget risk on large tasks
- One agent per file — loses cross-file coherence
**Reasoning:** Semantic batches preserve coherence within batch. Contracts prevent conflicts between batches. Shared files go to final batch.

## D-009: Branch-Scoped State, Shared Knowledge

**Context:** How to handle multiple developers?
**Decision:** Task state is branch-scoped (gitignored). Knowledge is shared (git-tracked, merges with PRs).
**Alternatives rejected:**
- Everything shared — state conflicts between developers
- Everything isolated — knowledge doesn't accumulate
**Reasoning:** State is per-session, per-task, per-developer. Knowledge benefits everyone and should merge through standard git flow.

## D-010: Controlled Quality Evolution

**Context:** Should the system improve existing code patterns?
**Decision:** Two modes: CONFORM (default, follow patterns) and EVOLVE (explicit, systematic improvement). Evolution requires evidence threshold + user approval.
**Alternatives rejected:**
- Always improve — creates chaos, inconsistency
- Never improve — project stagnates
- Automatic improvement — no human oversight
**Reasoning:** Consistency > perfection for daily work. Evolution happens when evidence is strong and scope is controlled.

## D-011: Batch Audit Approval by Risk Level

**Context:** How to approve audit recommendations?
**Decision:** Low-risk: batch apply with confirmation. Medium: individual approval. High: detailed review required.
**Alternatives rejected:**
- All individual — too slow for low-risk items
- All batch — risky for high-impact changes
**Reasoning:** Proportional approval reduces overhead while maintaining safety for impactful changes.

## D-012: Tiered Audit Depth

**Context:** How often and how deep should audits run?
**Decision:** Light audit every 10 tasks (passive), standard every 20 (or manual), deep on upgrade/quarterly.
**Alternatives rejected:**
- Always deep — wastes tokens and time
- Only manual — issues accumulate undetected
**Reasoning:** Most issues caught by light/standard audit. Deep audit reserved for significant events.

## D-013: Self-Contained System

**Context:** Should Moira depend on external skill systems (GSD, Superpowers, etc.)?
**Decision:** Moira is self-contained with no external dependencies.
**Alternatives rejected:**
- Build on GSD — external changes could break Moira
- Integrate Superpowers — creates coupling
**Reasoning:** Independence ensures stability. External system changes cannot break Moira.

## D-014: Escape Hatch with Explicit Activation Only

**Context:** Should engineers be able to bypass the pipeline?
**Decision:** Yes, but only through `/moira bypass:` command with explicit "2" confirmation. Cannot be triggered by prompt manipulation.
**Alternatives rejected:**
- No bypass — too rigid for experienced engineers
- Easy bypass — becomes default, undermines system
**Reasoning:** Availability reduces friction. Friction to activate prevents misuse. Audit tracks usage for quality correlation.

## D-015: Foreground Sequential, Background Parallel

**Context:** How to spawn agents — foreground (blocking) or background?
**Decision:** Sequential pipeline steps: foreground. Parallel batches: background. Post-task reflection: background.
**Alternatives rejected:**
- All foreground — can't parallelize independent work
- All background — orchestrator can't make step-dependent decisions
**Reasoning:** Quality requires seeing each step's result before deciding next step. Speed comes from parallelizing independent batches.

## D-016: User Documentation Inside Moira

**Context:** How to help users learn the system?
**Decision:** Built-in help system (`/moira help <topic>`) + micro-onboarding + progressive disclosure.
**Alternatives rejected:**
- External docs only — hard to access during work
- No docs, intuitive UX only — complex system needs reference
**Reasoning:** Help at point of use is most effective. Progressive disclosure prevents overwhelm.

## D-017: Constitutional Invariants for Self-Protection

**Context:** How to prevent the system from degrading during iterative development?
**Decision:** Three-layer defense: regression detection + design conformance + constitutional verification. Constitution defines binary pass/fail invariants that cannot be violated.
**Alternatives rejected:**
- Tests only — can't catch architectural violations, only functional ones
- Code review only — relies on reviewer catching every invariant, not systematic
- No formal protection — "we'll be careful" is not a strategy
**Reasoning:** Moira is complex enough that accidental degradation is inevitable without structural protection. Constitution makes invariants explicit and verifiable. Three layers catch different types of regression.

## D-018: Design-First Development Protocol

**Context:** What happens when implementation needs to deviate from design?
**Decision:** Design documents MUST be updated FIRST (with user approval), THEN implementation follows. Never implement first and document later.
**Alternatives rejected:**
- Implementation-first — design docs become stale, divergence grows
- No formal protocol — leads to "I'll update docs later" which never happens
**Reasoning:** Design documents are the source of truth. If they diverge from implementation, nobody knows which is correct. Design-first ensures intentional evolution.

## D-019: Risk-Classified Change Management

**Context:** Should all changes go through the same review process?
**Decision:** Four risk levels (RED/ORANGE/YELLOW/GREEN) with proportional verification requirements.
**Alternatives rejected:**
- All changes equal — too slow for safe changes, not careful enough for dangerous ones
- No classification — developers guess what needs extra attention
**Reasoning:** Proportional effort. Typo fix shouldn't need constitutional review. Pipeline gate removal absolutely should.

## D-020: File-Copy Distribution Model

**Context:** How should users install Moira?
**Decision:** Single shell script (`install.sh`) that copies files to `~/.claude/moira/`. No package manager, no build step, no runtime dependencies beyond Claude Code + git + bash.
**Alternatives rejected:**
- npm package — adds Node.js dependency, unnecessary complexity for non-JS projects
- Homebrew formula — platform-specific, adds maintenance burden
- Claude Code plugin/extension system — doesn't exist yet, can't depend on future features
- Docker — absurd overhead for config files
**Reasoning:** Moira is just markdown + YAML + shell scripts. Installation = file copy. Simplest possible distribution. Works on any OS with Claude Code. Install in <30 sec.

## D-021: Verification Agents for Moira Development

**Context:** How to automate the three-layer verification?
**Decision:** Two dedicated agents: moira-verifier (post-change) and moira-impact-analyzer (pre-change). Defined in AGENTS.md for the Moira project itself.

## D-022: Project Config via Git, State via Gitignore

**Context:** What gets committed to the project repo?
**Decision:** Project rules, knowledge, config, metrics → committed (shared with team). Task state, locks, bypass log → gitignored (per-developer).
**Alternatives rejected:**
- Everything committed — task state conflicts between developers
- Nothing committed — each developer re-bootstraps from scratch, no shared knowledge
- Separate config repo — adds complexity for no benefit
**Reasoning:** Rules and knowledge benefit the whole team. Task state is per-session and per-developer. Git is the natural sharing mechanism for team config. Second developer joining project gets all accumulated knowledge instantly.
**Alternatives rejected:**
- Manual verification only — humans miss things, especially after long sessions
- CI/CD pipeline — not available in Claude Code context
- Single agent for everything — too much responsibility, unclear output
**Reasoning:** Pre-change analysis prevents bad changes from being made. Post-change verification catches what slipped through. Two agents with clear roles match Moira's own design philosophy.

## D-023: Layered Testing Architecture

**Context:** How to test both orchestration correctness and agent output quality?
**Decision:** Three-layer architecture: Structural Verifier (bash, 0 tokens, deterministic), Behavioral Bench (full Moira runs on fixtures, LLM-judge), Live Telemetry (passive metrics during real use).
**Alternatives rejected:**
- Test-as-Pipeline (testing as another Moira pipeline) — circular dependency, broken Moira = broken tests
- External Harness (separate tool outside Moira) — duplicates orchestration logic, two things to maintain
**Reasoning:** Structural layer is independent (works even if Moira is broken). Behavioral layer tests real behavior without duplication. Live layer is nearly free. Each layer catches different failure modes.

## D-024: LLM-Judge with Anchored Rubrics

**Context:** How to evaluate stochastic agent output quality objectively?
**Decision:** Separate Claude call evaluates results against rubrics with concrete anchored examples per score level (1-5). Hybrid approach: automated checks (compile/lint) as hard pass/fail, LLM-judge for qualitative assessment.
**Alternatives rejected:**
- Automated checks only — too shallow, passing lint doesn't mean good code
- Free-form LLM evaluation — too noisy, unpredictable scores
- Structured rubric without anchors — less calibrated, subjective interpretation of scale
**Reasoning:** Anchored examples minimize judge subjectivity. Calibration set validates judge stability. Judge SHOULD use a different model tier than agents when budget allows; same-tier evaluation is acceptable but marked in reports. Model tiers (not pinned versions) are specified in design to avoid staleness.

## D-025: Statistical Confidence Bands for Metrics

**Context:** How to distinguish real regressions from stochastic noise in LLM outputs?
**Decision:** Baseline + variance tracking per metric. Three zones: NORMAL (within band, ignore), WARN (1-2σ, observe), ALERT (>2σ, investigate). Minimum effect size threshold prevents reacting to insignificant changes.
**Alternatives rejected:**
- Fixed thresholds — don't account for natural variance per metric
- Multiple runs per test — too expensive in tokens
- No statistical model — every fluctuation looks like regression
**Reasoning:** Accumulation over time builds statistical profile cheaply. Cold start protocol handles initial lack of data. Deterministic checks separated entirely (binary, no variance).

## D-026: Tiered Test Execution by Change Risk

**Context:** When to run full bench vs quick checks?
**Decision:** Three tiers: Tier 1 (structural smoke, 0 tokens, always), Tier 2 (targeted bench, 3-5 tests, for prompt/rule changes), Tier 3 (full bench, all tests, for pipeline/gate/role boundary changes). Auto-detected from git diff, user can override.
**Alternatives rejected:**
- Always full bench — too expensive, burns token budget
- Always smoke only — misses behavioral regressions
- Manual selection only — requires user to know which tests matter
**Reasoning:** Proportional testing matches Moira's own risk classification (RED/ORANGE/YELLOW/GREEN). Budget guards prevent runaway spending.

## D-027: Privacy-First Live Telemetry

**Context:** How to collect metrics from real projects without leaking sensitive data?
**Decision:** Record only numbers and enums, never content. Three privacy levels: local-only (default), anonymized export (opt-in), team sharing (aggregates only). Sanitization pipeline rejects unexpected strings.
**Alternatives rejected:**
- No live telemetry — lose the most valuable real-world signal
- Full logging — privacy risk, storage bloat
- Opt-in only — most users won't opt in, insufficient data
**Reasoning:** Default-safe (local-only, gitignored) builds trust. Metrics without content is sufficient for all decision-making. Sanitization catches bugs that might leak content.

## D-028: Classifier as Full Agent

**Context:** pipelines.md references a Classifier agent but agents.md doesn't define it. Is it a separate agent or orchestrator function?
**Decision:** Classifier is the 10th agent (8 base + Auditor + Classifier) with full role definition, NEVER constraints, and budget allocation.
**Alternatives rejected:**
- Orchestrator-embedded classification — violates Art 1.1 (orchestrator purity), creates exception to "orchestrator never executes"
**Reasoning:** Preserves Art 1.1 completely. Consistent with architecture principle that all work is done by agents. Classification is a decision that benefits from knowledge context (L1 access).

## D-029: Full YAML Schemas Upfront

**Context:** Five state files (manifest.yaml, current.yaml, queue.yaml, config.yaml, status.yaml) referenced throughout design but no schemas defined. Should we define them minimally or fully?
**Decision:** Full schemas designed upfront for all 12 phases.
**Alternatives rejected:**
- Minimal schemas (Phase 1-3 only) — requires schema migration later, risks ad-hoc decisions
- Minimal + reserved sections — false precision for unknown fields
**Reasoning:** Per D-018, design documents must be updated first. Inventing schemas during implementation = making architectural decisions ad-hoc. Full schemas prevent this. All 12 phases have enough design context to specify fields now.

## D-030: Native Custom Commands for Distribution

**Context:** How to make `/moira` commands available to users?
**Decision:** Use Claude Code native custom commands (`~/.claude/commands/moira/*.md`). Same file convention as GSD, but zero GSD runtime dependency.
**Alternatives rejected:**
- Plugin system (marketplace) — requires marketplace infrastructure, overkill for v1
- CLAUDE.md-only — no slash command entry points, poor UX
- GSD runtime dependency — violates D-013 (self-contained)
**Reasoning:** Custom commands are a native Claude Code feature. File-based discovery (markdown + YAML frontmatter). `install.sh` copies files — consistent with D-020 (file-copy distribution). No external dependencies — consistent with D-013.

## D-031: Three-Layer Guard Mechanism

**Context:** Design assumed PreToolUse hooks for blocking orchestrator violations. Research confirmed PreToolUse does not exist in Claude Code — only PostToolUse.
**Decision:** Three-layer defense replacing single guard.sh:
1. `allowed-tools` in command frontmatter (prevention — orchestrator physically cannot call Edit/Grep/Glob/Bash)
2. PostToolUse `guard.sh` hook (detection — logs violations, injects warning into context)
3. CLAUDE.md prompt enforcement (guidance — inviolable rules about orchestrator boundaries)
**Alternatives rejected:**
- Prompt-only enforcement — no structural guarantee, relies on model compliance
- PostToolUse with rollback — too complex, cannot undo all side effects
**Reasoning:** `allowed-tools` is stronger than PreToolUse would have been — it prevents the tool from being available at all, not just blocking individual calls. PostToolUse provides audit trail for constitutional verification (Art 6.3). Prompt rules are defense-in-depth.

## D-032: Bootstrap Scanners as Explorer Invocations

**Context:** knowledge.md introduces 4 scanner agents (Tech, Structure, Convention, Pattern) not defined in agents.md. Should they be new agent types?
**Decision:** Scanners are Explorer agent invocations with different task-specific instructions (Layer 4 rules). No new agent types.
**Alternatives rejected:**
- 4 separate agents — agent proliferation (13 total), each scanner does exactly what Explorer does
- Single Scanner agent with mode parameter — unnecessary abstraction for 4 invocations
**Reasoning:** Explorer's role is "reads code, reports facts — NEVER proposes solutions." Scanning is exactly this. Layer 4 instructions customize what facts to report. Consistent with D-005 (modular rules, Layer 4 = task-specific). No new NEVER constraints needed — Explorer's existing constraints apply.

## D-034: Greek Mythology Naming System

**Context:** System needs a memorable, unique, viral-friendly identity. Original name "Forge" is overloaded (SourceForge, Electron Forge, Minecraft Forge, etc.), has poor SEO, and doesn't convey orchestration.
**Decision:** Rename system to **Moira** (the three Fates). All agents, components, and pipeline phases named after Greek mythological figures. Every name displayed as `Name (role)` format — always, everywhere, no exceptions.
**Alternatives rejected:**
- Keep "Forge" — poor googlability, crowded namespace, no mythological depth for subsystem naming
- Latin/Norse mythology — Greek has strongest cultural recognition and largest namespace
- Abstract tech names — forgettable, no narrative cohesion
**Reasoning:** Greek mythology provides: (1) meaningful metaphors (three Fates = three pipeline phases), (2) vast extensible namespace, (3) cultural resonance that aids memorability and word-of-mouth, (4) unique identity in dev tooling space. The `Name (role)` convention ensures mythology never becomes a barrier to understanding. Full mapping in `architecture/naming.md`.

## D-033: Locks in Committed Zone with TTL

**Context:** locks.yaml was in gitignored state/ directory, but locks must be visible across developers.
**Decision:** Move locks.yaml to committed config zone (`.claude/moira/config/locks.yaml`). Add TTL (`expires_at` field) for stale lock detection.
**Alternatives rejected:**
- Keep in gitignored state — defeats purpose of locks (invisible to other developers)
- External lock service — violates D-013 (self-contained)
- Shared network file — requires infrastructure beyond git
**Reasoning:** Locks exist for cross-developer coordination. Must be in git to be shared. TTL prevents permanent locks from crashed sessions. Stale lock detection runs during audit (D-012). Standard git merge handles conflicts.
