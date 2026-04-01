# Moira Init — Run #2: sveltkit-todos

Дата: 2026-03-13
Проект: `sveltkit-todos` (SvelteKit + Svelte 5 + Prisma + Tailwind)
Режим: fresh init (не `--force`)

---

## Общий результат

Init завершился успешно. Все 4 сканера отработали. Из 11 багов предыдущего запуска воспроизвелась **1 проблема**, остальные либо не проявились, либо были обойдены.

---

## Воспроизведённые проблемы

### BUG-1 (сохраняется): `bootstrap.sh` — zsh parse error

**Файл:** `~/.claude/moira/lib/bootstrap.sh:578`
**Severity:** Medium
**Статус:** Не исправлен, обойдён

При прямом `source ~/.claude/moira/lib/bootstrap.sh` в zsh:
```
/Users/minddecay/.moira/lib/bootstrap.sh:578: parse error near `|'
```

Проблемная строка:
```bash
if [[ "$line" =~ Location:|Directory:|Path: ]]; then
```

zsh интерпретирует `|` как pipe, а не альтернацию в regex.

**Workaround:** Все вызовы bootstrap.sh обёрнуты в `bash -c '...'`.

**Рекомендация:** Добавить shebang `#!/usr/bin/env bash` и вызывать через `bash -c` в скилле `/moira:init`, либо исправить regex для zsh-совместимости:
```bash
local pat='Location:|Directory:|Path:'
if [[ "$line" =~ $pat ]]; then
```

---

## Что улучшилось по сравнению с Run #1

> **Примечание:** Система пресетов (`templates/stack-presets/`) была полностью удалена из Moira после Run #1. BUG-2, 3, 6, 8 больше не актуальны.

| # | Баг | Статус в Run #2 | Примечание |
|---|-----|-----------------|------------|
| 1 | zsh parse error | **Воспроизведён** | Обойдён через `bash -c` |
| ~~2~~ | ~~Нет SvelteKit пресета~~ | **ЗАКРЫТ** | Пресеты удалены из Moira |
| ~~3~~ | ~~data_fetching/error_handling из пресета~~ | **ЗАКРЫТ** | Пресеты удалены из Moira |
| 4 | "Not detected (reason...)" проходит фильтр | **Не проверялся** | |
| 5 | Дубликат node_modules/ | **Не проверялся** | |
| ~~6~~ | ~~dist/ и index.html от React-пресета~~ | **ЗАКРЫТ** | Пресеты удалены из Moira |
| 7 | summary.md почти пустой | **Не проверялся** | |
| ~~8~~ | ~~Секция structure потеряна~~ | **ЗАКРЫТ** | Пресеты удалены из Moira |
| 9 | Таблица без header | **Не проверялся** | |
| 10 | scaffold.sh output | **Воспроизведён** (вывел `type_name=...`) | Info-уровень |
| 11 | Только 1 из 4 scanners | **Исправлено** | Все 4 агента запущены параллельно и завершились успешно |

---

## Статистика сканеров

| Сканер | Токены | Tool calls | Время (с) | Статус |
|--------|--------|------------|-----------|--------|
| Tech scan | 30,831 | 35 | 98.5 | OK |
| Structure scan | 23,099 | 28 | 119.2 | OK |
| Convention scan | 47,744 | 50 | 140.5 | OK |
| Pattern scan | 32,364 | 36 | 132.3 | OK |
| **Итого** | **134,038** | **149** | **~140** (parallel) | **4/4 OK** |

---

## Ключевые находки сканеров

- **Stack:** TypeScript 5.9.3, SvelteKit 2.49.1, Svelte 5.47.0, Vite 7.3.1, Tailwind CSS 4.1.17, Prisma 7.3.0 + PostgreSQL
- **Package manager:** pnpm
- **Layout:** single-app, file-based routing, ~44 source files
- **Auth:** Custom auth system в `src/lib/server/auth/` (11 files)
- **Testing:** Отсутствует (нет фреймворка, нет тестовых файлов)
- **CI/CD:** Отсутствует
- **Patterns:** Svelte 5 runes, SvelteKit form actions (no +server.ts), direct Prisma queries (no service layer)

---

## Рекомендации для следующего шага

1. **Исправить BUG-1** — единственный воспроизведённый баг, простой fix
2. **Проверить knowledge/** — убедиться что summary файлы содержат полезные данные (BUG-7, 9)
