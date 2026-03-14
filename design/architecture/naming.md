# Naming & Identity System

## System Name

**Moira** (Μοῖρα) — the three Fates of Greek mythology who spin, measure, and cut the threads of destiny. The system orchestrates agents through deterministic pipelines, just as the Moirai determine the course of each thread.

## Naming Principle

> **Every name appears as `Name (role)` — everywhere, always, without exception.**

Users learn mythology naturally through repetition but are never blocked by unfamiliarity. The role in parentheses makes every message self-explanatory.

### Display Rules

1. **CLI output**: `Hermes (explorer) scanning codebase...`
2. **Error messages**: `[Aegis · self-protection] Constitutional violation detected`
3. **Logs**: `Themis (reviewer) found 2 issues`
4. **Documentation**: glossary table in `moira help` and README
5. **Conversational references**: "Themis rejected the code" is fine in docs/community — the `(role)` suffix is required only in system output

## Pipeline Phases — The Three Fates

The three Moirai map directly to pipeline phases:

| Fate | Greek | Meaning | Pipeline Phase | Action |
|------|-------|---------|----------------|--------|
| **Kloto** | Κλωθώ | "the spinner" | Dispatch | Spins new threads — creates agents, forms the task |
| **Lachesis** | Λάχεσις | "the allotter" | Execute | Measures the thread — distributes work, tracks budget |
| **Atropos** | Ἄτροπος | "the unturnable" | Gate | Cuts the thread — irreversible decision: approve / reject / return |

## Agents — The Pantheon

Each agent is named after a deity whose mythological role mirrors the agent's function.

| Agent Role | Name | Greek | Why This Deity |
|------------|------|-------|----------------|
| Classifier | **Apollo** (Ἀπόλλων) | God of prophecy and order | Sees the nature of the task, classifies before action begins |
| Explorer | **Hermes** (Ἑρμῆς) | Messenger god, boundary-crosser | Scouts and reports back, crosses boundaries others cannot |
| Analyst | **Athena** (Ἀθηνᾶ) | Goddess of wisdom and strategy | Formalizes requirements with wisdom, identifies what others miss |
| Architect | **Metis** (Μῆτις) | Titaness of wise counsel | Mother of Athena — deeper strategic thinking, shapes the structure |
| Planner | **Daedalus** (Δαίδαλος) | Master craftsman, labyrinth builder | Decomposes complex designs into buildable steps |
| Implementer | **Hephaestus** (Ἥφαιστος) | God of the forge, divine smith | The only one who builds with his hands — writes actual code |
| Reviewer | **Themis** (Θέμις) | Titaness of divine law and justice | Judges code against standards, impartial and absolute |
| Tester | **Aletheia** (Ἀλήθεια) | Spirit of truth and disclosure | Reveals what is true and what fails — tests expose reality |
| Reflector | **Mnemosyne** (Μνημοσύνη) | Titaness of memory, mother of Muses | Preserves learnings, turns experience into wisdom |
| Auditor | **Argus** (Ἄργος) | The hundred-eyed giant | Sees everything at once — independent, comprehensive oversight |

## System Components — Cosmological Forces

| Component | Name | Greek | Why |
|-----------|------|-------|-----|
| Constitution | **Ananke** (Ἀνάγκη) | Primordial goddess of necessity/inevitability | Mother of the Moirai — the force above fate itself. Cannot be violated. |
| Orchestrator | **Moira** | The system itself | Weaves all threads together |
| Thread of execution | **Klosthos** (κλωστή) | Thread, yarn | The unit of work being spun through the pipeline |
| Gate | **Atropos** | "The unturnable" | Irreversible decision point — once cut, the thread cannot be uncut |
| Knowledge base | **Aletheia** (Ἀλήθεια) | Truth, un-forgetting | Repository of verified truth about the project [^1] |
| Budget system | **Chronos** (Χρόνος) | Primordial time | Finite resource that must be allocated wisely |
| Self-protection | **Aegis** (Αἰγίς) | Shield of Zeus and Athena | The divine shield — protects the system's invariants |
| Metrics | **Moiragetes** (Μοιραγέτης) | "Leader of the Fates" (epithet of Zeus) | Observes and tracks what the Fates produce |

## CLI Examples

### Pipeline execution

```
moira run

  ┌ Pipeline: standard
  │
  ├ Kloto (dispatch)
  │  └ Spinning Apollo (classifier)...
  │
  ├ Apollo (classifier)
  │  └ size=medium, confidence=high
  │
  ├ Hermes (explorer)
  │  └ Found 12 files, 3 patterns identified
  │
  ├ Athena (analyst)
  │  └ 8 requirements, 3 edge cases, 0 blockers
  │
  ├ Metis (architect)
  │  └ Decision: adapter pattern, 2 alternatives rejected
  │
  ├ Daedalus (planner)
  │  └ 4 tasks, 2 parallel batches
  │
  ├ Hephaestus (implementer)
  │  └ 4/4 tasks complete
  │
  ├ Themis (reviewer)
  │  └ 1 warning, 0 critical
  │
  ├ Aletheia (tester)
  │  └ 12 tests, all passing
  │
  └ Atropos (gate)
     └ ⏳ Awaiting your approval
```

### System status

```
moira status

  Thread: klosthos-7a3f
  Pipeline: standard (step 6/9)
  Aegis: all invariants hold
  Chronos: 58% budget remaining
  Mnemosyne: 2 reflections pending
```

### Help / glossary

```
moira help agents

  Name          Role           Does what
  ─────────────────────────────────────────────────────
  Apollo        classifier     Determines task size and pipeline
  Hermes        explorer       Explores codebase, reports facts
  Athena        analyst        Formalizes requirements
  Metis         architect      Makes technical decisions
  Daedalus      planner        Decomposes into execution steps
  Hephaestus    implementer    Writes and modifies code
  Themis        reviewer       Reviews code against standards
  Aletheia      tester         Writes and runs tests
  Mnemosyne     reflector      Analyzes tasks for learning
  Argus         auditor        Independent system health checks

moira help system

  Name          Role              Does what
  ─────────────────────────────────────────────────────
  Ananke        constitution      Inviolable system rules
  Aegis         self-protection   Guards invariants
  Chronos       budget            Tracks resource usage
  Atropos       gate              Approval checkpoints
  Klosthos      thread            Unit of work in pipeline
  Moiragetes    metrics           Observes system performance
```

[^1]: "Aletheia" is intentionally shared between the Tester agent and the Knowledge Base concept — both embody "truth/verification".

## Extensibility

The Greek pantheon and mythology provide a vast namespace for future agents and components. When adding new elements:

1. Choose a figure whose mythological role genuinely mirrors the system function
2. Prefer lesser-known figures over overloaded ones (Argus over Zeus)
3. Document the "why" — the mapping must be meaningful, not decorative
4. Always include the `(role)` display alongside the name
