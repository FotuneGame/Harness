# Helm charts платформы

Каталог `k8s/<папка>` — chart одной папки. Папка задаёт namespace, путь
секретов в Vault и каталог данных в `volumes/`:

| Вид | Папки | Namespace | Vault | Данные |
|---|---|---|---|---|
| Общие (один экземпляр) | `vcs`, `cicd`, `proxy`, `secret`, `logs`, `backup` | `<папка>` | `<папка>/<секрет>` | `volumes/<папка>/...` |
| Окружения dev, stage, prod | `db`, `mb`, `llm`, `acl`, `app` | `<папка>-<env>` | `<папка>/<env>/<секрет>` | `volumes/<папка>/<env>/...` |
| Служебные | `foundation`, `gpu` | default, kube-system | — | — |

`./cluster.sh up` разворачивает все общие charts и все три окружения, `./cluster.sh up
--dev` (`--stage`, `--prod`, можно несколько) — общие charts и выбранные окружения.
`db-prod` ставится всегда: в его PostgreSQL и Redis работает GitLab (без prod —
только они, `allServices: false`).

## Структура chart

```
k8s/<папка>/
  Chart.yaml          официальные charts — в dependencies
  Chart.lock          зафиксированные версии зависимостей
  values.yaml         общие значения (для окружений — общие для dev, stage, prod)
  values-<env>.yaml   только отличия окружения (charts окружений)
  templates/          только то, для чего нет официального chart
  charts/             скачанные зависимости (не в Git, кроме secret)
```

| Chart | Namespace | Релиз | Что внутри |
|---|---|---|---|
| `foundation` | default | `platform-foundation` | Namespace, NetworkPolicy окружений (и доступ общих сервисов — `usedBy`), StorageClass `local`, PersistentVolume |
| `secret` | secret | `platform-secret` | Vault, Vault Secrets Operator, синхронизация секретов |
| `proxy` | proxy | `platform-proxy` | NGINX Ingress (TLS), маршруты, DaemonSet `node-hosts` (имена `*.local` и CA для Docker узлов) |
| `gpu` | kube-system | `platform-gpu` | HAMi (Ubuntu, лимиты VRAM) или NVIDIA device plugin (WSL2) |
| `backup` | backup | `platform-backup` | K8up, MinIO; Schedule резервного копирования во всех namespace с данными |
| `logs` | logs | `platform-logs` | Prometheus, Alertmanager, Grafana (дашборды), Jaeger |
| `vcs` | vcs | `gitlab` | GitLab, Container Registry, MinIO для объектов GitLab |
| `cicd` | cicd | `platform-cicd` | Argo CD, GitLab Runner, Kyverno |
| `db` | db-`<env>` | `db-<env>` | PostgreSQL + pgAdmin, Redis + RedisInsight, ClickHouse, Elasticsearch + Kibana; базы сервисов из других namespace (Keycloak, в prod — GitLab) |
| `mb` | mb-`<env>` | `mb-<env>` | Kafka + Kafka UI |
| `llm` | llm-`<env>` | `llm-<env>` | llama.cpp (API и веб-интерфейс) |
| `acl` | acl-`<env>` | `acl-<env>` | Keycloak (база — PostgreSQL окружения) |
| `app` | app-`<env>` | `app-<env>` | Папка `/app-data` для приложений из Argo CD (PVC и политика Kyverno) |

## Правила

1. Есть официальный chart — подключайте его в `dependencies` в `Chart.yaml`,
   настройки пишите под ключом `<имя>:` в `values.yaml`. Свои шаблоны в
   `templates/` — только если официального chart нет (llama.cpp, RedisInsight,
   Registry).
2. Общее — в `values.yaml`, в `values-<env>.yaml` — только то, что отличается
   (пути веб-интерфейсов, адреса, ресурсы). Не копируйте `values.yaml` целиком.
3. Секретов в values нет. Значение хранится в Vault, Secret создаётся записью в
   `k8s/secret/values.yaml`, а сервис ссылается на него (`existingSecret` и т. п.).
4. Каждому поду нужен `nodeSelector`: `platform.node: core` — все сервисы,
   `llms` — llama.cpp, `apps` — свои приложения в `app-<env>`.
