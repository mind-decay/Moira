# Project Graph

> **Implementation note:** The project graph engine is a separate project called **Ariadne** (D-104). This document describes the design from Moira's perspective — what data Moira consumes and how agents use it. The engine implementation (parsers, algorithms, CLI, MCP server) lives in the [Ariadne repository](https://github.com/ariadne). The `ariadne` binary is consumed by Moira as an external CLI tool via PATH.

## Purpose

The Project Graph is a structural topology map of the target project. It captures file dependencies, architectural layers, module clusters, and architectural health metrics — enabling agents to navigate precisely, assess impact before making changes, and detect structural anti-patterns.

**Project Graph is NOT knowledge.** Knowledge (patterns, decisions, conventions, failures) belongs to the Knowledge System (and later Anamnesis). Project Graph is deterministic structural data derived from code — it doesn't learn, decay, or evolve through experience. It updates when code changes.

| | Project Graph | Knowledge System |
|---|---|---|
| **Contains** | Files, imports, dependencies, layers, metrics, smells | Patterns, decisions, conventions, failures |
| **Answers** | "How is the code structured?" | "What do we know about the project?" |
| **Updates** | When code changes (deterministic) | When tasks complete (evidence-based) |
| **Source** | Static analysis (tree-sitter) | Agent observations |

## Architecture

### Engine: Ariadne (Rust CLI + MCP Server)

A standalone Rust binary that parses source code via tree-sitter and produces a structural dependency graph. Also includes an MCP server mode for real-time graph queries.

**Why Rust:**
- Tree-sitter is written in Rust/C — native, first-class bindings
- Single binary, zero runtime dependencies
- Fastest option: 3000 files in 1-3 seconds
- No dependency on Node.js, Python, or any runtime

**Why tree-sitter:**
- Language-agnostic: 100+ grammar support
- Deterministic AST parsing — no LLM involvement, no token cost
- Incremental parsing support
- Battle-tested in editors (Neovim, Helix, Zed)

### Language Support

Each language implements a `LanguageParser` trait:

```rust
trait LanguageParser {
    fn language(&self) -> &str;
    fn extensions(&self) -> &[&str];
    fn tree_sitter_language(&self) -> Language;
    fn extract_imports(&self, tree: &Tree, source: &[u8]) -> Vec<Import>;
    fn extract_exports(&self, tree: &Tree, source: &[u8]) -> Vec<Export>;
    fn resolve_import_path(&self, import: &Import, file: &Path, root: &Path) -> Option<PathBuf>;
}
```

Adding a new language = implementing one trait. Grammars are crate dependencies.

**Tier 1 (implemented):**

| Language | Extensions | Import forms | Complexity |
|---|---|---|---|
| TypeScript / JavaScript | `.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs` | `import`, `require`, `export`, dynamic `import()`, barrel re-exports | High |
| Go | `.go` | `import "path"`, `import (...)` | Low |
| Python | `.py` | `import`, `from...import`, relative imports | Medium |
| Rust | `.rs` | `use`, `mod`, `extern crate` | Medium |
| C# | `.cs` | `using`, `using static` | Low |
| Java | `.java` | `import`, `import static` | Low |

**Tier 2 (future):** Kotlin, Swift, C/C++, PHP, Ruby, Dart.

**Tier 3 (on demand):** Elixir, Scala, Haskell, Lua, Zig, etc.

### Graph Data Model

**Nodes** — files with metadata:

```
Node {
    path: String,          // relative to project root (unique ID)
    type: FileType,        // source | test | config | style | asset | type_def
    layer: ArchLayer,      // api | service | data | util | component | hook | config | unknown
    arch_depth: u32,       // topological depth (0 = no dependencies)
    lines: u32,            // line count
    hash: String,          // content hash for delta detection (xxHash)
    exports: Vec<String>,  // exported symbol names
    cluster: String,       // assigned cluster ID
}
```

**Edges** — directed, typed connections:

```
Edge {
    from: String,          // source file path
    to: String,            // target file path
    edge_type: EdgeType,   // imports | tests | re_exports | type_imports
    symbols: Vec<String>,  // which symbols are used (optional)
}
```

This is a **directed multigraph** — multiple edges of different types can exist between two nodes.

