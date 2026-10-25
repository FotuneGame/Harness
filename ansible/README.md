# Ansible: сервер и платформа

`./cluster.sh up` запускает два playbook: `host.yml` (подготовка сервера, с
`sudo`), затем Terraform, затем `platform.yml` (Vault, Helm-релизы из `k8s/`).

| Роль | Что делает |
|---|---|
| `host` | Пакеты, helm, terraform, minikube, kubectl, Docker (Ubuntu), NVIDIA Container Toolkit, настройки WSL, ключ etcd, CA и сертификат `*.local`, hosts Linux и Windows, каталоги `volumes/` |
| `platform` | Зависимости charts, foundation, Vault (инициализация, политики, начальные секреты), proxy, GPU, все релизы, копия ключей GitLab, пароль Argo CD |

| Переменная (`roles/platform/defaults/main.yml`) | Назначение |
|---|---|
| `platform_releases` | Релизы Helm по порядку установки (`env` — окружение, `shared` — ставится всегда, `logins` — логины из Vault) |
| `platform_envs` | Окружения для `up` (по умолчанию все; `./cluster.sh up --dev` передаёт `[dev]`) |
| `platform_vault_seed` | Начальные значения Vault (`null` — случайный пароль) |
| `platform_wait_attempts` | Повторы ожидания, пока скачиваются образы |

| Файл | Назначение |
|---|---|
| `roles/platform/files/pull-images.sh`, `release-images.py` | Образы релиза заранее в узлы (Docker Hub — через зеркало, остальные — через Docker сервера) |
| `roles/platform/files/retry-downloading.sh` | Повтор `helm --wait`, пока идёт загрузка образов |
| `roles/platform/templates/vault-init.sh.j2` | Настройка Vault (выполняется в поде `vault-0`) |
| `roles/host/files/windows-hosts.ps1` | Имена `*.local` в hosts Windows (UAC) |
| `callback_plugins/progress.py` | Вывод с ходом долгих задач |

## Команды

Из корня репозитория.

| Действие | Команда |
|---|---|
| Всё (сервер, узлы, платформа) | `./cluster.sh up` |
| Только платформа, окружение dev | `ansible-playbook -i ansible/inventory.ini ansible/platform.yml -e '{"platform_envs": ["dev"]}'` |
| Проверка синтаксиса | `ansible-playbook -i ansible/inventory.ini ansible/platform.yml --syntax-check` |
| Список задач | `ansible-playbook -i ansible/inventory.ini ansible/host.yml --list-tasks` |

## Важно

- Повторный запуск безопасен: каждая задача проверяет, сделано ли действие.
- Изменение `k8s/secret/values.yaml`, `platform_vault_seed` или
  `vault-init.sh.j2` применяется к Vault заново — `up` попросит 3 unseal key.
