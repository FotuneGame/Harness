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
minikube addons enable metrics-server

echo "Minikube запущен по ресурсному профилю Terraform."
