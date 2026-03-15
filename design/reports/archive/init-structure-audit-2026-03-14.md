# Moira /moira:init — Аудит созданной структуры

**Проект:** sveltkit-todos
**Дата:** 2026-03-14

---

## Полное дерево

```
.claude/
├── CLAUDE.md                                    ✅ 43 строки — Moira section + boundaries
├── settings.json                                ✅ 19 строк — hooks registered
└── moira/
    ├── config.yaml                              ✅ 68 строк — основной конфиг
    ├── config/
    │   └── budgets.yaml                         ✅ 26 строк — бюджеты агентов
    ├── core/
    │   └── rules/
    │       ├── quality/                         ❌ ПУСТАЯ директория
    │       └── roles/                           ❌ ПУСТАЯ директория
    ├── hooks/                                   ❌ ПУСТАЯ директория
    ├── project/
    │   └── rules/
    │       ├── stack.yaml                       ⚠️  4 строки — НЕПОЛНЫЙ (2 из 7 полей)
    │       ├── conventions.yaml                 ✅ 20 строк
    │       ├── patterns.yaml                    ✅ 11 строк
    │       └── boundaries.yaml                  ✅ 12 строк
    ├── knowledge/
    │   ├── project-model/
    │   │   ├── full.md                          ✅ 205 строк — полный scan output
    │   │   ├── summary.md                       ⚠️ 11 строк — только заголовки
    │   │   └── index.md                         ⚠️ 11 строк — только заголовки
    │   ├── conventions/
    │   │   ├── full.md                          ✅ 426 строк — полный scan output
    │   │   ├── summary.md                       ⚠️ 10 строк — только заголовки
    │   │   └── index.md                         ⚠️ 10 строк — только заголовки
    │   ├── patterns/
    │   │   ├── full.md                          ✅ 208 строк — полный scan output
    │   │   ├── summary.md                       ⚠️ 10 строк — только заголовки
    │   │   ├── index.md                         ⚠️ 10 строк — только заголовки
    │   │   └── archive/                         ✅ пустая (ожидаемо)
    │   ├── quality-map/
    │   │   ├── full.md                          ⚠️ 21 строка — почти пусто
    │   │   └── summary.md                       ⚠️ 15 строк — почти пусто
    │   ├── decisions/
    │   │   ├── full.md                          ✅ 14 строк — шаблон
    │   │   ├── summary.md                       ✅  6 строк — шаблон
    │   │   ├── index.md                         ✅  8 строк — шаблон
    │   │   └── archive/                         ✅ пустая (ожидаемо)
    │   └── failures/
    │       ├── full.md                          ✅ 13 строк — шаблон
    │       ├── summary.md                       ✅  8 строк — шаблон
    │       └── index.md                         ✅  7 строк — шаблон
    └── state/
        ├── init/
        │   ├── tech-scan.md                     ✅ 221 строка — raw scanner output
        │   ├── structure-scan.md                ✅ 202 строки — raw scanner output
        │   ├── convention-scan.md               ✅ 423 строки — raw scanner output
        │   └── pattern-scan.md                  ✅ 205 строк — raw scanner output
        ├── audits/                              ❌ ПУСТАЯ директория
        ├── metrics/                             ❌ ПУСТАЯ директория
        ├── tasks/                               ❌ ПУСТАЯ директория
        ├── violations.log                       ✅  0 строк — создан, пуст (ожидаемо)
        ├── tool-usage.log                       ✅  0 строк — создан, пуст (ожидаемо)
        └── budget-tool-usage.log                ✅  0 строк — создан, пуст (ожидаемо)
```

**Итого:** 38 файлов, 7 директорий пусты (4 ожидаемо, 3 проблемных).

---

## Разбор по категориям

### 1. Что создано и работает корректно (✅)

#### `.claude/CLAUDE.md` — 43 строки
Интеграционный файл. Содержит:
- Секцию "Moira Orchestration System" с quick reference по командам
- Секцию "Orchestrator Boundaries" с абсолютными запретами
- Маркеры `<!-- moira:start -->` / `<!-- moira:end -->` для идемпотентного обновления

