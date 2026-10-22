# node-example

Шаблон бэкенда на Node.js 24 + NestJS для платформы из корня репозитория.
Подключения ко всем сервисам кластера уже настроены, CI/CD собирает образ и
разворачивает его через Argo CD в namespace `app` (узел apps).

## Что где

| Файл | Назначение |
|---|---|
| `src/config.ts` | Все настройки — переменные окружения |
| `src/connections/` | Подключения: Redis, ClickHouse, Elasticsearch, Kafka, MinIO (S3), llama.cpp, Keycloak |
| `src/app.module.ts` | PostgreSQL (TypeORM) |
| `src/tracing.ts` | Трейсы в Jaeger |
| `src/metrics/` | `/metrics` для Prometheus |
| `src/health/` | `/health` — состояние всех подключений |
| `src/auth/` | Вход по токену Keycloak (`@UseGuards(AuthGuard)`) |
| `src/notes/` | Пример: заметки, которые используют все сервисы |
| `deploy/` | Helm chart для Argo CD, `values-<env>.yaml` — окружения |
| `.gitlab-ci.yml` | Проверка → образ в registry.local → развёртывание |

Новый модуль: скопируйте `src/notes/`, подключения берите через конструктор
(`private readonly redis: RedisService`). Сервис без адреса в окружении
выключен: `enabled = false`, `/health` показывает `disabled`.

## Сервисы

| Сервис | Учётка (Vault) | В коде |
|---|---|---|
| PostgreSQL | `app/postgresql`, база = логин | TypeORM, `*.entity.ts` |
| Redis | `db/redis` | `RedisService.client` (ioredis) |
| ClickHouse | `app/clickhouse`, база = логин | `ClickHouseService.client` |
| Elasticsearch | без пароля | `ElasticsearchService.client` |
| Kafka | без пароля | `KafkaService.send()`, `subscribe()` |
| MinIO (S3) | `app/minio`, bucket `app` | `S3Service.put()`, `get()` |
| llama.cpp | без пароля | `LlmService.chat()` |
| Keycloak | без пароля (ключи realm) | `AuthGuard`, `KeycloakService` |
| Jaeger, Prometheus | — | автоматически |
| Папка `/app-data` | — | `config.appDataPath` |

Учётки `app/*` создаёт платформа при `./cluster.sh up` и передаёт в namespace
`app` как Secret. Пароли не хранятся в коде и `deploy/`.

## Локальный запуск

Нужны Node.js 24 и доступ `kubectl` к кластеру. В одном терминале:

```bash
npm install
npm run dev
```

`npm run dev` пишет `.env` с паролями и пробрасывает порты сервисов. Во втором
терминале:

```bash
npm start
```

API: http://localhost:3000/docs, состояние: http://localhost:3000/health.
Kafka локально недоступна (выключена в `.env`), остальные сервисы работают.

## Развёртывание

Один раз:

1. В GitLab создайте проект (например, `group/node-example`) и отправьте код.
   GitLab Runner должен быть включён (`cicd/gitlab-runner` в Vault).
2. Project access token (Settings → Access tokens, роль Developer, scope
   `write_repository`) → переменная CI/CD `GITOPS_TOKEN` (Masked).
3. Deploy token для образов (Settings → Repository → Deploy tokens, scope
   `read_registry`) и Secret в namespace `app`:

   ```bash
   kubectl create secret docker-registry gitlab-registry -n app --docker-server=registry.local \
     --docker-username=<имя deploy token> --docker-password=<deploy token>
   ```

4. Доступ Argo CD к GitLab — путь `cicd/argocd-gitlab` в Vault (README платформы).
5. Замените `group/node-example` на путь проекта в `deploy/values.yaml` и
   `deploy/argocd.yaml`, затем:

   ```bash
   kubectl apply -f deploy/argocd.yaml
   ```

Дальше каждый push в основную ветку: проверка, образ
`registry.local/<проект>:<commit>`, его тег в `deploy/values-dev.yaml`, Argo CD
обновляет под. Stage — ручной запуск `deploy-stage` в pipeline, prod — тег Git
и ручной `deploy-prod` (нужны свои Application, см. `deploy/argocd.yaml`).

Проверка в кластере:

```bash
kubectl port-forward -n app svc/node-example 3000:80
```

## Важно

- Таблицы PostgreSQL создаются по `*.entity.ts` при запуске (`synchronize`).
  Когда данные станут важными, перейдите на миграции TypeORM.
- Окружения в одном кластере используют общие базы `app`; Kafka-группы,
  трейсы и метрики разделены по имени Application.
- kafkajs на Node.js 24 при запуске печатает `TimeoutNegativeWarning` — это
  безвредно.
- Токен для `/me`: войдите в Keycloak (https://keycloak.local, realm `master`),
  создайте клиента и получите access token; метод проверяет подпись и издателя.
