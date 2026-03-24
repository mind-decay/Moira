# Системный аудит Moira — 2026-03-24

**Task ID:** task-2026-03-24-005
**Дата:** 2026-03-24
**Глубина:** standard (2 прохода анализа + 2 прохода ревью)

---

## 1. Executive Summary

Система Moira архитектурно здорова: конституционные gates соответствуют Art 2.2, NEVER-ограничения агентов не ослаблены, pipeline-ы близки к максимальной параллелизации, knowledge access matrix синхронизирована, budget/retry-системы комплементарны. Из 37 вопросов аудита по 8 измерениям все 37 получили ответы; 10 из 33 findings подтвердили корректную работу системы.

Однако обнаружены три проблемы уровня HIGH:

1. **F-001 — Отсутствует pre-commit hook (Art 6.3).** Конституция требует верификацию перед каждым коммитом, но ни одного механизма enforcement нет. Конституционное соответствие — на честном слове.
2. **F-015 — Неограниченный convergence loop.** Analytical pipeline может зацикливаться через `deepen` без hard cap. Единственный предохранитель — бюджет оркестратора (>60% → mandatory checkpoint).
3. **F-009 — Dual-implementation divergence (5 точек).** Shell-библиотеки и orchestrator.md реализуют одну логику независимо друг от друга. При обновлении одной стороны вторая может незаметно разойтись.

Дополнительно выявлены 6 проблем MEDIUM (boundary enforcement gaps, missing infrastructure) и 14 проблем LOW (config completeness, redundancy, edge cases). ~610 строк дублированного контента (~2,570 токенов) распределены по 5 категориям; дедупликация большинства нецелесообразна.

**Вердикт:** система функциональна и корректна в штатном режиме. Основные риски — в enforcement gaps (конституционная верификация, loop bounds) и maintenance risks (dual-implementation divergence при обновлениях).

---

## 2. Подтверждённые сильные стороны

Аудит подтвердил корректную работу следующих подсистем:

- **F-024:** Pipeline gates полностью соответствуют Constitution Art 2.2
- **F-025:** NEVER-ограничения всех агентов присутствуют и не ослаблены
- **F-026:** Knowledge access matrix синхронизирована между canonical source и role YAML
- **F-027:** Step name enums синхронизированы между state.sh и pipeline YAML
- **F-028:** Agent role names консистентны по всей системе
- **F-029:** Retry hard limits в budget.sh и state.sh комплементарны (не конфликтуют)
- **F-030:** Pipelines близки к максимальной параллелизации с учётом data dependencies
- **F-031:** Консолидация gates корректно заблокирована Art 2.2 (каждый gate = отдельный approval)
- **F-032:** Pre-assembled instruction files — эффективная оптимизация контекста
- **F-033:** Budget thresholds совпадают между budget.sh и orchestrator.md

Эти результаты показывают, что ядро системы (конституционные инварианты, boundary constraints, pipeline structure) реализовано корректно и согласованно.

---

## 3. Findings по приоритету

### 3.1 HIGH (3 findings)

#### F-001: Отсутствует Pre-Commit Verification Hook (Art 6.3)

- **Воздействие:** Конституция Art 6.3 требует: "A verification check MUST run before any system change is committed." Без enforcement нарушения проходят в коммиты незамеченными.
- **Доказательства:** Нет `.git/hooks/pre-commit`, нет husky/lint-staged, нет автоматического runner для invariant verification checklist (Constitution lines 162-193).
- **Связано с:** F-003 (xref validation можно интегрировать), F-002 (.version blocking upgrade safety)
- **Рекомендация:** Реализовать pre-commit hook, запускающий invariant checklist. Интегрировать xref-тесты (`src/tests/tier1/test-xref-manifest.sh`).

#### F-015: Неограниченный Convergence Loop в Analytical Pipeline

- **Воздействие:** Pipeline может зацикливаться бесконечно. `analytical.yaml` depth_checkpoint_gate `deepen` option возвращает к analysis без ограничений. Convergence trend tracking (orchestrator.md lines 507-523) — информационный, не enforcement.
- **Доказательства:** `redirect` имеет `max_per_pipeline: 1`, но `deepen` — нет. Единственный natural limit: budget >60% → mandatory checkpoint.
- **Рекомендация:** Добавить hard cap 5-10 проходов для `deepen` в `analytical.yaml`.

#### F-009: Dual-Implementation Divergence Risk (5 точек)

- **Воздействие:** Shell-библиотеки определяют каноническую логику, но оркестратор не может вызывать shell-функции и переимплементирует их. При обновлении одной стороны — silent divergence.
- **Доказательства:** 5 точек расхождения:
  - Gate decision enum: `state.sh:148-149` vs `orchestrator.md` Section 2
  - Step name validation: `state.sh:61` vs pipeline YAML reading
  - Budget thresholds: `budget.sh:296-305` vs `orchestrator.md:639-646`
  - Health report format: `gates.md:42-63` vs orchestrator generation
  - Retry counter logic: `state.sh:234-263` vs orchestrator error recovery
