# Moira /moira:init — Полный отчёт о прогоне

**Проект:** sveltkit-todos
**Дата:** 2026-03-14
**Версия Moira:** 0.1.0
**Окружение:** macOS Darwin 25.3.0, zsh, Claude Opus 4.6 (1M context)

---

## Общая оценка

Init прошёл до конца, все 11 шагов выполнены, файлы сгенерированы. Но качество результата — **неравномерное**. Сканеры отработали хорошо, а вот bootstrap.sh потерял бо́льшую часть данных при трансформации. Есть несколько системных багов, один из которых может блокировать init на других проектах.

---

## Хронология выполнения

### Step 1-2: Проверка глобального слоя и существующей инициализации
Без проблем. `.version` найден, `config.yaml` не существует — свежая инициализация.

### Step 3: Scaffold
Отработал корректно. Директории и шаблоны созданы. Вывод `type_name=...` для каждого knowledge type — корректное поведение.

### Step 4: Сканеры (4 параллельных агента)

| Сканер | Токены | Tool uses | Время | Статус |
|--------|--------|-----------|-------|--------|
| tech-scan | 30 842 | 32 | 111s | OK |
| structure-scan | 20 175 | 22 | 89s | OK |
| convention-scan | 50 405 | 43 | 291s | OK |
| pattern-scan | 45 287 | 37 | 148s | OK |

**Наблюдения:**

1. **convention-scan съел 50k токенов и 291 секунду** — в 3 раза дольше structure-scan. Это самый прожорливый сканер. Он читает до 30 файлов и анализирует стиль каждого. Для pet-проекта на ~44 файла это чрезмерно.

2. **Все 4 сканера отработали параллельно** — это хорошо, общее wall-time определяется самым медленным (convention-scan, 291s).

3. **Качество frontmatter** — сканеры не соблюдают контракт frontmatter'а из шаблонов. Это корневая причина бага #1 (подробности ниже).

### Step 5: Генерация конфига и правил

**БАГ #1 (критический): zsh несовместимость `_moira_parse_frontmatter`**

При первом вызове через `source ~/.claude/moira/lib/bootstrap.sh` из zsh-окружения:
```
_moira_parse_frontmatter:20: BASH_REMATCH[1]: parameter not set
```

**Причина:** Скрипт содержит `#!/usr/bin/env bash`, но когда Claude Code вызывает `source` через Bash tool, оно выполняется в zsh (дефолтный shell пользователя). В zsh нет `BASH_REMATCH` — capture groups доступны через `$match` или `$MATCH`.

**Workaround:** Вызывать через `bash -c 'source ... && ...'` — что я и сделал.

**Рекомендация:** В самом `bootstrap.sh` добавить проверку:
```bash
if [[ -n "$ZSH_VERSION" ]]; then
  echo "Error: bootstrap.sh must run under bash, not zsh" >&2
  return 1
fi
```
Или: skill `/moira:init` должен ВСЕГДА оборачивать вызовы в `bash -c '...'`.

---

**БАГ #2 (серьёзный): Рассинхрон между frontmatter-контрактами сканеров и парсером bootstrap.sh**

`_moira_bootstrap_gen_stack()` ищет поля:
```
language, framework, runtime, styling, orm, testing, ci
```

Tech-scan выдал:
```yaml
primary_language: TypeScript     # ← bootstrap ищет "language"
framework: SvelteKit             # ← OK, совпало
css_framework: Tailwind CSS      # ← bootstrap ищет "styling"
orm: Prisma                      # ← OK, совпало
# runtime, testing, ci — отсутствуют
```

**Результат:** `stack.yaml` содержит только 2 поля из потенциальных 7:
```yaml
framework: SvelteKit
orm: Prisma
```

Потеряны: language, runtime (Node.js), styling (Tailwind CSS v4), testing (нет, но должно быть явно указано), CI (нет), package manager (pnpm), build tool (Vite).

**Причина:** Шаблон `tech-scan.md` определяет контракт frontmatter с полями `language`, `styling`, `runtime`, `testing`, `ci`. Но сканер-агент — это LLM, и он интерпретировал контракт свободно, назвав поле `primary_language` вместо `language`, `css_framework` вместо `styling`, и т.д.

