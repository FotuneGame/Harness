# Terraform: узлы кластера

Создаёт minikube (драйвер docker) из трёх узлов и задаёт им ресурсы, метки
`platform.node` и taint. Запускается из `./cluster.sh up` и `delete`; state — в
`volumes/terraform/terraform.tfstate`.

| Файл | Что внутри |
|---|---|
| `variables.tf` | Сервер (`host`), узлы (`nodes`), GPU, зеркала Docker Hub, версия Kubernetes |
| `main.tf` | `terraform_data.cluster` — `minikube start`, `terraform_data.node` — ресурсы, метки, taint |
| `outputs.tf` | `nodes`, `allocated`, `ansible` (параметры для Ansible) |
| `.terraformrc` | Зеркало провайдеров (`terraform-mirror.yandexcloud.net`) |

| Узел | Метка `platform.node` | Назначение |
|---|---|---|
| `minikube` | `core` | Все сервисы платформы и окружений |
| `minikube-m02` | `llms` | llama.cpp, GPU |
| `minikube-m03` | `apps` | Свои приложения, taint `workload=apps:NoSchedule` |

## Команды

Из корня репозитория.

| Действие | Команда |
|---|---|
| Применить (вместе с Ansible) | `./cluster.sh up` |
| Что изменится | `TF_CLI_CONFIG_FILE=terraform/.terraformrc terraform -chdir=terraform plan` |
| Узлы и ресурсы | `terraform -chdir=terraform output nodes` |
| Проверка | `terraform -chdir=terraform fmt -check && terraform -chdir=terraform validate` |
| Удалить кластер | `./cluster.sh delete` |

## Важно

- Ресурсы задаются только в `variables.tf`: сумма узлов не больше `host` (RAM —
  с запасом для ОС, VRAM — не больше 4096 МиБ).
- Изменение числа узлов, ресурсов `core`, GPU, зеркал или версии Kubernetes
  пересоздаёт кластер (данные в `volumes/` сохраняются); ресурсы `llms`/`apps`
  и VRAM меняются без пересоздания.
