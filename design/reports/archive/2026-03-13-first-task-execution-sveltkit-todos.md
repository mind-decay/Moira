# Moira Task Execution — Первый запуск: sveltkit-todos

Дата: 2026-03-13
Проект: `sveltkit-todos` (SvelteKit + Svelte 5 + Prisma + Tailwind)
Задача: `Сделай полноценный rate-limiting для нашей системы`
Task ID: `task-2026-03-13-001`
Статус: **прервана на шаге exploration** (после classification gate)

---

## Общий результат

Первый реальный запуск `/moira:task` выявил **3 критических проблемы** в архитектуре оркестратора, из-за которых пайплайн работал некорректно. Задача была классифицирована Apollo (classifier) как `large / medium confidence → full pipeline`, пользователь одобрил классификацию, но выполнение было прервано пользователем на этапе dispatch Hermes + Athena.

---

## Хронология сессии

### Фаза 0: Проверка команд

Пользователь последовательно вызвал все Moira-команды для проверки состояния системы:

| Команда | Результат |
|---------|-----------|
| `/moira:help` | Отработала корректно, версия 0.1.0 прочитана |
| `/moira:status` | Stub — "will be implemented in Phase 3" |
| `/moira:knowledge` | Stub — "will be implemented in Phase 4" |
| `/moira:metrics` | Stub — "will be implemented in Phase 11" |
| `/moira:audit` | Stub — "will be implemented in Phase 11" |

**Замечание:** Все stub-команды корректно показали фазу реализации, но не дали никакой полезной информации о проекте, хотя `config.yaml` и init-сканы уже существовали в `.claude/moira/` проекта. Это упущенная возможность — `/moira:status` мог бы хотя бы показать bootstrap state.

### Фаза 1: Запуск задачи

1. `/moira:task` без аргументов — корректно попросил описание задачи
2. `/moira:task Сделай полноценный rate-limiting для нашей системы` — начал пайплайн

### Фаза 2: Инициализация задачи (Steps 1-7)

- Task ID сгенерирован: `task-2026-03-13-001`
- Создан каталог, `input.md`, `status.yaml`, `current.yaml`, `manifest.yaml`
- **BUG-1:** Все файлы создавались в `~/.claude/moira/state/` (глобальная директория) вместо `.claude/moira/state/` проекта — см. детали ниже

### Фаза 3: Загрузка оркестратора (Step 8)

Прочитаны:
- `~/.claude/moira/skills/orchestrator.md` — полностью
- `~/.claude/moira/skills/dispatch.md` — полностью
- `~/.claude/moira/skills/gates.md` — полностью
- `~/.claude/moira/core/rules/roles/apollo.yaml`
- `~/.claude/moira/core/rules/base.yaml`
- `~/.claude/moira/core/response-contract.yaml`

### Фаза 4: Bootstrap Deep Scan Check

Оркестратор должен был проверить `config.yaml → bootstrap.deep_scan_pending`.
- **BUG-2:** Оркестратор искал `config.yaml` в несуществующем пути, не нашёл его, и молча пропустил deep scan — см. детали ниже

### Фаза 5: Классификация (Apollo)

Apollo (classifier) диспатчен как Agent, отработал за ~34 секунд, потратил 10,458 токенов (из бюджета 20k).

Результат:
- Size: **large**
- Confidence: **medium**
- Pipeline: **full**
- Reasoning: rate-limiting — cross-cutting concern, 5-10+ файлов, высокая сложность и неопределённость

Классификация записана в `classification.md`. Gate представлен пользователю.

### Фаза 6: Classification Gate

Пользователь ответил `proceed`. Gate записан в `status.yaml`.

### Фаза 7: Прерывание

Оркестратор начал готовить параллельный dispatch Hermes (explorer) + Athena (analyst), но был прерван пользователем, который заметил, что состояние задачи ведётся в неправильном месте.

---

## Выявленные проблемы

### BUG-1 (CRITICAL): Состояние задачи записывалось в глобальную директорию

**Суть:** Оркестратор создавал и обновлял файлы задачи в `~/.claude/moira/state/tasks/task-2026-03-13-001/` вместо `.claude/moira/state/tasks/task-2026-03-13-001/` внутри проекта.

**Почему это произошло — мои рассуждения:**

Скилл `task.md` (точка входа `/moira:task`) во всех путях использует `~/.claude/moira/state/`. Например:

```
Write `~/.claude/moira/state/tasks/{task_id}/input.md`
Write `~/.claude/moira/state/current.yaml`
```

Я буквально следовал этим инструкциям. При этом в проекте уже существовала полноценная локальная структура:

```
.claude/moira/
├── config.yaml          # конфиг проекта с бюджетами, quality mode, bootstrap state
├── state/
│   ├── tasks/           # пустая — здесь должны были быть задачи
│   ├── init/            # результаты init-сканов (4 файла)
│   ├── audits/
│   └── metrics/
├── knowledge/           # knowledge base с conventions, patterns, etc.
├── project/
├── hooks/
└── core/
```

