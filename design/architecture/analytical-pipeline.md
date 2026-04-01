# Analytical Pipeline Architecture

## Purpose

The Analytical Pipeline handles tasks that produce **analysis and documentation** rather than code. It shares Moira's core principles (deterministic structure, approval gates, agent specialization, file-based communication) but introduces progressive depth, formal CS methods for rigor, and a new agent (Calliope) for document synthesis.

**Motivation:** Many high-value engineering tasks — architecture review, weakness analysis, decision comparison, documentation — don't produce code. Without a dedicated pipeline, these tasks either bypass Moira entirely or get forced through code-oriented pipelines where half the steps don't apply.

## Classification Extension

Apollo gains a second classification dimension: **mode**.

```
Classification output:
  mode: implementation | analytical
  size: small | medium | large | epic        (for implementation)
  subtype: research | design | audit |        (for analytical)
           weakness | decision | documentation
  confidence: high | low
```

Pipeline selection becomes two-dimensional (Art 2.1 — determinism preserved):

| Mode | Size/Subtype | Pipeline |
|------|-------------|----------|
| implementation | small + high confidence | Quick |
| implementation | small + low confidence | Standard |
| implementation | medium | Standard |
| implementation | large | Full |
| implementation | epic | Decomposition |
| analytical | any subtype | Analytical |

Apollo uses these signals to distinguish modes:
- Task mentions "implement", "fix", "add feature", "write", "create" → implementation
- Task mentions "analyze", "review", "audit", "compare", "document", "design", "investigate", "find weaknesses" → analytical
- Ambiguous → Apollo asks (STATUS: blocked)

---

## Analytical Subtypes

| Subtype | Description | Primary Agents | Ariadne Focus |
|---------|-------------|---------------|---------------|
| `research` | "How does X work?" | Hermes (deep) + Metis | targeted queries on area of interest |
| `design` | "Design subsystem Y" | Metis | smells, coupling, metrics for informed design |
| `audit` | "Verify state of Z" | Argus ∥ Metis | full scan: smells, cycles, layers, metrics |
| `weakness` | "Find architectural weaknesses in W" | Argus ∥ Metis | coupling hotspots, spectral analysis, smells |
| `decision` | "Compare approaches A vs B vs C" | Metis | blast radius per alternative, coupling impact |
| `documentation` | "Update/create document" | Athena → Calliope | whatever relevant to the docs being written |

---

## Pipeline Structure

```
Apollo (classifier) → classify (mode: analytical, subtype: ...)
  └─ GATE #1: confirm classification + scope

GATHER:
  Hermes (explorer) → code exploration per scope + Ariadne baseline queries
  (smells, metrics, coupling overview, clusters, layers)
  Implementation note (D-125): Hermes executes both code exploration and Ariadne
  baseline queries in a single foreground dispatch, not as parallel steps. The
  orchestrator cannot run Bash, and all pipeline steps are agent dispatches.

Athena (analyst) → analytical scope formalization
  - What questions are we answering?
  - What criteria define "sufficient"?
  - What is out of scope?
  - Depth recommendation: light / standard / deep
  └─ GATE #2: confirm scope + approve depth

ANALYSIS PASS 1:
  [subtype-specific agents — see table above]
  Agents have access to Ariadne MCP tools for targeted queries
  → initial findings (hypothesis + evidence + confidence)
  └─ GATE #3: depth checkpoint
      ├─ sufficient → proceed to synthesis
      ├─ deepen    → expand scope, run Pass 2
      ├─ redirect  → re-scope (back to Athena with prior findings as context, max 1x per pipeline)
      └─ abort

ANALYSIS PASS 2 (if deepened):
  [agents with expanded scope + targeted Ariadne queries on gaps]
  → detailed findings
  └─ GATE #4: depth checkpoint
      ├─ sufficient → proceed to synthesis
      ├─ deepen    → Pass 3 (cross-cutting analysis, rare)
      └─ abort

  ... (Pass N, converging toward fixpoint)

SYNTHESIS:
  Calliope (scribe) → write new / update existing documents

REVIEW:
  Themis (reviewer) → analytical quality review (QA1-QA4)
  └─ GATE #5: final review
      ├─ done       — accept deliverables
      ├─ details    — show full analysis
      ├─ modify     — provide feedback (→ re-synthesis by Calliope)
      ├─ re-analyze — evidence gap (→ back to analysis with QA feedback)
      └─ abort

Chat summary presented to user.
Post: Mnemosyne (background reflection)
Budget report displayed.
```

