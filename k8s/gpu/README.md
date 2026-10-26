# gpu: GPU для llama.cpp

## Состав

| Параметр | Значение |
|---|---|
| Релиз | `platform-gpu` |
| Namespace | `kube-system` |
| Узел | `llms` (метка `platform.gpu=on`) |
| Ubuntu | [HAMi](https://github.com/Project-HAMi/HAMi), лимит VRAM на под |
| WSL2 | [NVIDIA device plugin](https://github.com/NVIDIA/k8s-device-plugin), time-slicing без лимита VRAM |

## Команды

- Для установки и обновления: `./cluster.sh up`
- Для проверки GPU узла: `kubectl describe node minikube-m02 | grep -i nvidia`

## Важно

- Chart выбирает и настраивает Ansible (`ansible/roles/platform/tasks/gpu.yml`), вручную не устанавливается.
- Без NVIDIA GPU релиз не ставится, llama.cpp работает на CPU.
- Доля VRAM узла — `nodes.llms.vram_mib` в `terraform/variables.tf`.
