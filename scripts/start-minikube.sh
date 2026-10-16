#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command in docker minikube kubectl terraform jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Не найдена команда $command. Установите её перед запуском Minikube." >&2
    exit 1
  fi
done

if ! docker info >/dev/null; then
  echo "Docker недоступен. Запустите Docker Desktop или службу Docker." >&2
  exit 1
fi

gpu_args=()
gpu_available=false
is_wsl=false
if grep -qi microsoft /proc/version 2>/dev/null; then
  is_wsl=true
fi

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  if docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi -L >/dev/null 2>&1; then
    gpu_args=(--gpus all)
    gpu_available=true
  elif [[ "$is_wsl" == "true" ]]; then
    echo "Предупреждение: Docker не передал NVIDIA GPU. Minikube продолжит работу без GPU." >&2
  else
    echo "Docker не может использовать NVIDIA GPU. Проверьте NVIDIA Container Toolkit:" >&2
    echo "  sudo nvidia-ctk runtime configure --runtime=docker" >&2
    echo "  sudo systemctl restart docker" >&2
    echo "  docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu22.04 nvidia-smi -L" >&2
    exit 1
  fi
elif [[ "$is_wsl" == "true" ]]; then
  echo "Предупреждение: NVIDIA GPU недоступен в WSL2; Minikube продолжит работу без GPU." >&2
else
  echo "NVIDIA GPU не обнаружен. Проверьте драйвер командой nvidia-smi." >&2
  exit 1
fi

if [[ "$is_wsl" != "true" && -r /proc/sys/net/core/bpf_jit_harden ]] &&
  [[ "$(cat /proc/sys/net/core/bpf_jit_harden)" != "0" ]]; then
  echo "Minikube GPU требует net.core.bpf_jit_harden=0. Выполните:" >&2
  echo "  sudo sysctl -w net.core.bpf_jit_harden=0" >&2
  echo "Затем повторите запуск." >&2
  exit 1
fi

if [[ "$gpu_available" == "true" ]] && minikube status -p minikube >/dev/null 2>&1; then
  gpu_requests="$(docker inspect --format '{{json .HostConfig.DeviceRequests}}' minikube 2>/dev/null || true)"
  if ! grep -qi nvidia <<<"$gpu_requests"; then
    echo "Уже созданный Minikube-профиль не был запущен с GPU." >&2
    echo "Сохраните данные и пересоздайте профиль с параметром --gpus all." >&2
    exit 1
  fi
fi

node_profiles="$(terraform -chdir=terraform output -json node_profiles)"
node_count="$(jq -er 'select(has("platform") and has("applications")) | length' <<<"$node_profiles")"
platform_cpu="$(jq -er '.platform.cpu_cores | select(type == "number" and . > 0)' <<<"$node_profiles")"
platform_memory="$(jq -er '.platform.memory_gib | select(type == "number" and . > 0)' <<<"$node_profiles")"
platform_disk="$(jq -er '.platform.disk_gib | select(type == "number" and . > 0)' <<<"$node_profiles")"
application_cpu="$(jq -er '.applications.cpu_cores | select(type == "number" and . > 0)' <<<"$node_profiles")"
application_memory="$(jq -er '.applications.memory_gib | select(type == "number" and . > 0)' <<<"$node_profiles")"
application_disk="$(jq -er '.applications.disk_gib | select(type == "number" and . > 0)' <<<"$node_profiles")"
platform_memory_mb="$((platform_memory * 1024))"

if [[ "$platform_disk" != "$application_disk" ]]; then
  echo "Minikube создаёт одинаковый размер диска для узлов одного профиля." >&2
  echo "Укажите одинаковый disk_gib для platform и applications в Terraform." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/volumes"
minikube start \
  --profile=minikube \
  --driver=docker \
  --nodes="$node_count" \
  --cpus="$platform_cpu" \
  --memory="$platform_memory_mb" \
  --disk-size="${platform_disk}g" \
  "${gpu_args[@]}" \
  --mount \
  --mount-string="$ROOT_DIR/volumes:/volumes"

docker update \
  --cpus="$platform_cpu" \
  --memory="${platform_memory}g" \
  --memory-swap="${platform_memory}g" \
  minikube
docker update \
  --cpus="$application_cpu" \
  --memory="${application_memory}g" \
  --memory-swap="${application_memory}g" \
  minikube-m02

kubectl config use-context minikube
kubectl wait --for=condition=Ready node --all --timeout=5m
kubectl label node minikube node-role.platform=true --overwrite
kubectl taint node minikube-m02 workload=applications:NoSchedule --overwrite
kubectl label node minikube platform.gpu="$gpu_available" --overwrite
minikube addons enable metrics-server

echo "Minikube запущен по ресурсному профилю Terraform."
if [[ "$gpu_available" == "true" ]]; then
  echo "NVIDIA GPU будет включён для Ollama после установки device plugin."
else
  echo "Ollama будет использовать CPU."
fi