### Gate Count

| Scenario | Gates |
|----------|-------|
| Light (single pass, sufficient) | 3 (classify, scope, final) |
| Standard (single pass + synthesis) | 4 (classify, scope, depth checkpoint, final) |
| Deep (multi-pass) | 4+ (classify, scope, N depth checkpoints, final) |

Minimum gates: 3. Depth checkpoints add gates dynamically but each one requires user decision — Art 4.2 preserved.

**Cost unpredictability note:** Unlike implementation pipelines where scope (and therefore cost) is estimable upfront, analytical task depth is fundamentally open-ended. Each analysis pass costs 100k-240k tokens. The scope gate should inform the user that analytical depth is progressive and budget usage depends on how many passes are needed. Convergence metrics at each depth checkpoint help the user make informed decisions about whether to continue.

---

## New Agent: Calliope (Scribe)

**Name origin:** Καλλιόπη — Muse of epic poetry and eloquence, eldest of the nine Muses. Transforms raw knowledge into structured narrative.

**Purpose:** Synthesizes analytical findings into deliverable markdown documents.

**Input:** Structured findings from analysis phase (lattice-organized — see CS Methods §6) + existing documents to update
**Output:** New and/or updated markdown documents in project

**Response format:**
```
STATUS: success|failure|blocked
SUMMARY: <documents written/updated>
ARTIFACTS: [list of created/modified file paths]
NEXT: review
```

**Rules:**
- Writes ONLY markdown documentation — NEVER source code
- Does NOT perform analysis — synthesizes findings produced by other agents
- Does NOT decide what to include/exclude — follows the synthesis plan from findings
- Does NOT add conclusions beyond what findings support
- Does NOT fabricate references, metrics, or evidence
- Preserves existing document structure when updating (targeted edits, not rewrites)
- When updating: reads current version, identifies sections to modify, applies changes
- Must cite evidence source for every claim (file path, Ariadne metric, agent finding)

**Knowledge access:** L1 (project-model), L1 (conventions — for document style), L0 (decisions)

**Capability profile:** Read + Edit + Write (markdown only, scoped to documentation paths)

**Budget:** 80k

---

## Ariadne Integration (Level C)

Two-tier integration: baseline queries on Gather + agent-driven queries on Analysis.

### Tier 1: Baseline Queries (Gather Phase)

Executed automatically as part of parallel Gather, before analysis begins. Results written to `state/tasks/{id}/ariadne-baseline.md`.

| Query | Purpose | Used By |
|-------|---------|---------|
| `ariadne overview` | High-level graph stats | Athena (scope sizing) |
| `ariadne smells` | All detected architectural smells | Argus, Metis |
| `ariadne metrics` | Martin metrics per module | Metis, Argus |
| `ariadne layers` | Architectural layer violations | Metis, Argus |
| `ariadne cycles` | Dependency cycles | Metis, Argus |
| `ariadne clusters` | Module clustering | Athena (scope partitioning) |

For scoped analysis (not whole-project), queries are filtered by relevant scope:
- `ariadne blast-radius <entry-point>` — what's affected
- `ariadne file <path>` — per-file detail for scope files

### Tier 2: Agent-Driven Queries (Analysis Phase)

Analytical agents (Metis, Argus) have access to Ariadne MCP tools during their analysis pass. This enables targeted, hypothesis-driven queries:

- `ariadne blast-radius` — test impact hypotheses ("if we change X, what breaks?")
- `ariadne importance` — prioritize analysis targets
- `ariadne spectral` — hidden structural patterns not visible in direct dependencies
- `ariadne coupling` — verify coupling hypotheses
- `ariadne compressed` — hierarchical view for large-scope analysis
- `ariadne diff` — structural change comparison (for before/after scenarios)