**File types:**
- `source` — application code
- `test` — test files (detected by path pattern or naming convention)
- `config` — configuration files (tsconfig, webpack, etc.)
- `style` — CSS/SCSS/styled-components
- `asset` — static assets (images, fonts, JSON data)
- `type_def` — type definition files (.d.ts, .pyi)

**Edge types:**
- `imports` — runtime dependency (import/require/use)
- `tests` — test file covers source file (inferred from naming + imports)
- `re_exports` — barrel file re-exports (index.ts pattern)
- `type_imports` — compile-time only dependency (TypeScript `import type`, Python `TYPE_CHECKING`)

### Storage Format

Ariadne stores data in `.ariadne/graph/` and `.ariadne/views/` by default. Moira reads from these locations directly — no copying or symlinking (D-105). The `.ariadne/` directory is committed to git (deterministic, reproducible output).

```
.ariadne/graph/
├── graph.json          # full graph — source of truth
├── clusters.json       # cluster definitions with metadata
├── stats.json          # precomputed metrics (centrality, layers, SCCs)
├── raw_imports.json    # raw import statements per file (for freshness tracking)
└── .lock               # lock file (prevents CLI writes while MCP server running)

.ariadne/views/
├── index.md            # L0: cluster list, critical files, cycles
└── clusters/           # L1: per-cluster detail
    ├── auth.md
    ├── api.md
    └── ...
```

**graph.json format:**

```json
{
  "nodes": {
    "src/auth/login.ts": {
      "file_type": "source",
      "layer": "service",
      "arch_depth": 2,
      "lines": 142,
      "hash": "a1b2c3d4",
      "exports": ["login", "LoginParams"],
      "cluster": "auth"
    }
  },
  "edges": [
    {
      "from": "src/api/auth.ts",
      "to": "src/auth/login.ts",
      "edge_type": "imports",
      "symbols": ["login"]
    }
  ]
}
```

**clusters.json format:**

```json
{
  "clusters": {
    "auth": {
      "files": ["src/auth/login.ts", "src/auth/logout.ts"],
      "file_count": 12,
      "internal_edges": 28,
      "external_edges": 15,
      "cohesion": 0.65
    }
  }
}
```

**stats.json format:**

```json
{
  "version": 1,
  "centrality": {
    "src/utils/format.ts": 0.89,
    "src/auth/middleware.ts": 0.72
  },
  "sccs": [
    ["src/billing/invoice.ts", "src/auth/permissions.ts"]
  ],
  "layers": {
    "0": ["src/utils/constants.ts", "src/types/index.ts"],
    "1": ["src/services/auth.ts"],
    "2": ["src/api/routes.ts"]
  },
  "summary": {
    "max_depth": 7,
    "avg_in_degree": 2.8,
    "avg_out_degree": 2.8,
    "bottleneck_files": ["src/utils/format.ts"],
    "orphan_files": ["src/legacy/old-helper.ts"]
  }
}
```

**Git tracking:**
- `graph/graph.json`, `clusters.json`, `stats.json`: **committed** (canonical, deterministic)
- `views/`: **committed** (generated but stable, useful for review)
- `raw_imports.json`: **committed** (used by freshness tracking)
- `.lock`: **gitignored** (runtime state)

## Algorithms

### 1. Blast Radius — Reverse BFS

Answers: "If I change file X, what else might break?"

```
blast_radius(X, max_depth=∞) → {file: distance}:
    visited = {}
    queue = [(X, 0)]
    while queue not empty:
        node, depth = dequeue
        if node in visited: skip
        visited[node] = depth
        for each dependent in reverse_edges[node]:
            if depth + 1 ≤ max_depth:
                enqueue (dependent, depth + 1)
    return visited
```

**Depth semantics:**
- depth=1: direct dependents — almost certainly affected
- depth=2: transitive dependents — probably affected
- depth=3+: distant dependents — possibly affected

**Complexity:** O(V + E), linear in graph size.

### 2. Betweenness Centrality — Brandes Algorithm

Identifies bottleneck files (files that many dependency paths pass through).

```
BC(v) = Σ_{s≠v≠t} (σ_st(v) / σ_st)
```

Where σ_st = number of shortest paths from s to t, σ_st(v) = those passing through v.

**Brandes algorithm:** O(VE), computes all centralities in one pass. For V=3000, E=~8000: milliseconds.

**Use:** Files with BC > 0.7 are marked as bottlenecks in stats.json. Changes to these files trigger elevated review.

