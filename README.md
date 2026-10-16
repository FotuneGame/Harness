# Локальная инфраструктура

Двухузловой Minikube-кластер. Первый узел выделен под инфраструктурные
сервисы, второй — под собственные приложения.

## Технические характеристики сервера

| Ресурс | Характеристика |
|---|---|
| Процессор | Intel Core i5-11400F, 6 ядер, 2.6 ГГц |
| Оперативная память | 32 ГБ |
| Диск | 450 ГБ |
| Видеокарта | NVIDIA GeForce GTX 1650, 4 ГБ |
| Операционная система | Windows 11 с WSL2 Ubuntu 22.04+ или Ubuntu 22.04+ |

Terraform описывает физический профиль и распределение ресурсов между
логическими узлами. По умолчанию `minikube` получает 4 CPU, 20 ГиБ RAM и
100 ГиБ диска, а `minikube-m02` — 2 CPU, 8 ГиБ RAM и 100 ГиБ диска.
На Ubuntu установите NVIDIA driver; `prepare-host.sh` настроит Container Toolkit
для Docker. В WSL2 GPU работает best effort и включается только при успешной
проверке Docker и Kubernetes. При недоступном GPU Ollama работает на CPU.
Ollama запрашивает GPU через `nvidia.com/gpu`.

## Используемые технологии

| Технология | Назначение |
|---|---|
| Kubernetes (Minikube) | Локальный двухузловой кластер. |
| Docker | Контейнерный runtime Minikube. |
| Helm | Официальные charts и локальный chart ресурсов платформы. |
| Ansible | Установка системных зависимостей и CLI-инструментов. |
| Terraform | Источник распределения физических ресурсов сервера и узлов. |
| HashiCorp Vault | Хранилище секретов. |

### Сервисы кластера

| Namespace | Сервисы |
|---|---|
| `db` | PostgreSQL, pgAdmin, Redis, RedisInsight, ClickHouse |
| `mb` | Kafka, Kafka UI |
| `vcs` | GitLab, GitLab Container Registry |
| `cicd` | GitLab Runner, Argo CD |
| `proxy` | NGINX Ingress Controller |
| `llm` | Ollama, Open WebUI |
| `acl` | Keycloak |
| `secret` | Vault, Vault Secrets Operator |
| `logs` | Prometheus, Alertmanager, Grafana, Jaeger, Exporters |
| `backup` | K8up, MinIO |

## Структура Kubernetes

`k8s/Chart.yaml` задаёт базовый Helm chart. `k8s/values.yaml` содержит список
namespaces; `k8s/templates/namespaces.yaml` создаёт их циклом Helm.
`k8s/templates/volumes.yaml` создаёт StorageClass и PV по списку `storage.volumes`
в `k8s/values.yaml`. Для каждого PV там указываются имя, размер, путь на узле и
при необходимости PVC-привязка или labels. Имя узла хранения задаётся через
`storage.nodeName`.
В `k8s/charts/` находятся локальные charts платформы.
Каждый манифест Kubernetes расположен отдельно в `templates/*.yaml`;
переменные и параметры из `values.yaml` выводятся стандартными выражениями
Helm `{{ ... }}`. В корне каждого chart лежат только `Chart.yaml`, `values.yaml`
и профильные `values-*.yaml`. Values официальных charts и дополнительные файлы
расположены в `templates/`; файлы с префиксом `_` не рендерятся локальным chart
и передаются в upstream chart из `scripts/start-cluster.sh`.

