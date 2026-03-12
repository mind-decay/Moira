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

## D-035: Pipeline Definitions as Separate YAML Files

**Context:** Where should pipeline step sequences and gate definitions live — inline in the orchestrator skill or as separate data files?
**Decision:** Separate YAML files in `core/pipelines/` (quick.yaml, standard.yaml, full.yaml, decomposition.yaml). Orchestrator reads the appropriate definition at runtime.
**Alternatives rejected:**
- Inline in orchestrator skill — mixes data with logic, not independently testable, harder to diff
- Single pipelines.yaml — all 4 pipelines in one file makes targeted testing harder
**Reasoning:** Separation of data from logic. Pipeline definitions are independently testable by Tier 1 structural checks. Changes are detectable by git diff for D-026 trigger matrix. One file per pipeline type matches the deterministic selection model (Art 2.1).

## D-036: Extended Pipeline State Steps

**Context:** `state.sh` defines valid pipeline steps for `moira_state_transition()`. Original set (Phase 1): classification, exploration, analysis, architecture, plan, implementation, review, testing, reflection. Phase 3 pipelines require additional steps.
**Decision:** Add three step names: `decomposition` (Planner decomposes epic), `integration` (cross-phase/cross-task verification), `completion` (final gate + post-pipeline actions).
**Alternatives rejected:**
- Reuse existing names (e.g., `plan` for decomposition) — semantically wrong, confuses state tracking
- Free-form step names without validation — loses determinism guarantee, any typo silently passes
**Reasoning:** State machine step names must be explicit and validated. Each new step corresponds to a distinct pipeline phase that doesn't map to existing names. Validation prevents silent errors.

## D-037: Final Gate Completion Actions Separate from Gate Decisions

**Context:** `moira_state_gate()` validates gate decisions as proceed/modify/abort. But the final gate offers done/tweak/redo/diff/test — these don't fit the gate decision model.
**Decision:** Final gate completion actions are NOT gate decisions. When user chooses any completion action, the gate is recorded as `proceed`. The completion action (done/tweak/redo/diff/test) triggers a separate orchestrator flow after the gate record.
**Alternatives rejected:**
- Extend `moira_state_gate()` to accept completion actions — mixes gate semantics (approve/reject/modify) with post-completion flow control
- Don't record the final gate — violates Art 3.1 (all decisions traceable)
**Reasoning:** Gates are approval checkpoints (Art 2.2). Completion actions are workflow routing. Keeping them separate preserves clean gate semantics and allows state.sh to remain simple and validated. The completion action is tracked separately in status.yaml `completion.action` field (already in schema).

## D-038: E7/E8 Error Stubs in Phase 3

**Context:** fault-tolerance.md defines 8 error types (E1-E8). E7 (rule drift) depends on guard hooks (Phase 8). E8 (stale knowledge) depends on knowledge system (Phase 4). Should Phase 3 implement full handlers or stubs?
**Decision:** E1-E6 fully implemented. E7 and E8 are stub handlers: log if detected, escalate to user. No automated detection logic.
**Alternatives rejected:**
- Full E1-E8 implementation — impossible without Phase 4/8 dependencies
- Omit E7/E8 entirely — errors.md would be incomplete, Phase 4/8 would need structural additions
**Reasoning:** Stubs establish the handler structure so future phases only need to fill in detection logic, not restructure the error handling system.

## D-039: Full Knowledge Dimensions in Access Matrix

**Context:** Phase 4 review revealed knowledge-access-matrix.yaml had only 4 dimensions (project_model, conventions, decisions, patterns) while knowledge.md defines 6 knowledge types (+ quality_map, failures). The plan hardcoded quality-map access for only 2 of 3 agents that need it, missing daedalus.
**Decision:** Expand knowledge-access-matrix.yaml to include all 6 dimensions. quality_map: metis=L1, daedalus=L0, themis=L1, mnemosyne/argus=L2, rest=null. failures: mnemosyne/argus=L2, rest=null (populated by Reflector in Phase 10). Remove hardcoded special-casing from plan — all access is matrix-driven.
**Alternatives rejected:**
- Keep 4 dimensions + hardcode quality-map — fragile, easy to miss agents, violates single source of truth
- Add failures access for more agents now — no content exists until Phase 10, premature
**Reasoning:** Single source of truth for agent knowledge access. Matrix-driven access is testable and prevents hardcoded exceptions that diverge from design docs over time.

## D-040: Daedalus Writes Instruction Files (Not Orchestrator)

**Context:** Who should assemble the multi-layer instruction files for post-planning agents?
**Decision:** Daedalus (planner) writes complete instruction files to `state/tasks/{id}/instructions/{agent}.md`. The orchestrator reads these files at dispatch time instead of constructing prompts inline.
**Alternatives rejected:**
- Orchestrator assembles instructions at dispatch time — moves complexity into orchestrator, violates Art 1.1 (orchestrator purity)
- Separate "assembler" utility — adds a component when Daedalus already understands the plan context
**Reasoning:** The Planner is the only agent that understands the full task plan and can determine which knowledge and rules each downstream agent needs. Keeps orchestrator simple.

