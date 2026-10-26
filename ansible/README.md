# ansible: сервер и платформа

## Состав

| Playbook | Роль | Что делает |
|---|---|---|
| `host.yml` | `host` | Пакеты, Docker, minikube, kubectl, helm, terraform, настройки WSL, CA `*.local`, hosts, каталоги `volumes/` |
| `platform.yml` | `platform` | Vault, Helm-релизы из `k8s/`, ключи GitLab, пароль Argo CD |

## Переменные (`roles/platform/defaults/main.yml`)

| Переменная | Значение |
|---|---|
| `platform_releases` | Релизы Helm в порядке установки |
| `platform_envs` | Окружения `up`, по умолчанию `[dev, stage, prod]` |
| `platform_vault_seed` | Начальные значения Vault, `null` — случайный пароль |
| `platform_wait_attempts` | Повторы ожидания загрузки образов |

## Файлы

| Файл | Назначение |
|---|---|
| `roles/platform/files/pull-images.sh`, `release-images.py` | Загрузка образов релиза в узлы |
| `roles/platform/files/retry-downloading.sh` | Повтор `helm --wait` во время загрузки образов |
| `roles/platform/templates/vault-init.sh.j2` | Настройка Vault |
| `roles/host/files/windows-hosts.ps1` | Имена `*.local` в hosts Windows |
| `callback_plugins/progress.py` | Вывод хода долгих задач |

## Команды

Из корня репозитория.

- Для установки и обновления всего: `./cluster.sh up`
- Для обновления одного окружения: `./cluster.sh up --dev`
- Для проверки синтаксиса: `ansible-playbook -i ansible/inventory.ini ansible/platform.yml --syntax-check`
- Для просмотра списка задач: `ansible-playbook -i ansible/inventory.ini ansible/host.yml --list-tasks`

## Важно

- `./cluster.sh up` запускает `host.yml` (с `sudo`), Terraform, затем `platform.yml`.
- Повторный запуск безопасен: задачи проверяют, сделано ли действие.
- Изменение `k8s/secret/values.yaml`, `platform_vault_seed` или `vault-init.sh.j2` применяется к Vault заново, `up` попросит 3 unseal key.
- Первый `up` может попросить `wsl.exe --shutdown` (WSL) или перелогиниться (Ubuntu), затем повторите `./cluster.sh up`.