Я не проверил наличие локальной структуры и не задался вопросом "куда писать". Просто следовал путям из скилла.

**Корневая причина:** Скилл `task.md` хардкодит `~/.claude/moira/` как базовый путь. Это расходится с реальной архитектурой, где init создаёт проектно-локальную структуру в `.claude/moira/`. Нет механизма определения "рабочей директории Moira" (глобальная vs локальная), и скиллы не знают о существовании проектного `.claude/moira/`.

**Последствия:**
- Состояние задачи изолировано от проекта
- Разные проекты будут перезаписывать общий `current.yaml`
- Init-сканы (structure, tech, convention, pattern) недоступны из глобальной директории
- `config.yaml` проекта (бюджеты, quality mode, bootstrap state) не найден

**Исправление (после обнаружения):** Я скопировал задачу из `~/.claude/moira/state/tasks/` в `.claude/moira/state/tasks/` проекта и `current.yaml` туда же. Но это был ручной патч.

**Рекомендация:**
1. Определить canonical base path: `{project_root}/.claude/moira/` для project-scoped state
2. Обновить все скиллы (`task.md`, `orchestrator.md`, `dispatch.md`, `gates.md`, `errors.md`) — заменить `~/.claude/moira/state/` на `{project_root}/.claude/moira/state/`
3. `~/.claude/moira/` оставить только для: глобальных скиллов, шаблонов, core rules, schemas — то, что не project-specific
4. Разграничение: core (глобальные, неизменяемые) vs state/config/knowledge (проектные)

---

### BUG-2 (CRITICAL): Deep scan не запустился

**Суть:** В `config.yaml` проекта стоит `bootstrap.deep_scan_pending: true`, но оркестратор не нашёл этот файл и пропустил deep scan.

**Почему это произошло — мои рассуждения:**

Orchestrator skill (Section 2, Bootstrap Deep Scan Check) говорит:

> Read `.claude/moira/config.yaml` field `bootstrap.deep_scan_pending`

Это относительный путь. Я интерпретировал его как проектный `.claude/moira/config.yaml`, но из-за BUG-1 я уже работал в контексте `~/.claude/moira/`. Поэтому я искал `config.yaml` сначала в рабочей директории проекта (нет такого файла в корне), потом в `~/.claude/moira/config.yaml` (не существует), и заключил: "config не найден, deep scan не pending".

При этом реальный `config.yaml` лежал тут:
```
/Users/minddecay/Documents/Projects/pet/sveltkit-todos/.claude/moira/config.yaml
```

И в нём:
```yaml
bootstrap:
  quick_scan_completed: true
  deep_scan_completed: false
  deep_scan_pending: true    # ← ЭТО ДОЛЖНО БЫЛО ТРИГГЕРНУТЬ DEEP SCAN
```

**Корневая причина:** Та же, что BUG-1 — неопределённость base path. Оркестратор не знал, что `config.yaml` нужно искать в `.claude/moira/` проекта.

**Последствия:**
- Deep scan (4 фоновых агента: architecture, dependency, test-coverage, security) не был запущен
- Knowledge base не обогащена deep findings
- Quality map не обновлён
- `deep_scan_pending` так и остался `true` — будет триггериться на каждом запуске задачи, пока не пофиксят

**Дополнительная деталь:** Deep scan templates существуют и доступны в `~/.claude/moira/templates/scanners/deep/`:
- `deep-architecture-scan.md`
- `deep-dependency-scan.md`
- `deep-security-scan.md`
- `deep-test-coverage-scan.md`

Проблема не в отсутствии шаблонов, а в том, что триггер (чтение config.yaml) не сработал.

---

### BUG-3 (MEDIUM): Оркестратор не прочитал init-сканы проекта

**Суть:** В `.claude/moira/state/init/` проекта лежат 4 детальных скана от `/moira:init`:
- `structure-scan.md` (7.0k) — полная структура проекта, файловое дерево, роли директорий
- `tech-scan.md` (7.1k) — стек, версии, зависимости
- `convention-scan.md` (11k) — naming, imports, error handling, code style
- `pattern-scan.md` (9.9k) — компонентные паттерны, API стиль, data access, state management

Ни один из этих файлов не был прочитан оркестратором или передан Apollo (classifier). Apollo классифицировал задачу "вслепую", не зная, что в проекте уже есть `rate-limit-buckets.ts` с Prisma моделью `RateLimitBucket`.

**Почему это произошло:**
1. BUG-1 — оркестратор не знал о локальной структуре
2. Dispatch skill не упоминает init-сканы как контекст для классификатора
3. Apollo's role definition говорит "You do NOT read project source code", но init-сканы — это не source code, а структурированные факты о проекте

**Последствия:**
- Apollo мог бы дать более точную классификацию, зная, что rate-limiting частично реализован
- Confidence могла бы быть выше, что могло изменить pipeline selection

---

