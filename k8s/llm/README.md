# llm: llama.cpp окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `llm-dev`, `llm-stage`, `llm-prod` |
| Namespace | `llm-<env>` |
| Узел | `llms` |
| Chart | свой (`templates/llama.yaml`) |
| Образ | `ghcr.io/ggml-org/llama.cpp:server`, с GPU — `:server-cuda` |
| Данные | `volumes/llm/<env>/llama` |

## Модель по умолчанию

| Параметр | Значение |
|---|---|
| Модель | [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) |
| Файл | [bartowski/Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF), `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` (~0,4 ГБ) |
| Имя в API (`model`) | `Qwen2.5-0.5B-Instruct` |
| Контекст | 8192 токена |

## Ресурсы

| Ресурс | На окружение | Узел `llms` |
|---|---|---|
| CPU | 0,5 ядра (запрос) | 4 ядра |
| RAM | 1 ГиБ запрос, 3 ГиБ лимит | 16 ГиБ |
| Диск | ~0,4 ГБ модель, том 20 ГиБ | 200 ГБ |
| VRAM | ~1,3 ГиБ (Ubuntu), без лимита (WSL2) | 4 ГиБ |

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

- Модель скачивается при первом запуске, нужен доступ к `huggingface.co`.
- Без GPU llama.cpp работает на CPU, медленнее.
- Другая модель: `llama.model` в `values.yaml` (`repository`, `name`, `quantization`), затем `./cluster.sh up`.
- Модель должна помещаться в лимит RAM и долю VRAM.
