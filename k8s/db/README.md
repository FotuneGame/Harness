# db: базы данных окружения

## Состав

| Параметр | Значение |
|---|---|
| Релизы | `db-dev`, `db-stage`, `db-prod` |
| Namespace | `db-<env>` |
| Узел | `core` |
| Charts | [postgresql](https://github.com/bitnami/charts/tree/main/bitnami/postgresql), [redis](https://github.com/bitnami/charts/tree/main/bitnami/redis), [clickhouse](https://github.com/bitnami/charts/tree/main/bitnami/clickhouse), [elasticsearch](https://github.com/bitnami/charts/tree/main/bitnami/elasticsearch), [kibana](https://github.com/bitnami/charts/tree/main/bitnami/kibana), [pgadmin4](https://github.com/rowanruseler/helm-charts) |
| `templates/service-databases.yaml` | Роли и базы сервисов (Keycloak, GitLab) |
| `templates/clickhouse-database.yaml` | База ClickHouse пользователя |
| `templates/redisinsight.yaml` | RedisInsight |
| Данные | `volumes/db/<env>/{pg,pgadmin,redis,ch,es}` |

## Адреса

| Сервис | Внутренний адрес | Веб-интерфейс | Vault |
|---|---|---|---|
| PostgreSQL | `postgresql.db-<env>:5432` | `https://platform.local/<env>/pgadmin` | `db/<env>/postgresql`, `db/<env>/pgadmin` |
| Redis | `redis-master.db-<env>:6379` | `https://platform.local/<env>/redis` | `db/<env>/redis` |
| ClickHouse | `clickhouse.db-<env>:8123` | `https://platform.local/<env>/clickhouse/play` | `db/<env>/clickhouse` |
| Elasticsearch | `elasticsearch.db-<env>:9200` | `https://platform.local/<env>/kibana` | — |

## Команды

- Для установки окружения: `./cluster.sh up --dev`
- Для проброса PostgreSQL: `kubectl port-forward -n db-dev svc/postgresql 5432:5432`
- Для восстановления базы из копии: `./cluster.sh restore db-dev data-postgresql-0`

## Важно

- В `db-prod` также база `gitlabhq_production` и Redis-база 1 для GitLab.
- Без `--prod` в `db-prod` ставятся только PostgreSQL и Redis (`allServices=false`).
- Новая база для сервиса — `serviceDatabases.databases` в `values.yaml`, создаётся при каждом `up`.
- ClickHouse Play: `https://platform.local/<env>/clickhouse/play?url=https://platform.local/<env>/clickhouse/`.
- Изменение пароля в Vault не меняет уже созданных пользователей.