### 3. PageRank

Ranks files by "authority" — how many important files depend on them. Identifies foundational files that underpin the project.

- Damping factor: 0.85
- Max iterations: 100, tolerance: 1e-6
- Only considers `imports` and `re_exports` edges (excludes `tests` and `type_imports`)

**Combined Importance Score:** `0.5 * normalized_centrality + 0.5 * normalized_pagerank` — balances bridging role (centrality) with foundational role (PageRank).

### 4. Cycle Detection — Tarjan's SCC

Finds circular dependencies (strongly connected components of size > 1).

```
Tarjan's algorithm: O(V + E)
    - DFS with lowlink tracking
    - Nodes on stack form SCCs
    - SCC size > 1 = circular dependency
```

**Use:** SCCs reported in stats.json and surfaced in health checks. Reviewer (Themis) checks if changes introduce new cycles.

### 5. Clustering — Two-Level

**Level 1: Directory-based (free).** Files in `src/auth/` → cluster "auth". Natural, intuitive, zero computation.

**Level 2: Louvain community detection (refinement).**

```
Modularity Q = (1/2m) Σ_{ij} [A_ij - k_i·k_j / 2m] · δ(c_i, c_j)
```

Louvain maximizes Q greedily in O(n·log n). Detects real module boundaries that may not align with directories (e.g., a util file that belongs semantically to a specific domain).

**Cluster assignment:** Start with directory clusters, then run Louvain. If Louvain reassigns a file, it overrides the directory-based cluster. Cluster IDs use directory names where possible for readability. Louvain can be disabled with `--no-louvain`.

**Clusters are the unit of loading for agents.** An agent doesn't load the full graph — it loads relevant clusters.

### 6. Architectural Layers — Topological Sort

On DAG (after contracting SCCs into supernodes), topological sort produces dependency layers:

```
Layer 0: files with no outgoing dependencies (utils, constants, types)
Layer 1: files depending only on Layer 0
Layer 2: files depending on Layer 0-1
...
```

**Use:** Automatic architecture discovery. Planner uses layer information to order implementation steps (bottom-up). Architect sees layer violations (service importing from API layer).

### 7. Martin Metrics (per cluster)

Package-level design quality metrics:

| Metric | Formula | Meaning |
|---|---|---|
| **Instability (I)** | Ce / (Ca + Ce) | 0 = maximally stable, 1 = maximally unstable |
| **Abstractness (A)** | abstract files / total files | 0 = fully concrete, 1 = fully abstract |
| **Distance (D)** | \|A + I - 1\| | Deviation from main sequence (ideal: 0) |
| **Afferent Coupling (Ca)** | incoming cross-cluster edges | How many other clusters depend on this one |
| **Efferent Coupling (Ce)** | outgoing cross-cluster edges | How many clusters this one depends on |

**Zone Classification:**
- **Main Sequence** — balanced abstractness and instability (D ≈ 0)
- **Zone of Pain** — concrete and stable (hard to change, many dependents)
- **Zone of Uselessness** — abstract and unstable (over-engineered, no dependents)
- **Off Main Sequence** — deviates from ideal balance

### 8. Architectural Smell Detection (7 types)

Automated detection of structural anti-patterns:

| Smell | Detection Rule | Severity |
|---|---|---|
| **God File** | centrality > 0.8 AND out-degree > 20 AND lines > 500 | High |
| **Circular Dependency** | Any SCC with size > 1 | High |
| **Layer Violation** | Edge from lower arch_depth to higher | Medium |
| **Hub-and-Spoke** | One file handles >50% of cluster's external edges | Medium |
| **Unstable Foundation** | Cluster with instability > 0.7 AND afferent_coupling > 10 | High |
| **Dead Cluster** | No outgoing edges (isolated cluster) | Low |
| **Shotgun Surgery** | Single file involved in many scattered imports | Medium |

Each smell includes: type, involved files, severity, human-readable explanation, quantitative metrics (primary value vs threshold).

### 9. Spectral Analysis

Graph-theoretic analysis of overall project structure:

- **Algebraic connectivity (λ₂):** Second-smallest eigenvalue of the graph Laplacian. Low λ₂ = graph close to splitting into disconnected components. High λ₂ = tightly interconnected.
- **Monolith score:** λ₂ / λ_max — normalized connectivity. Higher = more monolithic (tightly coupled).
- **Fiedler vector bisection:** Natural partition of graph into two communities via power iteration on shifted Laplacian. Identifies natural module boundaries.