## D-041: Dual Prompt Construction Path

**Context:** How do pre-planning agents (Apollo, Hermes, Athena) get their prompts when no instruction files exist yet?
**Decision:** Two paths: pre-planning agents use simplified Phase 3 assembly; post-planning agents use pre-assembled instruction files from Daedalus. Quick pipeline uses simplified assembly throughout.
**Alternatives rejected:**
- Require Daedalus for all agents — creates circular dependency (classifier must run before planner)
- Single assembly path with optional knowledge — loses the structured instruction file benefits
**Reasoning:** Pre-planning agents run before Daedalus, so no instruction files can exist. The simplified path is the correct minimal-context path for agents that don't need full project knowledge.

## D-042: Structural Consistency Validation (Not Semantic)

**Context:** How should knowledge consistency be checked at write time?
**Decision:** Shell-based keyword heuristics that catch obvious contradictions (same key, different value). Not LLM reasoning.
**Alternatives rejected:**
- Skip consistency checks entirely — risks silent knowledge corruption
- Full semantic validation at write time — requires agent dispatch, too expensive for every write
**Reasoning:** Shell can't do semantic reasoning. Structural checks catch the most common contradictions cheaply. Full semantic consistency is the Reflector's job (Phase 10/11).

## D-043: Knowledge Templates as Installed Files

**Context:** How should knowledge structure templates be distributed?
**Decision:** Templates are part of the global installation (`~/.claude/moira/templates/knowledge/`) and copied to projects by `scaffold.sh`. Static files, not generated dynamically.
**Alternatives rejected:**
- Generate templates dynamically at init — adds runtime complexity, harder to test
- Inline templates in scaffold.sh — harder to maintain, not inspectable
**Reasoning:** Templates define structure, not content. File-based approach is testable, versionable, inspectable. Consistent with D-020 (file-copy distribution model).

## D-044: AGENTS.md Generation Deferred

**Context:** `distribution.md` Step 7 defines AGENTS.md generation with project-adapted agent definitions during `/moira:init`. Should Phase 5 implement this?
**Decision:** Defer AGENTS.md generation to Phase 6+ when quality gates exist to validate adapted agent definitions.
**Alternatives rejected:**
- Implement in Phase 5 with basic validation — adapted agents need quality gates to verify the adaptations don't weaken NEVER constraints
- Generate static AGENTS.md without adaptation — low value, global agent definitions from Phase 2 work correctly
**Reasoning:** (1) Adapted agents need quality gates (Phase 6) to validate that project-specific customization doesn't violate agent role boundaries (Art 1.2). (2) Global agent definitions work correctly without project adaptation. (3) The value of project-adapted AGENTS.md is marginal until the system has run enough tasks to understand what adaptations matter.

## D-045: Bootstrap Fields in Config Schema

**Context:** Phase 5 `/moira:init` needs to track bootstrap state (quick scan completed, deep scan pending) in config.yaml. These fields were referenced in the Phase 5 spec but not defined in config.schema.yaml.
**Decision:** Add `bootstrap.*` fields to config.schema.yaml: `quick_scan_completed` (bool), `quick_scan_at` (string/timestamp), `deep_scan_completed` (bool), `deep_scan_pending` (bool). All optional, default to false/"".
**Reasoning:** Per D-029 (full YAML schemas upfront), schema must be defined before implementation. Bootstrap state is project config (committed to git) because team members need to know whether deep scan has run.

## D-046: LLM-Judge Deferred to Phase 10

**Context:** Roadmap Phase 6 testing section mentions "LLM-judge with anchored rubrics (D-024)". However, `testing.md` roadmap integration explicitly assigns LLM-Judge implementation to Phase 10 alongside the Reflector. Which timing is correct?
**Decision:** Phase 6 creates rubric DEFINITION files (YAML with anchored examples) and bench infrastructure with automated checks only (compile, lint, test pass/fail). The actual LLM-Judge invocation (Claude call for qualitative evaluation) is deferred to Phase 10.
**Alternatives rejected:**
- Full LLM-Judge in Phase 6 — the judge evaluates the same dimensions as the Reflector (requirements coverage, code correctness, architecture quality, conventions adherence). Implementing them together ensures consistency.
- No bench infrastructure in Phase 6 — the fixtures and test case format are needed regardless of the judge. Automated checks provide immediate value.
**Reasoning:** testing.md's Phase 10 assignment is correct. The LLM-Judge and Reflector share evaluation patterns — implementing them in the same phase prevents divergence. Phase 6 bench results include structural/automated scores only; quality scores are `null` until the judge is operational.

