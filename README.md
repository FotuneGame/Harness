# Локальная инфраструктура

Двухузловой Minikube-кластер. 

Первый узел является ифраструктурный для официальных образов баз данных, систем контроля версий, брокеров сообщений, непрерывной интеграции, проксирования, large language models, списока управления доступом, хранилищем секретов, логированием/мониторингом, резервным копированием.

Второй узел зарезервирован под собственные приложения.

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

## Используемые технологии

| Технология | Назначение |
|---|---|
| Kubernetes (Minikube) | Локальный двухузловой кластер. |
| Docker | Контейнерный runtime Minikube. |
| Helm | Установка официальных чартов и конфигурация окружений. |
| Ansible | Установка системных зависимостей и CLI-инструментов. |
| Terraform | Источник распределения физических ресурсов сервера и узлов. |
| HashiCorp Vault | Хранилище секретов. |

### Сервисы кластера

| Namespace | Сервисы |
|---|---|
| `db` | PostgreSQL, pgAdmin, Redis, RedisInsight, ClickHouse |
| `mb` | Kafka, Kafka UI |
| `vcs` | GitLab, GitLab Container Registry |
| `ci` | GitLab Runner |
| `proxy` | NGINX Ingress Controller |
| `llm` | Ollama, Open WebUI |
| `acl` | Keycloak |
| `secret` | Vault, Vault Secrets Operator |
| `logs` | Prometheus, Alertmanager, Grafana, Jaeger, Exporters |
| `backup` | K8up, MinIO |

## Быстрый запуск

Требуются Ubuntu 22.04+ или WSL2 Ubuntu и Docker (в Windows — Docker Desktop с
WSL integration).

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

4. Установите сервисы и Kubernetes-манифесты:

```bash
bash scripts/start-cluster.sh
```

При первом запуске скрипт установит платформенные Helm-чарты и остановится,
если Vault не инициализирован или необходимые секреты ещё не синхронизированы.
Выполните первичную настройку ниже, заполните Vault и запустите команду снова.
По умолчанию используется профиль `dev`.

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
настроит Kubernetes auth, KV v2, policies, роли и VSO. При повторном запуске
инициализацию выполнять не будет.

После завершения внесите значения секретов из таблицы ниже через Vault UI или
CLI. Проверьте синхронизацию VSO и запустите приложения:

```bash
kubectl get vaultstaticsecret -A
bash scripts/start-cluster.sh
```

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
| `kv/ci/gitlab-runner` | `runner-token`, `runner-registration-token` — требуется только для Runner |

Для доступа GitLab к S3-хранилищу MinIO значения `aws_access_key_id` и
`aws_secret_access_key` внутри `connection` должны совпадать с
`MINIO_GITLAB_ACCESS_KEY` и `MINIO_GITLAB_SECRET_KEY` в
`kv/backup/minio`. Используйте отдельного MinIO-пользователя GitLab, не root
учётную запись MinIO. Полный перечень потребителей и маппинг Secret указан в
[`k8s/secret/vault-static-secrets.yaml`](./k8s/secret/vault-static-secrets.yaml).

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

Для публикации в Интернет отдельно настройте TLS, firewall и внешний WAF/DDoS protection.

## Мониторинг

Prometheus собирает метрики Kubernetes, узлов, pod и экспортеров БД и Kafka.
Правила алертов и настройки Grafana/Alertmanager находятся в `k8s/logs/`.
SMTP-параметры задаются в `k8s/logs/values.yaml`. Пароль хранится в Vault.

## Резервное копирование

K8up выполняет резервное копирование ежедневно в 02:00. Расписание и срок
хранения заданы в `k8s/backup/schedule.yaml`. MinIO хранит резервные копии в
`volumes/backups`. Каталог следует копировать на отдельное хранилище.

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
