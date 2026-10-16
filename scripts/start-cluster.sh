#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
HELM_ENV="${HELM_ENV:-dev}"

case "$HELM_ENV" in
  dev) PROFILE_NAME=development ;;
  staging) PROFILE_NAME=staging ;;
  prod) PROFILE_NAME=production ;;
  *)
    echo "HELM_ENV must be one of: dev, staging, prod." >&2
    exit 1
    ;;
esac

if ! docker info >/dev/null; then
  echo "Docker is not available. Start Docker Desktop or the Docker service, then retry." >&2
  exit 1
fi

if ! minikube status -p minikube >/dev/null 2>&1; then
  echo "Minikube is not running. Start it yourself with: bash scripts/start-minikube.sh" >&2
  exit 1
fi

if [[ "$(kubectl config current-context)" != "minikube" ]]; then
  echo "The active kubectl context is not minikube. Start/select the Minikube profile first." >&2
  exit 1
fi

kubectl wait --for=condition=Ready node --all --timeout=5m

kubectl config use-context minikube
if ! helm upgrade --help | grep -q -- '--take-ownership'; then
  echo "Требуется Helm 3.17 или новее для безопасного переноса существующих ресурсов." >&2
  exit 1
fi

helm lint ./k8s
for chart in k8s/charts/*/; do
  helm lint "$chart"
done

helm upgrade --install platform-foundation ./k8s \
  --namespace default --take-ownership --wait --timeout 5m

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add gitlab https://charts.gitlab.io --force-update
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add k8up https://k8up-io.github.io/k8up --force-update
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts --force-update
helm repo add nvidia-device-plugin https://nvidia.github.io/k8s-device-plugin --force-update
helm repo add argo https://argoproj.github.io/argo-helm --force-update
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --version 4.15.1 -n proxy \
  -f k8s/charts/proxy/templates/_ingress-values.yaml --wait --timeout 10m
helm upgrade --install vault hashicorp/vault \
  --version 0.34.1 -n secret -f k8s/charts/secret/templates/_vault-values.yaml
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  --version 1.6.0 -n secret
helm upgrade --install logs prometheus-community/kube-prometheus-stack \
  --version 92.9.0 -n logs \
  -f k8s/charts/logs/templates/_prometheus-values.yaml \
  -f "k8s/charts/logs/values-$PROFILE_NAME.yaml"
helm upgrade --install jaeger jaegertracing/jaeger \
  --version 4.16.1 -n logs -f k8s/charts/logs/templates/_jaeger-values.yaml
helm upgrade --install k8up k8up/k8up \
  --version 4.10.0 -n backup -f k8s/charts/backup/templates/_k8up-values.yaml

kubectl wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 \
  -n secret --timeout=10m

wait_for_crd() {
  kubectl wait --for=condition=Established "crd/$1" --timeout=5m
}

wait_for_crd vaultconnections.secrets.hashicorp.com
wait_for_crd vaultauths.secrets.hashicorp.com
wait_for_crd vaultstaticsecrets.secrets.hashicorp.com
wait_for_crd servicemonitors.monitoring.coreos.com
wait_for_crd prometheusrules.monitoring.coreos.com
wait_for_crd schedules.k8up.io

vault_status="$(kubectl exec -n secret vault-0 -- vault status -format=json 2>/dev/null || true)"
if [[ -z "$vault_status" ]] || ! jq -e '.initialized == true and .sealed == false' \
  <<<"$vault_status" >/dev/null; then
  cat >&2 <<'EOF'
The platform charts are installed, but Vault is not initialized and unsealed.
Initialize and unseal Vault, configure Kubernetes auth with:
  VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=<root-token> bash scripts/configure-vault.sh
Then add the required values to Vault and rerun bash scripts/start-cluster.sh.
See the "First-time Vault setup" section in README.md.
EOF
  exit 1
fi

helm upgrade --install platform-secrets ./k8s/charts/secret \
  --namespace secret --take-ownership --wait --timeout 5m
helm upgrade --install platform-cicd ./k8s/charts/cicd \
  --namespace cicd --take-ownership --wait --timeout 5m

required_secrets=(
  "db postgres-secret"
  "db postgres-app-credentials"
  "db pgadmin-secret"
  "db redis-secret"
  "db clickhouse-secret"
  "vcs gitlab-postgresql-password"
  "vcs gitlab-object-storage"
  "vcs gitlab-gitlab-initial-root-password"
  "acl keycloak-secret"
  "backup minio-secret"
  "backup k8up-s3"
  "backup k8up-restic"
  "logs smtp-credentials"
)
missing_secrets=()
for attempt in $(seq 1 60); do
  missing_secrets=()
  for entry in "${required_secrets[@]}"; do
    read -r namespace name <<<"$entry"
    if ! kubectl get secret "$name" -n "$namespace" >/dev/null 2>&1; then
      missing_secrets+=("$namespace/$name")
    fi
  done
  if ((${#missing_secrets[@]} == 0)); then
    break
  fi
  sleep 5
done
if ((${#missing_secrets[@]})); then
  printf 'Vault-synced Kubernetes secrets are missing:\n' >&2
  printf '  - %s\n' "${missing_secrets[@]}" >&2
  echo "Run bash scripts/configure-vault.sh if Vault auth is not configured." >&2
  echo "Add the corresponding KV values, wait for VSO, then rerun this script." >&2
  exit 1
fi

gpu_enabled=false
gpu_label="$(kubectl get node minikube -o json | jq -r '.metadata.labels["platform.gpu"] // "false"')"
if [[ "$gpu_label" == "true" ]]; then
  if helm upgrade --install nvidia-device-plugin \
    nvidia-device-plugin/nvidia-device-plugin --version 0.20.1 \
    --namespace kube-system \
    -f k8s/charts/gpu/values.yaml \
    --wait --timeout 5m; then
    for attempt in $(seq 1 60); do
      if kubectl get node minikube -o json |
        jq -e '(.status.allocatable["nvidia.com/gpu"] // "0" | tonumber) > 0' >/dev/null; then
        gpu_enabled=true
        break
      fi
      sleep 2
    done
  elif grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Предупреждение: NVIDIA device plugin недоступен в WSL2; Ollama будет работать на CPU." >&2
  else
    echo "Не удалось установить NVIDIA device plugin. Проверьте GPU-доступность узла." >&2
    exit 1
  fi
fi

if [[ "$gpu_label" == "true" && "$gpu_enabled" != "true" ]]; then
  if grep -qi microsoft /proc/version 2>/dev/null; then
    echo "Предупреждение: Kubernetes не обнаружил GPU в WSL2; Ollama будет работать на CPU." >&2
  else
    echo "Узел Minikube не зарегистрировал ресурс nvidia.com/gpu." >&2
    kubectl describe node minikube >&2
    exit 1
  fi
fi

helm upgrade --install platform-db ./k8s/charts/db \
  --namespace db --take-ownership
helm upgrade --install platform-mb ./k8s/charts/mb \
  --namespace mb --take-ownership
helm upgrade --install platform-acl ./k8s/charts/acl \
  --namespace acl --take-ownership
helm upgrade --install platform-backup ./k8s/charts/backup \
  --namespace backup --take-ownership
helm upgrade --install platform-llm ./k8s/charts/llm \
  --namespace llm --set gpu.enabled="$gpu_enabled" --take-ownership
helm upgrade --install platform-logs ./k8s/charts/logs \
  --namespace logs --take-ownership
helm upgrade --install platform-proxy ./k8s/charts/proxy \
  --namespace proxy --take-ownership
helm upgrade --install platform-hpa ./k8s/charts/hpa \
  --namespace default --take-ownership

kubectl rollout status statefulset/postgresql -n db --timeout=10m
kubectl rollout status statefulset/redis -n db --timeout=5m
kubectl wait --for=condition=complete job/minio-init -n backup --timeout=5m

helm upgrade --install gitlab gitlab/gitlab --version 10.5.0 -n vcs \
  -f k8s/charts/vcs/templates/_gitlab-values.yaml \
  -f "k8s/charts/vcs/values-$PROFILE_NAME.yaml"
kubectl rollout status deployment/gitlab-webservice-default -n vcs --timeout=20m
helm upgrade --install platform-vcs ./k8s/charts/vcs \
  --namespace vcs --take-ownership
kubectl rollout status deployment/registry -n vcs --timeout=10m

helm upgrade --install argocd argo/argo-cd \
  --version 10.10.5 -n cicd \
  -f k8s/charts/cicd/templates/_argocd-values.yaml --wait --timeout 10m

if kubectl get secret gitlab-runner-secret -n cicd >/dev/null 2>&1; then
  helm upgrade --install gitlab-runner gitlab/gitlab-runner \
    --version 0.94.0 -n cicd -f k8s/charts/cicd/templates/_runner-values.yaml
else
  echo "GitLab Runner skipped: add kv/cicd/gitlab-runner and sync its secret to enable it."
fi

if ! kubectl get secret argocd-gitlab-repository -n cicd >/dev/null 2>&1; then
  echo "Argo CD is installed without GitLab repository credentials."
  echo "Add kv/cicd/argocd-gitlab to Vault; VSO will sync the credentials automatically."
fi

echo "Cluster deployment ($HELM_ENV) is complete. Start bash scripts/forward-ingress.sh for localhost access."