## D-047: Quality Findings as Separate YAML Files

**Context:** Should quality findings (checklist results, severity classifications) be embedded in the main agent output files (review.md, requirements.md) or written to dedicated files?
**Decision:** Dedicated files: `state/tasks/{id}/findings/{agent}-{gate}.yaml`. Structured YAML format with machine-parseable verdict field.
**Alternatives rejected:**
- Inline in agent markdown output — requires parsing markdown for routing decisions, fragile
- Findings in status.yaml — bloats the per-task status file, mixes state with data
**Reasoning:** (1) Machine-parseable: YAML enables deterministic routing without markdown parsing. (2) Separation of concerns: detailed analysis in .md, routing data in .yaml. (3) Aggregation: quality.sh can scan the directory without understanding markdown structure. (4) Historical: findings persist for Reflector analysis in Phase 10.

## D-048: Bench Mode Gate Auto-Response

**Context:** Behavioral bench tests need to run Moira pipelines with predefined gate responses (from test case YAML). How should gates be handled during bench runs?
**Decision:** A `bench_mode` flag in `current.yaml`. When true, the orchestrator reads gate responses from the test case file instead of prompting the user. All gate decisions are still recorded in state files.
**Alternatives rejected:**
- Separate bench pipeline that skips gates — tests different behavior than production, defeats purpose
- External harness that intercepts and responds — duplicates orchestration logic, maintenance burden
**Reasoning:** Bench tests must exercise the ACTUAL pipeline to be meaningful. Auto-response reuses production code with a single flag check at each gate. Does not violate Art 4.2 because the user explicitly chose to run the bench test. Full traceability maintained (Art 3.1).

## D-049: QUALITY Line in Agent Response Contract

**Context:** How should the orchestrator determine quality gate verdict without reading the full findings file?
**Decision:** Add a `QUALITY` summary line to the agent response contract: `QUALITY: {gate}={verdict} ({critical}C/{warning}W/{suggestion}S)`. The orchestrator reads the full findings file ONLY when presenting WARNING details to the user.
**Alternatives rejected:**
- Always read full findings file — wastes orchestrator context on every quality gate
- Parse findings inline from agent return text — fragile markdown parsing
**Reasoning:** Per D-001 (minimal orchestrator context), the QUALITY line provides routing signal in a single line. Full findings are file-based (D-002). The orchestrator reads findings only for WARNING gate presentation, not for pass/fail_critical routing.

## D-050: Deep Scan as Phase 6 Deliverable

**Context:** Phase 5 placed the deep scan trigger in the orchestrator but deferred agent instructions. When should deep scan templates be implemented?
**Decision:** Phase 6 implements deep scan agent instructions. Deep scan output is validated through the quality map system — scan results feed into the quality map with `medium` confidence, requiring 3+ task observations to reach `high` confidence (Art 5.2).
**Alternatives rejected:**
- Phase 5 — quality gates needed to validate deep scan output quality
- Phase 10 — too late, deep scan data feeds quality map which is needed earlier
**Reasoning:** Phase 6 provides quality gates. Deep scan results are structural knowledge (file lists, dependency graphs) validated by the quality map confidence system, not by LLM judgment. Phase 5 left the stub; Phase 6 completes it.

## D-051: Quality Map Evolution is Structural, Not Semantic

**Context:** How should quality map entries be updated based on Reviewer findings?
**Decision:** `moira_knowledge_update_quality_map` uses keyword matching and observation counting (shell-based), not LLM reasoning. Consistent with D-042 (structural consistency validation).
**Alternatives rejected:**
- LLM-based semantic analysis at write time — too expensive for every task completion
- No automated updates — quality map stagnates
**Reasoning:** Shell can catch keyword-level matches (same pattern name + location). Counting observations is trivial. Full semantic analysis of pattern quality is the Reflector's job (Phase 10). This keeps the write path cheap and deterministic.

## D-052: Fixture Projects are Minimal

**Context:** How large should bench fixture projects be?
**Decision:** Fixtures are intentionally small (3-25 files). They test Moira's pipeline behavior, not its ability to handle large codebases.
**Alternatives rejected:**
- Large realistic fixtures (100+ files) — slow to scan, expensive to reset, test the wrong thing
- Single fixture with flags — loses the greenfield/mature/legacy behavioral distinctions
**Reasoning:** Pipeline behavior (gate routing, quality checks, agent sequencing) doesn't depend on codebase size. Large codebase handling is tested via live telemetry on real projects (Phase 3). Minimal fixtures keep bench runs fast and token-efficient.

## D-053: WARNING Gate is a Conditional Gate Type