Agents decide which queries to run based on their analysis needs. This is less deterministic than Tier 1 but enables deeper, more relevant analysis.

### Ariadne Budget

Ariadne queries are lightweight (CLI calls, not LLM tokens), but MCP tool calls during analysis do consume agent context. Budget tracking accounts for Ariadne MCP usage within agent budgets (budget-track.sh hook tracks normally — no special treatment needed).

---

## CS Methods Integration

Six formal CS methods support analytical rigor. They are tiered by readiness:

**Tier A — v1 operational (no Ariadne dependency):**
- CS-3: Hypothesis-Driven Analysis — structures findings as hypothesis → evidence → verdict
- CS-6: Lattice-Based Organization — organizes findings into hierarchical document structure

**Tier B — activate when Ariadne analytical integration is validated (D-127):**
- CS-1: Fixpoint Convergence — formal depth termination via delta tracking
- CS-2: Graph-Based Coverage — completeness metric using Ariadne as coverage space
- CS-4: Abductive Reasoning — competing explanations using Ariadne structural data
- CS-5: Information Gain — deepening prioritization using Ariadne centrality/smell metrics

Tier B methods are fully designed below but are included in agent instructions conditionally: they activate only when Ariadne is available and has been indexed for the current project. Without Ariadne, agents use CS-3 and CS-6 only. Depth checkpoint convergence is reported as simple finding count delta (without the formal Δ formula).

### CS-1: Fixpoint Convergence (Depth Control) — Tier B

**Problem:** When to stop deepening?
**Method:** Track delta findings between analysis passes.

```
Δ(Pass N, Pass N+1) = |new_findings| + |qualitatively_changed_findings|

If Δ < ε (threshold) → convergence reached → recommend "sufficient"
```

**Implementation:** Themis computes delta at each depth checkpoint. Presented to user as data point:
```
Pass 1: 14 findings
Pass 2: 6 new findings, 2 refinements of existing
Pass 3: 1 new finding, 1 refinement
→ Convergence signal: strong (Δ decreasing monotonically)
→ Recommendation: sufficient
```

**Threshold ε:** Not a hard cutoff — Themis reports the convergence trend, user decides. The metric informs the gate, doesn't control it (Art 4.2).

### CS-2: Graph-Based Coverage (Completeness) — Tier B

**Problem:** How to know if analysis is complete?
**Method:** Use Ariadne graph as coverage space.

```
relevant_nodes = ariadne.blast_radius(scope) ∪ ariadne.coupled_components(scope)
analyzed_nodes = nodes touched by Hermes ∪ nodes queried via Ariadne
coverage = |analyzed_nodes ∩ relevant_nodes| / |relevant_nodes|
```

**Implementation:** Athena computes `relevant_nodes` at scope gate using Ariadne. At each depth checkpoint, Themis reports coverage:
```
Structural coverage: 78% (23/29 relevant nodes analyzed)
Uncovered: src/auth/session.ts (centrality: high), src/middleware/cors.ts (centrality: low), ...
→ Gap priority: session.ts (high centrality + connected to 3 scope nodes)
```

Coverage gaps with high centrality or high coupling to scope → deepen candidates.

### CS-3: Hypothesis-Driven Analysis (Scientific Method) — Tier A

**Problem:** How to ensure analytical rigor vs surface-level observation?
**Method:** Structure analysis as hypothesis → evidence → verdict.

Each finding from Metis/Argus follows this structure:
```
HYPOTHESIS: <claim about the system>
EVIDENCE:
  - <concrete data point: file path, metric, code pattern>
  - <concrete data point>
CONFIDENCE: high | medium | low
VERDICT: confirmed | refuted | insufficient
```

**Implementation:** Agent instructions require this format. At depth checkpoint:
- `confirmed` findings → ready for synthesis
- `refuted` findings → documented as "investigated, not an issue"
- `insufficient` findings → deepen candidates (need more evidence)

Count of `insufficient` hypotheses is a deepen signal: "3 hypotheses still lack sufficient evidence."

### CS-4: Abductive Reasoning (Root Cause Analysis) — Tier B