- **Рекомендация:** Добавить xref-manifest entries для каждой точки. Документировать canonical source в inline-комментариях orchestrator.md.

### 3.2 MEDIUM (6 findings)

#### F-004: dispatch.md пропускает Calliope в post-agent guard check

- **Воздействие:** Calliope пишет markdown в project paths, но post-agent guard check не применяется.
- **Доказательства:** `orchestrator.md` line 269 включает "implementer, explorer, calliope". `dispatch.md` line 232 — только "implementer or explorer".
- **Рекомендация:** Добавить calliope в dispatch.md line 232. Исправление — 1 строка.

#### F-023: Deep Scan никогда не выполнялся

- **Воздействие:** Quality map лишён deep insights (architecture patterns, test coverage, security). Агенты Metis, Themis, Daedalus, Aletheia получают менее полное руководство. EVOLVE mode ограничен.
- **Доказательства:** `config.yaml`: `deep_scan_completed: false`, `deep_scan_pending: false`.
- **Рекомендация:** Установить `deep_scan_pending: true` в config.yaml для запуска при следующем pipeline run.

#### F-002: Отсутствует .version файл

- **Воздействие:** `upgrade.sh`, `completion.sh`, `scaffold.sh`, `audit.sh` ссылаются на `.version`, но файл не существует. Upgrade command не может определить version compatibility.
- **Доказательства:** Файл отсутствует в `src/global/` и installed location.
- **Рекомендация:** Создать `src/global/.version`, обеспечить деплой через install.sh.

#### F-005: Violations Log лишён контекста

- **Воздействие:** 977 нарушений за 3 дня, все из dev-сессий (87.7% Read, 11.8% Edit, 1.4% Write). Нет поля task_id — невозможно отличить pipeline-time violations от development noise. Каждый audit-таск раздувает счётчик.
- **Доказательства:** violations.log не содержит task_id. 95 записей добавлены самим этим аудитом.
- **Рекомендация:** Добавить task_id в записи violations.log при активном pipeline. Записывать pre-task baseline count.

#### F-003: xref Validation существует, но enforcement отложен

- **Воздействие:** `test-xref-manifest.sh` обнаруживает stale xrefs, но не блокирует коммиты. Detection без prevention.
- **Доказательства:** Enforcement отложен до Phase 12 (D-093g). Тест находится в `src/tests/tier1/`.
- **Рекомендация:** Интегрировать xref-тесты в pre-commit hook при реализации F-001.

#### F-006: State-файлы растут без ограничений

- **Воздействие:** При ~150 строк/задачу, после 100 задач логи достигнут ~15,000 строк. Чтение violations.log такого размера — ~75k токенов (7.5% capacity оркестратора).
- **Доказательства:** `tool-usage.log`: 4,655 строк; `budget-tool-usage.log`: 5,131; `violations.log`: 977. Нет ротации, truncation, архивации.
- **Рекомендация:** Реализовать log rotation (хранить последние N задач или N строк), архивировать старые записи.

### 3.3 LOW (14 findings)

**Config completeness (F-018, F-019, F-020):**
Три пропущенные секции в config.yaml: scribe budget (`F-018`), `graph:` section (`F-019`), `tooling.post_implementation` (`F-020`). Все имеют working fallbacks — runtime ошибок нет. Исправление: добавить недостающие секции.

**Sync risk (F-010, F-011, F-012, F-013, F-014):**
~610 строк дублированного контента по 5 категориям. Response contract (`F-010`) — 4 locations с текстовыми расхождениями, нормализация рекомендована. Error handlers (`F-011`, ~280 строк) и gate definitions (`F-013`, ~120 строк) — дедупликация нецелесообразна (net savings <340 токенов при добавленной сложности merge-логики). Budget values (`F-012`) — 4 locations, lookup chain детерминирован, но scribe budget пропущен. Knowledge access matrix (`F-014`) — синхронизирована, отслеживается xref-004.

**Behavioral edge cases (F-016, F-017):**
Quality verdict dual-source (`F-016`) — агент может написать "pass" в response, а findings YAML покажет critical_count: 1. Silent step enforcement (`F-017`) — оркестратор молча исполняет пропущенные шаги перед final gate без уведомления пользователя (Art 3.3 edge case).

**Context optimization (F-021, F-022):**
19 redundant file reads в standard pipeline (`F-021`, ~1,425 токенов overhead). Orchestrator fixed overhead 33k-48k токенов (`F-022`, 3.3-4.8% от 1M) — в допустимых пределах. Section splitting не рекомендован.

**Boundary info (F-007, F-008):**
Zero AGENT_VIOLATION entries (`F-007`) — требует исследования: либо агенты идеальны, либо post-agent guard не реализован. Guard.sh detection-only (`F-008`) — by design, Layer 1 (`allowed-tools`) обеспечивает prevention.

---

## 4. Анализ дублирования

