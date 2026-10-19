# Локальная инфраструктура

Minikube-кластер из трёх узлов: `minikube` (платформенные сервисы),
`minikube-m02` (LLM) и `minikube-m03` (приложения из Argo CD). Развёртывание
описано Ansible-ролями и запускается одним playbook.

## Узлы

Профиль ресурсов задан в `terraform/variables.tf`.

| Узел | Роль | CPU | RAM | Диск | `platform.node` | Назначение |
|---|---|---|---|---|---|---|
| `minikube` | `platform` | 2 | 16 ГиБ | 100 ГиБ | `core` | Платформенные сервисы и мониторинг |
| `minikube-m02` | `llm` | 2 | 8 ГиБ | 100 ГиБ | `llm` | llama.cpp, Open WebUI |
| `minikube-m03` | `applications` | 2 | 4 ГиБ | 100 ГиБ | `apps` | Приложения из Argo CD |

На узле LLM выставляется метка `platform.gpu`. Узел приложений закрыт taint-ом
`workload=applications:NoSchedule` — приложения из Argo CD должны добавлять
соответствующие tolerations. Изменение состава узлов требует `minikube delete`
и повторного запуска операции 1.

## Состав кластера

Манифесты сгруппированы по компонентам в `k8s/charts/<компонент>/`: каждый
ресурс Kubernetes описан отдельным файлом `[имя]-[тип].yml` в `templates/`,
значения лежат рядом в `values-dev.yaml`, `values-staging.yaml` и
`values-prod.yaml` (профиль выбирается переменной `HELM_ENV`). Официальные
charts подключены как `dependencies` в `Chart.yaml` и скачиваются в каталог
`charts/` командой `helm dependency build`. Charts Vault и Vault Secrets
Operator зафиксированы в репозитории (`k8s/charts/secret/charts/`), потому что
репозиторий `helm.releases.hashicorp.com` недоступен.

| Namespace | Узел | Сервисы |
|---|---|---|
| `db` | `core` | PostgreSQL, pgAdmin, Redis, RedisInsight, ClickHouse, Elasticsearch |
| `mb` | `core` | Kafka, Kafka UI |
| `vcs` | `core` | GitLab, GitLab Container Registry |
| `cicd` | `core` | Argo CD, GitLab Runner |
| `proxy` | `core` | NGINX Ingress Controller |
| `secret` | `core` | Vault, Vault Secrets Operator |
| `acl` | `core` | Keycloak |
| `logs` | `core` | Prometheus, Alertmanager, Grafana, Jaeger, exporters |
| `backup` | `core` | K8up, MinIO |
| `llm` | `llm` | llama.cpp, Open WebUI |
| `applications` | `apps` | Приложения из Argo CD |

Данные сервисов хранятся в каталогах `volumes/<namespace>/...` узла `minikube`
(PV `pv-*` заранее привязаны к PVC). Для Elasticsearch в узле выставляется
`vm.max_map_count=262144`.

## Подготовка

Требуются Ubuntu 22.04+ или WSL2 Ubuntu, Docker (в Windows — Docker Desktop с
включённой WSL integration) и Helm 3.17+. Для GPU в Ubuntu нужны NVIDIA driver
и NVIDIA Container Toolkit; в WSL2 кластер работает без GPU, и llama.cpp
использует CPU.

Запустите Docker Desktop и подготовьте host из корня репозитория:

```bash
bash scripts/prepare-host.sh
```

Роль `bootstrap` устанавливает базовые пакеты, Docker, Minikube, kubectl, Helm,
Terraform и Vault CLI, добавляет `metadata` в `/etc/wsl.conf`, создаёт
пользователя `cluster` с доступом к Docker и назначает его пользователем WSL по
умолчанию. При первом изменении конфигурации выполните `wsl.exe --shutdown` в
Windows, откройте WSL заново и проверьте, что `whoami` выводит `cluster`.
Дальнейшие команды выполняйте из корня репозитория от имени `cluster`.

## Команды

Номер операции передаётся в `cluster_action`:

