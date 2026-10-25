# llm: llama.cpp окружения

Своя llama.cpp в каждом окружении (namespace `llm-<env>`, узел `llms`): OpenAI-
совместимый API и веб-интерфейс. Официального chart нет — `templates/llama.yaml`.

## Модель по умолчанию

| Параметр | Значение |
|---|---|
| Модель | [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct) |
| Файл | [bartowski/Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF), `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` (~0,4 ГБ) |
| Имя в API (`model`) | `Qwen2.5-0.5B-Instruct` |
| Контекст | 8192 токена |
| Образ | `ghcr.io/ggml-org/llama.cpp:server-cuda` (без GPU — `:server`) |

Модель скачивается init-контейнером при первом запуске в `volumes/llm/<env>/llama`.

## Технические требования

| Ресурс | На окружение | Всего (dev, stage, prod) |
|---|---|---|
| CPU | запрос 0,5 ядра | узел `llms`: 4 ядра |
| RAM | запрос 1 ГиБ, лимит 3 ГиБ | узел `llms`: 16 ГиБ |
| Диск | модель ~0,4 ГБ, том 20 ГиБ | ~1,2 ГБ |
| VRAM (NVIDIA) | Ubuntu (HAMi) — треть доли узла, ~1,3 ГиБ; WSL2 — time-slicing без лимита | 4 ГиБ (GTX 1650) |
| Сеть | доступ к `huggingface.co` при первом запуске | — |

Без GPU llama.cpp работает на CPU (медленнее). Доля VRAM узла — `nodes.llms.vram_mib`
в `terraform/variables.tf`.

## Адреса

| Откуда | Адрес |
|---|---|
| Браузер | `https://platform.local/<env>/llama/` |
| Поды окружения | `http://llama.llm-<env>.svc.cluster.local:8080/<env>/llama` (API: `.../v1`) |

## Команды

| Действие | Команда |
|---|---|
| Состояние | `kubectl get pods -n llm-dev` |
| Журнал | `kubectl logs -n llm-dev deploy/llama` |
| Проброс веб-интерфейса | `kubectl port-forward -n llm-dev svc/llama 8080:8080` → http://localhost:8080/dev/llama/ |
| Проверка API | `curl http://localhost:8080/dev/llama/v1/chat/completions -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"Привет"}]}'` |

## Другая модель

В `values.yaml` — `llama.model`: `repository` (репозиторий GGUF на Hugging Face),
`name` и `quantization` (файл `<name>-<quantization>.gguf`), при необходимости
`storage`, `contextSize`, `resources`; затем `./cluster.sh up`. Модель должна
помещаться в RAM лимита и долю VRAM.