5. Сеть окружения закрыта: к подам `<папка>-<env>` подключаются только поды
   того же окружения (метка namespace `platform.env`) и namespace `logs`, `proxy`.
   Исключения — `environments.usedBy` в `k8s/foundation/values.yaml` (`vcs` →
   `db-prod`); `stop`/`delete --<env>` не трогают перечисленные там сервисы.
6. Версии фиксированы: в `Chart.yaml` — версия chart, в values — тег образа
   (кроме уже используемых `latest`/`main`). После смены версии закоммитьте
   `Chart.lock`, который обновит `./cluster.sh up`.

## Команды

Из корня репозитория.

| Действие | Команда |
|---|---|
| Применить все charts | `./cluster.sh up` (только окружение: `./cluster.sh up --dev`) |
| Проверить шаблоны | `helm lint k8s/db -f k8s/db/values-dev.yaml` |
| Посмотреть итоговые манифесты | `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml` |
| Сравнить с кластером до применения | `helm template db-dev k8s/db -n db-dev -f k8s/db/values-dev.yaml \| kubectl diff -n db-dev -f -` |
| Текущие values релиза | `helm get values db-dev -n db-dev` |
| История и откат | `helm history db-dev -n db-dev`, `helm rollback db-dev <ревизия> -n db-dev` |

Применяйте charts через `./cluster.sh up`: Ansible передаёт логины из Vault,
параметры GPU и Runner и настраивает Vault.

Зависимости (`charts/*.tgz`) `./cluster.sh up` приводит к `Chart.yaml` сам:
добавляет Helm-репозитории, скачивает недостающие архивы, удаляет лишние и при
изменённом `Chart.yaml` пересоздаёт `Chart.lock` — закоммитьте его. Архивы chart
`secret` лежат в Git (`helm.releases.hashicorp.com` недоступен), их не меняйте.

## Изменить сервис

1. Найдите параметр в `values.yaml` chart (для официального chart — в его
   документации или `helm show values <repo>/<chart>`).
2. Для всех окружений — в `values.yaml`, только для одного — в `values-<env>.yaml`:

   ```yaml
   # k8s/db/values-prod.yaml
   elasticsearch:
     master:
       heapSize: 1g
   ```

3. Проверьте `helm template` / `kubectl diff`, затем `./cluster.sh up`.

## Добавить сервис

1. Подключите chart в `k8s/<папка>/Chart.yaml`:

   ```yaml
   dependencies:
     - name: mongodb
       version: 16.5.0
       repository: oci://registry-1.docker.io/bitnamicharts
   ```

2. Добавьте настройки в `values.yaml` под ключом `mongodb:` (`fullnameOverride`,
   `nodeSelector`, ресурсы, `existingSecret`).
3. Данные, пароль, веб-интерфейс — разделы ниже.
4. `./cluster.sh up`: зависимость скачается, `Chart.lock` обновится — закоммитьте его.

## Добавить папку

1. Скопируйте структуру chart в `k8s/<папка>/` (для окружений — с тремя
   `values-<env>.yaml`).
2. В `k8s/foundation/values.yaml`: общая — в `namespaces`, окружений — ключ
   `<папка>: {}` в `environments.folders`.
3. Релизы — в `platform_releases` в `ansible/roles/platform/defaults/main.yml`
   (порядок списка = порядок установки):

   ```yaml
   - { name: platform-<папка>, chart: <папка> }                            # общая
   - { name: <папка>-dev, chart: <папка>, namespace: <папка>-dev, env: dev }  # и stage, prod
   ```

4. Резервные копии — namespace в `schedule.namespaces` в `k8s/backup/values.yaml`.
5. `./cluster.sh up`.

## Хранение данных

Данные хранятся в `volumes/` через заранее созданные PersistentVolume
(`k8s/foundation/values.yaml`):

- окружений — в `environments.folders.<папка>.volumes`, каталог
  `volumes/<папка>/<env>/<path>`, PV `pv-<папка>-<env>-<path>`:

  ```yaml
  db:
    volumes:
      - { path: mongo, claim: datadir-mongodb-0, size: 5Gi }
  ```