| Папка | Файлы и назначение |
|---|---|
| `acl` | `templates/config.yaml` — переменные окружения Keycloak; `templates/keycloak.yaml` — Service и StatefulSet. |
| `backup` | `templates/minio.yaml` — MinIO и начальная настройка buckets/users; `templates/minio-policy.yaml` — политики MinIO; `templates/schedule.yaml` — суточный K8up backup; `values.yaml` — настройки локального chart; `templates/_k8up-values.yaml` — официальный K8up chart. |
| `cicd` | `templates/vault-secrets.yaml` — Vault credentials для Runner и Argo CD; `values.yaml` — адрес и пути Vault для локального chart; `templates/_runner-values.yaml` — официальный GitLab Runner chart; `templates/_argocd-values.yaml` — официальный Argo CD chart. |
| `db` | `templates/postgres*.yaml`, `redis*.yaml`, `clickhouse*.yaml` — workloads, настройки и переменные окружения БД. |
| `gpu` | `values.yaml` — настройки официального NVIDIA device plugin chart. |
| `hpa` | `templates/ui.yaml` — HPA для интерфейсов pgAdmin, RedisInsight, Kafka UI и Open WebUI; цели и порог CPU заданы в `values.yaml`. |
| `llm` | `templates/config.yaml` — переменные окружения Open WebUI; `templates/ollama.yaml` — Ollama с опциональным GPU и Open WebUI. |
| `logs` | `templates/alerts.yaml`, `templates/dashboard.yaml` — правила алертов и Grafana dashboard; `templates/exporter-config.yaml`, `templates/exporters.yaml` — экспортеры и ServiceMonitor с параметрами из `values.yaml`; `templates/_prometheus-values.yaml` — базовые значения Prometheus chart; профильные overrides — `values-development.yaml`, `values-staging.yaml`, `values-production.yaml`; `templates/_jaeger-values.yaml` — официальный Jaeger chart. |
| `mb` | `templates/config.yaml`, `templates/kafka.yaml` — переменные окружения и workloads Kafka и Kafka UI. |
| `proxy` | `templates/ingress.yaml` — маршруты и ограничения запросов; `values.yaml` — namespaces локального chart; `templates/_ingress-values.yaml` — официальный ingress-nginx chart. |
| `secret` | `templates/auth-reviewer.yaml` — Kubernetes auth для Vault; `templates/vault-static-secrets.yaml` — синхронизация секретов из Vault; `templates/policies/_*.txt` — политики Vault в HCL; `values.yaml` — адрес Vault и namespaces; `templates/_vault-values.yaml` — официальный Vault chart. |
| `vcs` | `templates/registry*.yaml` — GitLab Container Registry; `templates/_gitlab-values.yaml` — базовые значения GitLab chart; `values-development.yaml`, `values-staging.yaml`, `values-production.yaml` — профильные overrides. |

Профили находятся в корне `k8s/charts/logs/` и `k8s/charts/vcs/`. Скрипт
сопоставляет `HELM_ENV=dev|staging|prod` файлам `values-development.yaml`,
`values-staging.yaml` и `values-production.yaml`. Версии и upstream-репозитории
официальных charts зафиксированы в `scripts/start-cluster.sh`.

## Быстрый запуск

Требуются Ubuntu 22.04+ или WSL2 Ubuntu и Docker (в Windows — Docker Desktop с
WSL integration), Helm 3.17+ и NVIDIA driver для GPU в Ubuntu.

1. Подготовьте зависимости:

```bash
bash scripts/prepare-host.sh
```

2. Инициализируйте Terraform и проверьте профиль ресурсов:

```bash
export TF_CLI_CONFIG_FILE="$PWD/terraform/.terraformrc"
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

3. Запустите Minikube самостоятельно, используя профиль Terraform:

```bash
bash scripts/start-minikube.sh
```

4. Установите charts:

```bash
bash scripts/start-cluster.sh
```

Локальные charts сгруппированы в `k8s/charts/` по назначению. Namespaces и
тома объявлены отдельно в `k8s/templates/`. Официальные charts загружаются
из своих Helm-репозиториев с зафиксированными версиями. Скрипт устанавливает
foundation-ресурсы, Vault и операторы; после настройки Vault и добавления
секретов запустите его повторно для развёртывания сервисов.
По умолчанию используется профиль `dev`.

## Профиль кластера: dev, staging, prod

Профиль выбирается при каждом запуске `start-cluster.sh`. Команда ниже
повторно применяет настройки к текущему кластеру через Helm upgrade.
Для переключения используйте `HELM_ENV=dev`, `HELM_ENV=staging` или
`HELM_ENV=prod`. Если `HELM_ENV` не задан, используется `dev`:

```bash
HELM_ENV=dev bash scripts/start-cluster.sh
```

Профильные values GitLab и Prometheus находятся рядом с `Chart.yaml` в папках
`k8s/charts/vcs/` и `k8s/charts/logs/`.

## Первичная настройка Vault (один раз)

После установки Vault и запуска pod `vault-0` выполните из корня репозитория
одну команду:

```bash
bash scripts/bootstrap-vault.sh
```

Скрипт проверит состояние Vault. Если Vault ещё не инициализирован, он попросит
подтверждение `INIT` и выведет пять unseal keys и root token. **Скопируйте и
сохраните их вне репозитория**: для последующих разблокировок понадобятся любые
три ключа, а root token — для настройки. Затем скрипт запросит три ключа по
очереди, сам поднимет port-forward, попросит root token без отображения ввода и
настроит Kubernetes auth, KV v2 и policies. При повторном запуске
инициализацию выполнять не будет.

После завершения внесите значения секретов из таблицы ниже через Vault UI или
CLI, затем разверните сервисы:

```bash
bash scripts/start-cluster.sh
```

Манифесты сгруппированы по компонентам в `k8s/charts/`. Vault values и
политики находятся в `k8s/charts/secret/`. Официальные Helm charts
устанавливаются из upstream-репозиториев с версиями, зафиксированными в
`scripts/start-cluster.sh`.

| Vault KV v2 путь | Ключи |
|---|---|
| `kv/db/postgres` | `POSTGRES_PASSWORD` |
| `kv/db/postgres-app-credentials` | `gitlab_password`, `keycloak_password`, `exporter_password` |
| `kv/db/pgadmin` | `PGADMIN_DEFAULT_EMAIL`, `PGADMIN_DEFAULT_PASSWORD` |
| `kv/db/redis` | `REDIS_PASSWORD` |
| `kv/db/clickhouse` | `CLICKHOUSE_PASSWORD` |
| `kv/vcs/gitlab-postgresql` | `postgresql-password` — тот же пароль, что `gitlab_password` |
| `kv/vcs/object-storage` | `connection` — JSON MinIO S3 connection с GitLab user credentials |
| `kv/vcs/gitlab-root-password` | `password` — первоначальный root пароль GitLab |
| `kv/acl/keycloak` | `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD`, `KC_DB_PASSWORD` |
| `kv/backup/minio` | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, `MINIO_GITLAB_ACCESS_KEY`, `MINIO_GITLAB_SECRET_KEY`, `MINIO_K8UP_ACCESS_KEY`, `MINIO_K8UP_SECRET_KEY` |
| `kv/backup/k8up-s3` | `accessKeyID`, `secretAccessKey` — те же K8up credentials |
| `kv/backup/k8up-restic` | `password` |
| `kv/logs/smtp` | `password` |
| `kv/cicd/gitlab-runner` | `runner-token`, `runner-registration-token` — требуется только для Runner |
| `kv/cicd/argocd-gitlab` | `type`, `url`, `username`, `password` — GitLab repository credential template для Argo CD |

Для доступа GitLab к S3-хранилищу MinIO значения `aws_access_key_id` и
`aws_secret_access_key` внутри `connection` должны совпадать с
`MINIO_GITLAB_ACCESS_KEY` и `MINIO_GITLAB_SECRET_KEY` в
`kv/backup/minio`. Используйте отдельного MinIO-пользователя GitLab, не root
учётную запись MinIO. Полный перечень потребителей и маппинг Secret указан в
[vault-static-secrets.yaml](./k8s/charts/secret/templates/vault-static-secrets.yaml).

После первого запуска GitLab создайте пользователя и Personal Access Token
с правом `read_repository`. Argo CD обращается к GitLab по внутреннему адресу
`http://gitlab-webservice-default.vcs.svc.cluster.local:8181/`. Сохраните в
`kv/cicd/argocd-gitlab`:
`type=git`, `url` с указанным URL-префиксом, `username` и `password` (PAT).
VSO создаст помеченный Argo CD Secret в течение минуты; токен не хранится в
Helm values.

