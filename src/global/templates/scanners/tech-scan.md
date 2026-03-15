# Scanner: Technical Stack Discovery
# Agent: Hermes (explorer)
# Phase: Bootstrap (/moira:init)

## Objective

Identify the following technical facts about this project:

1. **Languages** — primary and secondary languages with versions
2. **Frameworks** — web/API/CLI framework with version
3. **Build tools** — package manager, bundler, build system
4. **Test frameworks** — test runner, test config location, test directory pattern
5. **Linting & formatting** — linter, formatter, type checker with config paths
6. **Database & ORM** — database type, ORM/query builder, migration tool
7. **CI/CD** — platform, config file path
8. **Deployment** — container technology, hosting platform
9. **Package managers** — which lock file(s) exist

## Scan Strategy

Read files in this order. Stop after collecting sufficient data — do NOT exhaustively read every file.

1. **Root config files** (read contents):
   - `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`

2. **Tool configs** (read contents):
   - `tsconfig.json`, `.eslintrc*`, `.prettierrc*`, `jest.config*`, `vitest.config*`, `.babelrc*`, `webpack.config*`, `vite.config*`, `next.config*`, `nuxt.config*`

3. **CI/CD files** (read contents):
   - `.github/workflows/*.yml`, `.gitlab-ci.yml`, `Jenkinsfile`, `Dockerfile`, `docker-compose*`

4. **Environment examples** (read contents — NEVER read `.env`, it may contain secrets):
   - `.env.example`, `.env.sample`

5. **Lock files** (check existence ONLY — do NOT read contents):
   - `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Pipfile.lock`, `poetry.lock`, `go.sum`

## Output Format

Start output with a YAML frontmatter block between `---` delimiters. Fields you cannot determine — omit entirely.

After the second `---`, write the detailed markdown report.

### Frontmatter Contract

```yaml
---
language: TypeScript
language_version: "5.3"
framework: SvelteKit
framework_version: "2.0"
framework_type: web
runtime: Node.js
package_manager: pnpm
build_tool: vite
styling: Tailwind CSS
orm: Prisma
testing: Vitest
ci: GitHub Actions
deployment: Vercel
---
```

Fields: `language`, `language_version`, `framework`, `framework_version`, `framework_type`, `runtime`, `package_manager`, `build_tool`, `styling`, `orm`, `testing`, `ci`, `deployment`.

**CRITICAL:** Use these EXACT field names VERBATIM. Do NOT rename fields (e.g., do NOT use `primary_language` instead of `language`, do NOT use `css_framework` instead of `styling`). The downstream parser matches these exact strings — renamed fields will be silently lost.

All values are plain strings. Omit any field you cannot determine.

### Markdown Body

After the frontmatter, write the detailed report using this format:

```markdown
## Language & Runtime
- Primary: {language} {version}
- Secondary: {if any}

## Framework
- Name: {framework} {version}
- Type: {web/api/cli/library/monorepo}

## Build & Tooling
- Package manager: {npm/yarn/pnpm/pip/cargo/go}
- Build tool: {vite/webpack/turbopack/esbuild/tsc/none}
- Bundler config: {path or "default"}

## Testing
- Framework: {jest/vitest/pytest/go test/...}
- Config: {path}
- Test directory pattern: {co-located/__tests__/test/...}

## Linting & Formatting
- Linter: {eslint/pylint/golangci-lint/...} with config at {path}
- Formatter: {prettier/black/gofmt/...} with config at {path}
- Type checking: {typescript/mypy/none}

## Database & ORM
- Database: {postgres/mysql/sqlite/mongodb/none}
- ORM/Query: {prisma/drizzle/sqlalchemy/gorm/none}
- Migration tool: {prisma migrate/alembic/goose/none}

## CI/CD
- Platform: {github actions/gitlab ci/jenkins/none}
- Config: {path}

## Deployment
- Container: {docker/none}
- Platform: {vercel/aws/gcp/self-hosted/unknown}
```

## Output Path

Write the complete output to: `.claude/moira/state/init/tech-scan.md`

## Constraints

- Report ONLY observed facts with file path evidence
- Never propose solutions
- Never express opinions
- Never make recommendations
- NO opinions, NO recommendations, NO proposals
- Do NOT write `Not detected` or `unknown` in frontmatter — omit the field
- In the markdown body, write "Not detected" for empty categories — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
- For each fact, note which file it was found in (e.g., "from package.json")