**Problem:** Architectural symptoms (smells, high coupling) have multiple possible causes. Surface-level analysis just reports the symptom.
**Method:** Generate competing explanations, find discriminating evidence.

For `weakness` and `audit` subtypes, when Ariadne reports a structural symptom:

```
OBSERVATION: Module X has fan-in of 47 (Ariadne metric)

COMPETING EXPLANATIONS:
  H1: X is a legitimate shared utility (benign)
      → discriminating evidence: check responsibility cohesion
  H2: X is a God module (architectural smell)
      → discriminating evidence: count distinct responsibility domains
  H3: X is a bottleneck from missing abstraction layer
      → discriminating evidence: check if dependents use different subsets of X's API

INVESTIGATION: [agent explores discriminating evidence]

CONCLUSION: H2 confirmed — X handles auth, session management, AND user
  preferences (3 distinct domains). Evidence: methods cluster into 3 groups
  with no cross-references between groups.
```

**Implementation:** Argus and Metis instructions for `weakness`/`audit` subtypes include the abductive reasoning template. Findings without competing explanations considered → QA4 violation ("alternative explanations not considered").

### CS-5: Information Gain (Deepening Prioritization) — Tier B

**Problem:** When deepening, where to focus limited analytical budget?
**Method:** Prioritize areas with highest expected information gain.

```
IG(area) ∝ centrality(area) × unexplored(area) × smell_density(area)

High centrality + unexplored = high IG (central node we know nothing about)
High coupling + smell + unexplored = high IG (likely problem area)
Low centrality + isolated = low IG (leaf node, low impact)
```

**Implementation:** Athena and Themis use Ariadne metrics as IG proxies when recommending deepening direction:
```
Deepening recommendation:
  Priority 1: src/auth/ (centrality: 0.89, unexplored, 2 smells)
  Priority 2: src/api/middleware/ (centrality: 0.72, partially explored, 1 smell)
  Skip: src/utils/format.ts (centrality: 0.12, isolated, no smells)
```

### CS-6: Lattice-Based Finding Organization (Structure) — Tier A

**Problem:** Flat finding lists produce disorganized documents.
**Method:** Organize findings into a partial order (lattice) before synthesis.

```
Findings form a natural hierarchy:
  f1: "Auth subsystem has high coupling"
    ├─ f1.1: "Session store shared across 3 services"
    │   └─ f1.1.1: "No session abstraction layer"
    ├─ f1.2: "Token validation duplicated in 4 places"
    └─ f1.3: "Auth and user management have circular dependency"

  f2: "API layer lacks consistent error handling"
    ├─ f2.1: "3 different error response formats"
    └─ f2.2: "No global error boundary"
```

**Implementation:** Before passing findings to Calliope, the analysis phase organizes findings into a hierarchy based on:
- Causal relationships (f1 causes f1.1)
- Scope containment (f1 contains f1.1, f1.2, f1.3)
- Dependency (f2.1 depends on f2)

Calliope receives this lattice as the document skeleton — each top-level finding becomes a section, sub-findings become subsections. This produces naturally structured documents rather than "finding 1, finding 2, finding 3" flat lists.

---

## Analytical Quality Gates

Replace Q1-Q5 (code-oriented) with QA1-QA4 for analytical tasks.

### QA1: Scope Completeness (Athena + Themis)

```
- [ ] All questions from scope formalization have answers (or explicit "out of scope")
- [ ] Structural coverage ≥ threshold (CS-2: graph-based coverage, if Ariadne available)
- [ ] No high-centrality nodes in scope left unexplored (if Ariadne available; otherwise: no obvious scope areas left unexplored based on Hermes exploration)
- [ ] Ariadne data consulted for structural coverage verification (if available; without Ariadne: coverage assessed from explored file set)
- [ ] Scope boundaries explicitly documented (what was NOT analyzed and why)
```

### QA2: Evidence Quality (Themis)

```
- [ ] Every finding follows hypothesis-evidence-verdict format (CS-3)
- [ ] No "probably" / "likely" without supporting evidence
- [ ] Ariadne metrics cited with concrete numbers when available (not "high coupling" but "fan-in: 47"); without Ariadne: code-level evidence with file paths suffices
- [ ] Code references include file paths and line ranges
- [ ] Each finding's confidence level matches its evidence strength
      (high confidence requires 2+ independent evidence points)
- [ ] No evidence cited from outside analyzed scope without verification
```