## Сеть

Схема:

```text
Браузер -> Ingress NGINX -> Service -> Pod -> PVC -> PV -> /volumes/... на minikube
```

Для localhost-доступа запустите скрипт из корня репозитория:

```bash
bash scripts/forward-ingress.sh
```

| Имя | Интерфейс |
|---|---|
| `gitlab.local` / `registry.local` | GitLab / Container Registry |
| `pg.local` / `redis.local` | pgAdmin / RedisInsight |
| `clickhouse.local` / `kafka.local` | ClickHouse UI / Kafka UI |
| `ollama.local` / `keycloak.local` / `vault.local` | Open WebUI / Keycloak / Vault |
| `grafana.local` / `prometheus.local` / `alert.local` / `jaeger.local` | Grafana / Prometheus / Alertmanager / Jaeger |
| `argocd.local` | Argo CD |

Для публикации в Интернет отдельно настройте TLS, firewall и внешний WAF/DDoS protection.

## Мониторинг

Prometheus собирает метрики Kubernetes, узлов, pod и экспортеров БД и Kafka.
Правила алертов, dashboards и настройки Prometheus/Grafana/Alertmanager
находятся в `k8s/charts/logs/`. SMTP-пароль хранится в Vault.

## Резервное копирование

K8up выполняет резервное копирование ежедневно в 02:00. Расписание и срок
хранения заданы в `k8s/charts/backup/templates/schedule.yaml`. MinIO хранит
резервные копии в `volumes/backups`. Каталог следует копировать на отдельное
хранилище.

## Terraform state

Terraform проверяет профиль ресурсов и не создаёт кластер. State по умолчанию
хранится локально в `terraform/terraform.tfstate` и исключён из Git. Для работы
выполните:

```bash
export TF_CLI_CONFIG_FILE="$PWD/terraform/.terraformrc"
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

Чтобы изменить каталог хранения state, измените `path` в
[`terraform/versions.tf`](./terraform/versions.tf), например на
`../state/terraform.tfstate`. Путь задаётся относительно каталога `terraform/`.
При смене пути перенесите существующий state и выполните
`terraform -chdir=terraform init -migrate-state`; иначе Terraform может
создать новый пустой state. Если Terraform ранее был настроен на старый S3
backend, используйте ту же команду `init -migrate-state`, чтобы перенести
удалённый state в локальный файл.