#### `.claude/settings.json` — 19 строк
Хуки зарегистрированы:
```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "",
      "hooks": [
        { "type": "command", "command": "bash ~/.claude/moira/hooks/guard.sh" },
        { "type": "command", "command": "bash ~/.claude/moira/hooks/budget-track.sh" }
      ]
    }]
  }
}
```
Ссылается на **глобальные** скрипты `~/.claude/moira/hooks/guard.sh` и `budget-track.sh` — они существуют и исполняемы (3.3k и 2.5k соответственно). Но см. проблему с пустой локальной `hooks/`.

#### `config.yaml` — 68 строк
Основной конфиг. Всё заполнено:
- project.name: "sveltkit-todos", stack: SvelteKit
- 4 pipeline'а (quick/standard/full/decomposition) с gates
- Бюджеты для 10 ролей агентов
- quality.mode: conform
- bootstrap.quick_scan_completed: true

#### `config/budgets.yaml` — 26 строк
Отдельный файл бюджетов (дубль из config.yaml). Содержит per-agent allocations и MCP estimates.

#### `project/rules/conventions.yaml` — 20 строк
Самый полный из rule-файлов. 3 секции:
- naming: files (kebab-case), functions (camelCase), constants (UPPER_SNAKE_CASE), types (PascalCase)
- formatting: indent (2 spaces), quotes (single), semicolons (true)
- structure: 6 directory mappings (routes, lib, server_lib, prisma, static, generated)

#### `project/rules/patterns.yaml` — 11 строк
Все 9 полей из frontmatter-контракта заполнены. Значения — длинные строки с деталями (backtick-форматирование в кавычках). Функционально корректно, но читаемость страдает.

#### `project/rules/boundaries.yaml` — 12 строк
Чистый файл. 4 записи в do_not_modify (node_modules, .svelte-kit, src/generated, pnpm-lock.yaml), 3 в modify_with_caution (prisma/schema.prisma, prisma/migrations, .env).

#### `knowledge/*/full.md` — scan data
- `project-model/full.md` (205 строк) — полная структура проекта
- `conventions/full.md` (426 строк) — все конвенции с evidence
- `patterns/full.md` (208 строк) — все паттерны кода

L2 (full) уровень — это raw scanner output с freshness-маркерами. Самый полезный уровень knowledge.

#### `knowledge/decisions/` и `knowledge/failures/` — шаблоны
Пустые шаблоны с форматом для будущих записей. Это ожидаемо — decisions и failures накапливаются органически в процессе выполнения задач.

#### `state/init/*.md` — raw scanner output
4 файла (221 + 202 + 423 + 205 = 1051 строка). Это первичные данные сканеров, из которых bootstrap.sh генерирует всё остальное. Gitignored — не попадают в репозиторий.

#### `state/*.log` — лог-файлы
3 пустых файла (violations, tool-usage, budget-tool-usage). Созданы `touch` в Step 9. Заполняются хуками в runtime.

---

### 2. Что создано но с проблемами (⚠️)

#### `project/rules/stack.yaml` — 4 строки (НЕПОЛНЫЙ)
```yaml
# Stack configuration — generated by /moira:init

framework: SvelteKit
orm: Prisma
```

**Должно быть ~7-9 полей**, потеряно:
| Поле | Значение | Почему потеряно |
|------|----------|-----------------|
| language | TypeScript | Scanner написал `primary_language`, парсер ищет `language` |
| runtime | Node.js | Scanner не вывел это поле |
| styling | Tailwind CSS v4 | Scanner написал `css_framework`, парсер ищет `styling` |
| testing | (none) | Отсутствует — корректно, нечего было найти |
| ci | (none) | Отсутствует — корректно, нечего было найти |
| build_tool | Vite | Scanner написал `bundler`, парсер ищет... ничего — это поле не парсится |
| package_manager | pnpm | Парсер не читает это поле для stack.yaml |

**Корневая причина:** Двойной рассинхрон:
1. Scanner использует свои имена полей вместо контрактных
2. `_moira_bootstrap_gen_stack()` парсит только 7 жёстко зашитых полей, игнорируя остальные

#### `knowledge/*/summary.md` и `knowledge/*/index.md` — L1/L0 уровни
Все 6 файлов содержат только заголовки секций. Пример `conventions/summary.md`:
```
## 1. Naming Conventions
## 2. Import Style
## 3. Export Style
...
```

