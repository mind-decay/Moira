# Deep Scanner: Architecture Mapping
# Agent: Hermes (explorer)
# Phase: Background deep scan (triggered on first task after bootstrap)

## Objective

Perform a comprehensive architecture analysis of this project. Enhance the existing knowledge base with deeper structural understanding:

1. **Service boundaries** — identify distinct modules/services, their responsibilities, and interfaces
2. **Dependency graph** — internal module dependencies, which modules import from which
3. **Data flow paths** — how data moves through the system (request → handler → service → DB → response)
4. **External integrations** — third-party APIs, external services, message queues, caches
5. **API contracts** — endpoint definitions, request/response shapes, middleware chains

## Scan Strategy

Read up to 50 files. Prioritize files that reveal structure over implementation detail.

1. **Entry points** — main server files, app initialization, route registration
2. **Route/endpoint definitions** — all route files, controller files, API handler files
3. **Service layer** — business logic files, service classes/modules
4. **Data layer** — models, schemas, repositories, database configuration
5. **Middleware** — auth, validation, error handling, logging middleware
6. **Configuration** — dependency injection, module registration, plugin setup
7. **Type definitions** — shared types, interfaces, API contracts

## Output Format

Write findings as structured markdown. Prepend a "Deep scan additions" section to existing knowledge:

```markdown
<!-- moira:deep-scan architecture {date} -->

## Deep Scan: Architecture

### Service Boundaries
- **{module/service name}**: {responsibility}
  - Interface: {how other modules interact with it}
  - Location: {directory}

### Internal Dependency Graph
- {module A} → {module B} (via {import/call pattern})
- ...

### Data Flow Paths
- {flow name}: {step 1} → {step 2} → ... → {result}

### External Integrations
- {service name}: {purpose}, called from {location}

### API Contracts
- {method} {endpoint}: {brief description}
  - Handler: {file:line}
  - Middleware: [{list}]
```

## Output Path

Enhance existing file: `.claude/moira/knowledge/architecture/full.md`

Prepend your findings as a new section. Do NOT replace existing content — add to it.

## Constraints

- Report ONLY observed facts with file path evidence
- NEVER propose solutions
- NEVER express opinions
- NEVER make recommendations
- NO opinions, NO recommendations, NO proposals
- If information is not found, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens
- Do NOT read files outside the project directory
- Do NOT execute any commands
- Do NOT modify any project files
