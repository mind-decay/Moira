# Metrics Guide

Справочник по метрикам Moira: что измеряется, как читать, когда реагировать.

**Источники данных:** телеметрия пайплайна (`telemetry.yaml`) и статус задачи (`status.yaml`), собираемые при завершении каждой задачи. Агрегируются помесячно в `.claude/moira/state/metrics/monthly-{YYYY-MM}.yaml`.

**Дашборд:** `/moira metrics` — основной интерфейс. Подкоманды: `details <section>`, `compare`, `export`.

---

## 1. Task Metrics

Количественная картина нагрузки на систему.

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `tasks.total` | int | Всего завершённых задач за период |
| `tasks.by_size.{small,medium,large,epic}` | int | Распределение по размерам |
| `tasks.bypassed` | int | Задачи через escape hatch (без пайплайна) |
| `tasks.aborted` | int | Задачи, прерванные до завершения |

### Как читать

- **Распределение по размерам** — показывает типичную нагрузку. Если преобладают large/epic, система работает в тяжёлом режиме — ожидай больше retries и checkpoint'ов.
- **bypassed / total** — процент обхода пайплайна. Высокий (>20%) может означать, что пайплайн воспринимается как чрезмерный для типичных задач проекта.
- **aborted / total** — частота отмен. Высокий (>15%) указывает на проблемы с классификацией (задачи оказываются сложнее, чем ожидалось) или неясными требованиями.

---

## 2. Quality Metrics

Качество результатов агентов. Главная метрика системы.

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `quality.first_pass_accepted` | int | Задачи, принятые ревьюером без доработки |
| `quality.tweaks` | int | Задачи, потребовавшие точечной правки |
| `quality.redos` | int | Задачи, потребовавшие полного отката |
| `quality.retry_loops_total` | int | Суммарные повторы на quality gate'ах |
| `quality.reviewer_criticals` | int | Критические находки ревьюера |

### Целевые значения

| Метрика | Цель | Источник |
|---------|------|----------|
| First-pass rate | >80% | IMPLEMENTATION-ROADMAP |

### Как читать

- **First-pass rate** = `first_pass_accepted / total`. Основной индикатор здоровья. <70% — системная проблема.
- **Tweak rate** = `tweaks / total`. Точечные правки — нормальное явление. >30% — аналитик или архитектор пропускают нюансы.
- **Redo rate** = `redos / total`. Полный откат — дорогая операция. Любое значение >5% требует расследования.
- **retry_loops_total / total** — среднее число retry на задачу. >1.0 — имплементер систематически не проходит ревью с первого раза.
- **reviewer_criticals** — баги, пойманные до доставки. Парадоксально: 0 может означать, что ревьюер слишком мягкий, а не что код идеален.

### Связь с другими метриками

Quality → Efficiency: высокий retry rate раздувает контекст оркестратора (каждый retry = дополнительный цикл).
Quality → Evolution: стабильно низкий first-pass rate триггерит предложения по улучшению правил.

---

## 3. Accuracy Metrics

Точность предсказаний системы на ранних этапах пайплайна.

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `accuracy.classification_correct` | int | Задачи с верной классификацией размера |
| `accuracy.architecture_first_try` | int | Архитектура принята с первой попытки |
| `accuracy.plan_first_try` | int | План принят с первой попытки |

### Как читать

- **Classification accuracy** = `classification_correct / total`. Определяется по gate override — если пользователь меняет размер на Gate #1 (`overridden=true`), это ошибка классификатора.
  - <85% — классификатор нуждается в калибровке. Проверь, не изменился ли характер задач в проекте.
- **Architecture first-try** — процент принятых архитектур без modify. Низкий показатель указывает на разрыв между знаниями системы о проекте и реальными предпочтениями.
- **Plan first-try** — аналогично для планов. Обычно выше, чем architecture (план строится на уже одобренной архитектуре).

### Диагностика

- Classification accuracy падает → knowledge base устарела (project model не отражает реальность).
- Architecture first-try падает → проверь свежесть `conventions` и `patterns` в knowledge base.
- Plan first-try падает → planner не учитывает предыдущие modify-решения (проверь `failures` knowledge).

---

## 4. Efficiency Metrics