### 10. Hierarchical Graph Compression

For LLM context budgeting — presents the graph at different zoom levels:

| Level | Content | Token estimate |
|---|---|---|
| **L0 (Project)** | Clusters as nodes, inter-cluster edges only (~10-30 nodes). Each cluster shows file count, cohesion, top-3 key files | ~200-500 |
| **L1 (Cluster)** | Individual files within one cluster. Internal edges detailed, external edges aggregated by target cluster | ~500-2000 |
| **L2 (File)** | Single file plus N-hop neighborhood (default N=2). Full edge detail, file type and layer for all neighbors | ~1000-5000 |

Token estimates provided as `bytes / 4`.

### 11. Incremental Updates — Delta Computation

Full rebuild on every refresh is wasteful at scale. Delta approach:

```
update(old_graph, current_fs):
    // Phase 1: detect changes via content hash
    changed = {f : hash(f) ≠ old_graph.nodes[f].hash}
    added = current_fs - old_graph.nodes
    removed = old_graph.nodes - current_fs

    // Phase 2: re-parse only affected files
    for f in (changed ∪ added):
        parse imports/exports
        update edges from f

    // Phase 3: remove stale data
    remove all edges from/to removed files
    remove nodes for removed files

    // Phase 4: recompute derived data
    if |changed ∪ added ∪ removed| > 0.05 * |nodes|:
        full recompute (clusters, centrality, layers)
    else:
        incremental cluster update
        skip centrality recompute (use previous)
```

**Content hash:** xxHash64 — fast, collision-resistant, deterministic.

**Threshold:** If >5% of files changed, full recompute. Otherwise, incremental.

### 12. Structural Diff

Compares old and new graph snapshots, tracking:
- Added/removed nodes (files), added/removed edges (imports)
- Changed layers, changed cluster assignments
- New/resolved cycles, new/resolved architectural smells

**Change classification:**
- **Additive** — only additions (safe)
- **Refactor** — mostly internal reorganization
- **Migration** — cross-cluster movement of files
- **Breaking** — introduces cycles or smells

**Magnitude metric:** Normalized score based on change volume relative to graph size.

### 13. Subgraph Extraction

For agents — extract relevant neighborhood:

```
extract_subgraph(files, depth=2):
    result_nodes = {}
    for f in files:
        bfs(f, forward_edges, depth) → add to result_nodes
        bfs(f, reverse_edges, depth) → add to result_nodes
    for f in files:
        add all files in f.cluster to result_nodes
    return subgraph(result_nodes) with metrics
```

This is what gets rendered into L2 views for specific agents.

## Views: Markdown for Agents

### L0: Index (`views/index.md`)

~200-500 tokens. Overview for quick orientation.

```markdown
# Project Graph — Index

## Architecture Summary
Files: 847 | Edges: 2,341 | Clusters: 12 | Max depth: 7

## Clusters (12)
| Cluster | Files | Key file (highest centrality) | Cohesion |
|---------|-------|-------------------------------|----------|
| auth | 12 | src/auth/middleware.ts (0.72) | 0.65 |
| api | 23 | src/api/router.ts (0.65) | 0.48 |
| ...

## Critical Files (centrality > 0.7)
- src/utils/format.ts (0.89) — 47 dependents
- src/auth/middleware.ts (0.72) — 28 dependents

## Circular Dependencies (2)
- auth ↔ billing (via permissions.ts ↔ invoice.ts)
- ...

## Orphan Files
- src/legacy/old-helper.ts (disconnected)
```

### L1: Cluster Detail (`views/clusters/<name>.md`)

~500-2000 tokens per cluster. Internal structure and external connections.

```markdown
# Cluster: auth (12 files)

## Files
| File | Type | Layer | In° | Out° | Centrality |
|------|------|-------|-----|------|------------|
| middleware.ts | source | 2 | 28 | 3 | 0.72 |
| login.ts | source | 3 | 5 | 4 | 0.31 |
| ...

## Internal Dependencies
middleware.ts → session.ts → token.ts

## External Dependencies (outgoing)
auth/middleware.ts → utils/crypto.ts
auth/session.ts → database/redis.ts

## External Dependents (incoming)
api/routes.ts → auth/middleware.ts
api/admin.ts → auth/permissions.ts

## Tests
auth/__tests__/login.test.ts → login.ts
auth/__tests__/middleware.test.ts → middleware.ts
```

