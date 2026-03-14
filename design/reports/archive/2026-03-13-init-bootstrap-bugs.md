# Moira Init — Полный список ошибок и проблем

Дата: 2026-03-13
Проект-жертва: `sveltkit-todos` (SvelteKit + Svelte 5 + Prisma + Tailwind)

> **УСТАРЕЛО:** Этот отчёт зафиксирован по результатам Run #1. С тех пор система пресетов (`templates/stack-presets/`) была **полностью удалена** из Moira. BUG-2, BUG-3, BUG-6 и BUG-8, связанные с пресетами, больше не актуальны. Актуальный отчёт — `2026-03-13-init-run3-sveltkit-todos.md`.

---

## BUG-1: `bootstrap.sh` не работает в zsh (macOS default shell)

**Файл:** `~/.claude/moira/lib/bootstrap.sh:14`
**Severity:** Medium

```bash
_MOIRA_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

zsh не поддерживает `BASH_SOURCE`. Все вызовы bootstrap.sh пришлось оборачивать в `bash -c '...'`.

**Fix:** Либо всегда вызывать через `bash -c`, либо добавить zsh fallback:
```bash
_MOIRA_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
```

Тот же баг потенциально в `scaffold.sh` и `yaml-utils.sh` / `knowledge.sh`.

---

## ~~BUG-2: Нет SvelteKit preset — матчит react-vite~~ [ЗАКРЫТ — пресеты удалены]

> **Неактуален.** Система пресетов (`templates/stack-presets/`) полностью удалена из Moira. Config и rules теперь генерируются исключительно из данных сканеров без промежуточного слоя пресетов.

~~**Файл:** `~/.claude/moira/templates/stack-presets/` — нет `sveltekit.yaml`~~
~~**Severity:** High~~

---

## ~~BUG-3: `data_fetching` и `error_handling` из пресета~~ [ЗАКРЫТ — пресеты удалены]

> **Неактуален.** Система пресетов удалена. `data_fetching` и `error_handling` теперь берутся напрямую из frontmatter pattern-scan, без промежуточного слоя пресетов.

~~**Файл:** `bootstrap.sh:359-391` (`_moira_bootstrap_gen_patterns`)~~
~~**Severity:** Critical~~

---

## BUG-4: `_extract_scan_value` не работает с "Not detected (reason...)"

**Файл:** `bootstrap.sh:561`
**Severity:** Medium

```bash
if [[ -n "$val" && "$val" != "Not detected" ]]; then
```

Строгое сравнение `!=`. Но сканеры пишут: `Not detected (no vitest/jest config...)`. Строка не равна `"Not detected"` → функция возвращает её как реальное значение.

В случае testing это случайно работает правильно (значение содержательное), но логика ненадёжна. Любой "Not detected" с пояснением в скобках проходит как реальные данные.

**Fix:** Использовать prefix match:
```bash
if [[ -n "$val" && ! "$val" =~ ^Not\ detected ]]; then
```

---

## BUG-5: Дубликат `node_modules/` в boundaries.yaml [частично связан с пресетами]

**Файл:** `bootstrap.sh:424-451` (`_moira_bootstrap_gen_boundaries`)
**Severity:** Low

> **Примечание:** Дублирование из-за пресетов больше не актуально (пресеты удалены). Однако проблема с бэктиками в парсинге scan-output остаётся — structure-scan пишет `` `node_modules/` `` с бэктиками, и grep-дедупликация в bootstrap.sh не стрипает их. Это может привести к дублям если два скана упоминают одну директорию в разном форматировании.

**Fix:** Стрипать бэктики при парсинге: `dir_entry=$(echo "$dir_entry" | tr -d '\`')`

---

## ~~BUG-6: boundaries.yaml содержит `dist/` и `index.html` (от React-пресета)~~ [ЗАКРЫТ — пресеты удалены]

> **Неактуален.** Система пресетов удалена. Boundaries теперь формируются исключительно из данных structure-scan.

~~**Файл:** `bootstrap.sh:394-488`~~
~~**Severity:** Medium~~

---

## BUG-7: knowledge/project-model/summary.md — почти пустой

**Файл:** `bootstrap.sh:604-606` (`_condense_to_summary`)
**Severity:** Medium

```bash
_condense_to_summary "$scan_results_dir/structure-scan.md" \
  "$knowledge_dir/project-model/summary.md" "$today" \
  "Source Layout|Entry points|Pattern"
```

Функция grep'ит строки матчащие `Source Layout|Entry points|Pattern`. Но structure-scan пишет:
```markdown
## Source Layout          ← заголовок ## → матчит через ^##
- Pattern: single-app    ← матчит
- Source root: src/       ← НЕ матчит
- Entry points:           ← матчит, но вложенные items нет
  - src/app.html          ← отступ 2 spaces → ^- не матчит
