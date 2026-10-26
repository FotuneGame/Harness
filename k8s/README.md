# k8s: Helm charts платформы

## Charts

| Chart | Namespace | Сервисы | README |
|---|---|---|---|
| `foundation` | `default` | Namespace, NetworkPolicy, StorageClass `local`, PersistentVolume | [foundation](foundation/README.md) |
| `secret` | `secret` | Vault, Vault Secrets Operator | [secret](secret/README.md) |
| `proxy` | `proxy` | NGINX Ingress, маршруты `*.local` | [proxy](proxy/README.md) |
| `gpu` | `kube-system` | HAMi или NVIDIA device plugin | [gpu](gpu/README.md) |
| `logs` | `logs` | Prometheus, Alertmanager, Grafana, Jaeger | [logs](logs/README.md) |
| `backup` | `backup` | K8up, MinIO | [backup](backup/README.md) |
| `vcs` | `vcs` | GitLab, Container Registry, MinIO | [vcs](vcs/README.md) |
| `cicd` | `cicd` | Argo CD, GitLab Runner, Kyverno | [cicd](cicd/README.md) |
| `db` | `db-<env>` | PostgreSQL, Redis, ClickHouse, Elasticsearch, веб-интерфейсы | [db](db/README.md) |
| `mb` | `mb-<env>` | Kafka, Kafka UI | [mb](mb/README.md) |
| `llm` | `llm-<env>` | llama.cpp | [llm](llm/README.md) |
| `acl` | `acl-<env>` | Keycloak | [acl](acl/README.md) |
| `app` | `app-<env>` | Папка `/app-data` приложений | [app](app/README.md) |

## Папки

| Вид | Папки | Namespace | Vault | Данные |
|---|---|---|---|---|
| Общие | `vcs`, `cicd`, `proxy`, `secret`, `logs`, `backup` | `<папка>` | `<папка>/<секрет>` | `volumes/<папка>/...` |
| Окружения | `db`, `mb`, `llm`, `acl`, `app` | `<папка>-<env>` | `<папка>/<env>/<секрет>` | `volumes/<папка>/<env>/...` |
| Служебные | `foundation`, `gpu` | `default`, `kube-system` | — | — |

## Структура chart

| Файл | Содержимое |
|---|---|
| `Chart.yaml`, `Chart.lock` | Зависимости |
| `values.yaml` | Общие настройки |
| `values-<env>.yaml` | Отличия окружения |
| `templates/` | Ресурсы без официального chart |

## Где что менять

| Задача | Где |
|---|---|
| Параметр сервиса | `k8s/<папка>/values.yaml`, для окружения — `values-<env>.yaml` |
| Новый сервис | `dependencies` в `Chart.yaml`, ключ в `values.yaml` |
| Новая папка | `k8s/<папка>/`, `k8s/foundation/values.yaml`, `platform_releases` в `ansible/roles/platform/defaults/main.yml` |
| Данные в `volumes/` | `volumes` или `environments.folders.<папка>.volumes` в `k8s/foundation/values.yaml` |
| Секрет | `k8s/secret/values.yaml`, значение — Vault UI или `platform_vault_seed` |
| База PostgreSQL для сервиса | `serviceDatabases.databases` в `k8s/db/values.yaml` |
| Веб-интерфейс | `routes` в `k8s/proxy/values.yaml` |
| Резервные копии | `schedule` в `k8s/backup/values.yaml` |

## Команды

Из корня репозитория.

- Для применения изменений всех charts: `./cluster.sh up`
- Для применения изменений одного окружения: `./cluster.sh up --dev`
- Для проверки chart: `helm lint k8s/db -f k8s/db/values-dev.yaml`
- Для просмотра манифестов: `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml`
- Для сравнения с кластером: `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml | kubectl diff -n db-dev -f -`
- Для просмотра values релиза: `helm get values db-dev -n db-dev`
- Для просмотра истории релиза: `helm history db-dev -n db-dev`

## Важно

- Применять только через `./cluster.sh up`: Ansible передаёт логины из Vault, параметры GPU и Runner.
- Изменённый `Chart.lock` закоммитьте.
- Секретов в values нет: значения в Vault, Secret — запись в `k8s/secret/values.yaml`.
- Каждому поду нужен `nodeSelector` `platform.node`: `core`, `llms` или `apps`.
- К подам окружения подключаются только поды того же окружения, `logs` и `proxy`; исключения — `environments.usedBy` в `k8s/foundation/values.yaml`.
- Изменение секретов применяется к Vault заново, `up` попросит 3 unseal key.
