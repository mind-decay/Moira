# Deep Scanner: Security Surface Scan
# Agent: Hermes (explorer)
# Phase: Background deep scan (triggered on first task after bootstrap)

## Objective

Perform a comprehensive security surface scan. Identify potential security concerns through code pattern analysis:

1. **Hardcoded secrets** — strings that look like API keys, tokens, passwords, connection strings
2. **Input validation gaps** — system boundary handlers missing validation
3. **Auth middleware coverage** — which endpoints have auth protection, which don't
4. **Unsafe patterns** — eval, exec, dangerouslySetInnerHTML, SQL concatenation, shell injection vectors
5. **Sensitive data handling** — logging of sensitive data, error message information leakage

## Scan Strategy

Read up to 50 files. Focus on system boundaries and security-critical code.

1. **Environment and config files** (read):
   - `.env.example`, `.env.sample` (NEVER read `.env` — it may contain real secrets)
   - Config files that reference environment variables
   - Secret management setup (vault, KMS, etc.)

2. **API boundary handlers** (read all):
   - Route handlers, controllers, API endpoints
   - Check for input validation on each endpoint
   - Check for auth middleware in route chains

3. **Auth/security middleware** (read fully):
   - Authentication middleware
   - Authorization/RBAC middleware
   - CORS configuration
   - Rate limiting configuration
   - CSRF protection

4. **Data access layer** (scan):
   - Database queries — look for string concatenation in SQL
   - ORM usage — check for raw queries
   - File system access — check for path traversal risks

5. **Client-side rendering** (if applicable):
   - Check for dangerouslySetInnerHTML or equivalent
   - Check for eval() usage
   - Check for script injection vectors

6. **Error handling** (scan):
   - Error responses — do they leak stack traces or internal details?
   - Logging — does it log sensitive data (passwords, tokens, PII)?

## Output Format

Write findings as structured markdown:

```markdown
<!-- moira:deep-scan security {date} -->

## Deep Scan: Security

### Potential Hardcoded Secrets
- {file:line}: {description of what looks like a secret}
  - Type: {API key / token / password / connection string}
  - Risk: {high/medium/low}

### Input Validation Gaps
- {endpoint/handler}: {what validation is missing}
  - Location: {file:line}
  - Boundary: {API / file upload / query parameter / ...}

### Auth Coverage
| Endpoint | Auth Middleware | Status |
|----------|---------------|--------|
| {method} {path} | {middleware or "none"} | {protected/unprotected} |

### Unsafe Patterns
- {pattern}: {description}
  - Location: {file:line}
  - Risk: {description of potential exploit}

### Sensitive Data Handling
- {observation about logging/error handling of sensitive data}
  - Location: {file:line}
```

## Output Path

Enhance existing file: `.claude/moira/knowledge/security/full.md`

Prepend your findings as a new section. Do NOT replace existing content — add to it.

If `security/full.md` does not exist, create it with this content as the initial section.

## Constraints

- Report ONLY observed facts with file path evidence
- NEVER propose solutions
- NEVER express opinions
- NEVER make recommendations
- NO opinions, NO recommendations, NO proposals
- NEVER read `.env` files — they may contain real secrets
- If information is not found, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens
- Do NOT read files outside the project directory
- Do NOT execute any commands
- Do NOT modify any project files