- общих сервисов — в `volumes`, каталог `volumes/<path>`, PV `pv-<path через дефис>`:

  ```yaml
  - { path: vcs/mongo, claim: vcs/datadir-mongodb-0, size: 5Gi }
  ```

`claim` — точное имя PVC, которое создаст chart (`helm template ... | grep -A3
"kind: PersistentVolumeClaim"`); узел не core — `node: llms` или `apps` (у
окружений — у папки). Создайте каталоги с `.gitkeep` (для окружений — в dev, stage и prod);
права на запись `./cluster.sh up` выставит сам. В values сервиса укажите
`storageClass: local` и тот же размер.

## Резервные копии

K8up раз в сутки (02:00) копирует PVC каждого namespace из
`schedule.namespaces` (`k8s/backup/values.yaml`) в MinIO namespace `backup`.
Каталог копии повторяет каталог данных: `volumes/db/dev` →
`volumes/backups/volumes/db/dev` (репозиторий restic, пароль — Vault
`backup/restic`). Хранятся 7 последних и 7 ежедневных копий. Если в 02:00
сервер был выключен, копию создадут `./cluster.sh start` и `up` (когда за сутки
успешной не было). Кроме данных сервисов копируются файлы сервера:
`volumes/proxy/tls` (CA и сертификат `*.local`) и `volumes/vcs/rails` (ключи
шифрования базы GitLab) — PV с `hostFiles: true` в `k8s/foundation/values.yaml`.
Без копий: `cicd`, `acl-<env>` (данных нет, Keycloak хранит всё в PostgreSQL
окружения), `llm-<env>` (модели скачиваются заново), `backup`. Восстановление
PVC из копии: ID копии — `kubectl get snapshots -n db-dev` (столбец с путём
`/data/<PVC>`), затем остановите сервис и выполните:

```bash
kubectl apply -n db-dev -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: restore-pg
spec:
  snapshot: <ID>
  podSecurityContext:
    runAsUser: 0
  restoreMethod:
    folder:
      claimName: data-postgresql-0
  backend:
    s3:
      bucket: volumes/db/dev
EOF
```

## Секреты

1. Добавьте Secret в `k8s/secret/values.yaml` (путь — по папке):

   ```yaml
   secrets:
     db-dev:
       mongodb-credentials: { path: db/dev/mongodb }
   ```

   Namespace получит доступ только к перечисленным путям Vault.
2. Начальное значение — путь в `platform_vault_seed`
   (`ansible/roles/platform/defaults/main.yml`, `null` — случайный пароль), или
   запишите его в Vault UI (https://vault.local, путь `kv/db/dev/mongodb`).
3. Сошлитесь на Secret `mongodb-credentials` из values сервиса.
4. `./cluster.sh up`: изменение списка секретов применяется к Vault (попросит
   3 unseal key).

## База PostgreSQL для сервиса

Сервису из другого namespace (как Keycloak и GitLab) своя роль и база в
PostgreSQL окружения — в `serviceDatabases.databases` (`k8s/db/values.yaml` или
`values-<env>.yaml`):

```yaml
serviceDatabases:
  databases:
    mongo_app: { secret: mongo-app-db-credentials, extensions: [pg_trgm] }
```

Secret (логин и пароль из Vault `db/<env>/...`) нужен в `db-<env>` и в namespace
сервиса (`k8s/secret/values.yaml`). Задача Helm при каждом `up` создаёт роль и
базу и выставляет пароль из Vault; сервис подключается к
`postgresql.db-<env>.svc.cluster.local:5432`.

## Веб-интерфейс

Маршрут — в `routes` в `k8s/proxy/values.yaml`:

```yaml
# окружение: https://platform.local/dev/mongo
- { host: platform.local, path: /dev/mongo, namespace: db-dev, service: mongo-express, port: 8081 }
# общий сервис: https://mongo.local
- { host: mongo.local, namespace: vcs, service: mongo-express, port: 8081 }
```

Сервис окружения должен сам работать под путём `/<env>/<сервис>` (настройка
base path / context path в `values-<env>.yaml`); если не умеет — добавьте
`stripPath: true`, тогда путь убирается перед передачей сервису. `./cluster.sh up`
сам пропишет имена в hosts, CoreDNS и `/etc/hosts` узлов и перевыпустит
TLS-сертификат.