### QA3: Actionability (Themis)

```
- [ ] Each finding has a concrete recommended action (or explicit "informational only")
- [ ] Priority assignments are justified (not everything is "critical")
- [ ] Recommendations account for project constraints (stack, team, timeline)
- [ ] Dependencies between recommendations are explicit
      ("fix X before attempting Y")
- [ ] Estimated effort/impact provided for actionable findings
```

### QA4: Analytical Rigor (Themis)

```
- [ ] For weakness/audit: competing explanations considered (CS-4: abductive reasoning)
- [ ] No confirmation bias — evidence that contradicts hypotheses is reported
- [ ] Structural data (Ariadne) and code-level data (Hermes) are cross-validated when both available
      (structural smell confirmed by code-level evidence, or discrepancy explained)
- [ ] Findings are not circular (finding A's evidence is not finding B, whose evidence is A)
- [ ] Convergence trend documented (CS-1: are we at fixpoint?)
- [ ] Analysis limitations explicitly stated ("could not assess X because Y")
```

Issue severity for analytical review:
- **CRITICAL**: Finding unsupported by evidence, circular reasoning, fabricated data
- **WARNING**: Weak evidence, missing alternative explanations, low coverage area
- **SUGGESTION**: Could deepen, minor structural improvements to analysis

---

## Depth Checkpoint Gate UX

```
═══════════════════════════════════════════
 GATE: Depth Checkpoint (Pass N)
═══════════════════════════════════════════

 Findings: 14 total (8 confirmed, 3 refuted, 3 insufficient)

 Convergence: Δ = 6 new findings (Pass 1)
              → No prior pass to compare — initial analysis

 Coverage: 78% (23/29 relevant nodes)
   Gaps: src/auth/session.ts (high priority)
         src/middleware/cors.ts (low priority)

 Insufficient hypotheses:
   • "Session store creates implicit coupling" — needs code-level verification
   • "Error handling inconsistency is systematic" — only 2 samples found
   • "Circular dependency is intentional" — needs decision history check

 ▸ sufficient — proceed to synthesis with current findings
 ▸ deepen    — investigate gaps + insufficient hypotheses (Pass 2)
 ▸ redirect  — re-scope analysis (back to Athena)
 ▸ details   — show all findings
 ▸ abort     — cancel
═══════════════════════════════════════════
```

---

## Redirect State Management

When the user chooses `redirect` at a depth checkpoint:

1. **Prior findings are preserved.** All `analysis-pass-{N}.md` and `review-pass-{N}.md` files remain in state directory. They are NOT deleted or overwritten.
2. **Athena receives prior findings as context.** When re-scoping, Athena reads the existing findings to understand what was already discovered and why the scope needs adjustment.
3. **Maximum 1 redirect per pipeline execution.** Prevents infinite redirect loops. If the user needs a second re-scope, they must `abort` and start a new analytical task. This matches the `rearchitect` limit in implementation pipelines (D-112).
4. **Post-redirect analysis starts a new pass counter.** If redirect happens after Pass 2, the next analysis starts as Pass 3 (continuous numbering, not reset to 1).

## Themis Dual-Role in Analytical Pipeline

**Acknowledged design exception:** Themis performs two structurally different tasks in the Analytical Pipeline:

- **At depth checkpoint:** Convergence analysis — computes finding delta (CS-1), reports coverage (CS-2), assesses whether analysis is sufficient. This is meta-analytical quality review.
- **At final review:** QA1-QA4 quality assurance on Calliope's synthesized document. This is document quality review.

**Justification:** Both tasks are quality review with different focus — analytical output quality vs document output quality. Creating a separate agent for convergence analysis would be over-engineering: the convergence computation is a subset of Themis's existing quality assessment capability, not a distinct skill requiring separate role boundaries. The two invocations use different instructions (depth checkpoint template vs QA1-QA4 template) and produce different output files (`review-pass-{N}.md` vs `review.md`), maintaining clear separation within the same agent role.

