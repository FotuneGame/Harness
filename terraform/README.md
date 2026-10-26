# terraform: узлы кластера

## Состав

| Файл | Содержимое |
|---|---|
| `variables.tf` | Ресурсы сервера и узлов, GPU, зеркала Docker Hub, версия Kubernetes |
| `main.tf` | Создание minikube, ресурсы, метки и taint узлов |
| `outputs.tf` | Параметры для Ansible |
| `.terraformrc` | Зеркало провайдеров |
| State | `volumes/terraform/terraform.tfstate` |

## Узлы

| Узел | `platform.node` | CPU | RAM | Диск | VRAM | Назначение |
|---|---|---|---|---|---|---|
| `minikube` | `core` | 6 | 20 ГБ | 200 ГБ | 0 | Сервисы платформы и окружений |
| `minikube-m02` | `llms` | 4 | 16 ГБ | 200 ГБ | 4096 МБ | llama.cpp |
| `minikube-m03` | `apps` | 2 | 4 ГБ | 50 ГБ | 0 | Свои приложения, taint `workload=apps:NoSchedule` |

## Команды

Из корня репозитория.

- Для создания и обновления узлов: `./cluster.sh up`
- Для просмотра изменений: `TF_CLI_CONFIG_FILE=terraform/.terraformrc terraform -chdir=terraform plan`
- Для просмотра узлов и ресурсов: `terraform -chdir=terraform output nodes`
- Для проверки файлов: `terraform -chdir=terraform fmt -check && terraform -chdir=terraform validate`
- Для удаления кластера: `./cluster.sh delete`

## Важно

- Ресурсы задаются только в `variables.tf`, сумма узлов не больше ресурсов сервера.
- Изменение числа узлов, ресурсов `core`, GPU, зеркал или версии Kubernetes пересоздаёт кластер, данные в `volumes/` сохраняются.
- Ресурсы `llms`, `apps` и VRAM меняются без пересоздания.
