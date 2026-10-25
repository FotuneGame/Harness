# volumes: данные кластера

Каталог смонтирован в узлы как `/volumes`; PersistentVolume описаны в
`k8s/foundation/values.yaml`. В Git — только `.gitkeep` и этот файл.

| Каталог | Что хранится |
|---|---|
| `db/<env>/{pg,pgadmin,redis,ch,es}` | PostgreSQL, pgAdmin, Redis, ClickHouse, Elasticsearch окружения (в `db/prod` — ещё база GitLab) |
| `mb/<env>/kafka` | Kafka окружения |
| `llm/<env>/llama` | Модель llama.cpp (скачивается сама) |
| `app/<env>/<приложение>` | Папка `/app-data` своих приложений |
| `vcs/{gitaly,registry,minio}` | Репозитории GitLab, образы Container Registry, объекты GitLab |
| `vcs/rails` | Ключи шифрования базы GitLab (без них GitLab — ошибка 500) |
| `secret` | Данные Vault |
| `logs/{prometheus,alertmanager,grafana}` | Метрики, тревоги, Grafana |
| `backups` | MinIO с резервными копиями (`backups/volumes/<путь как здесь>`) |
| `proxy/tls` | CA и сертификат `*.local` |
| `minikube` | Ключ шифрования Secret в etcd |
| `terraform` | State Terraform |

## Команды

Из корня репозитория.

| Действие | Команда |
|---|---|
| Размер данных | `sudo du -sh volumes/*` |
| Список копий и восстановление | `./cluster.sh backups`, `./cluster.sh restore <namespace> <pvc> [ID]` |
| Полная очистка (сначала `./cluster.sh delete`) | `sudo find volumes -mindepth 1 ! -name .gitkeep ! -name README.md -delete 2>/dev/null` |

## Важно

- Удаляйте каталог только целиком: пароли в Vault (`secret`), данные баз и ключи
  GitLab (`vcs/rails`) связаны между собой.
- Права на каталоги выставляет `./cluster.sh up`; владельцы файлов — пользователи
  контейнеров, поэтому для чтения и удаления нужен `sudo`.
