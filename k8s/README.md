# Helm charts платформы

Каталог `k8s/<папка>` — chart одной папки. Папка задаёт namespace, путь секретов
в Vault и каталог данных:

| Вид | Папки | Namespace | Vault | Данные |
|---|---|---|---|---|
| Общие | `vcs`, `cicd`, `proxy`, `secret`, `logs`, `backup` | `<папка>` | `<папка>/<секрет>` | `volumes/<папка>/...` |
| Окружения | `db`, `mb`, `llm`, `acl`, `app` | `<папка>-<env>` | `<папка>/<env>/<секрет>` | `volumes/<папка>/<env>/...` |
| Служебные | `foundation`, `gpu` | default, kube-system | — | — |

| Chart | Что внутри |
|---|---|
| `foundation` | Namespace, NetworkPolicy, StorageClass `local`, PersistentVolume |
| `secret` | Vault, Vault Secrets Operator, список секретов |
| `proxy` | NGINX Ingress (TLS), маршруты `*.local` и `platform.local/<env>/...` |
| `gpu` | HAMi (Ubuntu) или NVIDIA device plugin (WSL2) |
| `backup` | K8up, MinIO, расписание копий |
| `logs` | Prometheus, Alertmanager, Grafana, Jaeger |
| `vcs` | GitLab, Container Registry, MinIO для объектов GitLab |
| `cicd` | Argo CD, GitLab Runner, Kyverno |
| `db` | PostgreSQL, Redis, ClickHouse, Elasticsearch и их веб-интерфейсы; в prod — ещё база GitLab |
| `mb` | Kafka, Kafka UI |
| `llm` | llama.cpp — [README](llm/README.md) |
| `acl` | Keycloak |
| `app` | Папка `/app-data` для приложений Argo CD |

Структура chart: `Chart.yaml` и `Chart.lock` (зависимости), `values.yaml` (общее),
`values-<env>.yaml` (только отличия окружения), `templates/` (только то, для чего
нет официального chart).

## Правила

- Официальный chart — в `dependencies`, настройки — под его ключом в `values.yaml`.
- Секретов в values нет: значения — в Vault, Secret — запись в `k8s/secret/values.yaml`.
- Каждому поду — `nodeSelector` `platform.node`: `core`, `llms` (llama.cpp) или `apps`.
- К подам окружения подключаются только поды того же окружения, `logs` и
  `proxy`; исключения — `environments.usedBy` в `k8s/foundation/values.yaml`
  (GitLab → PostgreSQL и Redis `db-prod`).
- Применять — только `./cluster.sh up`: Ansible передаёт логины из Vault, параметры
  GPU и Runner. Изменённый `Chart.lock` закоммитьте.

## Команды

| Действие | Команда |
|---|---|
| Применить | `./cluster.sh up` (окружение: `./cluster.sh up --dev`) |
| Проверить | `helm lint k8s/db -f k8s/db/values-dev.yaml` |
| Манифесты | `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml` |
| Отличия от кластера | `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml \| kubectl diff -n db-dev -f -` |
| Values и история релиза | `helm get values db-dev -n db-dev`, `helm history db-dev -n db-dev` |

## Где что менять

| Задача | Где |
|---|---|
| Параметр сервиса | `k8s/<папка>/values.yaml` (только для окружения — `values-<env>.yaml`) |
| Новый сервис | `dependencies` в `Chart.yaml` и его ключ в `values.yaml` |
| Новая папка | Chart в `k8s/<папка>/`; `namespaces` или `environments.folders` в `k8s/foundation/values.yaml`; релизы в `platform_releases` (`ansible/roles/platform/defaults/main.yml`) |
| Данные в `volumes/` | `volumes` или `environments.folders.<папка>.volumes` в `k8s/foundation/values.yaml` (`claim` — имя PVC из chart), каталог с `.gitkeep` |
| Секрет | `k8s/secret/values.yaml`; начальное значение — `platform_vault_seed` или Vault UI |
| База PostgreSQL для сервиса | `serviceDatabases.databases` в `k8s/db/values.yaml` (роль и база создаются при каждом `up`) |
| Веб-интерфейс | `routes` в `k8s/proxy/values.yaml`; сервис окружения работает под путём `/<env>/<сервис>` или с `stripPath: true` |
| Резервные копии | Namespace и расписание — `schedule` в `k8s/backup/values.yaml` |

Изменение секретов применяется к Vault заново — `up` попросит 3 unseal key.

## Резервные копии

K8up каждый день в 02:00 (UTC) копирует PVC namespace из `schedule.namespaces` в
MinIO (`volumes/backups/volumes/<путь данных>`, restic, пароль — Vault
`backup/restic`); пропущенную копию создают `start` и `up`.

| Действие | Команда |
|---|---|
| Список копий | `./cluster.sh backups` |
| Восстановить PVC из последней копии | `./cluster.sh restore db-dev data-postgresql-0` |
| Из конкретной копии | `./cluster.sh restore db-dev data-postgresql-0 25cda4f0` |

Команда останавливает сервисы с этим PVC, переносит текущие данные в
`.before-restore-<время>` в том же томе, восстанавливает копию и запускает
сервисы снова. Шаблоны — `k8s/backup/restore/`.
