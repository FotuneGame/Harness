# volumes: данные кластера

## Каталоги

| Каталог | Содержимое |
|---|---|
| `db/<env>/{pg,pgadmin,redis,ch,es}` | Базы окружения, в `db/prod` также база GitLab |
| `mb/<env>/kafka` | Kafka |
| `llm/<env>/llama` | Модель llama.cpp |
| `app/<env>/<приложение>` | `/app-data` приложений |
| `vcs/{gitaly,registry,minio}` | Репозитории, образы, объекты GitLab |
| `vcs/rails` | Ключи шифрования базы GitLab |
| `secret` | Vault |
| `logs/{prometheus,alertmanager,grafana}` | Метрики, тревоги, Grafana |
| `backups` | Резервные копии (`backups/volumes/<путь как здесь>`) |
| `proxy/tls` | CA и сертификат `*.local` |
| `minikube` | Ключ шифрования Secret в etcd |
| `terraform` | State Terraform |

## Команды

Из корня репозитория.

- Для просмотра размера данных: `sudo du -sh volumes/*`
- Для просмотра резервных копий: `./cluster.sh backups`
- Для восстановления PVC из копии: `./cluster.sh restore <namespace> <pvc> [ID]`
- Для полной очистки после `./cluster.sh delete`: `sudo find volumes -mindepth 1 ! -name .gitkeep ! -name README.md -delete 2>/dev/null`

## Важно

- Каталог смонтирован в узлы как `/volumes`, тома описаны в `k8s/foundation/values.yaml`.
- В Git только `.gitkeep` и этот файл.
- Удаляйте только целиком: пароли Vault (`secret`), данные баз и ключи GitLab (`vcs/rails`) связаны.
- Без `vcs/rails/gitlab-rails-secret.json` GitLab отвечает ошибкой 500.
- Владельцы файлов — пользователи контейнеров, для чтения и удаления нужен `sudo`.