| № | Действие | Команда |
|---|---|---|
| 1 | Настройка и запуск кластера | `ansible-playbook -i ansible/inventory.ini ansible/cluster.yml -e cluster_action=1` |
| 2 | Генерация ключей и разблокировка Vault | `... -e cluster_action=2` |
| 3 | Остановка кластера | `... -e cluster_action=3` |
| 4 | Перезагрузка кластера | `... -e cluster_action=4` |
| 5 | Включение проброса портов (`127.0.0.1:80`, `127.0.0.1:443`) | `... -e cluster_action=5` |
| 6 | Выключение проброса портов | `... -e cluster_action=6` |

Операция 1 настраивает Terraform, запускает Minikube с шифрованием etcd, ставит
базовые charts и настраивает Vault. После внесения секретов повторите её, чтобы
установить сервисы. Профиль значений выбирается переменной `HELM_ENV` (`dev` по
умолчанию):

```bash
HELM_ENV=staging ansible-playbook -i ansible/inventory.ini ansible/cluster.yml -e cluster_action=1
```

Логика вынесена в роли `ansible/roles/`: `bootstrap` готовит систему, `minikube`
запускает узлы по профилю Terraform, `platform` разворачивает Helm charts и
сервисы, `vault` инициализирует и настраивает Vault, `ingress` настраивает имена
`*.local` и проброс портов.

## Секреты

Секреты хранятся только в Vault (KV v2) и не попадают в Helm values; в
манифестах описаны лишь объекты `VaultStaticSecret` в
`k8s/charts/secret/templates/vault-static-secrets.yaml`. Значения Secret в etcd
шифруются: kube-apiserver запускается с `encryption-provider-config` (провайдер
`aescbc`), ключ шифрования хранится в `volumes/minikube/encryption` и исключён
из Git.

Внесите значения через Vault CLI или UI и повторите операцию 1. Для записи через
CLI откройте port-forward в отдельном терминале:

```bash
kubectl port-forward -n secret service/vault 8200:8200
```

В другом терминале:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
read -rsp "Vault CLI token: " VAULT_TOKEN
echo
export VAULT_TOKEN
vault kv put kv/db/postgres POSTGRES_PASSWORD='<пароль>'
unset VAULT_TOKEN
```

При первичной инициализации playbook выводит три unseal key для сохранения в
защищённом месте и ограниченный CLI token со сроком действия 7 дней; root token
используется только внутри роли и не сохраняется. Не сохраняйте ключи в
репозитории или shell history.

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
`MINIO_GITLAB_ACCESS_KEY` и `MINIO_GITLAB_SECRET_KEY` в `kv/backup/minio`.
Используйте отдельного MinIO-пользователя GitLab, а не root учётную запись.
Полный перечень потребителей и маппинг Secret указан в
[vault-static-secrets.yaml](./k8s/charts/secret/templates/vault-static-secrets.yaml).

После первого запуска GitLab создайте пользователя и Personal Access Token с
правом `read_repository`. Argo CD обращается к GitLab по внутреннему адресу
`http://gitlab-webservice-default.vcs.svc.cluster.local:8181/`. Сохраните в
`kv/cicd/argocd-gitlab`: `type=git`, `url` с этим префиксом, `username` и
`password` (PAT) — Vault Secrets Operator создаст помеченный для Argo CD Secret
в течение минуты.

GitLab Runner обращается к GitLab по тому же внутреннему адресу: он задан в
`gitlabUrl` и `clone_url` в `k8s/charts/cicd/values-[stage].yaml`, поэтому job'ы
клонируют репозиторий без внешнего DNS. Если секрет `gitlab-runner-secret`
отсутствует, роль `platform` отключает Runner и продолжает развёртывание.

## Доступные адреса сети

Схема: `Браузер -> Ingress NGINX -> Service -> Pod -> PVC -> PV -> /volumes/...`.
Проброс включают команды 5 и 6; он слушает только localhost.

| Имя | Сервис |
|---|---|
| `gitlab.local` / `registry.local` | GitLab / GitLab Container Registry |
| `pg.local` / `redis.local` | pgAdmin / RedisInsight |
| `clickhouse.local` / `kafka.local` | ClickHouse UI / Kafka UI |
| `llama.local` / `keycloak.local` / `vault.local` | Open WebUI / Keycloak / Vault |
| `grafana.local` / `prometheus.local` / `alert.local` / `jaeger.local` | Grafana / Prometheus / Alertmanager / Jaeger |
| `argocd.local` | Argo CD |