| Дублированный контент | Locations | Строки | Токены | Sync-механизм |
|---|---|---|---|---|
| Error handlers | 5 pipelines | ~280 | ~1,200 | Нет (xref-007 частично) |
| Gate definitions | 5 pipelines + gates.md | ~120 | ~500 | Нет |
| Response contract | 4 locations | ~60 | ~250 | Нет (есть комментарий) |
| Knowledge access matrix | Matrix + 11 role YAMLs | ~110 | ~450 | xref-004 (manual) |
| Budget values | 4 locations | ~40 | ~170 | xref-001 (manual) |
| **Итого** | | **~610** | **~2,570** | |

**Оценка:** Большинство дублирования стабильно и механистично. ROI дедупликации error handlers и gates — отрицательный (добавленная сложность > экономия). Рекомендуется нормализовать response contract (F-010) и задокументировать maintenance protocols для остального.

---

## 5. Анализ context budget

| Метрика | Значение |
|---|---|
| Orchestrator fixed overhead | 33k-48k токенов (3.3-4.8% от 1M) |
| Standard pipeline total (estimated) | ~93k токенов |
| Redundant reads per standard pipeline | 19 (~1,425 токенов recoverable) |
| Conditionally loadable sections | ~2,065 токенов (splitting не рекомендован) |
| Pre-assembled instruction files | Подтверждены как наиболее эффективная оптимизация |

**Вывод:** Context не является bottleneck. Overhead оркестратора в пределах нормы. Минорные оптимизации доступны (read-once pattern для dispatch.md, ~1,125 токенов экономии), но не срочны.

---

## 6. Implementation Roadmap

### Tier 1 — Немедленно (конституционное / safety)

| # | Finding | Действие | Сложность |
|---|---------|----------|-----------|
| 1 | F-004 | Добавить calliope в dispatch.md guard check (line 232) | 1-line fix |
| 2 | F-015 | Добавить hard cap для `deepen` в analytical.yaml | Minimal |
| 3 | F-018 + F-019 + F-020 | Заполнить пропуски в config.yaml (scribe budget, graph, tooling) | Simple additions |

### Tier 2 — Ближайшая очередь (infrastructure)

| # | Finding | Действие | Сложность |
|---|---------|----------|-----------|
| 4 | F-001 + F-003 | Pre-commit hook с интеграцией xref validation | Medium |
| 5 | F-002 | Создать .version файл, обновить install.sh | Simple |
| 6 | F-005 | Добавить task_id в violations log (guard.sh) | Simple |
| 7 | F-023 | Установить `deep_scan_pending: true` в config.yaml | 1-line fix |

### Tier 3 — Среднесрочно (maintenance quality)

| # | Finding | Действие | Сложность |
|---|---------|----------|-----------|
| 8 | F-010 | Нормализовать response contract по 4 locations | Medium |
| 9 | F-009 | Добавить xref-manifest entries для 5 dual-implementation точек | Medium |
| 10 | F-006 | Спроектировать и реализовать state file rotation | Medium |

### Tier 4 — Опционально (optimization)

| # | Finding | Действие | Сложность |
|---|---------|----------|-----------|
| 11 | F-021 | Read-once pattern для pre-planning dispatch assembly | Low |
| 12 | F-017 | Показать step enforcement в final gate display | Low |
| 13 | F-016 | Post-dispatch quality verdict verification | Low |
| 14 | F-012 | Добавить effective-budget query command | Low |

### Не рекомендовано

- **F-011:** Дедупликация error handlers (net 340 токенов, добавленная сложность)
- **F-013:** Извлечение gate definitions (аналогичный rationale)
- **F-022:** Splitting секций orchestrator.md (fragmentation risk > savings)

---

## 7. Risk Matrix

|  | **High Likelihood** | **Low Likelihood** |
|---|---|---|
| **High Impact** | **F-009** — dual-implementation divergence при любом обновлении shell libs или orchestrator.md | **F-001** — конституционное нарушение коммитится без pre-commit hook; **F-015** — бесконечный loop в bench mode |
| **Low Impact** | **F-005** — noise accumulation в violations log каждую сессию; **F-006** — log growth со временем | **F-016** — quality verdict расхождение; **F-017** — silent step enforcement |

---

## 8. Metadata аудита

| Параметр | Значение |
|---|---|
| Task ID | task-2026-03-24-005 |
| Дата | 2026-03-24 |
| Глубина | standard (2 прохода анализа + 2 прохода ревью) |
| Агенты | Argus (auditor), Metis (architect), Themis (reviewer) |
| Измерения | 8 |
| Вопросы | 37/37 отвечены |
| Coverage | Full (все измерения HIGH или MEDIUM-HIGH) |
| Self-correction | 1 exploration error скорректирована (install.sh), 3 pass-1 insufficiencies разрешены в pass 2 |
| Violations при старте | 882 |
| Violations при завершении | 977+ (95+ записей от самих audit-агентов) |
| Findings | 33 total: 3 HIGH, 6 MEDIUM, 14 LOW, 10 confirmed OK |
