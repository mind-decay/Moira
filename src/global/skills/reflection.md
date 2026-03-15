# Reflection Dispatch

Reference: `design/specs/2026-03-15-phase10-reflection-engine.md` (D3)

This skill defines how the orchestrator dispatches Mnemosyne (reflector) at the appropriate depth level after task completion.

---

## Level Determination

1. Read `post: reflection:` from the pipeline YAML for the current pipeline type
2. **Periodic escalation check:** Call `moira_reflection_deep_counter` on `state/reflection/deep-reflection-counter.yaml`:
   - If counter >= 5 AND level is `background` → escalate to `deep`, call `moira_reflection_deep_counter <state_dir> reset`
   - Otherwise: call `moira_reflection_deep_counter <state_dir> increment`
3. Route by level:
   - `lightweight` → write minimal note directly (no agent dispatch)
   - `background` → dispatch Mnemosyne as background agent
   - `deep` → dispatch Mnemosyne as foreground agent
   - `epic` → dispatch Mnemosyne as foreground agent with epic scope

## Lightweight Handling

Write minimal reflection note to `state/tasks/{id}/reflection.md` using `templates/reflection/lightweight.md` template. Substitute placeholders: {task_id}, {pipeline_type}, {final_gate_action}, {retry_count}, {budget_pct}. No agent dispatch.

## Prompt Assembly (background/deep/epic)

Construct Mnemosyne prompt from:

1. **Template:** Load appropriate template from `~/.claude/moira/templates/reflection/{level}.md`
2. **Task Context:**
   ```
   ## Task Context
   Task ID: {task_id}
   Pipeline: {pipeline_type}
   Task artifacts: {list of state/tasks/{id}/*.md paths}
   ```
3. **Knowledge Context:** Assemble using `moira_knowledge_read_for_agent` with agent=mnemosyne (all types at L2)
4. **Recent History:** Output from `moira_reflection_task_history` (last 5-10 tasks)
5. **Pending Observations:** Active pattern keys from `state/reflection/pattern-keys.yaml`

### Dispatch Mode
- `background` → Agent tool with `run_in_background: true`
- `deep` / `epic` → Agent tool foreground (blocking)

## Post-Reflection Processing

After Mnemosyne returns, the orchestrator processes the output:

1. **Knowledge Updates:** Parse KNOWLEDGE_UPDATES section from Mnemosyne output. For each update:
   - Call `moira_knowledge_validate_consistency` before writing (Art 5.3)
   - If valid: call `moira_knowledge_write` with appropriate type/level/content
   - If conflict: log warning, skip write

2. **Rule Proposals:** Parse RULE_PROPOSALS section. For each proposal:
   - Call `moira_reflection_record_proposal` to store
   - Check cooldown: read `config.yaml` → `quality.evolution.cooldown_remaining`
   - If NOT in cooldown: display proposal notification:
     ```
     Mnemosyne (reflector) — Rule Change Proposal

     Pattern: {pattern_key} (observed {count} times)
     Proposed: {description}

     Evidence:
       1. Task {id}: {observation}
       ...

       approve  — apply the proposed change
       defer    — revisit later
       reject   — dismiss proposal
       details  — show full evidence
     ```
   - If in cooldown: accumulate silently (proposals stored but not presented)

3. **MCP Caching:** Parse MCP caching recommendations. For each:
   ```
   MCP Caching Recommendation

   {server}:{tool}("{query}") called {count} times
   Estimated savings: ~{tokens}k tokens per task

     cache  — create knowledge/libraries/{name}.md
     ignore — library changes too often, always fetch fresh
   ```

4. **Pattern Registry Update:** Update `state/reflection/pattern-keys.yaml` with new observations

5. **Auto-defer stale proposals:** Call `moira_reflection_auto_defer_stale` before presenting new proposals
