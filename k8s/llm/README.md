# llm: llama.cpp окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `llm-dev`, `llm-stage`, `llm-prod` |
| Namespace | `llm-<env>` |
| Узел | `llms` |
| Chart | `templates/llama.yaml` |
| Образ | `ghcr.io/ggml-org/llama.cpp:server`, с GPU — `:server-cuda` |
| Данные | `volumes/llm/<env>/llama` |

## Модель по умолчанию

| Параметр | Значение |
|---|---|
| Модель | [Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) |
| Файл | [unsloth/Qwen3.5-4B-GGUF](https://huggingface.co/unsloth/Qwen3.5-4B-GGUF), `Qwen3.5-4B-Q4_K_M.gguf` (~2,6 ГиБ) |
| Имя в API | `Qwen3.5-4B` |
| Контекст | 32768 токенов |
| Режим рассуждений | выключен (`thinking: false`) |

## Ресурсы

| Ресурс | На окружение | Узел `llms` |
|---|---|---|
| CPU | 1 ядро (запрос) | 4 ядра |
| RAM | 3 ГиБ запрос, 5 ГиБ лимит | 16 ГиБ |
| Диск | ~2,6 ГиБ модель, том 20 ГиБ | 200 ГиБ |
| VRAM | ~1,3 ГиБ (Ubuntu, HAMi), свободная VRAM (WSL2) | 4 ГиБ |

## Адреса

| Откуда | Адрес |
|---|---|
| Браузер | `https://platform.local/<env>/llama/` |
| Поды окружения | `http://llama.llm-<env>.svc.cluster.local:8080/<env>/llama` |
| OpenAI API | `http://llama.llm-<env>.svc.cluster.local:8080/<env>/llama/v1` |

## Команды

- Для установки окружения: `./cluster.sh up --dev`
- Для просмотра журнала: `kubectl logs -n llm-dev deploy/llama`
- Для проброса веб-интерфейса на http://localhost:81/dev/llama/: `kubectl port-forward -n llm-dev svc/llama 81:8080`
- Для проверки API после проброса: `curl http://localhost:81/dev/llama/v1/chat/completions -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"Привет"}]}'`

## Важно

- Метрики llama.cpp (`/<env>/llama/metrics`) собирает Prometheus, графики — в дашборде Platform overview.
- Модель скачивается при первом запуске, нужен доступ к `huggingface.co`.
- Без GPU llama.cpp работает на CPU, медленнее.
- Модель (~2,6 ГиБ) целиком в VRAM не помещается при трёх окружениях: llama.cpp сам кладёт на GPU столько слоёв, сколько влезает в свободную VRAM (`gpu.layers: auto`, `--fit`), остальные считает на CPU.
- Рассуждения (thinking) включаются `thinking: true` в `values.yaml`.
- Другая модель: `llama.model` в `values.yaml` (`repository`, `name`, `quantization`), затем `./cluster.sh up`.
- Модель должна помещаться в лимит RAM и долю VRAM.