Ingress использует HTTPS и самоподписанный wildcard-сертификат для `*.local`.
Чтобы браузер не показывал предупреждение, добавьте
`volumes/proxy/tls/tls.crt` в доверенные сертификаты ОС или браузера. Закрытый
ключ лежит в `volumes/proxy/tls/tls.key` и исключён из Git. Для публикации в
Интернет замените локальный сертификат сертификатом доверенного центра,
настройте DNS, firewall и внешний WAF/DDoS protection.

## Мониторинг и резервное копирование

Prometheus собирает метрики Kubernetes, узлов, pod и экспортеров PostgreSQL,
Redis, ClickHouse и Kafka. Alertmanager отправляет письма через SMTP (пароль в
`kv/logs/smtp`), Grafana показывает dashboards, Jaeger принимает трейсы по OTLP.
Правила алертов, dashboards и настройки компонентов лежат в `k8s/charts/logs/`;
`prometheus-node-exporter` работает DaemonSet на всех узлах, включая узел
приложений.

K8up выполняет резервное копирование ежедневно в 02:00, проверку — по
воскресеньям в 03:00, очистку — по воскресеньям в 04:00. Расписание, сроки
хранения и список namespace заданы в `k8s/charts/backup/values-[stage].yaml` и
`k8s/charts/backup/templates/backup-schedule.yml`. Копии хранит MinIO в томе
`volumes/backups`; каталог следует регулярно копировать на отдельное хранилище.

## Примечания

### Terraform state

Terraform проверяет профиль ресурсов и не создаёт кластер. Пока удалённое
хранилище не настроено, state временно хранится локально в
`terraform/terraform.tfstate` и исключён из Git. Перед совместной работой
настройте удалённый backend и перенесите state командой
`terraform init -migrate-state`.

### Версии сервисов

Версии upstream-charts зафиксированы в `Chart.yaml` и `Chart.lock` каждого
компонента, версии локальных образов — в values-файлах:

| Компонент | Версия |
|---|---|
| Kubernetes (Minikube) | 1.34.0 |
| Terraform | 1.9.8 |
| Vault CLI | 1.18.5 |
| ingress-nginx | chart 4.15.1 |
| kube-prometheus-stack | chart 92.9.0 |
| jaeger | chart 4.16.1 |
| vault | chart 0.34.1 |
| vault-secrets-operator | chart 1.6.0 |
| postgresql / redis | charts 18.12.4 / 28.3.1 |
| clickhouse / elasticsearch | charts 9.4.4 / 22.1.6 |
| pgadmin4 | chart 1.70.4 |
| kafka | chart 32.4.3 |
| keycloak | chart 25.2.0 |
| minio | chart 5.4.0 |
| open-webui | chart 17.0.0 |
| k8up | chart 4.10.0 |
| gitlab | chart 10.5.0 |
| argo-cd | chart 10.10.5 |
| gitlab-runner | chart 0.94.0 |
| nvidia-device-plugin | chart 0.20.1 |
| llama.cpp | образ `ghcr.io/ggml-org/llama.cpp:server` (`server-cuda` при GPU) |
| RedisInsight, Kafka UI | образы `latest` из upstream-репозиториев |

Версионные образы Bitnami перенесены в репозиторий `bitnamilegacy/`, поэтому в
values заданы `global.security.allowInsecureImages: true` и этот репозиторий.
Обновляя образы `latest`, проверяйте совместимость с текущими values и томами;
версии upstream-charts меняйте вместе с `Chart.lock`.

### LLM по умолчанию и тест через perplexity

По умолчанию используется модель Qwen2.5-0.5B-Instruct в квантизации Q4_K_M
(файл скачивается init-контейнером в том `volumes/llm/llama`). Проверить модель
через `llama-perplexity` можно так:

```bash
helm upgrade --install platform-llm ./k8s/charts/llm \
  --namespace llm -f k8s/charts/llm/values-dev.yaml \
  --set perplexity.enabled=true --take-ownership
kubectl logs -n llm job/llama-perplexity
```

Задача считает perplexity по короткому демонстрационному тексту; замените его на
представительный корпус через `perplexity.input` в values. Если в узле
`minikube-m02` доступен ресурс `nvidia.com/gpu`, роль `platform` включает
GPU-варианты образов, иначе llama.cpp работает на CPU.