### L2: On-Demand Reports

Generated on-demand via `ariadne query subgraph` or `blast-radius`. Contains full dependency tree for specific files with all metrics. Not pre-generated — produced per query.

## MCP Server

Ariadne includes a built-in MCP server (`ariadne serve`) that provides real-time graph queries without CLI overhead. The MCP server is the **primary integration path** for Claude Code agents.

### Server Architecture

- Tokio async runtime (multi-threaded)
- File system watcher with debouncing (default 2000ms, configurable via `--debounce`)
- Lock file (`.ariadne/graph/.lock`) prevents CLI writes while server is running
- Graph state atomically swapped via `ArcSwap` on file change
- Pre-computes all views and indices on load for O(1) tool responses

### MCP Tools (17 total)

| Tool | Parameters | Description |
|---|---|---|
| `ariadne_overview` | — | Node/edge counts, language breakdown, layers, critical files, cycles, freshness |
| `ariadne_file` | `path` | File detail: type, layer, depth, exports, cluster, centrality, edges |
| `ariadne_blast_radius` | `path`, `depth?` | Reverse BFS: affected files with distances |
| `ariadne_subgraph` | `paths[]`, `depth?` | Extract neighborhood: nodes, edges, clusters |
| `ariadne_centrality` | `min?` | Bottleneck files by betweenness centrality |
| `ariadne_cycles` | — | All strongly connected components |
| `ariadne_layers` | `layer?` | Topological layers (optionally filter to specific layer) |
| `ariadne_cluster` | `name` | Cluster detail: files, deps, cohesion |
| `ariadne_dependencies` | `path`, `direction` | Direct dependencies: `in`, `out`, or `both` |
| `ariadne_freshness` | — | Graph freshness: confidence scores, stale/new/removed files |
| `ariadne_metrics` | — | Martin metrics per cluster: I, A, D, zone classification |
| `ariadne_smells` | `min_severity?` | Architectural smell detection (7 types) |
| `ariadne_diff` | — | Structural diff since last auto-update |
| `ariadne_importance` | `top?` | File importance ranking (centrality + PageRank) |
| `ariadne_compressed` | `level`, `focus?`, `depth?` | Hierarchical compression (L0/L1/L2) with token estimates |
| `ariadne_spectral` | — | Algebraic connectivity, monolith score, Fiedler bisection |
| `ariadne_views_export` | `level`, `cluster?` | Pre-generated markdown views (L0 index, L1 cluster) |

All tools return JSON. The MCP server auto-rebuilds the graph on file changes (with debounce) and tracks freshness confidence.

### Freshness Tracking

The MCP server maintains two-level freshness confidence:
- **Hash-level:** Tracks content changes (stale files whose hash differs from graph)
- **Structural-level:** Tracks import statement changes (files whose dependencies changed)
- Reports new files (not in graph) and removed files (in graph but deleted)

## Agent Integration

### Knowledge Access Matrix Extension

The graph adds a new column to the Knowledge Access Matrix:

| Agent | Graph context (in prompt) | Ariadne MCP tools | Key capabilities used |
|---|---|---|---|
| Classifier (Apollo) | L0 | All (D-115) | Complexity assessment via centrality + dependents |
| Explorer (Hermes) | L0 | All (D-115) | Cluster-targeted search, `ariadne_file`, `ariadne_subgraph` instead of blind grep |
| Analyst (Athena) | L1 + blast radius + smells | All (D-115) | `ariadne_blast_radius`, `ariadne_smells` for impact analysis |
| Architect (Metis) | L1 + metrics + spectral | All (D-115) | `ariadne_metrics`, `ariadne_spectral` for design quality |
| Planner (Daedalus) | L1 + blast radius + importance | All (D-115) | `ariadne_blast_radius`, `ariadne_importance` for file coverage |
| Implementer (Hephaestus) | L2 subgraph + compressed | All (D-115) | `ariadne_file`, `ariadne_dependencies` for exact imports |
| Reviewer (Themis) | L1 + diff + smells + cycles | All (D-115) | `ariadne_diff`, `ariadne_cycles` for regression checks |
| Tester (Aletheia) | L1 (test mappings) | All (D-115) | `ariadne_cluster` for test file discovery |
| Reflector (Mnemosyne) | L2 + metrics | All (D-115) | `ariadne_metrics` for structural reflection |
| Auditor (Argus) | L2 + stats + smells + spectral | All (D-115) | `ariadne_smells`, `ariadne_spectral` for health scoring |

