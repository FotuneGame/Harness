# Helm charts платформы

Каждый каталог — chart одного namespace. Окружение (dev, stage, prod) выбирается
при развёртывании: `./cluster.sh up <env>`.

## Структура chart

```
k8s/<chart>/
  Chart.yaml          официальные charts — в dependencies
  Chart.lock          зафиксированные версии зависимостей
  values.yaml         общие значения для всех окружений
  values-dev.yaml     только отличия dev
  values-stage.yaml   только отличия stage
  values-prod.yaml    только отличия prod
  templates/          только то, для чего нет официального chart
  charts/             скачанные зависимости (не в Git, кроме secret)
```

| Chart | Namespace | Релиз | Что внутри |
|---|---|---|---|
| `foundation` | default | `platform-foundation` | Namespace, StorageClass `local`, PersistentVolume |
| `secret` | secret | `platform-secret` | Vault, Vault Secrets Operator, синхронизация секретов |
| `proxy` | proxy | `platform-proxy` | NGINX Ingress, маршруты `*.local` |
| `gpu` | kube-system | `platform-gpu` | HAMi (Ubuntu, лимиты VRAM) или NVIDIA device plugin (WSL2) |
| `db` | db | `platform-db` | PostgreSQL, pgAdmin, Redis, RedisInsight, ClickHouse, Elasticsearch |
| `mb` | mb | `platform-mb` | Kafka, Kafka UI |
| `acl` | acl | `platform-acl` | Keycloak |
| `backup` | backup | `platform-backup` | MinIO, K8up |
| `llm` | llm | `platform-llm` | llama.cpp, Open WebUI |
| `logs` | logs | `platform-logs` | Prometheus, Alertmanager, Grafana, Jaeger, exporters |
| `vcs` | vcs | `gitlab` | GitLab, Container Registry |
| `cicd` | cicd | `platform-cicd` | Argo CD, GitLab Runner, Kyverno |
| `app` | app | `platform-app` | PVC `app-data`, политика Kyverno: папка `volumes/app/<приложение>` в `/app-data` |

## Правила

1. Есть официальный chart — подключайте его в `dependencies` в `Chart.yaml` с
   `condition: <имя>.enabled`, настройки пишите под ключом `<имя>:` в
   `values.yaml`. Свои шаблоны в `templates/` — только если официального chart нет.
2. Общее — в `values.yaml`, в `values-<env>.yaml` — только то, что отличается
   (реплики, ресурсы, лимиты). Не копируйте `values.yaml` целиком.
3. Секретов в values нет. Значение хранится в Vault, Secret создаётся записью в
   `k8s/secret/values.yaml`, а сервис ссылается на него (`existingSecret` и т. п.).
4. Каждому поду нужен `nodeSelector: { platform.node: core }` (или `llms` для
   LLM). Поды в namespace `app` попадают на узел apps и получают папку
   `volumes/app/<приложение>` в `/app-data` автоматически (chart `app`).
5. Версии фиксированы: в `Chart.yaml` — версия chart, в values — тег образа
   (кроме уже используемых `latest`/`main`). После смены версии закоммитьте
   `Chart.lock`, который обновит `./cluster.sh up`.

## Команды

Из корня репозитория.

| Действие | Команда |
|---|---|
| Применить все charts для окружения | `./cluster.sh up dev` (или `stage`, `prod`) |
| Проверить шаблоны | `helm lint k8s/db -f k8s/db/values-dev.yaml` |
| Посмотреть итоговые манифесты | `helm template platform-db k8s/db -n db -f k8s/db/values-dev.yaml` |
| Сравнить с кластером до применения | `helm template platform-db k8s/db -n db -f k8s/db/values-dev.yaml \| kubectl diff -n db -f -` |
| Применить один chart | `helm upgrade --install platform-db k8s/db -n db -f k8s/db/values-dev.yaml --take-ownership --wait` |
| Текущие values релиза | `helm get values platform-db -n db` |
| История и откат | `helm history platform-db -n db`, `helm rollback platform-db <ревизия> -n db` |