Расход ресурсов. Контекст — единственный невосполнимый ресурс в системе.

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `efficiency.avg_orchestrator_context_pct` | int (0-100) | Средний % контекста оркестратора при завершении задачи |
| `efficiency.avg_implementer_context_pct` | int (0-100) | Средний пиковый % контекста имплементера |
| `efficiency.checkpoints_needed` | int | Количество checkpoint'ов из-за переполнения контекста |
| `efficiency.mcp_calls` | int | Всего MCP-вызовов |
| `efficiency.mcp_useful` | int | MCP-вызовы, давшие полезный результат |
| `efficiency.mcp_cache_hits` | int | MCP-вызовы, обслуженные из кеша |

### Целевые значения и пороги

**Оркестратор (1M контекст):**

| Уровень | Порог | Действие |
|---------|-------|----------|
| Healthy | <25% (<250k) | Нормальная работа |
| Monitor | 25-40% (250-400k) | Показывать в статусе |
| Warning | 40-60% (400-600k) | Алерт пользователю |
| Critical | >60% (>600k) | Рекомендовать checkpoint |

**Агенты (бюджет зависит от роли):**

| Уровень | Порог | Индикатор |
|---------|-------|-----------|
| Healthy | <50% бюджета | ✅ |
| Warning | 50-70% бюджета | ⚠️ |
| Critical | >70% бюджета | 🔴 — risk of quality degradation |

### Как читать

- **avg_orchestrator_context_pct** — главный efficiency-индикатор. Растёт с количеством retry и агентов. Если стабильно >25%, агенты возвращают слишком много данных в оркестратор.
- **checkpoints_needed** — ненулевое значение означает, что задачи вынужденно прерываются. Нормально для epic-задач, проблема для medium.
- **MCP precision** = `mcp_useful / mcp_calls`. <80% — агенты запрашивают ненужную документацию.
- **MCP cache rate** = `mcp_cache_hits / mcp_calls`. Рост = экономия бюджета на повторных запросах.

---

## 5. Knowledge Metrics

Состояние базы знаний — основы контекстных решений системы.

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `knowledge.patterns_total` | int | Всего задокументированных паттернов |
| `knowledge.patterns_added` | int | Паттернов добавлено за период |
| `knowledge.decisions_total` | int | Всего архитектурных решений |
| `knowledge.decisions_added` | int | Решений добавлено за период |
| `knowledge.quality_map_coverage_pct` | int (0-100) | % проекта, покрытого quality map |
| `knowledge.freshness_pct` | int (0-100) | % записей, подтверждённых как актуальные |
| `knowledge.stale_entries` | int | Количество устаревших записей |

### Модель устаревания (exponential decay)

Каждая запись в knowledge base имеет confidence score, убывающий экспоненциально:

```
confidence(entry) = e^(-λ × tasks_since_verified)
```

Скорость убывания (λ) зависит от типа знания:

| Тип знания | λ | Смысл |
|-----------|---|-------|
| decisions | 0.01 | Архитектурные решения устаревают медленно |
| conventions | 0.02 | Конвенции стабильны |
| failures | 0.03 | Ошибки актуальны пока код не меняется |
| patterns | 0.05 | Паттерны могут эволюционировать |
| libraries | 0.05 | Зависимости обновляются |
| quality_map | 0.07 | Карта качества теряет актуальность при рефакторинге |
| project_model | 0.08 | Модель проекта устаревает быстрее всего |

### Категории confidence

| Диапазон | Категория | Legacy-имя | Значение |
|---------|-----------|------------|----------|
| >70% | trusted | fresh | Можно использовать без проверки |
| 30-70% | usable | aging | Можно использовать, но верифицировать при возможности |
| <30% | needs-verification | stale | Нельзя использовать без проверки |

### Как читать

- **freshness_pct <80%** — база знаний деградирует. Запусти `/moira refresh`.
- **stale_entries >10** — накопились непроверенные записи. Каждая — потенциальный источник ошибок.
- **quality_map_coverage_pct <60%** — значительная часть проекта не покрыта картой качества. Система будет хуже предсказывать проблемные зоны.
- **patterns_added = 0 при tasks.total >10** — система не учится. Проверь reflector.

---

## 6. Evolution Metrics

