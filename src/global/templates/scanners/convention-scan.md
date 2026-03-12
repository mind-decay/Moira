# Scanner: Coding Convention Detection
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective

Detect coding conventions actually used in this project by examining real code samples:

1. **Naming conventions** — file naming, function naming, component naming, constants, types
2. **Import style** — named vs default, path aliases, import ordering
3. **Export style** — default exports, barrel re-exports
4. **Error handling** — try-catch, error boundaries, result types, middleware
5. **Logging** — library used, structured vs unstructured
6. **Code organization** — typical function/file length, comment style

## Scan Strategy

1. Read linter/formatter configs for explicit rules
2. Sample 3-5 files from EACH of these categories (if they exist):
   - Components/views (UI files)
   - API routes/handlers
   - Services/business logic
   - Utilities/helpers
   - Type definitions
   - Test files
3. For each file: note naming, imports, exports, error handling pattern
4. Look for shared patterns across samples
5. **NEVER read more than 30 files total**

## Output Format

Write your findings as structured markdown using EXACTLY this format:

```markdown
## Naming Conventions
| What | Convention | Evidence |
|------|-----------|----------|
| Files | {kebab-case/camelCase/PascalCase} | src/components/user-profile.tsx, ... |
| Functions | {camelCase/snake_case} | getUserById in src/services/user.ts:12 |
| Components | {PascalCase} | UserProfile in src/components/user-profile.tsx:5 |
| Constants | {UPPER_SNAKE/camelCase} | MAX_RETRIES in src/config/constants.ts:3 |
| Types/Interfaces | {PascalCase} | User in src/types/user.ts:1 |
| Test files | {*.test.ts/*.spec.ts} | src/services/__tests__/user.test.ts |

## Import Style
- Module imports: {named/default/mixed}
- Path aliases: {@ = src, ~ = root, none}
- Import order: {framework → external → internal → relative}
- Evidence: {file:line examples}

## Export Style
- Default exports: {used/not used}
- Re-export barrels: {index.ts files present/absent}
- Evidence: {file:line examples}

## Error Handling
- Pattern: {try-catch/error boundary/result type/middleware}
- Custom errors: {yes — path, no}
- Evidence: {file:line examples}

## Logging
- Library: {console/winston/pino/slog/none}
- Pattern: {structured/unstructured}
- Evidence: {file:line examples}

## Code Organization
- Function length: {typical range}
- File length: {typical range}
- Comments: {frequent/rare/JSDoc/none}
- Evidence: {representative files}
```

## Output Path

Write the complete output to: `.claude/moira/state/init/convention-scan.md`

## Constraints

- Report ONLY observed facts with file path evidence
- Never propose solutions
- Never express opinions
- Never make recommendations
- NO opinions, NO recommendations, NO proposals
- Every claim MUST include `file:line` evidence
- If a category has no data, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