`llm`, `cicd`, `gpu` и `secret` применяйте только через `./cluster.sh up`: для
них Ansible добавляет параметры (GPU, Runner, доли VRAM) и настраивает Vault.

Зависимости (`charts/*.tgz`) `./cluster.sh up` приводит к `Chart.yaml` сам:
добавляет Helm-репозитории, скачивает недостающие архивы, удаляет лишние и при
изменённом `Chart.yaml` пересоздаёт `Chart.lock` — закоммитьте его. Архивы chart
`secret` лежат в Git (`helm.releases.hashicorp.com` недоступен), их не меняйте.

## Изменить сервис

1. Найдите параметр в `values.yaml` chart (для официального chart — в его
   документации или `helm show values <repo>/<chart>`).
2. Общее изменение — в `values.yaml`, только для окружения — в `values-<env>.yaml`:

   ```yaml
   # k8s/logs/values-prod.yaml
   kube-prometheus-stack:
     prometheus:
       prometheusSpec:
         retention: 30d
   ```

3. Проверьте `helm template` / `kubectl diff`, затем `./cluster.sh up prod`.

## Добавить сервис в существующий namespace

1. Подключите chart в `k8s/<chart>/Chart.yaml`:

   ```yaml
   dependencies:
     - name: mongodb
       version: 16.5.0
       repository: oci://registry-1.docker.io/bitnamicharts
       condition: mongodb.enabled
   ```

2. Добавьте настройки в `values.yaml` под ключом `mongodb:` (`fullnameOverride`,
   `nodeSelector`, ресурсы, `existingSecret`).
3. Если нужны данные — см. «Хранение данных», пароль — «Секреты», веб-интерфейс —
   «Адрес *.local».
4. `./cluster.sh up <env>`: зависимость скачается, `Chart.lock` обновится —
   закоммитьте его.

## Добавить новый namespace

1. Скопируйте структуру любого chart в `k8s/<имя>/` (Chart.yaml, values.yaml,
   три `values-<env>.yaml`).
2. Добавьте namespace в список `namespaces` в `k8s/foundation/values.yaml`.
3. Добавьте релиз в `platform_releases` в
   `ansible/roles/platform/defaults/main.yml` — порядок списка = порядок установки:

   ```yaml
   - { name: platform-<имя>, chart: <имя> }
   ```

4. `./cluster.sh up <env>`.

## Хранение данных

Данные хранятся в `volumes/` через заранее созданные PersistentVolume:

1. Добавьте том в `volumes` в `k8s/foundation/values.yaml`:

   ```yaml
   - { name: pv-db-mongo, size: 5Gi, path: db/mongo, claim: db/mongodb }
   ```

   `claim` — namespace и точное имя PVC, которое создаст chart (смотрите в
   `helm template ... | grep -A3 "kind: PersistentVolumeClaim"`); `node: llms` —
   если сервис работает на узле llms.
2. Создайте `volumes/db/mongo/.gitkeep`.
3. В values сервиса укажите `storageClass: local` и тот же размер.

## Секреты

1. Добавьте Secret в `k8s/secret/values.yaml`:

   ```yaml
   secrets:
     db:
       mongodb-credentials: { path: db/mongodb }
   ```

   Namespace получит доступ только к перечисленным путям Vault.
2. Значение: на новом кластере — добавьте путь в `platform_vault_seed`
   (`ansible/roles/platform/defaults/main.yml`, `null` — случайный пароль); на
   работающем — запишите его в Vault UI (https://vault.local, путь `kv/db/mongodb`).
3. Сошлитесь на Secret `mongodb-credentials` из values сервиса.

Политики Vault создаются при его инициализации. Для нового namespace или пути на
работающем кластере добавьте политику и роль вручную (root token через
`vault operator generate-root`) или пересоздайте кластер с очисткой `volumes/`.

## Адрес *.local

Добавьте маршрут в `routes` в `k8s/proxy/values.yaml`:

```yaml
- { host: mongo.local, namespace: db, service: mongo-express, port: 8081 }
```

`./cluster.sh up` сам пропишет имя в hosts и перевыпустит TLS-сертификат.