**Graph context vs MCP tools:** Graph context is static data pre-loaded into the agent prompt (L0/L1/L2 views). MCP tools provide interactive, on-demand queries — agents can call `ariadne_blast_radius`, `ariadne_file`, etc. during execution to get structural data they need. Both channels complement each other: context provides orientation, MCP provides depth.

**No agent has write access to the graph.** The graph is updated only by `ariadne` CLI/MCP server (deterministic, from code).

**MCP inheritance:** Subagents spawned via the Agent tool inherit MCP servers from the parent Claude Code session. Infrastructure MCP tools (Ariadne) are always available to all agents — dispatch injects instructions via the `## Infrastructure Tools (Always Available)` prompt section (D-115).

### How Each Agent Benefits

**Classifier (Apollo):** Receives L0 index in prompt. Can call `ariadne_file` to assess true complexity by checking if affected files have high centrality or many dependents. "Rename a function" in a file with in-degree 47 → complex, not simple.

**Explorer (Hermes):** Receives L0 index in prompt. Can call `ariadne_cluster`, `ariadne_file`, `ariadne_subgraph` to navigate precisely instead of reading files one by one. Knows which cluster to search instead of blind grep. Reduces token usage by 50-70% on file discovery.

**Analyst (Athena):** Receives L1 clusters in prompt. Can call `ariadne_blast_radius`, `ariadne_smells`, `ariadne_dependencies` for affected files. Reports architectural impact: "This change affects 23 files across 3 layers. Circular dependency exists between auth and billing. Hub-and-spoke detected in api/router.ts."

**Architect (Metis):** Receives L1 + Martin metrics + spectral analysis. Designs solutions that respect layer boundaries, avoid new cycles, don't increase coupling of bottleneck files, and consider monolith score. Can use compressed graph views for context-efficient design review.

**Planner (Daedalus):** Receives L1 + blast radius + importance ranking. Plans include ALL affected files (not just the obvious ones). Orders tasks by topological depth (dependencies first). Uses importance scores to prioritize critical-path files. This is the second biggest win after Explorer.

**Implementer (Hephaestus):** Receives L2 subgraph of working area. Knows exact import paths, available exports from neighboring modules, and which tests cover the current file. Compressed L2 views provide context within token budgets.

**Reviewer (Themis):** Receives L1 + structural diff + smells + cycles. Checks: new cycles introduced? Layer violations? New architectural smells? High-centrality file changed without adequate test coverage? Structural diff shows exactly what changed architecturally.

**Tester (Aletheia):** Receives L1 with test mappings. Knows which test files exist for changed sources. Identifies untested files.

**Reflector (Mnemosyne):** Receives L2 + Martin metrics. During post-task reflection, analyzes whether changes respected architectural boundaries, introduced new cycles, or affected high-centrality files. Martin metrics show if changes moved clusters toward Zone of Pain. Structural context enriches reflection quality — e.g., "this task touched 3 clusters across 2 layers" informs pattern detection.

**Auditor (Argus):** Receives L2 + stats + smells + spectral. During system audits, verifies graph health (cycle count trends, bottleneck evolution, cluster cohesion, monolith score evolution). Smell detection identifies architectural degradation. Spectral analysis reveals coupling trends.

### Planner Integration

The Planner (Daedalus) already assembles instruction files for downstream agents. Graph loading adds steps:

```
For each downstream agent:
  1. Load knowledge by access matrix (existing)
  2. Load graph view by access matrix level (NEW)
  3. If blast radius needed: call `ariadne query blast-radius` or MCP tool (NEW)
  4. If architectural analysis needed: load smells + metrics (NEW)
  5. Assemble instruction file
```

Graph views are pre-generated markdown — no parsing needed. Blast radius and smell queries are CLI calls or MCP tool invocations returning structured data.

## CLI Interface

### `ariadne` — Standalone CLI

