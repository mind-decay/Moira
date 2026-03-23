# Gate Input Classification and Routing

Source: analytical task-2026-03-24-001
Decisions: D-136, D-137, D-138, D-139, D-140

**Type:** Design Document
**Risk:** GREEN — additive behavior within existing orchestrator flow
**Scope:** Orchestrator gate interaction handling
**Status:** Draft

---

> **Decisions in this document:**
>
> - **D-136:** Gate input classification — 5-category taxonomy with uniform classification
> - **D-137:** Gate routing — store-and-reprompt pattern
> - **D-138:** Gate recording — two-layer (state stores content, telemetry stores enums)
> - **D-139:** Gate re-prompt — soft bound of 3
> - **D-140:** Feedback buffer — accumulated free-form input enriches modify flow

---

## 1. Overview

### Purpose

This document defines how the orchestrator classifies and routes user input received at approval gates. Gates currently expect explicit menu selections (e.g., `proceed`, `modify`, `abort`), but users frequently provide free-form input — feedback, questions, contextual instructions, or ambiguous shorthand. This design specifies a deterministic classification and routing layer that handles all input types while preserving constitutional guarantees. (F1, F2)

### Scope

- Input classification taxonomy for all gate types
- Routing rules per input category
- Feedback accumulation mechanism
- Re-prompt bounds
- State and telemetry recording
- Constitutional compliance verification

### Risk Classification

**GREEN.** This design is additive — it inserts a classification step into the existing gate interaction flow without modifying gate definitions, pipeline structures, or agent boundaries. No existing orchestrator.md content is removed or altered. (F7a)

---

## 2. Input Classification Taxonomy

All user input at gates SHALL be classified into exactly one of five categories. Classification is uniform across all gate types — the same rules apply whether the gate is an approval gate, a quality gate, or a selection gate. (F1, F7)

| Category | Definition | Examples | Expected Frequency |
|---|---|---|---|
| **Menu selection** | Input that exactly matches a gate option (case-insensitive) or its numeric index | `"1"`, `"proceed"`, `"modify"`, `"abort"` | Expected (primary path) |
| **Feedback-as-selection** | Free-form input that provides feedback implying a gate decision | `"looks good but change the naming"`, `"the approach is fine, just use interfaces"` | High |
| **Question** | Input requesting information before making a decision | `"what files will this touch?"`, `"how does this affect the API?"` | Medium |
| **Contextual instruction** | Input providing direction that changes the task context | `"actually, use Redis instead of Memcached"`, `"target Python 3.12"` | Medium |
| **Ambiguous/typo** | Input that appears to be a menu selection attempt but does not exactly match | `"procede"`, `"go"`, `"ok"`, `"y"` | Low-Medium |

### Classification Rules

1. The classifier receives the current gate's option list for exact-match detection. (F7)
2. **Menu selection** is determined by exact match (case-insensitive) against the gate's option list or numeric index.
3. All other categories are determined by input structure and content, not by gate type.
4. Classification is uniform — the same classifier handles all 13+ gate types. Per-gate classifiers are explicitly rejected due to maintenance burden. (F7)
5. A single classifier without gate awareness is explicitly rejected because it cannot handle selection gates where options vary. (F7)

---

## 3. Routing Rules

The core routing pattern is **store-and-reprompt**: all non-menu input is stored as context, and the gate menu is re-presented for explicit selection. A gate decision SHALL only result from an explicit menu selection. (F2)

### Routing Table

| Input Category | Action | Gate Decision? | State Change? |
|---|---|---|---|
| **Menu selection** | Execute the selected gate option | YES | YES — gate transitions |
| **Feedback-as-selection** | Store in feedback buffer; re-present gate | NO | NO — context only |
| **Question** | Answer the question; re-present gate | NO | NO — display only |
| **Contextual instruction** | Store in feedback buffer; re-present gate | NO | NO — context only |
| **Ambiguous/typo** | Clarify ambiguity; re-present gate | NO | NO — display only |

### Design Rationale

The store-and-reprompt pattern was selected over three alternatives (F2):

- **Classify-then-confirm** (rejected): Risks implicit decision-making — violates Art 2.3.
- **Auto-classify** (rejected): Directly violates Art 2.3 — the system would make gate decisions without explicit user selection.
- **Ignore non-menu input** (rejected): Poor user experience — discards valuable feedback.

### Re-present Behavior

When re-presenting the gate after non-menu input, the orchestrator SHALL follow the `details` display-only precedent established in gates.md (L460-462, L541-542, L585): display information, re-present the gate options, and apply no state change. (F5)

