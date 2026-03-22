# Cluster: tests

## Files

| File | Type | Layer | In | Out | Centrality |
|------|------|------:|---:|----:|-----------:|
| `src/tests/bench/fixtures/greenfield-webapp/src/index.ts` | source | 1 | 0 | 1 | 0.0000 |
| `src/tests/bench/fixtures/greenfield-webapp/src/routes/health.ts` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/greenfield-webapp/src/types/index.ts` | source | 0 | 0 | 0 | 0.0000 |
| `src/tests/bench/fixtures/legacy-webapp/__tests__/health.test.js` | test | 0 | 0 | 0 | 0.0000 |
| `src/tests/bench/fixtures/legacy-webapp/src/app.js` | source | 1 | 0 | 2 | 0.0000 |
| `src/tests/bench/fixtures/legacy-webapp/src/controllers/UserController.js` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/legacy-webapp/src/routes/health.js` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/index.ts` | source | 3 | 0 | 4 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/middleware/error-handler.ts` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/routes/health.ts` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/routes/products.ts` | source | 2 | 1 | 1 | 0.0083 |
| `src/tests/bench/fixtures/mature-webapp/src/routes/users.ts` | source | 2 | 1 | 2 | 0.0083 |
| `src/tests/bench/fixtures/mature-webapp/src/services/product-service.ts` | source | 1 | 1 | 1 | 0.0083 |
| `src/tests/bench/fixtures/mature-webapp/src/services/user-service.ts` | source | 1 | 1 | 1 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/types/product.ts` | source | 0 | 1 | 0 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/src/types/user.ts` | source | 0 | 2 | 0 | 0.0000 |
| `src/tests/bench/fixtures/mature-webapp/tests/health.test.ts` | test | 0 | 0 | 0 | 0.0000 |

## Internal Dependencies

- `src/tests/bench/fixtures/greenfield-webapp/src/index.ts` → `src/tests/bench/fixtures/greenfield-webapp/src/routes/health.ts` (imports)
- `src/tests/bench/fixtures/legacy-webapp/src/app.js` → `src/tests/bench/fixtures/legacy-webapp/src/controllers/UserController.js` (imports)
- `src/tests/bench/fixtures/legacy-webapp/src/app.js` → `src/tests/bench/fixtures/legacy-webapp/src/routes/health.js` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/index.ts` → `src/tests/bench/fixtures/mature-webapp/src/middleware/error-handler.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/index.ts` → `src/tests/bench/fixtures/mature-webapp/src/routes/health.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/index.ts` → `src/tests/bench/fixtures/mature-webapp/src/routes/products.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/index.ts` → `src/tests/bench/fixtures/mature-webapp/src/routes/users.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/routes/products.ts` → `src/tests/bench/fixtures/mature-webapp/src/services/product-service.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/routes/users.ts` → `src/tests/bench/fixtures/mature-webapp/src/services/user-service.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/routes/users.ts` → `src/tests/bench/fixtures/mature-webapp/src/types/user.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/services/product-service.ts` → `src/tests/bench/fixtures/mature-webapp/src/types/product.ts` (imports)
- `src/tests/bench/fixtures/mature-webapp/src/services/user-service.ts` → `src/tests/bench/fixtures/mature-webapp/src/types/user.ts` (imports)

## Tests

- `src/tests/bench/fixtures/legacy-webapp/__tests__/health.test.js` tests `src/tests/bench/fixtures/legacy-webapp/src/app.js`
- `src/tests/bench/fixtures/mature-webapp/tests/health.test.ts` tests `src/tests/bench/fixtures/mature-webapp/src/index.ts`