```
ariadne build <project-root> [options]
    Parse project, build full graph → graph.json, clusters.json, stats.json
    Options:
      --output <dir>        Output directory (default: .ariadne/graph/)
      --verbose             Per-stage timing, import warnings
      --warnings [human|json]  Warning output format
      --strict              Exit code 1 on warnings
      --timestamp           Include generation timestamp
      --max-file-size <N>   Max file size in bytes (default: 1MB)
      --max-files <N>       Max files to process (default: 50,000)
      --no-louvain          Disable Louvain clustering

ariadne update <project-root> [options]
    Incremental update via delta computation (same options as build)

ariadne query blast-radius <file> [--depth N] [--format json|md] [--graph-dir <dir>]
    Reverse BFS from file, output dependents with distance

ariadne query subgraph <file...> [--depth N] [--format json|md]
    Extract neighborhood around specified files

ariadne query stats [--format json|md]
    Output precomputed metrics (centrality, SCCs, layers)

ariadne query centrality [--min <threshold>] [--format json|md]
    Show betweenness centrality scores

ariadne query cluster <name> [--format json|md]
    Output cluster detail

ariadne query file <path> [--format json|md]
    All info about a specific file: deps, dependents, metrics

ariadne query cycles [--format json|md]
    List all circular dependencies

ariadne query layers [--format json|md]
    Show architectural layers

ariadne query metrics [--format json|md]
    Show Martin metrics per cluster (I, A, D, zone)

ariadne query smells [--min-severity high|medium|low] [--format json|md]
    Detect architectural smells (7 types)

ariadne query importance [--top N] [--format json|md]
    File importance ranking (centrality + PageRank)

ariadne query spectral [--format json|md]
    Spectral analysis: algebraic connectivity, monolith score, Fiedler bisection

ariadne query compressed --level 0|1|2 [--focus <name>] [--depth N] [--format json|md]
    Hierarchical compression at project/cluster/file level

ariadne views generate [--output <dir>] [--graph-dir <dir>]
    Generate/regenerate all markdown views (L0 index + L1 cluster views)

ariadne serve [options]
    Start MCP server for real-time graph queries
    Options:
      --project <dir>       Project root (default: .)
      --output <dir>        Graph output directory
      --debounce <ms>       File watcher debounce (default: 2000)
      --no-watch            Disable file system watcher

ariadne info
    Version, supported languages, build info
```

Default `--format` is `md` (human/agent readable). `json` for programmatic use.

### `/moira:graph` — Moira Skill

Wraps `ariadne` CLI calls for use within Claude Code sessions:

```
/moira:graph                          # overview: clusters, critical files, cycles
/moira:graph blast-radius <file>      # who depends on this file
/moira:graph cluster <name>           # files and connections in cluster
/moira:graph file <path>              # everything about a file
/moira:graph cycles                   # all circular dependencies
/moira:graph layers                   # architectural layers
/moira:graph metrics                  # Martin metrics per cluster
/moira:graph smells                   # architectural anti-patterns
/moira:graph importance               # file importance ranking
/moira:graph spectral                 # connectivity and monolith score
/moira:graph diff                     # structural changes since last update
/moira:graph compressed <level>       # hierarchical compression view
```

### Integration with Existing Commands

**`/moira:init`** — Step 4b: `ariadne build` runs in parallel with scanner agents. Views generated after build. If `ariadne serve` is available, registers Ariadne as infrastructure MCP server in `.mcp.json` (project root, D-120) and adds it to the MCP registry with `infrastructure: true` (D-108). This ensures all pipeline agents can query the graph interactively regardless of pipeline type.

**`/moira:refresh`** — Runs `ariadne update` (delta). Reports changes including structural diff: "Graph updated: 7 files changed, 3 added, 1 removed. 1 new cycle detected. 2 smells resolved."

**`/moira:status`** — Displays graph summary section:
```
Project Graph:
  Files: 847 | Edges: 2,341 | Clusters: 12
  Cycles: 2 | Bottlenecks: 3 | Smells: 4
  Monolith score: 0.23 | Freshness: 98%
  Last updated: 4 tasks ago | Status: fresh
```

**`/moira:health`** — Includes graph health checks:
```
Graph Health:
  ✓ Graph exists and is current
  ⚠ 2 circular dependencies (auth ↔ billing)
  ⚠ 3 files with centrality > 0.9 (bottlenecks)
  ⚠ 1 god file detected (src/utils/format.ts)
  ✓ All clusters < 50 files
  ✓ No unstable foundations
  ✓ Monolith score: 0.23 (healthy)
```