Самосовершенствование системы. Конституционное ограничение: любое изменение правил требует минимум 3 наблюдений (Art 5.2).

| Поле | Тип | Что измеряет |
|------|-----|-------------|
| `evolution.improvements_proposed` | int | Предложено улучшений правил |
| `evolution.applied` | int | Принято и применено |
| `evolution.deferred` | int | Отложено |
| `evolution.rejected` | int | Отклонено |
| `evolution.regressions` | int | Регрессии от применённых изменений |

### Целевые значения

| Метрика | Цель |
|---------|------|
| `regressions` | **0** — всегда |

### Как читать

- **applied / proposed** — acceptance rate. Очень низкий (<20%) — reflector генерирует шум. Очень высокий (>90%) — возможно, недостаточно критичная оценка.
- **deferred** — предложения, требующие больше наблюдений для подтверждения. Здоровый показатель: система не спешит с выводами.
- **regressions >0** — КРАСНЫЙ ФЛАГ. Применённое улучшение ухудшило результат. Требует немедленного расследования и отката.

---

## 7. Trend Indicators

Тренды сравнивают текущий период с предыдущим.

| Индикатор | Значение |
|-----------|----------|
| ↑ | Улучшение (разница ≥5 пунктов, D-093(a)) |
| ↓ | Ухудшение (разница ≥5 пунктов) |
| → | Стабильно (разница <5 пунктов) |

**Порог 5 пунктов** — абсолютная разница, не процентная. Переход first-pass rate с 82% на 78% = 4 пункта = стабильно (→). С 82% на 76% = 6 пунктов = ухудшение (↓).

---

## 8. Statistical Methods (Bench)

Статистические методы используются в bench-тестировании (Layer 2-3) для отделения сигнала от шума в стохастических метриках.

### 8.1 Evaluation Zones

Каждая метрика оценивается относительно базовой линии (baseline):

```
  ┌─────────┬──────┬─────────────────────┬──────┬─────────┐
  │  ALERT  │ WARN │      NORMAL         │ WARN │  ALERT  │
  │  <-2σ   │-1-2σ │    baseline ±σ      │+1-2σ │  >+2σ   │
  └─────────┴──────┴─────────────────────┴──────┴─────────┘
  regression         statistical noise         improvement
```

| Зона | Условие | Реакция |
|------|---------|---------|
| NORMAL | В пределах ±1σ от baseline | Шум. Логировать, не реагировать |
| WARN | 1-2σ от baseline | Возможное изменение. Одиночный WARN — наблюдать. Два подряд на одной метрике — сигнал |
| ALERT | >2σ от baseline | Значимое изменение. Расследовать |

**Подтверждение регрессии** (любое из):
- Единичный ALERT (>2σ ниже baseline)
- 2+ WARN подряд на одной метрике
- 3+ метрик одновременно в WARN
- CUSUM drift detected (см. ниже)

### 8.2 SPRT — Sequential Probability Ratio Test

Позволяет прекратить bench-тесты досрочно, когда статистических данных уже достаточно для вывода.

**Гипотезы:**
- H₀: μ ≥ μ₀ (качество не хуже baseline — регрессии нет)
- H₁: μ ≤ μ₀ - δ (качество упало на δ или больше)

**Параметры по умолчанию:**

| Параметр | Значение | Смысл |
|----------|---------|-------|
| α | 0.05 | False positive rate (ложная регрессия) |
| β | 0.10 | False negative rate (пропущенная регрессия) |
| A | 18 | Верхний порог = (1-β)/α |
| B | 0.105 | Нижний порог = β/(1-α) |
| δ (composite) | 3 points | Минимальный эффект для композитного скора |
| δ (sub-metric) | 5 points | Минимальный эффект для отдельной метрики |

**Инкремент log-likelihood для наблюдения x:**

```
Δ = -δ(2x - 2μ₀ + δ) / (2σ²)
```

**Правила решения:**
- log(Λ) > log(A) → **reject H₀** — регрессия подтверждена, STOP
- log(Λ) < log(B) → **accept H₀** — регрессии нет, STOP
- Иначе → **continue** — данных недостаточно, продолжить тестирование

**Как читать в отчёте:**
```
Regression confirmed after 4/12 tests (SPRT early stop)
```
— регрессия выявлена после 4 тестов из 12 запланированных. Остальные 8 не нужны.

