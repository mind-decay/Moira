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

Start output with a YAML frontmatter block between `---` delimiters. Fields you cannot determine — omit entirely.

After the second `---`, write the detailed markdown report.

### Frontmatter Contract

```yaml
---
naming_files: kebab-case
naming_functions: camelCase
naming_components: PascalCase
naming_constants: UPPER_SNAKE_CASE
naming_types: PascalCase
indent: 2 spaces
quotes: single
semicolons: false
max_line_length: 100
import_style: named
export_style: default
---
```

Fields: `naming_files`, `naming_functions`, `naming_components`, `naming_constants`, `naming_types`, `indent`, `quotes`, `semicolons`, `max_line_length`, `import_style`, `export_style`.

**CRITICAL:** Use these EXACT field names VERBATIM. Do NOT rename fields (e.g., do NOT use `file_naming` instead of `naming_files`). The downstream parser matches these exact strings — renamed fields will be silently lost.

All values are plain strings. Omit any field you cannot determine.

### Markdown Body

After the frontmatter, write the detailed report using this format:

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

Write the complete output to: `.moira/state/init/convention-scan.md`

## Constraints

- Report ONLY observed facts with file path evidence
- Never propose solutions
- Never express opinions
- Never make recommendations
- NO opinions, NO recommendations, NO proposals
- Every claim MUST include `file:line` evidence
- Do NOT write `Not detected` or `unknown` in frontmatter — omit the field
- In the markdown body, write "Not detected" for empty categories — do NOT guess
- Budget: stay within 100k tokens — sample, don't exhaustively scan
