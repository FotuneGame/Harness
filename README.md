# Локальная инфраструктура в Kubernetes (minikube)

Набор конфигов, который разворачивает на локальном **minikube** полный dev-стек:
VCS с Container Registry, CI, базы данных, брокер, LLM, секреты, IAM и
наблюдаемость (метрики, алерты, трейсинг) — каждый компонент в своём
namespace, официальные образы, данные на диске хоста.

Оркестрация — **Terraform** (провайдеры `helm` / `kubernetes` / `kubectl`),
пакетирование — **Helm** (официальные чарты), bootstrap окружения — **Ansible**.

---

## Компоненты

| # | Компонент | Namespace | Каталог | Образ / чарт | Веб-интерфейс |
|---|-----------|-----------|---------|--------------|---------------|
| 1 | GitLab CE | `vcs` | `k8s/vcs` | chart `gitlab/gitlab` | да |
| 2 | Container Registry | `vcs` | `k8s/vcs` | `registry:2` + PVC | да |
| 3 | GitLab Runner | `ci` | `k8s/ci` | chart `gitlab/gitlab-runner` | — |
| 4 | PostgreSQL | `db` | `k8s/db/pg` | `postgres:latest` + `dpage/pgadmin4` | pgAdmin |
| 5 | Redis | `db` | `k8s/db/redis` | `redis:latest` + `redis/redisinsight` | RedisInsight |
| 6 | ClickHouse | `db` | `k8s/db/ch` | `clickhouse/clickhouse-server` | Play UI `/play` |
| 7 | Kafka | `mb` | `k8s/mb` | `apache/kafka` + `provectuslabs/kafka-ui` | Kafka UI |
| 8 | Ingress (nginx) | `ingress` | `k8s/proxy` | chart `ingress-nginx/ingress-nginx` | — |
| 9 | Ollama | `llm` | `k8s/llm/ollama` | `ollama/ollama` + `open-webui` | Open WebUI |
| 10 | Vault | `secret` | `k8s/secret` | chart `hashicorp/vault` | да, `/ui` |
| 11 | Keycloak | `acl` | `k8s/acl` | `quay.io/keycloak/keycloak` | Admin Console |
| 12 | Prometheus + Grafana | `logs` | `k8s/logs` | chart `prometheus-community/kube-prometheus-stack` | Grafana, Prometheus |
| 13 | Alertmanager | `alert` | `k8s/alert` | chart `prometheus-community/alertmanager` | да |
| 14 | Jaeger | `tracing` | `k8s/tracing` | chart `jaegertracing/jaeger` | Jaeger UI |
| 15 | K8up + MinIO | `backup` | `k8s/backup` | chart `k8up/k8up` + `minio/minio` | — |

GitLab использует общие PostgreSQL и Redis из namespace `db`; БД `gitlabhq_production`
и роль создаются init-скриптом (`terraform/secrets.tf`).

```
.
├── terraform/            # namespaces, secrets, storage, helm releases, ingresses
│   └── modules/manifests # применение multi-doc YAML из k8s/**
├── k8s/                  # Helm values и K8s-манифесты по компонентам
│   ├── proxy/  vcs/  ci/  secret/
│   ├── db/pg  db/redis  db/ch
│   ├── mb/  llm/ollama/  acl/  backup/
│   ├── logs/  alert/  tracing/
├── volumes/              # каталоги данных на хосте (зеркалят k8s/)
├── ansible/              # bootstrap рабочей станции
└── run.ps1               # запуск Ansible из Windows через WSL
```

---

## 1. Что необходимо установить

