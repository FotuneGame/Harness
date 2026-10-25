# Локальная инфраструктура Kubernetes

Minikube из трёх узлов. Terraform создаёт узлы, Ansible устанавливает пакеты,
настраивает сервер и разворачивает Helm charts (`k8s/<папка>`). Папки `db`, `mb`,
`llm`, `acl`, `app` разделены на окружения dev, stage, prod, папки `vcs`, `cicd`,
`proxy`, `secret`, `logs`, `backup` общие для всех окружений.

## Сервер

| Параметр | Значение |
|---|---|
| CPU | Intel Core i5-11400F, 6 ядер / 12 потоков, 2.6 ГГц |
| RAM | 48 ГБ, кластеру выделено 40 ГБ |
| Диск | 450 ГБ |
| GPU | NVIDIA GeForce GTX 1650, 4 ГБ |
| ОС | Ubuntu 22.04+ или Windows 11 + WSL2 Ubuntu 22.04+ с Docker Desktop (WSL integration) |

## Узлы (`terraform/variables.tf`)

| Узел | `platform.node` | CPU | RAM | Диск | VRAM | Назначение |
|---|---|---|---|---|---|---|
| `minikube` | `core` | 6 | 20 ГБ | 200 ГБ | 0 | Все сервисы платформы и всех окружений |
| `minikube-m02` | `llms` | 4 | 16 ГБ | 200 ГБ | 4096 МБ | llama.cpp всех окружений |
| `minikube-m03` | `apps` | 2 | 4 ГБ | 50 ГБ | 0 | Свои приложения всех окружений (taint `workload=apps:NoSchedule`) |

## Namespace и адреса

Окружения изолированы по сети (CNI Calico, NetworkPolicy): к подам
`<папка>-<env>` подключаются только поды того же окружения и namespace `logs`,
`proxy`.

| Namespace | Узел | Сервисы | Внутренние адреса (`*.svc.cluster.local`) | Веб-интерфейсы |
|---|---|---|---|---|
| `proxy` | core | NGINX Ingress (TLS) | `ingress-nginx-controller.proxy` | — |
| `vcs` | core | GitLab, Container Registry, MinIO (объекты GitLab) | `gitlab-webservice-default.vcs:8181`, `registry.vcs:5000`, `minio.vcs:9000` | https://gitlab.local, https://registry.local |
| `cicd` | core | Argo CD, GitLab Runner, Kyverno | `argocd-server.cicd` | https://argocd.local |
| `secret` | core | Vault, Vault Secrets Operator | `vault.secret:8200` | https://vault.local |
| `logs` | core | Prometheus, Alertmanager, Grafana, Jaeger | `logs-prometheus.logs:9090`, `jaeger.logs:4317/4318` (OTLP) | https://prometheus.local, https://alert.local, https://grafana.local, https://jaeger.local |
| `backup` | core | K8up, MinIO (резервные копии) | `minio.backup:9000` | https://backups.local |
| `db-<env>` | core | PostgreSQL, Redis, ClickHouse, Elasticsearch (в `db-prod` — ещё база `gitlabhq_production` и Redis-база 1 для GitLab) | `postgresql.db-<env>:5432`, `redis-master.db-<env>:6379`, `clickhouse.db-<env>:8123`, `elasticsearch.db-<env>:9200` | `/<env>/pgadmin`, `/<env>/redis`, `/<env>/clickhouse/play`, `/<env>/kibana` |
| `mb-<env>` | core | Kafka | `kafka.mb-<env>:9092` | `/<env>/kafka` |
| `acl-<env>` | core | Keycloak | `keycloak.acl-<env>:8080/<env>/keycloak` | `/<env>/keycloak` |
| `llm-<env>` | llms | llama.cpp | `llama.llm-<env>:8080/<env>/llama` (OpenAI API: `.../v1`) | `/<env>/llama` |
| `app-<env>` | apps | Свои приложения (Argo CD) | `<приложение>.app-<env>` | — |

