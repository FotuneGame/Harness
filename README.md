# Локальная инфраструктура Kubernetes

Minikube из трёх узлов. Terraform создаёт узлы, Ansible устанавливает пакеты,
настраивает сервер и разворачивает Helm charts (`k8s/<namespace>`), Helm
разделяет окружения dev, stage и prod.

## Сервер

| Параметр | Значение |
|---|---|
| CPU | Intel Core i5-11400F, 6 ядер / 12 потоков, 2.6 ГГц |
| RAM | 48 ГБ, кластеру выделено 32 ГБ |
| Диск | 450 ГБ |
| GPU | NVIDIA GeForce GTX 1650, 4 ГБ |
| ОС | Ubuntu 22.04+ или Windows 11 + WSL2 Ubuntu 22.04+ с Docker Desktop (WSL integration) |

## Узлы (`terraform/variables.tf`)

| Узел | `platform.node` | CPU | RAM | Диск | VRAM | Назначение |
|---|---|---|---|---|---|---|
| `minikube` | `core` | 6 | 16 ГБ | 100 ГБ | 0 | Платформенные сервисы и мониторинг |
| `minikube-m02` | `llms` | 4 | 8 ГБ | 100 ГБ | 4096 МБ | llama.cpp, Open WebUI |
| `minikube-m03` | `apps` | 2 | 4 ГБ | 100 ГБ | 0 | Приложения из Argo CD (taint `workload=apps:NoSchedule`) |

| Namespace | Узел | Сервисы | Адреса |
|---|---|---|---|
| `db` | core | PostgreSQL, pgAdmin, Redis, RedisInsight, ClickHouse, Elasticsearch | pg.local, redis.local, clickhouse.local |
| `mb` | core | Kafka, Kafka UI | kafka.local |
| `vcs` | core | GitLab, GitLab Container Registry | gitlab.local, registry.local |
| `cicd` | core | Argo CD, GitLab Runner, Kyverno | argocd.local |
| `proxy` | core | NGINX Ingress Controller | — |
| `secret` | core | Vault, Vault Secrets Operator | vault.local |
| `acl` | core | Keycloak | keycloak.local |
| `logs` | core | Prometheus, Alertmanager, Grafana, Jaeger, exporters | prometheus.local, alert.local, grafana.local, jaeger.local |
| `backup` | core | K8up, MinIO | — |
| `llm` | llms | llama.cpp, Open WebUI | llama.local |
| `app` | apps | Приложения из Argo CD, папки `volumes/app/<приложение>` | — |

## Команды

Из корня репозитория в терминале Ubuntu/WSL от обычного пользователя:

| Действие | Команда |
|---|---|
| Установка, запуск и обновление (повторяемо) | `./cluster.sh up [dev\|stage\|prod]` |
| Запуск после остановки | `./cluster.sh start` |
| Остановка | `./cluster.sh stop` |
| Перезапуск | `./cluster.sh restart` |
| Разблокировка Vault | `./cluster.sh unseal` |
| Проброс 80/443 на `127.0.0.1` (https://*.local) | `./cluster.sh ports open` |
| Проброс 80/443 в локальную сеть | `./cluster.sh ports open 0.0.0.0` |
| Закрытие проброса | `./cluster.sh ports close` |
| Состояние | `./cluster.sh status` |
| Удаление кластера (данные в `volumes/` сохраняются) | `./cluster.sh delete` |

Проброс отдельного сервиса (закрывается Ctrl+C):

```bash
kubectl port-forward -n db svc/postgresql 5432:5432
```

Доверие к HTTPS-сертификату `*.local` (один раз после первого `up`, затем
перезапустите браузер). Windows 11, из терминала WSL в корне репозитория:

```bash
certutil.exe -user -addstore Root "$(wslpath -w volumes/proxy/tls/ca.crt)"
```

Ubuntu:

```bash
sudo cp volumes/proxy/tls/ca.crt /usr/local/share/ca-certificates/platform.crt && sudo update-ca-certificates
```

## Важно

- Первый `up` может остановиться с просьбой выполнить `wsl.exe --shutdown` (WSL:
  `metadata` в `/etc/wsl.conf`, 32 ГБ в `.wslconfig`) или перелогиниться (Ubuntu:
  группа `docker`). После этого повторите `./cluster.sh up`. Hosts Windows
  обновляется через запрос UAC.
- Образы Docker Hub скачиваются через зеркало `mirror.gcr.io` (напрямую Docker Hub
  отдаёт их очень медленно); список зеркал — `registry_mirrors` в
  `terraform/variables.tf`. Первый `up` всё равно долгий: образов около 10 ГБ.
  Пока образы и модель llama.cpp скачиваются, `up` продолжает ждать (до 12
  повторов таймаута на релиз) и падает только при настоящей ошибке; после
  сбоя загрузку можно продолжить повторным `./cluster.sh up`.
- Ошибка «Docker недоступен» в WSL: запустите Docker Desktop, дождитесь
  «Engine running», включите Settings → Resources → WSL integration →
  переключатель вашего дистрибутива (например, Ubuntu) → Apply & restart.
  Откройте WSL заново, проверьте `docker info` и повторите `./cluster.sh up`.
- При первом `up` выводятся 5 unseal key Vault и пароль пользователя `admin` —
  сохраните их, повторно они не показываются. После каждого запуска Vault
  запечатан: `start`, `up` и `unseal` просят 3 ключа.
- Логины и пароли — в Vault (какой путь для какого сайта — таблица выше).
  - Создаются автоматически при первом `up` (список — `platform_vault_seed` в
    `ansible/roles/platform/defaults/main.yml`); `backup/restic` — пароль
    шифрования резервных копий K8up, без него копии не восстановить.
    Изменение в Vault позже не меняет уже созданные учётные записи; исключение —
    пароль Argo CD, он применяется при следующем `up`.
  - Заполняются вручную, затем `./cluster.sh up`:
    - `logs/smtp` — почта для оповещений Alertmanager (замените `password`);
    - `cicd/gitlab-runner` — `runner-token` и `runner-registration-token`
      (пока пути нет, GitLab Runner выключен);
    - `cicd/argocd-gitlab` — доступ Argo CD к репозиториям GitLab: `type=git`,
      `url=http://gitlab-webservice-default.vcs.svc.cluster.local:8181/<группа>`,
      `username` и `password` (personal access token с `read_repository`).
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
- Образ из registry в приложении Argo CD: создайте в GitLab deploy token
  (проект или группа → Settings → Repository → Deploy tokens, scope
  `read_registry`) и Secret в namespace `app`, затем укажите в поде
  `imagePullSecrets: [{ name: gitlab-registry }]` и образ
  `registry.local/<группа>/<проект>:<тег>`:

  ```bash
  kubectl create secret docker-registry gitlab-registry -n app --docker-server=registry.local \
    --docker-username=<имя deploy token> --docker-password=<deploy token>
  ```
- HTTPS: без доверия к `volumes/proxy/tls/ca.crt` (команды выше) браузер
  показывает предупреждение о сертификате. CA действует только для имён `*.local`.
- `ports open 0.0.0.0` открывает сервисы в сеть; Prometheus, Alertmanager,
  Jaeger, Kafka UI и RedisInsight работают без авторизации.
- Данные хранятся в `volumes/` (в Git не попадают). Удаляйте каталог только
  целиком: пароли в Vault (`volumes/secret`) и данные БД связаны.
- Приложения Argo CD разворачивайте в namespace `app`: поды автоматически
  попадают на узел apps и получают папку `volumes/app/<приложение>` в `/app-data`
  (имя — метка `app.kubernetes.io/instance`, иначе `app.kubernetes.io/name`, иначе
  `app`, иначе `shared`). Данные приложений входят в резервное копирование.
- Характеристики сервера и узлов (CPU, RAM, диск, VRAM, память WSL, версия
  Kubernetes) задаются только в `terraform/variables.tf`; Ansible читает их из Terraform.
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
  автоматически). Если GPU недоступен (часто в WSL2), llama.cpp работает на CPU.
- Отличия окружений — в `k8s/<chart>/values-<env>.yaml`, общие значения — в
  `values.yaml`. Как менять и добавлять сервисы — [k8s/README.md](k8s/README.md).