### 8.3 CUSUM — Cumulative Sum Change Detection

Детектирует **малые устойчивые сдвиги**, которые не ловятся зонами (каждое отдельное наблюдение в NORMAL, но тренд есть).

**Аккумуляторы:**
```
S⁺ₙ = max(0, S⁺ₙ₋₁ + (xₙ - μ₀ - k))   — детекция сдвига вверх
S⁻ₙ = max(0, S⁻ₙ₋₁ + (μ₀ - k - xₙ))   — детекция сдвига вниз
```

**Параметры:**

| Параметр | Формула | Смысл |
|----------|---------|-------|
| k | δ/2 | Reference value — половина минимального эффекта |
| h | 4σ | Порог решения |
| μ₀ | baseline mean | Базовая линия |

**Сигналы:**
- S⁺ > h → **drift_up** (улучшение)
- S⁻ > h → **drift_down** (регрессия)

**Отличие от зон:** CUSUM ловит деградацию в 1 пункт за 5 запусков (совокупно -5), которую зоны классифицируют как NORMAL каждый раз.

**Как читать в отчёте:**
```
CUSUM drift_down detected: quality score (-1.2 avg shift over 5 runs)
```
— каждый отдельный запуск был "нормальным", но накопленный сдвиг вниз значим.

### 8.4 Benjamini-Hochberg — Multiple Comparison Correction

Контролирует false discovery rate при одновременной оценке нескольких метрик.

**Проблема:** при 4 метриках без коррекции P(≥1 ложная тревога) ≈ 18.5% на bench run.

**Алгоритм:**
1. Отсортировать p-values: p₁ ≤ p₂ ≤ ... ≤ pₘ
2. Найти наибольшее k, где pₖ ≤ (k/m) × α
3. Отклонить гипотезы 1..k (значимые), принять k+1..m (шум)

**α = 5%** по умолчанию. FDR ≤ 5%.

**Как читать в отчёте:**
```
3/4 metrics flagged, 2 survive BH correction: code_correctness, conventions_adherence
```
— из 3 подозрительных метрик только 2 прошли коррекцию. Третья — вероятный шум.

### 8.5 Cold Start

Статистическая модель проходит три фазы калибровки:

| Фаза | Запуски | Ширина полосы | Реакция |
|------|---------|--------------|---------|
| Calibration | 3-5 | — | Только сбор данных, никаких решений |
| Provisional | 5-10 | Широкая (±2σ) | Только ALERT триггерит реакцию |
| Stable | 10+ | Нормальная (±1σ) | Полная модель |

---

## 9. Budget System

Бюджеты агентов — механизм предотвращения контекстного переполнения.

### 9.1 Аллокации по ролям

| Агент | Бюджет | Назначение |
|-------|--------|-----------|
| Classifier (Apollo) | 20k | Минимальный — только задача + история |
| Explorer (Hermes) | 140k | Максимальный — может читать много кода |
| Analyst (Athena) | 80k | Требования, не код |
| Architect (Metis) | 100k | Полная модель проекта + решения |
| Planner (Daedalus) | 70k | Архитектура + список файлов |
| Implementer (Hephaestus) | 120k | Код для написания/модификации |
| Reviewer (Themis) | 100k | Код для ревью |
| Tester (Aletheia) | 90k | Тесты |
| Reflector (Mnemosyne) | 80k | Рефлексия |
| Auditor (Argus) | 140k | Кросс-ссылки между файлами |

### 9.2 Adaptive Safety Margin

Фиксированный запас в 30% заменяется адаптивной моделью по мере накопления данных:

```
margin_a = max(0.20, min(0.50, μ_a + k × σ_a))
```

где μ_a и σ_a — среднее и стандартное отклонение ошибки оценки для агента типа a:

```
ε_a = (actual_usage - estimated_usage) / estimated_usage
```

| Наблюдений | Формула | Обоснование |
|------------|---------|-------------|
| <5 | Фиксированные 30% | Cold start — данных нет |
| 5-20 | max(0.20, μ + 3σ) | Широкий интервал — данных мало |
| 20+ | max(0.20, min(0.50, μ + 2σ)) | Стандартная формула |

