# Scanner: Recurring Pattern Identification
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective

Identify recurring code patterns, component structures, and architectural abstractions:

1. **Component patterns** (if frontend) — functional vs class, state management, styling approach
2. **API patterns** — REST/GraphQL/RPC, handler structure, request validation, response format
3. **Data access patterns** — repository/active record/direct ORM/raw SQL, transaction handling
4. **State management** (if frontend) — client state library, server state library
5. **Common abstractions** — base classes, HOCs, hooks, decorators, middleware chains, utility wrappers
6. **Recurring structures** — patterns that appear across multiple files with consistent shape

## Scan Strategy

1. Read 3-5 representative files per architectural layer:
   - UI components (if frontend)
   - API handlers/controllers
   - Data access / repository layer
   - Business logic / services
   - Middleware / interceptors
2. For each layer: identify the RECURRING structure (not unique one-offs)
3. Note abstractions: base classes, HOCs, hooks, decorators, middleware chains
4. Look for project-specific patterns (custom hooks, utility wrappers, etc.)
5. **NEVER read more than 25 files total**

## Output Format

Write your findings as structured markdown using EXACTLY this format:

```markdown
## Component Pattern (if frontend)
- Structure: {functional/class/mixed}
- State: {hooks/stores/context/redux}
- Styling: {CSS modules/Tailwind/styled-components/...}
- Example: {path — representative file}

## API Pattern
- Style: {REST/GraphQL/RPC/tRPC}
- Handler structure: {controller→service→repo / route handler / serverless function}
- Request validation: {zod/joi/class-validator/manual/none}
- Response format: {envelope pattern/raw/standard}
- Example: {path — representative file}

## Data Access Pattern
- Pattern: {repository/active record/direct ORM/raw SQL}
- Transaction handling: {middleware/manual/none}
- Example: {path — representative file}

## State Management (if frontend)
- Client state: {zustand/redux/context/jotai/...}
- Server state: {react-query/swr/rtk-query/manual}
- Example: {path — representative file}

## Common Abstractions
| Abstraction | Location | Purpose |
|-------------|----------|---------|
| {e.g., useQuery hook} | {path} | {what it wraps} |
| ... | ... | ... |

## Recurring Structures
| Pattern | Frequency | Example |
|---------|-----------|---------|
| {e.g., "every service has constructor injection"} | {all/most/some} | {path:line} |
| ... | ... | ... |
```

## Output Path

Write the complete output to: `.claude/moira/state/init/pattern-scan.md`

## Constraints

- Report ONLY observed facts with file path evidence
- Never propose solutions
- Never express opinions
- Never make recommendations
- NO opinions, NO recommendations, NO proposals
- Focus on RECURRING patterns — ignore one-off implementations
- If a category has no data, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