Веб-интерфейсы окружений — на https://platform.local, например
https://platform.local/dev/kibana. ClickHouse Play:
`https://platform.local/<env>/clickhouse/play?url=https://platform.local/<env>/clickhouse/`.

## Команды

Из корня репозитория в терминале Ubuntu/WSL от обычного пользователя:

| Действие | Без флагов: кластер и все окружения |
|---|---|
| Установка и обновление (повторяемо) | `./cluster.sh up` |
| Запуск | `./cluster.sh start` |
| Остановка | `./cluster.sh stop` |
| Перезапуск | `./cluster.sh restart` |
| Проброс 80/443 на `127.0.0.1` (https://*.local) | `./cluster.sh ports open` |
| Проброс 80/443 в локальную сеть | `./cluster.sh ports open 0.0.0.0` |
| Закрытие | `./cluster.sh ports close` |
| Состояние | `./cluster.sh status` |
| Удаление (данные в `volumes/` сохраняются) | `./cluster.sh delete` |
| Разблокировка Vault | `./cluster.sh unseal` |
| Список резервных копий | `./cluster.sh backups` |
| Восстановление PVC | `./cluster.sh restore <namespace> <pvc> [ID]` |

Флаги `--dev`, `--stage`, `--prod` можно сочетать: `./cluster.sh up --dev --stage`.
Флаги действуют на namespace окружения (`db`, `mb`, `llm`, `acl`, `app`), общие
сервисы (GitLab, Argo CD, Vault, мониторинг, резервные копии) работают всегда.
GitLab хранит данные в PostgreSQL и Redis окружения prod, поэтому они в
`db-prod` есть всегда. Разблокировка Vault применяется без флагов `--dev`, `--stage`, `--prod`.

Проброс отдельного сервиса без ingress (закрывается Ctrl+C), например веб-интерфейс
llama.cpp окружения dev — http://localhost:81/dev/llama/:

```bash
kubectl port-forward -n llm-dev svc/llama 81:8080
```

Доверие к HTTPS-сертификату `*.local` (один раз после первого `up`, затем
перезапустите браузер).

Windows 11, из терминала WSL в корне репозитория:

```bash
certutil.exe -user -addstore Root "$(wslpath -w volumes/proxy/tls/ca.crt)"
```

Ubuntu:

```bash
sudo cp volumes/proxy/tls/ca.crt /usr/local/share/ca-certificates/platform.crt && sudo update-ca-certificates
```

## Важно

- Первый `up` может остановиться с просьбой выполнить `wsl.exe --shutdown` (WSL:
  `metadata` в `/etc/wsl.conf`, память в `.wslconfig`) или перелогиниться
  (Ubuntu: группа `docker`). После этого повторите `./cluster.sh up`. Hosts
  Windows обновляется через запрос UAC.
- Образы Docker Hub скачиваются через зеркало `mirror.gcr.io` (напрямую Docker Hub
  отдаёт их очень медленно); список зеркал — `registry_mirrors` в
  `terraform/variables.tf`. Первый `up` всё равно долгий: образов около 10 ГБ.
  Пока образы и модели llama.cpp скачиваются, `up` продолжает ждать (до 12
  повторов таймаута на релиз) и падает только при настоящей ошибке; после
  сбоя загрузку можно продолжить повторным `./cluster.sh up`.
- Ошибка «Docker недоступен» в WSL: запустите Docker Desktop, дождитесь
  «Engine running», включите Settings → Resources → WSL integration →
  переключатель вашего дистрибутива (например, Ubuntu) → Apply & restart.
  Откройте WSL заново, проверьте `docker info` и повторите `./cluster.sh up`.
- При первом `up` выводятся 5 unseal key Vault и пароль пользователя `admin` —
  сохраните их, повторно они не показываются. После каждого запуска Vault
  запечатан: `start`, `up` и `unseal` просят 3 ключа. Если изменились пути
  секретов (`k8s/secret/values.yaml`) или начальные значения, `up` тоже просит
  3 ключа: по ним создаётся временный root token, который отзывается после
  настройки.
- Логины и пароли — в Vault (https://vault.local, метод Userpass, `admin`),
  ключи `username` и `password`.
  - Создаются автоматически при первом `up` (список — `platform_vault_seed` в
    `ansible/roles/platform/defaults/main.yml`). Окружения: `db/<env>/postgresql`
    (владелец базы `app`), `db/<env>/redis`, `db/<env>/clickhouse`,
    `db/<env>/pgadmin` (вход в pgAdmin), `db/<env>/keycloak` (база Keycloak),
    `acl/<env>/keycloak` (администратор Keycloak). `backup/restic` — пароль
    шифрования резервных копий, без него копии не восстановить.
    Изменение в Vault позже не меняет уже созданные учётные записи; исключение —
    пароль Argo CD, он применяется при следующем `up`.
  - Заполняются вручную, затем `./cluster.sh up`:
    - `logs/smtp` — почта для оповещений Alertmanager: `username` — адрес
      ящика, `password` — пароль приложения почты; сервер, отправитель и
      получатели — `alertmanager.config` в `k8s/logs/values.yaml`;
    - `cicd/gitlab-runner` — `runner-token` и `runner-registration-token`
      (пока пути нет, GitLab Runner выключен);
    - `cicd/argocd-gitlab` — доступ Argo CD к репозиториям GitLab: `type=git`,
      `url=http://gitlab-webservice-default.vcs.svc.cluster.local:8181/<группа>`,
      `username` и `password` (personal access token с `read_repository`);
    - `vcs/registry` — deploy token GitLab (scope `read_registry`, ключи
      `username`, `password`): Secret `gitlab-registry` для скачивания образов
      появится в каждом `app-<env>`.
- Для проверки применени deploy токена группы проектов как секерт после его внесения в Vault (автоприменение 1-2 минуты, иначе комманда `./cluster.sh up`):

  ```bash
  kubectl get secret -n app-dev gitlab-registry
  ```

- Проверка уведомлений Alertmanager — тестовая тревога, письмо приходит примерно
  через 30 секунд:

  ```bash
  kubectl exec -n logs alertmanager-logs-alertmanager-0 -c alertmanager -- amtool alert add TestAlert severity=warning --annotation=summary="Проверка" --alertmanager.url=http://localhost:9093
  ```

  Если письма нет, на https://alert.local появится тревога
  `AlertmanagerFailedToSendAlerts`, причина — в журнале:
  `kubectl logs -n logs alertmanager-logs-alertmanager-0 -c alertmanager --tail=20`.

- https://registry.local — API Container Registry без веб-интерфейса (в браузере
  пустая страница): `docker login registry.local`, образы видны в GitLab
  (проект → Deploy → Container Registry).
- Внутри кластера registry доступен по тому же адресу `registry.local`:
  - поды и узлы находят его сами, а узлы доверяют его сертификату, поэтому
    образы `registry.local/...` скачиваются без дополнительной настройки
    (настраивает DaemonSet `node-hosts` в namespace `proxy`);
  - в задачах GitLab CI сертификат CA лежит в
    `/etc/docker/certs.d/registry.local/ca.crt`, вход —
    `docker login -u "$CI_REGISTRY_USER" -p "$CI_REGISTRY_PASSWORD" "$CI_REGISTRY"`;
  - собирайте образы в CI через kaniko с
    `--registry-certificate registry.local=/etc/docker/certs.d/registry.local/ca.crt`:
    docker-in-docker не работает, задачи запускаются без привилегий.
- HTTPS: без доверия к `volumes/proxy/tls/ca.crt` (команды выше) браузер
  показывает предупреждение о сертификате. CA действует только для имён `*.local`.
- `ports open 0.0.0.0` открывает сервисы в сеть; Prometheus, Alertmanager,
  Jaeger, Kafka UI, Kibana, RedisInsight и llama.cpp работают без авторизации.
- Данные хранятся в `volumes/` (в Git только `.gitkeep`), там же state
  Terraform (`volumes/terraform`). Удаляйте каталог только целиком: пароли в
  Vault (`volumes/secret`) и данные БД связаны. Ключи шифрования базы GitLab —
  `volumes/vcs/rails/gitlab-rails-secret.json`: без них GitLab отвечает ошибкой 500.
- Графики состояния: https://grafana.local (вход — Vault `logs/grafana`) →
  Dashboards → **Platform overview**: активные тревоги, CPU и память узлов и
  namespace, неготовые поды и перезапуски, PostgreSQL, Redis и ClickHouse всех
  окружений. Стандартные дашборды kube-prometheus-stack (Kubernetes / …, Node
  Exporter) показывают объекты кластера, но графики CPU и памяти контейнеров в
  них пусты: в minikube с Docker cAdvisor не видит контейнеры. Потребление
  ресурсов — в Platform overview (по узлам, подам и namespace).
- Резервные копии: K8up раз в сутки (02:00) копирует данные всех namespace
  (и сертификаты `*.local`, ключи GitLab) в MinIO namespace `backup`, каталог
  копии повторяет `volumes/`: `volumes/db/dev` → `volumes/backups/volumes/db/dev`.
  Пропущенную копию (сервер был выключен) создают `start` и `up`. Восстановление —
  [k8s/README.md](k8s/README.md#резервные-копии).
- Свои приложения разворачивайте через Argo CD в namespace `app-dev`,
  `app-stage` или `app-prod` с `nodeSelector: { platform.node: apps }`: поды
  получают папку `volumes/app/<env>/<приложение>` в `/app-data` (имя —
  метка `app.kubernetes.io/instance`, иначе `app.kubernetes.io/name`, иначе
  `app`, иначе `shared`). В `app-<env>` есть Secret `postgresql-credentials`,
  `redis-credentials`, `clickhouse-credentials` баз окружения. Шаблон бэкенда с
  настроенными подключениями и CI/CD — [example/node](example/node/README.md).
- Память: на core работают GitLab, мониторинг и сервисы трёх окружений — 20 ГБ
  заняты почти полностью. Если поды core уходят в OOMKilled, уменьшите heap
  сервисов в `k8s/<папка>/values.yaml` или выключите ненужные веб-интерфейсы.
- Характеристики сервера и узлов (CPU, RAM, диск, VRAM, память WSL, версия
  Kubernetes) задаются только в `terraform/variables.tf`; Ansible читает их из
  Terraform. Minikube даёт всем узлам один диск (наибольший `disk_gib`), в
  драйвере docker диск узлов общий с Docker.
- Изменение числа узлов, ресурсов `core`, GPU или версии Kubernetes в
  `terraform/variables.tf` пересоздаёт кластер при `up`; ресурсы `llms`/`apps`
  и VRAM меняются без пересоздания.
- VRAM: доли узлов — `nodes.*.vram_mib` в `terraform/variables.tf` (сумма не
  больше 4096 МиБ), затем `./cluster.sh up`. GPU получают только узлы с долей.
  В Ubuntu HAMi ограничивает VRAM подов: под запрашивает `nvidia.com/gpu: 1` и
  `nvidia.com/gpumem: <МиБ>`; образы с `NVIDIA_VISIBLE_DEVICES=all` без запроса
  GPU обходят ограничение. В WSL2 VRAM не ограничивается (библиотека HAMi
  несовместима с CUDA в WSL2): под запрашивает только `nvidia.com/gpu: 1`.
- GPU: в Ubuntu нужен драйвер NVIDIA (Container Toolkit ставится
  автоматически). Видеокарту делят llama.cpp трёх окружений (HAMi — по трети
  VRAM, WSL2 — time-slicing); если GPU недоступен, llama.cpp работает на CPU.
- LLM по умолчанию — [Qwen2.5-0.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct)
  (GGUF Q4_K_M); требования, адреса и смена модели — [k8s/llm/README.md](k8s/llm/README.md).
- Как менять и добавлять сервисы, папки, тома и маршруты — [k8s/README.md](k8s/README.md).