## State Files

Analytical tasks use the same state directory structure with analytical-specific files:

```
.moira/state/tasks/{id}/
├── input.md                    # Original task description
├── classification.md           # Apollo output (mode: analytical, subtype: ...)
├── ariadne-baseline.md         # Tier 1 Ariadne query results
├── scope.md                    # Athena scope formalization
├── exploration.md              # Hermes findings
├── analysis-pass-{N}.md       # Findings per analysis pass
├── finding-lattice.md          # CS-6 organized finding hierarchy
├── synthesis-plan.md           # What Calliope will write/update
├── deliverables.md             # List of documents created/updated
├── review.md                   # Themis QA1-QA4 review
├── reflection.md               # Mnemosyne post-task reflection
├── status.yaml                 # Task status
├── manifest.yaml               # Checkpoint for resume
├── telemetry.yaml              # Per-task metrics
└── instructions/               # Assembled agent instructions
    ├── explorer.md
    ├── analyst.md
    ├── architect.md             # (if subtype uses Metis)
    ├── auditor.md               # (if subtype uses Argus)
    ├── calliope.md
    └── reviewer.md
```

---

## Constitutional Compliance

| Article | How Analytical Pipeline Complies |
|---------|--------------------------------|
| **1.1 Orchestrator Purity** | Orchestrator dispatches agents, reads summaries. Never reads project files. Same as implementation pipelines. |
| **1.2 Agent Single Responsibility** | Each agent has one role. Calliope writes docs, doesn't analyze. Metis analyzes, doesn't write docs. Argus audits, doesn't fix. |
| **1.3 No God Components** | Pipeline structure prevents accumulation. Findings → synthesis → review are separate steps. |
| **2.1 Pipeline Determinism** | analytical mode → always Analytical Pipeline. Subtype determines agent composition deterministically. |
| **2.2 Gate Determinism** | Fixed gate set: classify, scope, depth checkpoint(s), final. Depth checkpoints are structural — they may repeat but never skip. |
| **2.3 No Implicit Decisions** | Hypothesis-driven analysis (CS-3) explicitly prevents "I'll assume..." patterns. |
| **3.1 All Decisions Traceable** | Every pass writes to state files. Finding lattice is explicit. |
| **3.2 Budget Visibility** | Standard budget reporting. Ariadne queries tracked within agent budgets. |
| **3.3 Error Transparency** | Same error handling as implementation pipelines. |
| **4.1 No Fabrication** | QA2 checks evidence for every claim. Ariadne metrics must cite concrete numbers. |
| **4.2 User Authority** | User controls depth at every checkpoint. Convergence metrics inform, don't decide. |
| **4.3 Rollback Capability** | Document changes are git-backed. Calliope writes through standard file operations. |
| **5.1 Knowledge Evidence-Based** | Analytical findings become knowledge only through standard reflection (Mnemosyne). |
| **5.2 Rule Changes Require Threshold** | Standard 3-confirmation threshold. Analytical pipeline doesn't bypass this. |
| **6.1 Constitutional Immutability** | No pipeline step writes to CONSTITUTION.md. Calliope is scoped to project documentation paths. |
| **6.2 Design Document Authority** | Analytical Pipeline conforms to design documents. Implementation follows analytical-pipeline.md specification. |
| **6.3 Invariant Verification** | Argus audits analytical pipeline behavior as part of standard system health. Post-agent diff check applies to Calliope writes. |

---

## Pipeline Definition (YAML)

The Analytical Pipeline will have a YAML definition alongside existing pipeline definitions at `core/pipelines/analytical.yaml`.

Implementation note (D-123): The implementation uses gate-level `next_step` fields for flow control instead of step-level `next` fields. This keeps flow control on gates (consistent with existing pipelines where gate decisions determine the next action). See `src/global/core/pipelines/analytical.yaml` for the implemented YAML structure.