**Границы:** минимум 20% (структурный минимум), максимум 50% (чтобы не тратить зря).

### 9.3 Оценка токенов

Приблизительный метод: `tokens ≈ file_size_bytes / 4` (D-056).

Система не может точно измерить runtime-потребление. Используется pre-launch estimate (входные файлы + инструкции) и post-completion estimate (вход + выход).

### 9.4 Orchestrator Budget

Оркестратор работает в контексте 1M токенов. Бюджеты агентов определяют максимум полезной работы, а не лимит контекста.

**Стратегии минимизации контекста оркестратора:**
1. Агенты возвращают только status summaries (не полные результаты)
2. Оркестратор читает знания уровня L0-L1 (не L2)
3. Большие выходы агентов записываются в файлы
4. Gate displays генерируются из файлов, а не из памяти

---

## 10. Retry Metrics

Система оптимизации повторных попыток на основе Markov decision model.

### 10.1 Модель решения

При ошибке (E5-QUALITY, E6-AGENT, E9-SEMANTIC) система решает: повторить или эскалировать пользователю.

**Правило:** retry, если вероятность успеха ≥ 30%. Иначе — эскалация.

### 10.2 Вероятности по умолчанию

| Ошибка | Агент | Max retries | P(success) attempt 1 | P(success) attempt 2 |
|--------|-------|-------------|----------------------|----------------------|
| E5-QUALITY | implementer | 2 | 70% | 30% |
| E5-QUALITY | architect | 1 | 50% | — |
| E6-AGENT | any | 1 | 60% | — |
| E9-SEMANTIC | implementer | 2 | 50% | 30% |

### 10.3 Обновление вероятностей (EMA)

Система учится на результатах через exponential moving average:

```
p_new = α × outcome + (1-α) × p_old
```

- α = **0.8** — сильный вес на недавние результаты
- outcome = 100 (успех) или 0 (неудача)

Пример: текущая p=70%, retry failed → p_new = 0.8×0 + 0.2×70 = 14%. Следующий retry для этой пары (error, agent) будет skip (14% < 30%).

### 10.4 Модель стоимости

```
cost_retry = 100 (абстрактные единицы)
cost_escalate = 200 (2× retry)
```

Expected cost = сумма стоимостей retry-шагов с учётом вероятностей провала + стоимость эскалации если все retry провалились.

### 10.5 Как читать в отчёте

```
Retry recommended (estimated 65% success probability based on 12 historical observations)
```
— система рекомендует повторить, основываясь на 12 предыдущих подобных ситуациях.

```
Escalating to user (estimated 18% success probability — retry unlikely to help)
```
— вероятность слишком низкая, retry будет тратой ресурсов.

---

## 11. Audit Triggers

Метрики автоматически триггерят аудиты:

| Условие | Тип аудита |
|---------|-----------|
| Каждые 10 задач | Light (rules + knowledge) |
| Каждые 20 задач | Standard (rules + knowledge + agents + config + consistency) |

Триггер устанавливается при `moira_metrics_collect_task()` через флаг `audit_pending.yaml`. Проверяется при старте следующего пайплайна.

---

## 12. Composite Health Score

Используется в `/moira health`. Агрегированный скор 0-100:

| Компонент | Вес | Источник |
|-----------|-----|----------|
| Structural Conformance | 30% | Tier 1 tests (constitutional invariants, pipeline integrity, agent contracts, rules consistency) |
| Result Quality | 50% | First-pass rate + LLM-judge scores (code correctness, architecture quality, requirements coverage, conventions adherence) |
| Efficiency | 20% | Orchestrator/agent context vs budget + retry/escalation rate |

**Нормализация LLM-judge:**
- Judge выдаёт 1-5. Конвертация: `(score - 1) × 25` → 0-100.
- Если automated checks fail (compile/lint/tests) — quality capped at 20, независимо от judge score.

---

## 13. Диагностика: метрика плохая — что делать