---

## 4. Feedback Buffer and Modify Flow

### Feedback Buffer

The orchestrator SHALL maintain a **pending feedback buffer** — a transient, in-memory accumulation of free-form user input collected during gate interactions. (F6)

- When input is classified as **feedback-as-selection** or **contextual instruction**, the input text is appended to the feedback buffer.
- The buffer accumulates across multiple re-prompts within the same gate interaction.
- The buffer is associated with the current gate instance.

### Modify Flow Integration

When the user selects `modify`, the accumulated feedback buffer contents SHALL become the feedback payload dispatched to the modifying agent. This enriches the existing modify flow without introducing new gate structures. (F6)

### Buffer Clearing

The feedback buffer SHALL be cleared on any of the following events (F6):

1. **Modify dispatch** — buffer contents consumed as payload
2. **Task completion** — no longer relevant
3. **Explicit user clear** — user requests buffer reset

No new gate structures are introduced by this mechanism. The feedback buffer operates entirely within the existing gate interaction flow. (F6)

---

## 5. Re-prompt Bounds

### Soft Bound

The orchestrator SHALL apply a **soft bound of 3 re-prompts** per gate interaction. (F4)

- After 3 consecutive re-prompts (non-menu inputs), the orchestrator SHALL present explicit numbered options:

  ```
  Please select an option by number:
  1) proceed
  2) modify
  3) abort
  ```

- This is a **soft bound** — it does not force a decision. The user may continue providing non-menu input, which will be stored and the numbered options re-presented.

### Counter Reset

The re-prompt counter SHALL reset to zero on (F4):

1. **Menu selection** — user made a gate decision
2. **`details` display** — informational flow resets interaction context

---

## 6. State Recording

Gate input classification and routing SHALL be recorded using a **two-layer model** that satisfies both Art 3.1 (full traceability) and D-027 (no content in telemetry). (F3)

### Layer 1: State (status.yaml)

| Field | Type | Content |
|---|---|---|
| `gate_interactions[].input_text` | string | Full user input text |
| `gate_interactions[].category` | enum | Classification result |
| `gate_interactions[].feedback_buffer` | string[] | Accumulated feedback entries |
| `gate_interactions[].notes` | string | Any contextual notes |

State stores **content strings** — full input text, feedback, notes. This satisfies Art 3.1 full traceability. (F3)

### Layer 2: Telemetry (telemetry.yaml)

| Field | Type | Content |
|---|---|---|
| `gate_interactions[].input_category` | enum | `menu_selection`, `feedback`, `question`, `instruction`, `ambiguous` |
| `gate_interactions[].reprompt_count` | integer | Number of re-prompts before decision |

Telemetry stores **enums and counts only** — no content strings. This satisfies D-027. (F3)

---

## 7. Constitutional Compliance

All aspects of this design have been verified against constitutional constraints. (F7a)

| Article / Decision | Constraint | How This Design Satisfies It |
|---|---|---|
| **Art 2.2** | Gate types are fixed | No new gate types introduced. Classification and routing operate within existing gate interaction flow. |
| **Art 2.3** | No implicit decisions | Gate decisions result ONLY from explicit menu selection. Non-menu input is stored, never auto-interpreted as a decision. |
| **Art 3.1** | Full traceability | State layer (status.yaml) records all input text, classifications, and feedback — complete audit trail. |
| **Art 4.2** | User authority preserved | Re-prompt pattern returns control to user. Soft bound does not force decisions. User always selects. |
| **D-027** | No content in telemetry | Telemetry layer stores only enums (`input_category`) and integers (`reprompt_count`). All content strings remain in state. |

---

## 8. Implementation Guidance

### Location

This classification and routing logic SHALL be implemented as an additive insertion in **orchestrator.md, Section 2, step (f)** — the gate interaction handling step. (F7a)

### Integration Approach

- **Additive insertion.** No existing orchestrator.md content is removed or modified.
- The classification step executes immediately upon receiving user input at a gate, before any gate transition logic.
- The feedback buffer is maintained as transient orchestrator state during gate interaction.

### Risk

**GREEN.** This change:
- Introduces no new gate types (Art 2.2 preserved)
- Modifies no pipeline definitions
- Changes no agent boundaries or responsibilities
- Adds no new approval requirements

### Dependencies

- Existing gate option lists (for exact-match classification)
- Existing `details` display-only precedent (for re-present behavior)
- Existing `modify` flow (for feedback payload delivery)
