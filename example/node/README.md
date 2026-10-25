# node-example

Шаблон бэкенда на Node.js 24 + NestJS с готовыми подключениями к сервисам
платформы. CI/CD собирает образ, Argo CD разворачивает его в `app-<env>`.

| Путь | Назначение |
|---|---|
| `src/config.ts` | Настройки — переменные окружения |
| `src/connections/` | Redis, ClickHouse, Elasticsearch, Kafka, llama.cpp, Keycloak, S3 |
| `src/app.module.ts` | PostgreSQL (TypeORM) |
| `src/notes/` | Пример модуля, использующего все сервисы |
| `src/health/`, `src/metrics/`, `src/tracing.ts` | `/health`, `/metrics` (Prometheus), трейсы (Jaeger) |
| `src/auth/` | Вход по токену Keycloak (`@UseGuards(AuthGuard)`) |
| `test/` | Тесты Jest, сервисы заменены заглушками |
| `deploy/` | Helm chart и Application Argo CD, `values-<env>.yaml` — окружения |
| `.gitlab-ci.yml` | Проверка, тесты → образ → развёртывание |

## Сервисы окружения

Адреса — в `deploy/values.yaml`, пароли — Secret из Vault `db/<env>/*`.
Сервис без адреса выключен: `/health` показывает `disabled`.

| Сервис | Адрес (`*.svc.cluster.local`) | Secret |
|---|---|---|
| PostgreSQL | `postgresql.db-<env>:5432` | `postgresql-credentials` |
| Redis | `redis-master.db-<env>:6379` | `redis-credentials` |
| ClickHouse | `clickhouse.db-<env>:8123` | `clickhouse-credentials` |
| Elasticsearch | `elasticsearch.db-<env>:9200` | — |
| Kafka | `kafka.mb-<env>:9092` | — |
| llama.cpp | `llama.llm-<env>:8080/<env>/llama` | — |
| Keycloak | `keycloak.acl-<env>:8080/<env>/keycloak` | — |
| Jaeger | `jaeger.logs:4318` | — |
| Папка `/app-data` | `volumes/app/<env>/<приложение>` | — |

S3 в окружениях нет, `S3Service` выключен.

## Команды

| Действие | Команда |
|---|---|
| Зависимости | `npm install` |
| Порты и `.env` окружения dev (терминал 1) | `npm run dev` |
| Запуск (терминал 2) | `npm start` → http://localhost:3000/docs |
| Тесты (без кластера) | `npm test` |
| Проверка кода | `npm run lint` |
| Приложение в кластере | `kubectl port-forward -n app-dev svc/node-example 3000:80` |

## Развёртывание

Один раз:

1. Проект в GitLab, код отправлен; GitLab Runner включён (Vault `cicd/gitlab-runner`).
2. Project access token (Maintainer, `write_repository`) → переменная CI/CD
   `GITOPS_TOKEN` (Masked).
3. Deploy token (`read_registry`) → Vault `vcs/registry`, затем `./cluster.sh up`.
4. Доступ Argo CD к GitLab — Vault `cicd/argocd-gitlab`.
5. Путь проекта — в `image` (`deploy/values.yaml`) и `repoURL` (`deploy/argocd-*.yaml`).
6. После первого pipeline: `kubectl apply -f deploy/argocd-dev.yaml` (для stage и
   prod — после их первого развёртывания).

| Окружение | Когда развёртывается |
|---|---|
| dev | Каждый push в основную ветку |
| stage | Ручной `deploy-stage` в pipeline |
| prod | Тег Git и ручной `deploy-prod` |

Таблицы PostgreSQL создаются по `*.entity.ts` при запуске (`synchronize`): для
важных данных перейдите на миграции TypeORM.