**Context:** Should quality warnings use an existing gate type or a new one?
**Decision:** WARNING gate is a new conditional gate type, distinct from required approval gates. It has different options (proceed/fix/details/abort) and is ONLY presented when warning findings exist.
**Alternatives rejected:**
- Reuse existing approval gate — different semantics (approval vs quality triage)
- Auto-proceed on warnings — violates Art 4.2 (user authority over quality decisions)
**Reasoning:** Required gates (classification, architecture, plan, final) are defined in pipeline YAML per Art 2.2. The WARNING gate is a conditional error-handling path, similar to E5-QUALITY retry. It doesn't violate Art 2.2 because it's not a pipeline-defined gate — it's a quality routing mechanism that only activates when warnings are present.

## D-054: Config Quality Fields Reconciled for Phase 6

**Context:** Phase 1 (D-029) created `quality.evolution_threshold` and `quality.review_severity_minimum` in config.schema.yaml based on early quality.md design. Phase 6 spec requires `quality.evolution.current_target` and `quality.evolution.cooldown_remaining` for EVOLVE mode lifecycle tracking.
**Decision:** Remove `quality.evolution_threshold` (superseded by hardcoded 3-observation rule per Art 5.2) and `quality.review_severity_minimum` (superseded by fixed severity routing: critical→retry, warning→gate, suggestion→log). Replace with `quality.evolution.current_target` (string) and `quality.evolution.cooldown_remaining` (number).
**Alternatives rejected:**
- Keep all fields — `evolution_threshold` conflicts structurally with `evolution.current_target` nesting, and configurable severity minimum contradicts the deterministic routing model (Art 2.1)
- Make evolution threshold configurable — Art 5.2 mandates 3+ observations, not user-configurable
**Reasoning:** The 3-observation threshold is a constitutional requirement (Art 5.2), not a tunable parameter. Severity routing is deterministic by design (Art 2.1). Configurable fields that contradict invariants create confusion about what the system actually does.

## D-055: Separate Budget Library

**Context:** Should budget functions live in state.sh or a dedicated module?
**Decision:** Dedicated `budget.sh` library, separate from `state.sh`. State handles transitions, budget handles estimation/tracking/reporting.
**Alternatives rejected:**
- Inline in state.sh — adds 9+ functions, violates Art 1.3 (no god components)
- Distributed across multiple modules — budget logic is cohesive, splitting it loses clarity
**Reasoning:** Single responsibility. Budget estimation is independently testable. state.sh remains focused on state transitions.

## D-056: Approximate Token Estimation

**Context:** How to estimate token counts without tokenizer access?
**Decision:** Use `file_size_bytes / 4` as token estimation ratio (industry-standard approximation for English/code).
**Alternatives rejected:**
- Exact tokenizer — not available in shell environment
- Character count only — tokens ≠ characters, ratio provides better approximation
- No estimation — budget system needs numbers to make split/no-split decisions
**Reasoning:** Sufficient for threshold decisions (below 50%, near 70%, above 70%). The 30% safety margin absorbs estimation errors. Precision is not needed — only directional correctness.

## D-057: Budget Config as Separate File

**Context:** Should budget allocations live in config.yaml or a dedicated file?
**Decision:** Separate `config/budgets.yaml` for per-project tuning. `config.schema.yaml` fields serve as fallback defaults.
**Alternatives rejected:**
- Inline in config.yaml — mixes general config with specialized tuning
- No project-level overrides — teams can't tune budgets for their codebase complexity
**Reasoning:** Budget allocations are the most likely config to need per-project tuning. Separation allows updating budgets without touching main config. Three-level lookup: budgets.yaml → config.yaml → schema defaults.

## D-058: Proxy-Based Orchestrator Context Estimation

**Context:** How to measure orchestrator token usage at runtime?
**Decision:** Proxy approach: base overhead (15k) + per-step processing (500/step) + gate interactions (2k/gate) + agent return summaries.
**Alternatives rejected:**
- Direct measurement — not feasible in Claude Code runtime
- No measurement — loses orchestrator health visibility
- Token counting hooks — hooks execute in separate processes, can't measure orchestrator context
**Reasoning:** Rough but sufficient for threshold-based decisions. The 25%/40%/60% thresholds have wide gaps specifically because estimation is approximate. Proxy is cheap to compute.

## D-059: Config-Driven MCP Token Estimates

**Context:** How to estimate MCP call token impact for budget calculations?
**Decision:** Static estimates from `budgets.yaml` (`mcp_estimates` section). Planner uses these estimates before calls happen.
**Alternatives rejected:**
- Runtime measurement — MCP call sizes only known after the call
- No MCP budgeting — MCP calls can be large (14k+ for context7), ignoring them risks budget overflow
- Hardcoded estimates — not tunable per project
**Reasoning:** MCP call sizes vary by query but have predictable ranges. Config-driven allows projects to tune based on actual usage patterns. Default values are conservative (14k for context7, 5k for unknown).