**Причина:** `_condense_to_summary()` ищет grep'ом строки, начинающиеся с `- ` и содержащие ключевые слова. Но scanner-output использует `**bold**` маркеры и таблицы — grep их не матчит.

**Влияние:** L1 уровень knowledge бесполезен. Агенты, запрашивающие summary, получат пустое оглавление вместо сжатых данных. Придётся всегда грузить L2 (full), что расходует больше бюджета.

#### `knowledge/quality-map/full.md` — 21 строка (почти пуст)
```markdown
## ✅ Strong Patterns
(пусто)

## ⚠️ Adequate Patterns
(пусто)

## 🔴 Problematic Patterns
### Handler Structure
```

Из всего scan-output'а (208 строк patterns) извлечена одна запись. Причина: keyword grep ("consistent"/"missing"/"broken") не матчит прозаический текст сканера.

#### `knowledge/quality-map/summary.md` — 15 строк
```
Strong: None detected yet
Adequate: None detected yet
Problematic: Handler Structure
```

Зеркало full.md — те же проблемы.

---

### 3. Что НЕ создано (❌)

#### `.claude/moira/hooks/` — ПУСТАЯ директория

Scaffold создал директорию, но никто не положил в неё файлы. При этом:
- `settings.json` ссылается на `~/.claude/moira/hooks/guard.sh` (глобальный путь) — **работает**
- Локальная `hooks/` директория — видимо, задумана для project-specific хуков

**Вопрос:** Зачем scaffold создаёт локальную `hooks/` если все хуки живут глобально? Варианты:
1. Задел на будущее — project-specific hooks override
2. Баг scaffold.sh — создаёт лишнюю директорию
3. Хуки должны были быть скопированы сюда, но этот шаг пропущен

**Рекомендация:** Либо не создавать, либо положить README с пояснением, либо копировать хуки из глобальных для кастомизации.

#### `.claude/moira/core/rules/quality/` — ПУСТАЯ директория

Scaffold создал, но ничего не положил. По архитектуре Moira здесь должны быть quality rule definitions (Layer 2 — core rules).

**Анализ:** Эти файлы живут глобально в `~/.claude/moira/core/rules/quality/`. Scaffold создаёт локальную копию директории по ошибке — или для project-level override.

Проблема: агенты, ищущие quality rules в project-local пути, найдут пустоту.

#### `.claude/moira/core/rules/roles/` — ПУСТАЯ директория

Аналогично quality/. Role definitions (hermes.yaml, hephaestus.yaml и т.д.) живут глобально. Локальная директория пуста.

**Влияние на runtime:** Зависит от того, где оркестратор ищет roles — в `{project}/.claude/moira/core/rules/roles/` или `~/.claude/moira/core/rules/roles/`. Если в проектной — сломается.

#### `state/audits/` — ПУСТАЯ директория
Ожидаемо пустая. Заполняется при выполнении `/moira:audit`.

#### `state/metrics/` — ПУСТАЯ директория
Ожидаемо пустая. Заполняется метриками после выполнения задач.

#### `state/tasks/` — ПУСТАЯ директория
Ожидаемо пустая. Заполняется при выполнении `/moira:task`.

#### Отсутствующий `state/current.yaml`
Gitignore упоминает `.claude/moira/state/current.yaml`, но файл не создан. Видимо, создаётся при первом `/moira:task`.

#### Отсутствующий `state/bypass-log.yaml`
Gitignore упоминает `.claude/moira/state/bypass-log.yaml`, но файл не создан. Создаётся при первом `/moira:bypass`.

---

## Матрица: что создаёт scaffold vs bootstrap vs scan