| Симптом | Вероятная причина | Действие |
|---------|------------------|----------|
| First-pass rate <70% | Слабые правила имплементера или устаревшие конвенции | Аудит rules + проверка knowledge freshness |
| High tweak rate (>30%) | Аналитик или архитектор пропускают нюансы | Обновить checklist'ы аналитика |
| High retry rate (>1.0/task) | Имплементер систематически не проходит ревью | Усилить правила имплементера, проверить quality checklist |
| Orchestrator context >25% | Агенты возвращают слишком много данных | Проверить summary format агентов, сократить L1-summaries |
| Low MCP precision (<80%) | Лишние запросы документации | Ужесточить MCP authorization rules |
| Classification accuracy <85% | Project model устарел | `/moira refresh` + проверить project model |
| freshness_pct <80% | Knowledge base деградирует | `/moira refresh` |
| stale_entries >10 | Накопились непроверенные записи | Ручная верификация или автоматический refresh |
| regressions >0 | Применённое улучшение сломало что-то | Немедленный откат + расследование |
| checkpoints >0 для medium-задач | Бюджеты неверно настроены или задачи неверно классифицированы | Проверить budget allocations + classification accuracy |
| bypassed >20% | Пайплайн воспринимается как overhead | Проверить, не слишком ли тяжёлый quick pipeline для типичных задач |

---

## Appendix A: Storage Format

```yaml
# .claude/moira/state/metrics/monthly-{YYYY-MM}.yaml

period: "2026-03"
tasks:
  total: 47
  by_size: {small: 18, medium: 21, large: 6, epic: 2}
  bypassed: 4
  aborted: 2
quality:
  first_pass_accepted: 38
  tweaks: 7
  redos: 2
  retry_loops_total: 19
  reviewer_criticals: 5
accuracy:
  classification_correct: 44
  architecture_first_try: 41
  plan_first_try: 45
efficiency:
  avg_orchestrator_context_pct: 16
  avg_implementer_context_pct: 47
  checkpoints_needed: 1
  mcp_calls: 23
  mcp_useful: 21
  mcp_cache_hits: 8
knowledge:
  patterns_total: 31
  patterns_added: 8
  decisions_total: 12
  decisions_added: 4
  quality_map_coverage_pct: 84
  freshness_pct: 91
  stale_entries: 3
evolution:
  improvements_proposed: 6
  applied: 3
  deferred: 2
  rejected: 1
  regressions: 0
task_records:
  - task_id: "t-2026-03-11-004"
    pipeline: standard
    size: medium
    first_pass: true
    tweaked: false
    redone: false
    retries: 0
    orchestrator_pct: 12
    reviewer_criticals: 0
```

## Appendix B: Per-Task Telemetry Format

```yaml
# .claude/moira/state/tasks/{id}/telemetry.yaml

task_id: "t-2026-03-11-004"
timestamp: "2026-03-11T14:32:00Z"
moira_version: "0.3.1"

pipeline:
  type: standard
  classification_confidence: high
  classification_correct: true

execution:
  agents_called:
    - role: explorer
      status: success
      context_pct: 42
      duration_sec: 35
  gates:
    - name: classification
      result: proceed
    - name: architecture
      result: modify
      retry_count: 1
    - name: final
      result: done
  retries_total: 1
  budget_total_tokens: 45000

quality:
  reviewer_findings: {critical: 0, warning: 2, suggestion: 3}
  first_pass_accepted: false
  final_result: done

structural:
  constitutional_pass: true
  violations: []
```

## Appendix C: Design Document References

| Тема | Документ |
|------|---------|
| Определения метрик | `design/subsystems/metrics.md` |
| Бюджеты и пороги | `design/subsystems/context-budget.md` |
| Quality gates | `design/subsystems/quality.md` |
| Fault tolerance и retry | `design/subsystems/fault-tolerance.md` |
| Статистическая модель | `design/subsystems/testing.md` |
| Self-monitoring | `design/subsystems/self-monitoring.md` |
| Audit system | `design/subsystems/audit.md` |
| Knowledge decay | `design/subsystems/knowledge.md` |
| D-093 (trend threshold, audit triggers) | `design/specs/archive/2026-03-15-phase11-metrics-audit.md` |
| Metrics schema | `src/schemas/metrics.schema.yaml` |
| Telemetry schema | `src/schemas/telemetry.schema.yaml` |
| Metrics library | `src/global/lib/metrics.sh` |
| Budget library | `src/global/lib/budget.sh` |
| Retry library | `src/global/lib/retry.sh` |
| Bench/SPRT/CUSUM | `src/global/lib/bench.sh` |