## Installation

### Requirements

- Ariadne binary (Rust CLI)
- No Rust toolchain needed if using prebuilt binaries

### Installation Methods

**Via cargo (recommended for developers):**
```bash
cargo install ariadne-graph
```

**Via install script:**
```bash
curl -sSL https://raw.githubusercontent.com/anthropics/ariadne/main/install.sh | bash
```

**Via GitHub Releases (manual):**
```bash
# Download for your platform from GitHub Releases
# macOS ARM64, macOS x64, Linux x64, Windows x64
```

**Via Moira installer (future):**
`install.sh` checks for `ariadne` and offers to install if missing.

### Init-Time Check

During `/moira:init`, Moira checks for `ariadne` binary:

```
✓ ariadne v0.3.0 found (MCP server available)
```

or:

```
⚠ ariadne not found
  Project Graph features will be unavailable.
  Install: cargo install ariadne-graph
  Or: curl -sSL https://raw.githubusercontent.com/anthropics/ariadne/main/install.sh | bash
```

Graph features degrade gracefully — Moira works without the graph, but agents lose navigation, impact analysis, and architectural intelligence capabilities (D-102).

## Future: Anamnesis Integration

The Project Graph and Anamnesis (knowledge graph) are complementary layers:

- **Project Graph:** structural topology (files, imports, layers) — deterministic, from code
- **Anamnesis:** semantic knowledge (patterns, decisions, failures) — learned, from experience

### Integration Points (planned)

1. **Shared taxonomy:** Graph node domains/tags will align with Anamnesis taxonomy format. When Anamnesis replaces the Knowledge System, both systems use the same semantic vocabulary.

2. **Cross-referencing:** Anamnesis engrams can reference graph node paths. "This pattern applies to files in the `auth` cluster" → engram links to cluster ID.

3. **Enriched retrieval:** Anamnesis retrieval can use graph structure as a signal. "Give me knowledge relevant to files that depend on `auth/middleware.ts`" → blast radius → domain extraction → Anamnesis query.

4. **Structural context for consolidation:** When Anamnesis consolidates post-task, graph provides structural context: which clusters were touched, what was the blast radius, were layer boundaries crossed. Martin metrics and smell data enrich reflection quality.

### Boundary Principle

- **Graph does NOT store knowledge.** No patterns, no decisions, no lessons.
- **Anamnesis does NOT store topology.** No file dependencies, no import maps, no layers.
- **Integration is at the query level**, not the storage level. Each system maintains its own source of truth.

## Quantitative Impact (Expected)

| Metric | Without Graph | With Graph | Improvement |
|---|---|---|---|
| Explorer token usage | 30-80k/task | 10-25k/task | 50-70% reduction |
| Missed files in plans | ~15% of tasks | ~2% of tasks | 7x fewer |
| Import errors in implementation | ~10% of tasks | ~1% of tasks | 10x fewer |
| Architectural violations | not detected | auto-detected | new capability |
| Classification accuracy | description-only | description + structure | higher accuracy |
| Architectural smell detection | manual review | automated (7 types) | new capability |
| Design quality tracking | not measured | Martin metrics + spectral | new capability |
| Structural change impact | manual assessment | automated diff + classification | new capability |

## Constitutional Compliance

- **Art 1.1:** Graph is built by external CLI (`ariadne`), not by orchestrator. Orchestrator reads pre-generated views only. MCP server runs as a separate process.
- **Art 1.2:** No agent writes to graph. Graph is read-only for all agents.
- **Art 2.1:** Graph data is a deterministic input to classification (same graph + same description = same classification). Pipeline selection remains a pure function of classification output.
- **Art 3.1:** Graph build/update operations are triggered during `/moira:init` and `/moira:refresh`, which are user-initiated commands outside the task pipeline. Graph operations are not pipeline steps — they are infrastructure maintenance. Graph files are committed and fully reproducible. MCP server auto-updates are transparent infrastructure, not pipeline state changes.
- **Art 5.1:** Graph is structural data from code, not knowledge from observation. Knowledge integrity rules don't apply (graph is not knowledge).
- **Art 6.2:** This design document is the authoritative source for Project Graph.