```yaml
pipeline: analytical
description: Analysis, audit, and documentation tasks — no code output

# Steps in execution order
steps:
  classify:
    agent: apollo
    next: gather
    writes: [classification.md]
    gate:
      type: approval
      options: [proceed, modify, abort]

  gather:
    agent: hermes
    writes: [exploration.md, ariadne-baseline.md]
    # D-125: Hermes handles both code exploration and Ariadne baseline queries
    # in a single foreground dispatch. No separate "action" type needed.
    next: scope

  scope:
    agent: athena
    writes: [scope.md]
    next: analysis
    gate:
      type: approval
      options: [proceed, modify, abort]

  analysis:
    # Agent composition determined by subtype (see agent_map)
    agent: subtype_primary
    writes: [analysis-pass-{N}.md]
    next: depth_checkpoint
    ariadne_mcp: true  # Tier 2: agents can query Ariadne MCP

  depth_checkpoint:
    agent: themis
    writes: [review-pass-{N}.md]
    gate:
      type: depth
      options: [sufficient, deepen, redirect, abort]
      redirect_max: 1  # max 1 redirect per pipeline execution (same as rearchitect limit)
    next:
      sufficient: organize
      deepen: analysis  # loop back
      redirect: scope   # re-scope — prior analysis-pass-{N}.md files preserved, Athena receives them as context

  organize:
    # CS-6: lattice organization of findings
    agent: metis  # universal organizer for all subtypes — lattice construction is structural reasoning
    writes: [finding-lattice.md, synthesis-plan.md]
    next: synthesis

  synthesis:
    agent: calliope
    writes: [deliverables.md]
    next: review

  review:
    agent: themis
    writes: [review.md]
    gate:
      type: approval
      options: [done, details, modify, abort]
    next:
      done: complete
      modify: synthesis    # re-synthesize with feedback (QA3/QA1 failures)
      re-analyze: analysis # re-analyze with QA feedback (QA2/QA4 failures — evidence gap)

  complete:
    action: finalize
    writes: [status.yaml]
    post: [mnemosyne]  # background reflection

# Subtype → agent mapping for analysis step
agent_map:
  research:
    primary: metis
    support: []
  design:
    primary: metis
    support: []
  audit:
    primary: [argus, metis]  # parallel
    support: []
  weakness:
    primary: [argus, metis]  # parallel
    support: []
  decision:
    primary: metis
    support: []
  documentation:
    primary: athena
    support: [calliope]  # early synthesis for doc-only tasks
```

---

## Calliope in Knowledge Access Matrix

Addition to `knowledge-access-matrix.yaml`:

| Knowledge Type | Calliope Access | Justification |
|---|---|---|
| project-model | L1 (summary) | Context for document style and structure |
| conventions | L1 (summary) | Follow project documentation conventions |
| decisions | L0 (index) | Reference existing decisions |
| patterns | L0 (index) | Awareness of existing patterns |
| quality-map | — | Not relevant to document synthesis |
| failures | — | Not relevant to document synthesis |
| libraries | — | Not relevant to document synthesis |
| graph | L0 (overview only) | High-level structural context for docs |

**Write access:** None (Calliope writes project documents, not knowledge base entries)

---

## Interaction with Existing Systems

### Budget (Chronos)
Analytical tasks use the same budget tracking. Typical budget profile:
- Apollo: 20k (same as implementation)
- Hermes: 140k (same, may use less for focused scope)
- Ariadne baseline: ~0 tokens (CLI calls, not LLM)
- Athena: 80k (same)
- Metis/Argus per pass: 100k/140k (same budgets)
- Calliope: 80k
- Themis per checkpoint: 100k (same)
- Total multi-pass: potentially higher than implementation due to N passes

### Checkpoint/Resume
Each depth checkpoint is a natural checkpoint boundary. User can close session after any depth checkpoint gate, resume later with `/moira resume`. State files contain all findings from previous passes.

### Reflection (Mnemosyne)
Post-task reflection runs normally. Analytical tasks feed into knowledge base the same way — patterns observed, efficiency assessed, accuracy evaluated.

### Metrics (Moiragetes)
Analytical tasks contribute to system metrics. New analytical-specific metrics:
- Average depth (passes per task)
- Convergence rate (how quickly Δ decreases)
- Coverage achieved at completion
- Finding quality distribution (confirmed/refuted/insufficient ratios)