```

Grep pattern на line 704:
```bash
grep -E "^## |^- .*(${patterns})|^\|[[:space:]]*(${patterns})" "$scan_file"
```

Проблемы:
- Entry points перечислены как `  - src/app.html` (с отступом) → не матчат `^- `
- Directory Roles — таблица, но keyword `Pattern` не в ней
- Configuration, Route Structure, Tech Stack — секции полностью теряются

Результат — скелет без мяса:
```markdown
## Project Root
## Source Layout
- Pattern: single-app
- Entry points:           ← список пуст!
## Directory Roles        ← таблица пропала
## Generated (do not modify)
## Configuration          ← таблица пропала
## Test Organization
- Pattern: Not detected
```

**Fix:** `_condense_to_summary` для project-model нужна другая стратегия:
1. Расширить patterns: добавить `Source root|Directory|Route|Config|Test`
2. Поддержать `^  - ` (вложенные списки) в grep
3. Переписать на секционный парсинг (не grep)

---

## ~~BUG-8: conventions.yaml — потеряна секция `structure` из пресета~~ [ЗАКРЫТ — пресеты удалены]

> **Неактуален.** Система пресетов удалена. Секция `structure` в conventions.yaml формируется из данных convention-scan и structure-scan напрямую, без пресет-шаблонов.

~~**Файл:** `bootstrap.sh:300-357` (`_moira_bootstrap_gen_conventions`)~~
~~**Severity:** Low~~

---

## BUG-9: conventions/summary.md — сломанная таблица

**Файл:** Результат `_condense_to_summary` для conventions
**Severity:** Low

```markdown
## Naming Conventions
| Files (routes) | SvelteKit convention: ... | `src/routes/+page.svelte`, ... |
| Files (lib modules) | kebab-case `.ts` | ... |
| Functions | camelCase, ... | ... |
```

Таблица пишется без header row и separator row (`|---|---|---|`). Это потому что grep ловит только строки с keyword `Files|Functions|Components`, но header `| What | Convention | Evidence |` и separator `|------|-----------|----------|` не матчат.

---

## BUG-10: scaffold.sh — непоследовательный output

**Файл:** `scaffold.sh`
**Severity:** Info

Первый запуск вывел:
```
type_name=conventions
type_name=decisions
...
```
Повторный (--force) — тишина. Непоследовательный output при повторном запуске.

---

## BUG-11: Только 1 scanner agent запускается вместо 4

**Файл:** Инструкция `/moira:init` Step 4
**Severity:** High (процесс)

Инструкция требует запуска 4 агентов **параллельно в одном сообщении**. На практике Claude Code запускает только 1 (convention-scan). Остальные 3 (tech-scan, structure-scan, pattern-scan) используют данные от предыдущего запуска.

Причина: промпты для всех 4 агентов не помещаются в одно сообщение, или Claude оптимизирует и пропускает. При `--force` это означает stale данные от предыдущих сканов.

---

## Сводная таблица

> Пресеты удалены из Moira. BUG-2, BUG-3, BUG-6, BUG-8 закрыты как неактуальные.

| # | Severity | Файл | Проблема | Статус |
|---|----------|------|----------|--------|
| ~~**3**~~ | ~~Critical~~ | ~~`bootstrap.sh:359-391`~~ | ~~`data_fetching`/`error_handling` из пресета~~ | **ЗАКРЫТ** — пресеты удалены |
| ~~**2**~~ | ~~High~~ | ~~`templates/stack-presets/`~~ | ~~Нет SvelteKit пресета → React-дефолты~~ | **ЗАКРЫТ** — пресеты удалены |
| **11** | **High** | init Step 4 | Только 1 из 4 scanner agents запускается при --force | Открыт |
| **1** | **Medium** | `bootstrap.sh:14` | `BASH_SOURCE` ломается в zsh | Открыт |
| **4** | **Medium** | `bootstrap.sh:561` | `"Not detected (reason...)"` проходит через проверку `!= "Not detected"` | Открыт |
| ~~**6**~~ | ~~Medium~~ | ~~`bootstrap.sh:394-488`~~ | ~~`dist/`/`index.html` из React-пресета~~ | **ЗАКРЫТ** — пресеты удалены |
| **7** | **Medium** | `bootstrap.sh:604-606` | `_condense_to_summary` grep теряет вложенные списки и таблицы | Открыт |
| **5** | **Low** | `bootstrap.sh:441` | Дубликат — grep не стрипает бэктики из scan output | Открыт |
| ~~**8**~~ | ~~Low~~ | ~~`bootstrap.sh:300-357`~~ | ~~Секция `structure` из пресета игнорируется~~ | **ЗАКРЫТ** — пресеты удалены |
| **9** | **Low** | conventions summary | Таблица без header/separator row | Открыт |
| **10** | **Info** | `scaffold.sh` | Непоследовательный output при повторном запуске | Открыт |