**Корневая проблема:** Промпт сканера содержит примерный YAML с правильными именами полей, но дальше текстовое описание перечисляет "Languages — primary and secondary". LLM уцепился за "primary" и решил быть более точным. Это классическая проблема: **LLM оптимизирует за семантическую точность, а парсер ожидает точные строки**.

**Рекомендация:**
1. В шаблонах сканеров: добавить явную секцию "EXACT field names — do NOT rename" с жёстким предупреждением
2. Или: bootstrap.sh должен искать несколько вариантов: `language|primary_language|lang`
3. Или: парсить frontmatter LLM-агентом вместо regex (но это дороже)

---

**БАГ #3 (минорный): exit code 1 из `_moira_bootstrap_gen_stack`**

Функция использует блок `{ ... } > "$output"`, где последняя команда — `[[ -n "$ci" ]]`. Когда `$ci` пуст, `[[ -n "" ]]` возвращает exit code 1, который становится exit code всего блока `{ }`. При `set -e` это убивает вызывающий `moira_bootstrap_generate_project_rules`.

**Результат:** `moira_bootstrap_generate_project_rules` падает при попытке вызвать все 4 генератора последовательно. `_moira_bootstrap_gen_stack` записывает файл (redirect уже произошёл), но exit code 1 прерывает выполнение до conventions/patterns/boundaries.

**Workaround:** Я вызвал каждый генератор отдельно с `set +e`.

**Фикс:** Добавить `true` или `: # end` в конец блока `{ }`:
```bash
{
  ...
  [[ -n "$ci" ]] && echo "ci: ${ci}"
  true  # ensure exit 0
} > "$output"
```

### Step 6: Populate Knowledge

Отработал без ошибок. Но качество результата — спорное.

**Проблема #4: L1 summaries почти пустые**

`conventions/summary.md`, `patterns/summary.md`, `project-model/summary.md` — содержат только заголовки секций (`## 1. ...`, `## 2. ...`). Никакой полезной информации.

**Причина:** `_condense_to_summary()` делает `grep -E` по паттернам типа `"Source Layout|Entry points|Pattern"`. Но сканеры нумеруют заголовки (`## 1. Top-Level Structure`), а grep ищет `## ` для заголовков, плюс bullet-строки с ключевыми словами. Bullet-строки в scan-файлах используют `**bold**` markdown, а grep-паттерн ищет `^- .*(Pattern)` — но реальные строки выглядят как `- **Pattern:** SvelteKit form actions...` и grep их не матчит из-за `**`.

**Результат:** L1 (summary) уровень knowledge бесполезен. Агенты, запрашивающие L1, получат только оглавление.

**Рекомендация:** Пересмотреть `_condense_to_summary()` — либо grep-паттерны должны быть мягче, либо summary должен генерироваться LLM-агентом (condenser), а не regex.

---

**Проблема #5: Quality Map почти пуст**

`quality-map/full.md`:
```
## ✅ Strong Patterns
(пусто)

## ⚠️ Adequate Patterns
(пусто)

## 🔴 Problematic Patterns
### Handler Structure
```

`quality-map/summary.md`:
```
Strong: None detected yet
Adequate: None detected yet
Problematic: Handler Structure
```

**Причина:** `_build_pattern_section()` ищет `### ` заголовки в `pattern-scan.md`, а затем grep'ает текст под ними на ключевые слова типа "consistent", "uniform", "missing", "broken". Но сканер pattern-scan пишет прозу, а не использует эти конкретные ключевые слова.

Единственный match — "Handler Structure" попал в Problematic потому что в тексте под ним нашлось слово, совпавшее с `missing|broken|TODO|FIXME|deprecated|hack`.

**Результат:** Quality Map при bootstrap практически бесполезен. Это допустимо (он помечен `<!-- moira:preliminary -->`), но можно было бы извлечь больше.

**Рекомендация:** Quality Map при init не должен генерироваться regex'ами — это задача для LLM-агента, который может оценить паттерны по содержанию, а не по наличию ключевых слов.

