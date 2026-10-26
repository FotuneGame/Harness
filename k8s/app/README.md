# app: приложения окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `app-dev`, `app-stage`, `app-prod` |
| Namespace | `app-<env>` |
| Узел | `apps` (taint `workload=apps:NoSchedule`) |
| Chart | свой (`templates/app-data.yaml`) |
| PVC | `app-data`, 20 ГиБ, ReadWriteMany |
| Папка в поде | `/app-data` |
| Данные | `volumes/app/<env>/<приложение>` |

## Secret в namespace

| Secret | Vault |
|---|---|
| `postgresql-credentials` | `db/<env>/postgresql` |
| `redis-credentials` | `db/<env>/redis` |
| `clickhouse-credentials` | `db/<env>/clickhouse` |
| `gitlab-registry` | `vcs/registry` |

## Команды

- Для установки окружения: `./cluster.sh up --dev`
- Для просмотра приложений: `kubectl get pods -n app-dev`
- Для проверки Secret образов: `kubectl get secret -n app-dev gitlab-registry`

## Важно

- Приложения разворачивает Argo CD, пример — [example/node](../../example/node/README.md).
- Поду нужен `nodeSelector: { platform.node: apps }`, toleration узла `apps` namespace добавляет сам.
- Имя папки — метка `app.kubernetes.io/instance`, иначе `app.kubernetes.io/name`, иначе `app`, иначе `shared`.
- `/app-data` монтирует политика Kyverno, вручную том не добавляется.