| Артефакт | Создатель | Наполнитель | Статус |
|----------|-----------|-------------|--------|
| Директории | scaffold.sh | — | ✅ все созданы |
| config.yaml | bootstrap `generate_config` | tech-scan frontmatter | ✅ полный |
| budgets.yaml | scaffold.sh (template copy) | — | ✅ шаблон |
| stack.yaml | bootstrap `gen_stack` | tech-scan frontmatter | ⚠️ 2/7 полей |
| conventions.yaml | bootstrap `gen_conventions` | convention-scan + structure-scan | ✅ полный |
| patterns.yaml | bootstrap `gen_patterns` | pattern-scan frontmatter | ✅ полный |
| boundaries.yaml | bootstrap `gen_boundaries` | structure-scan frontmatter | ✅ полный |
| knowledge L2 (full) | bootstrap `populate_knowledge` | scan .md files (copy) | ✅ полные |
| knowledge L1 (summary) | bootstrap `condense_to_summary` | grep extraction | ⚠️ пустоваты |
| knowledge L0 (index) | bootstrap `condense_to_index` | grep `## ` headers | ⚠️ только заголовки |
| quality-map | bootstrap `gen_quality_map` | keyword grep on patterns | ⚠️ почти пуст |
| decisions/failures | scaffold.sh (template copy) | — | ✅ шаблоны |
| CLAUDE.md | bootstrap `inject_claude_md` | template | ✅ полный |
| settings.json | bootstrap `inject_hooks` | — | ✅ корректный |
| .gitignore | bootstrap `setup_gitignore` | — | ✅ дополнен |
| state logs | bootstrap `inject_hooks` | touch | ✅ пустые файлы |
| local hooks/ | scaffold.sh | никто | ❌ пустая |
| local core/rules/* | scaffold.sh | никто | ❌ пустые |

---

## Дубликация данных

Одни и те же данные хранятся в нескольких местах:

| Данные | Расположение 1 | Расположение 2 | Расположение 3 |
|--------|----------------|----------------|----------------|
| Бюджеты агентов | config.yaml → budgets | config/budgets.yaml | — |
| Scan output | state/init/*.md | knowledge/*/full.md | — |
| Conventions | convention-scan.md | conventions/full.md | conventions.yaml (сжатие) |
| Patterns | pattern-scan.md | patterns/full.md | patterns.yaml (сжатие) |
| Structure | structure-scan.md | project-model/full.md | conventions.yaml → structure |

`knowledge/*/full.md` = `state/init/*.md` + freshness marker. Это буквальная копия с 2 строками метаданных сверху.

**Вопрос:** Нужна ли дубликация? state/init/ gitignored, knowledge/ нет. Но при `--force` reinit оба перезаписываются. Возможно, state/init/ — это "raw", а knowledge/ — "processed", но сейчас processing = prepend 2 строки.

---

## Общая статистика

```
Файлов создано:        38
Директорий создано:    19 (7 пустых)
Полезных файлов:       24
Шаблонов/заглушек:      9
Пустых/бесполезных:     5 (summary/index уровни)

Строк кода/контента: ~2500
  - Raw scan data:    1051 строк (42%)
  - Knowledge full:    839 строк (34%) — копия scan data
  - Rules/config:      143 строки (6%)
  - Templates:          56 строк (2%)
  - Integration:        62 строки (2%)
  - Quality map:        36 строк (1%) — почти пуст
  - Summaries/indexes:  72 строки (3%) — почти пусты
  - Logs:                0 строк
```

---

## Выводы

### Что scaffold.sh делает лишнего
Создаёт пустые директории `hooks/`, `core/rules/quality/`, `core/rules/roles/` в проекте, хотя эти артефакты живут глобально и init не наполняет их локально. Это сбивает с толку при аудите.

### Где теряется информация
Бутылочное горлышко — `bootstrap.sh`. Сканеры генерируют ~1050 строк подробных данных. Bootstrap.sh проводит их через regex-парсеры и теряет:
- 5 из 7 полей stack.yaml (несовпадение имён)
- Весь контент L1 summaries (grep не матчит bold markdown)
- 90% quality map (keyword mismatch)

При этом L2 (full) файлы = буквальная копия scan output. Вся "переработка" данных сканеров в compact-формы не работает.

### Что реально будет использоваться runtime-агентами
1. `config.yaml` — да, оркестратор читает его
2. `project/rules/*.yaml` — да, агенты получают их как контекст
3. `knowledge/*/full.md` — да, но это дорого (400+ строк per type)
4. `knowledge/*/summary.md` — нет, бесполезны
5. `quality-map` — нет, почти пуст
6. `CLAUDE.md` + `settings.json` — да, Claude Code читает автоматически
7. `state/init/*.md` — нет, только для reinit/refresh