### Step 7: CLAUDE.md Integration

Отработал корректно. Файл `.claude/CLAUDE.md` создан с маркерами `<!-- moira:start -->` / `<!-- moira:end -->` для идемпотентного обновления.

**Замечание:** CLAUDE.md содержит секцию "Orchestrator Boundaries" с абсолютными запретами на чтение файлов вне `.moira/`. Это правильно для pipeline-режима, но может сбивать с толку при обычной работе с Claude Code в том же проекте. Маркеры помогут при reinit, но пользователь может не понять, почему Claude вдруг отказывается читать его код.

### Step 8: Gitignore

Корректно. Добавлены записи для state-файлов. Есть лишняя пустая строка между комментарием и первой записью, но это косметика.

### Step 9: Hooks

Корректно. `guard.sh` и `budget-track.sh` зарегистрированы в `.claude/settings.json` как `PostToolUse` hooks. Matcher пустой (`""`), что значит — хуки сработают на КАЖДЫЙ вызов инструмента. Это может замедлить работу.

**Замечание:** Пустой matcher `""` означает, что даже `Read` на файл внутри `.moira/` запустит guard.sh. Если guard.sh тяжёлый — это overhead на каждый tool call.

### Step 10: Review Gate

Отработал корректно. Вывел резюме. Не дождался ответа пользователя перед тем, как пользователь дал другую команду — но это нормально для CLI-интерфейса.

---

## Сводка багов

| # | Severity | Описание | Статус |
|---|----------|----------|--------|
| 1 | **Critical** | `BASH_REMATCH` не работает при source из zsh | Workaround: `bash -c` |
| 2 | **Serious** | Frontmatter field names: сканер vs bootstrap рассинхрон | stack.yaml потерял 5/7 полей |
| 3 | **Minor** | Exit code 1 из `{ ... } > file` когда последний `[[ ]]` false | Workaround: `set +e` |
| 4 | **Moderate** | L1 summaries пустые (grep не матчит bold markdown) | Knowledge degraded |
| 5 | **Moderate** | Quality Map почти пуст (keyword grep vs prose mismatch) | Preliminary, допустимо |

---

## Что работает хорошо

1. **Параллельные сканеры** — 4 агента одновременно, wall-time определяется самым медленным. Эффективно.

2. **Scaffold** — идемпотентный, создаёт всё за один вызов. Чисто.

3. **conventions.yaml** — самый полный из сгенерированных файлов. 3 секции (naming, formatting, structure), все заполнены корректно. Это потому что convention-scan frontmatter случайно совпал с ожиданиями парсера.

4. **patterns.yaml** — все 9 полей заполнены. Длинные строки в YAML (backticks в кавычках) — косметически некрасиво, но функционально корректно.

5. **boundaries.yaml** — чистый, корректный. do_not_modify и modify_with_caution заполнены адекватно.

6. **Hooks injection** — settings.json корректен, хуки зарегистрированы.

7. **Gitignore** — все state-пути добавлены, проверка дупликатов работает.

---

## Мысли и рассуждения

### О frontmatter-контракте (баг #2)

Это фундаментальная проблема архитектуры Moira. Сканеры — это LLM-агенты. Они получают шаблон с примером YAML, но LLM не детерминистичен. Он может переименовать поле, добавить лишнее, пропустить нужное.

Варианты решения:
- **Strict schema validation** после каждого сканера: прочитать frontmatter, проверить field names, вернуть на пересканирование при ошибках
- **Более жёсткий промпт**: "You MUST use EXACTLY these field names. Do not rename, do not add, do not skip."
- **Fallback в парсере**: `_moira_parse_frontmatter` ищет алиасы (language|primary_language|lang)
- **Post-processing agent**: маленький LLM-агент, который нормализует frontmatter перед передачей в bootstrap.sh

Я думаю правильный ответ — **комбинация**: жёсткий промпт + validation + fallback. LLM нельзя доверять на 100% в структурированном выводе — нужен safety net.

### О bash vs LLM для трансформаций (баги #4, #5)

