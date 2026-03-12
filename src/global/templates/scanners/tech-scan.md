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

Write your findings as structured markdown using EXACTLY this format:

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
- If a category has no data, write "Not detected" — do NOT guess
- Budget: stay within 140k tokens — sample, don't exhaustively scan
- For each fact, note which file it was found in (e.g., "from package.json")