| Инструмент | Назначение |
|------------|------------|
| Docker Desktop / Docker Engine | драйвер minikube |
| [minikube](https://minikube.sigs.k8s.io/docs/start/) | локальный кластер |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | работа с кластером |
| [Helm](https://helm.sh/docs/intro/install/) ≥ 3.14 | чарты |
| [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6 | оркестрация |

**Windows (winget):**
```powershell
winget install Docker.DockerDesktop
winget install Kubernetes.minikube
winget install Kubernetes.kubectl
winget install Helm.Helm
winget install Hashicorp.Terraform
```

> На Windows всё это можно поставить одной командой через
> WSL2 (см. раздел 9). Docker Desktop обязателен: он даёт и драйвер для minikube,
> и Docker внутри WSL.

**Linux / macOS:**
```bash
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  && sudo install minikube-linux-amd64 /usr/local/bin/minikube
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" \
  && sudo install kubectl /usr/local/bin/kubectl
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
brew install terraform   # macOS
```

Либо разом через Ansible (раздел 9).

---

## 2. Что необходимо запустить

### 2.1 Кластер (с монтированием каталога volumes)

```bash
# Linux / macOS
minikube start --driver=docker --cpus=6 --memory=16384 --disk-size=60g \
  --mount-string="$PWD/volumes:/volumes"
```

```powershell
# Windows (PowerShell, из корня репозитория)
minikube start --driver=docker --cpus=6 --memory=16384 --disk-size=60g `
  --mount-string="$PWD\volumes:/volumes"
```

`--mount-string` пробрасывает хостовый каталог `volumes/` в ноду как `/volumes`,
поэтому данные БД остаются на хосте. GitLab тяжёлый — дайте кластеру ≥ 6 CPU и 16 ГБ RAM.

> Память minikube не может превышать лимит Docker/WSL. Если увидите
> `RSRC_OVER_ALLOC_MEM: Requested memory allocation ... is more than your system limit ...`,
> уменьшите `--memory` (в Ansible — `minikube_memory` в `ansible/roles/bootstrap/defaults/main.yml`).

### 2.2 Доступ к ingress (в отдельном терминале, оставить запущенным)

```bash
minikube tunnel          # Windows: от имени администратора
```

### 2.3 Развернуть стек

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply -auto-approve
```

Первый `apply` идёт 10–20 мин (образы + миграции БД).

### 2.4 Прописать хосты

```bash
kubectl get svc -n ingress ingress-nginx-controller   # взять EXTERNAL-IP
```

Добавьте в `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`), заменив `<IP>`:

```
<IP>  gitlab.local registry.local pg.local redis.local clickhouse.local kafka.local ollama.local vault.local keycloak.local grafana.local prometheus.local alert.local jaeger.local
```

> Для **Container Registry** (раздел 5) нужен ещё адрес в `/etc/docker/daemon.json` —
> см. там же.

### 2.5 Инициализировать и распечатать Vault

Vault работает в режиме **standalone** с хранением на диске и после первого старта
запечатан. Выполните один раз:

```bash
kubectl exec -n secret vault-0 -- vault operator init -key-shares=1 -key-threshold=1
kubectl exec -n secret vault-0 -- vault operator unseal <UNSEAL_KEY>
```

Сохраните `Unseal Key` и `Initial Root Token` из вывода. UI: http://vault.local/ui
(метод входа **Token**). После рестарта пода Vault нужно распечатать заново той же командой `unseal`.

### 2.6 Зарегистрировать GitLab Runner

1. http://gitlab.local, вход как `root`. Пароль:
   `kubectl get secret gitlab-gitlab-initial-root-password -n vcs -o jsonpath='{.data.password}' | base64 -d`.
2. **Admin → CI/CD → Runners → New instance runner** — скопируйте токен `glrt-...`.
3. Пропишите в `terraform/terraform.tfvars` (`gitlab_runner_token = "glrt-..."`) и выполните `terraform apply`.

### 2.7 Загрузить модель в Ollama (пример)

```bash
kubectl exec -it ollama-0 -n llm -- ollama pull llama3
```

---

## 3. Volumes

Каталоги в `volumes/` зеркалят структуру `k8s/`. Terraform создаёт StorageClass
`local` (`no-provisioner`) и по одному PV на каждый PVC с `hostPath = /volumes/<папка>`,
поэтому данные пишутся прямо в эти папки на хосте.

| Компонент | Папка (хост) | PVC | PV | Размер |
|-----------|--------------|-----|----|--------|
| PostgreSQL | `volumes/db/pg` | `data-postgresql-0` | `pv-db-pg` | **5 Gi** |
| Redis | `volumes/db/redis` | `data-redis-0` | `pv-db-redis` | **2 Gi** |
| ClickHouse | `volumes/db/ch` | `data-clickhouse-0` | `pv-db-ch` | **10 Gi** |
| Kafka | `volumes/mb` | `data-kafka-0` | `pv-mb` | **5 Gi** |
| Ollama (модели) | `volumes/llm/ollama` | `models-ollama-0` | `pv-llm-ollama` | **30 Gi** |
| GitLab — gitaly | `volumes/vcs/gitaly` | `repo-data-gitlab-gitaly-0` | `pv-vcs-gitaly` | **10 Gi** |
| GitLab — MinIO | `volumes/vcs/minio` | `gitlab-minio` | `pv-vcs-minio` | **5 Gi** |
| Vault | `volumes/secret` | `data-vault-0` | `pv-secret` | **2 Gi** |
| Keycloak | `volumes/acl` | `data-keycloak-0` | `pv-acl` | **2 Gi** |
| Container Registry | `volumes/vcs/registry` | `data-registry-0` | `pv-vcs-registry` | **10 Gi** |
| Grafana | `volumes/logs/grafana` | `logs-grafana` | `pv-logs-grafana` | **2 Gi** |
| Prometheus | `volumes/logs/prometheus` | (volumeClaimTemplate) | `pv-logs-prometheus` | **10 Gi** |
| Alertmanager | `volumes/alert` | `storage-alertmanager-0` | `pv-alert` | **1 Gi** |
| Бэкапы (MinIO) | `volumes/backups` | `data-minio-0` | `pv-backups` | **20 Gi** |

Итого ~114 Gi. Модели Ollama могут занимать десятки ГБ — при необходимости увеличьте
`--disk-size` и размер PV в `terraform/locals.tf`.

pgAdmin, RedisInsight, Kafka UI, Open WebUI, GitLab Runner, Jaeger — без своего хранилища
(stateless). Jaeger по умолчанию хранит трейсы в памяти пода.

> **Prometheus** и **Grafana** подключаются к своим PV не через `claimRef`, а через
> `volumeName` (`pv-logs-prometheus` / `pv-logs-grafana`) — так эти чарты умеют
> привязываться к существующему PV. Имена PVC у чартов фиксированные и проверены
> реальным `helm template`.

> Единственное расхождение с зеркалом: манифесты лежат в `k8s/backup`, а данные — в
> `volumes/backups`. Так папка называется по прямому указанию в задаче.

> **Права доступа (только для нативного Linux).** PV используют `hostPath`, а он не
> поддерживает `fsGroup`, поэтому непривилегированные контейнеры могут не получить доступ
> к папкам. При ошибках записи выполните `chmod -R 0777 volumes` перед `terraform apply`.
> В WSL2/Docker Desktop каталог монтируется как 0777, и это не требуется.

---

## 4. Порты и маршруты

Внешний доступ — только через ingress (host-based routing), класс `nginx`.

| Компонент | Хост | Ingress → Service:port | URL |
|-----------|------|------------------------|-----|
| GitLab | `gitlab.local` | `gitlab-webservice-default:8181` | http://gitlab.local |
| Container Registry | `registry.local` | `registry:5000` | http://registry.local/v2/ |
| pgAdmin | `pg.local` | `pgadmin:80` | http://pg.local |
| RedisInsight | `redis.local` | `redisinsight:5540` | http://redis.local |
| ClickHouse | `clickhouse.local` | `clickhouse:8123` | http://clickhouse.local/play |
| Kafka UI | `kafka.local` | `kafka-ui:8080` | http://kafka.local |
| Open WebUI | `ollama.local` | `open-webui:8080` | http://ollama.local |
| Vault | `vault.local` | `vault:8200` | http://vault.local/ui |
| Keycloak | `keycloak.local` | `keycloak:8080` | http://keycloak.local/admin |
| Grafana | `grafana.local` | `logs-grafana:80` | http://grafana.local |
| Prometheus | `prometheus.local` | `logs-prometheus:9090` | http://prometheus.local |
| Alertmanager | `alert.local` | `alertmanager:9093` | http://alert.local |
| Jaeger | `jaeger.local` | `jaeger:16686` | http://jaeger.local |

> У **Container Registry** отдельный набор аннотаций (`terraform/locals.tf` →
> `registry_annotations`): без лимитов на rps/соединения, `proxy-body-size: 0`
> (неограниченный размер образа), выключена буферизация и таймауты подняты до 900 с.
> Иначе `docker push` упирался бы в DDoS-лимиты.

Внутрикластерные адреса (для подключения из других подов):

| Сервис | Адрес | Порт |
|--------|-------|------|
| PostgreSQL | `postgresql.db.svc.cluster.local` | 5432 |
| Redis | `redis.db.svc.cluster.local` | 6379 |
| ClickHouse (HTTP / native) | `clickhouse.db.svc.cluster.local` | 8123 / 9000 |
| Kafka | `kafka.mb.svc.cluster.local` | 9092 |
| Ollama | `ollama.llm.svc.cluster.local` | 11434 |
| Vault | `vault.secret.svc.cluster.local` | 8200 |
| Container Registry | `registry.vcs.svc.cluster.local` | 5000 |
| Prometheus | `logs-prometheus.logs.svc.cluster.local` | 9090 |
| Alertmanager | `alertmanager.alert.svc.cluster.local` | 9093 |
| Jaeger (OTLP gRPC / HTTP) | `jaeger.tracing.svc.cluster.local` | 4317 / 4318 |
| Jaeger (UI / query) | `jaeger.tracing.svc.cluster.local` | 16686 |
| MinIO (S3) | `minio.backup.svc.cluster.local` | 9000 |

Учётные данные по умолчанию (меняются в `terraform/terraform.tfvars`):

| Сервис | Логин | Пароль |
|--------|-------|--------|
| PostgreSQL | `postgres` | `postgres` |
| pgAdmin | `admin@local` | `admin` |
| ClickHouse | `default` | `clickhouse` |
| Keycloak | `admin` | `admin` |
| Vault | — | `Initial Root Token` из `vault operator init` |
| Grafana | `admin` | `admin` (`grafana_admin_password`) |
| MinIO | `minio` | `minio123` (`minio_password`) |
| Restic (шифрование бэкапов) | — | `restic` (`restic_password`) |

---

## 5. Container Registry (локальные образы)

Образы хранятся в `volumes/vcs/registry` на хосте. Реализация — официальный
`registry:2` (Distribution) с PVC `data-registry-0`.

### Почему не встроенный registry чарта GitLab

Встроенный чарт `registry` из `gitlab/gitlab` **не поддерживает PVC**: в его
Deployment нет ни `extraVolumes`, ни `persistence`, а `storage` по умолчанию —
`filesystem: rootdirectory: /tmp/registry`, то есть данные живут в `emptyDir`
пода и исчезают при пересоздании. Поэтому:

- `global.registry.enabled: true` — GitLab знает о Registry и проксирует его;
- `registry.enabled: false` — встроенный Deployment не создаётся;
- Registry поднимается отдельным манифестом `k8s/vcs/registry.yaml`.

GitLab сам генерирует всё нужное для аутентификации (shared-secrets job):

| Секрет | Ключ | Назначение |
|--------|------|------------|
| `gitlab-registry-secret` | `registry-auth.crt` | публичный сертификат для проверки JWT (`rootcertbundle`) |
| `gitlab-registry-httpsecret` | `secret` | общий секрет `http.secret` |

Registry настроен через переменные окружения (`REGISTRY_*`) и проверяет токены
локально по сертификату, а клиенту отдаёт `realm = http://gitlab.local/jwt/auth`.

### Настроить Docker на небезопасный registry

Registry работает по HTTP, поэтому его нужно добавить в исключения. В
`/etc/docker/daemon.json` (Windows: Docker Desktop → **Settings → Docker Engine**):

```json
{
  "insecure-registries": ["registry.local:80"]
}
```

Затем перезапустить Docker (`sudo systemctl restart docker`). Проверка:

```bash
docker login registry.local        # логин/пароль — от GitLab (root + его пароль)
docker pull alpine
docker tag alpine registry.local/root/alpine:latest
docker push registry.local/root/alpine:latest
```

Образ появится в проекте `root/alpine` (GitLab → **Deploy → Container Registry**).

> Изнутри кластера (например, из GitLab CI) тот же registry доступен как
> `registry.vcs.svc.cluster.local:5000` — без настройки `insecure-registries`,
> если раннер настроен соответствующим образом.

---

## 6. Мониторинг, алерты и трейсинг

Три namespace, у каждого — свой веб-интерфейс.

### 6.1 `k8s/logs` — Prometheus + Grafana

Чарт `prometheus-community/kube-prometheus-stack` (`logs`) со своей Grafana:

- Prometheus пишет в `volumes/logs/prometheus` (retention 15 дней);
- Grafana хранит дашборды и пользователей в `volumes/logs/grafana`;
- `alertmanager.enabled: false` — встроенный Alertmanager выключен, вместо него
  используется отдельный релиз из `k8s/alert` (см. ниже);
- Prometheus отправляет алерты на него через `prometheusSpec.alertingEndpoints`.

Grafana: http://grafana.local (`admin` / `grafana_admin_password`).
Prometheus: http://prometheus.local.

### 6.2 `k8s/alert` — Alertmanager с веб-интерфейсом

Отдельный релиз чарта `prometheus-community/alertmanager` в namespace `alert`:
веб-UI на http://alert.local, состояние (silences, notification log) — в
`volumes/alert`.

Прометеус из `k8s/logs` шлёт алерты на сервис `alertmanager.alert:9093`.
Получатели заданы в `k8s/alert/values.yaml` (`config.receivers`, по умолчанию —
заглушка `default`); добавьте туда webhook/Slack/email.

```bash
# проверить, что Prometheus видит Alertmanager
kubectl get --raw /api/v1/namespaces/logs/services/logs-prometheus:9090/proxy/api/v1/alertmanagers
```

### 6.3 `k8s/tracing` — Jaeger

Чарт `jaegertracing/jaeger` (Jaeger v2, all-in-one) в namespace `tracing`.
UI: http://jaeger.local. По умолчанию трейсы хранятся **в памяти** пода
(`jaeger.storage`), поэтому отдельный том ему не нужен.

Приём трейсов из приложений в кластере:

| Протокол | Адрес |
|----------|-------|
| OTLP gRPC | `jaeger.tracing.svc.cluster.local:4317` |
| OTLP HTTP | `jaeger.tracing.svc.cluster.local:4318` |
| Zipkin | `jaeger.tracing.svc.cluster.local:9411` |
| Jaeger agent (UDP) | `jaeger.tracing.svc.cluster.local:6831` |

Пример для приложения в кластере:

```
OTEL_EXPORTER_OTLP_ENDPOINT=http://jaeger.tracing.svc.cluster.local:4318
```

---

## 7. Бэкапы (K8up)

Бэкапами управляет оператор **K8up** (Restic) в namespace `backup`. Резервные копии всех
PVC складываются в S3-совместимое хранилище **MinIO**, чьи данные физически лежат в
`volumes/backups` на хосте.

Схема:

```
Schedule (в namespace db/mb/llm/vcs/secret/acl)
   └─> backup-pod монтирует PVC этого namespace
          └─> Restic шифрует и отправляет в MinIO (backup/minio:9000)
                 └─> MinIO пишет в PVC data-minio-0 -> volumes/backups на хосте
```

Расписание (по одному `Schedule` на namespace, все PVC бэкапятся автоматически):

| Задача | Cron | Что делает |
|--------|------|------------|
| `backup` | `0 2 * * *` | ежедневный бэкап всех PVC |
| `check` | `0 3 * * 0` | еженедельная проверка целостности репозитория |
| `prune` | `0 4 * * 0` | еженедельная чистка, хранение `keepLast: 7`, `keepDaily: 7` |

Бэкенд задан глобально через env-переменные оператора (`k8s/backup/values.yaml`):
`BACKUP_GLOBAL*` + секреты `k8up-s3` и `k8up-restic`. Поэтому Schedule содержат только
расписания — креды не дублируются по namespace.

### Проверить и запустить вручную

```bash
kubectl get schedule -A                       # список расписаний
kubectl get backup,prune,check,snapshot -A    # история запусков
kubectl get pods -n backup                    # MinIO + оператор K8up

# внеплановый бэкап прямо сейчас
kubectl create -n db -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Backup
metadata:
  name: manual
spec: {}
EOF
```

### Восстановить данные

```bash
kubectl get snapshots -n db                                  # найти snapshot ID
kubectl create -n db -f - <<'EOF'
apiVersion: k8up.io/v1
kind: Restore
metadata:
  name: restore
spec:
  restoreMethod:
    folder:
      claimName: data-postgresql-0
EOF
```

### Важно

- **Пароль Restic** (`restic_password`, по умолчанию `restic`) — это ключ шифрования
  бэкапов. Без него восстановление невозможно: смените его в `terraform.tfvars` и
  сохраните копию **вне** кластера.
- Пароль задаётся один раз: если поменять его после первого бэкапа, старые снапшоты
  станут нечитаемыми.
- Чтобы исключить конкретный PVC из бэкапа, добавьте ему аннотацию `k8up.io/backup=false`.

---

## 8. Защита от DDoS (ingress)

Реализована штатными средствами nginx-ingress — без сторонних WAF.

**Контроллер** (`k8s/proxy/values.yaml`): доверенные заголовки `X-Forwarded-For`
(`use-forwarded-headers`, `compute-full-forwarded-for`, `enable-real-ip`), лимит размера
тела, коды ответа `429` вместо `503`.

**Каждый Ingress** (аннотации из `terraform/locals.tf`):

| Аннотация | Значение | Что делает |
|-----------|----------|------------|
| `limit-rps` | 20 | запросов/сек с одного IP |
| `limit-burst-multiplier` | 5 | допустимый всплеск (20 × 5) |
| `limit-connections` | 30 | одновременных соединений с одного IP |
| `limit-rate` | 5 MiB/s | лимит скорости отдачи |
| `limit-rate-after` | 10 MiB | включать лимит после N байт |
| `proxy-body-size` | 100m | максимальный размер запроса |

При превышении лимитов клиент получает `429 Too Many Requests`.

> Усиление: OWASP ModSecurity/Coraza (`controller.config.enable-modsecurity: "true"`),
> `denylist-source-range` или внешний WAF/Cloudflare перед кластером.

---

## 9. Ansible: установка и запуск одной командой

Ansible — управляющая машина только для Linux/macOS: на Windows он нативно не работает.
Поэтому на Windows playbook запускается **внутри WSL2** через обёртку `run.ps1`.

### Linux / macOS

```bash
sudo apt-get update && sudo apt-get install -y ansible    # или: brew install ansible
ansible-playbook -i ansible/inventory.ini ansible/site.yml --ask-become-pass
```

`--ask-become-pass` (кратко `-K`) обязателен: роль повышает права через `sudo`, а sudo
требует пароль. Пароль спрашивают один раз в начале.

### Windows (WSL2)

Подготовка (один раз):

```powershell
wsl --install -d Ubuntu          # Linux-дистрибутив (docker-desktop для этого не годится)
```

Перезагрузиться, затем в Docker Desktop включить
**Settings → Resources → WSL Integration → Ubuntu**.

---

## 10. Удаление

```bash
cd terraform && terraform destroy -auto-approve
minikube delete
```

Данные остаются в `volumes/` на хосте — удалите каталоги вручную, если они больше не нужны.