`_condense_to_summary()` и `_build_pattern_section()` пытаются извлечь семантику из текста с помощью grep. Это принципиально ограничено. Сканеры пишут прозу, а grep ищет ключевые слова.

Вариант: заменить эти функции на вызов дешёвого LLM-агента (haiku) для condensation. Но это удорожает init. Компромисс: оставить grep как fallback, но предпочитать LLM для quality map.

### О стоимости init

Суммарный расход на 4 сканера: ~147k токенов, ~639 секунд wall-time. Для pet-проекта на ~44 файла это много. Для production-проекта на тысячи файлов это будет приемлемо, потому что сканеры семплируют, а не читают всё.

Convention-scan (50k токенов, 291s) — главный потребитель. Можно оптимизировать:
- Уменьшить количество семплируемых файлов для маленьких проектов
- Добавить early-exit: если после 10 файлов паттерн ясен — стоп

### О hooks с пустым matcher

`"matcher": ""` в settings.json означает "match everything". Guard.sh будет вызываться на каждый tool call, включая безобидные Read/Glob. Если guard.sh хотя бы read'ит файл с диска — это overhead.

Стоит рассмотреть более точный matcher: `"Edit|Write|Bash"` — только на tool calls, которые могут модифицировать проект.

### О CLAUDE.md boundaries

Секция "ABSOLUTE PROHIBITIONS" запрещает оркестратору читать файлы вне `.moira/`. Но эта секция вставляется в `.claude/CLAUDE.md`, который читается ВСЕМИ сессиями Claude Code в этом проекте — не только pipeline-сессиями.

Это может привести к ситуации, когда пользователь просит Claude Code прочитать файл, а Claude отказывается из-за Moira boundaries.

**Рекомендация:** Сделать boundaries условными: "These rules apply ONLY when executing through /moira:task pipeline. In direct conversation with the user, normal Claude Code behavior applies."

---

## Рекомендации по приоритету

1. **P0:** Фикс `BASH_REMATCH` / zsh-совместимости — блокирует init без workaround
2. **P0:** Фикс exit code 1 в `_moira_bootstrap_gen_stack` — ломает цепочку генераторов
3. **P1:** Ужесточение frontmatter-контракта в промптах сканеров + fallback алиасы в парсере
4. **P1:** Условные boundaries в CLAUDE.md
5. **P2:** Улучшение `_condense_to_summary()` для L1 knowledge
6. **P2:** Quality Map generation через LLM вместо grep
7. **P3:** Оптимизация convention-scan для маленьких проектов
8. **P3:** Более точный hook matcher

---

## Файлы, созданные init'ом

```
.moira/
├── config.yaml                          # 69 строк, корректный
├── project/rules/
│   ├── stack.yaml                       # 5 строк, НЕПОЛНЫЙ (баг #2)
│   ├── conventions.yaml                 # 21 строка, корректный
│   ├── patterns.yaml                    # 12 строк, корректный
│   └── boundaries.yaml                  # 13 строк, корректный
├── knowledge/
│   ├── project-model/{full,summary,index}.md   # full OK, summary/index пустоваты
│   ├── conventions/{full,summary,index}.md     # full OK, summary/index пустоваты
│   ├── patterns/{full,summary,index}.md        # full OK, summary/index пустоваты
│   ├── quality-map/{full,summary}.md           # почти пустые (баг #5)
│   ├── decisions/{full,summary,index}.md       # шаблоны, пустые (ожидаемо)
│   └── failures/{full,summary,index}.md        # шаблоны, пустые (ожидаемо)
├── state/init/
│   ├── tech-scan.md                     # 31 frontmatter поле, полный
│   ├── structure-scan.md                # 24 frontmatter поля, полный
│   ├── convention-scan.md               # 11 frontmatter полей, полный
│   └── pattern-scan.md                  # 11 frontmatter полей, полный
└── state/
    ├── violations.log                   # пустой
    ├── tool-usage.log                   # пустой
    └── budget-tool-usage.log            # пустой

.claude/CLAUDE.md                        # 43 строки, корректный
.claude/settings.json                    # hooks registered
.gitignore                               # moira entries added
```