### BUG-4 (LOW): `gate_pending` не сброшен после одобрения

**Суть:** После того как пользователь ответил `proceed` на classification gate, я обновил `status.yaml` (записал gate decision), но `current.yaml` остался с `gate_pending: "classification_gate"`. По правилам из `gates.md`:

> `moira_state_gate()` sets `gate_pending: null` in `current.yaml`

Это не было сделано. Я обновил `current.yaml` с `step_status: "completed"`, но оставил `gate_pending`.

---

## Решения оркестратора, которые стоит задокументировать

### Решение 1: Буквальное следование путям из скиллов

Я решил буквально следовать путям из `task.md` (`~/.claude/moira/state/...`), не проверив, существует ли проектно-локальная альтернатива. Это был неправильный выбор. Правильное поведение: сначала проверить наличие `.claude/moira/` в проекте, и если оно есть — использовать его как base path.

### Решение 2: Пропуск deep scan при отсутствии config

Когда `config.yaml` не был найден, оркестратор skill говорит: "If false or field not present: continue silently". Я следовал этому правилу. Но правильнее было бы активно искать config в `.claude/moira/` проекта, зная что `/moira:init` был ранее выполнен.

### Решение 3: Упрощённый prompt для Apollo

Apollo получил минимальный контекст: описание задачи + "This is a SvelteKit todos application". Я не включил:
- Init-сканы проекта (не знал о них из-за BUG-1)
- Информацию о существующем `rate-limit-buckets.ts` и `RateLimitBucket` Prisma model
- Knowledge base из `.claude/moira/knowledge/`

Это привело к тому, что Apollo оценил задачу как "с нуля", хотя часть инфраструктуры уже существует.

### Решение 4: Копирование состояния как исправление

После обнаружения BUG-1 пользователем я решил скопировать (не переместить) файлы из `~/.claude/moira/state/tasks/` в проектную директорию. Это оставило дубликаты в глобальной директории. Более правильным было бы: переместить (mv) и удалить глобальные копии.

---

## Что работало корректно

1. **Task ID generation** — формат `task-{date}-{NNN}` с проверкой существующих задач
2. **Apollo dispatch и response parsing** — Agent tool call, response в контрактном формате, парсинг STATUS/SUMMARY/ARTIFACTS
3. **Classification gate presentation** — формат из `gates.md`, health report, options
4. **Gate decision recording** — запись в `status.yaml`
5. **Pipeline selection** — large + medium → full, по таблице из Section 3
6. **Orchestrator self-discipline** — ни разу не прочитал source code проекта напрямую, всё через агентов (хотя до dispatch Hermes дело не дошло)

---

## Контекстный бюджет

| Agent | Budget | Использовано | % | Status |
|-------|--------|-------------|---|--------|
| Apollo (classifier) | 20k | 10.5k | 52% | ⚠ |
| Hermes (explorer) | 140k | — | — | не запущен |
| Athena (analyst) | 80k | — | — | не запущена |
| Orchestrator | 200k | ~40k (est.) | ~20% | ✅ |

---

## Рекомендации по исправлению

### P0 — Блокирующие (без них следующий запуск сломается так же)

1. **Определить base path resolution** — добавить в `task.md` или `orchestrator.md` логику:
   ```
   1. Check {project_root}/.claude/moira/ — if exists, use as MOIRA_BASE
   2. Fallback to ~/.claude/moira/
   ```
   И все пути в скиллах сделать относительными к `MOIRA_BASE`.

2. **Обновить task.md** — заменить все `~/.claude/moira/state/` на `{MOIRA_BASE}/state/`

3. **Обновить orchestrator.md Section 2** — bootstrap deep scan check должен читать `{MOIRA_BASE}/config.yaml`

### P1 — Важные

4. **Передавать init-сканы в контекст агентов** — dispatch.md должен включать L1 project model (из init-сканов) в prompt для всех агентов, включая Apollo

5. **Knowledge base доступ** — `{MOIRA_BASE}/knowledge/` должна читаться при сборке промптов для агентов с `knowledge_access` в role definition

### P2 — Улучшения

6. **`/moira:status` stub** — даже в Phase 3 stub мог бы показывать: bootstrap state из config.yaml, наличие init-сканов, список задач
7. **Gate state cleanup** — убедиться, что `gate_pending` сбрасывается в null после каждого gate decision
8. **Dual state cleanup** — при исправлении BUG-1 удалить глобальные копии задач

---

## Текущее состояние задачи

```
Task: task-2026-03-13-001
Pipeline: full
Status: INTERRUPTED (user-initiated)
Last completed step: classification
Last gate: classification_gate → proceed
Next step: exploration (parallel: Hermes + Athena)
State location: ~/.claude/moira/state/ (глобальная) + .claude/moira/state/ (копия)
Deep scan: NOT RUN (should have been triggered)
```

Задача может быть возобновлена через `/moira:resume` после исправления BUG-1 и BUG-2, но рекомендуется начать заново с чистого состояния.
