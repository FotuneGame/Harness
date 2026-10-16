#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
HELM_ENV="${HELM_ENV:-dev}"

case "$HELM_ENV" in
  dev|staging|prod) ;;
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
kubectl apply -f k8s/namespaces.yaml
kubectl apply -f k8s/storage.yaml

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
helm repo add gitlab https://charts.gitlab.io --force-update
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
helm repo add k8up https://k8up-io.github.io/k8up --force-update
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts --force-update
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n proxy -f k8s/proxy/values.yaml --wait --timeout 10m
helm upgrade --install vault hashicorp/vault \
  -n secret -f k8s/secret/values.yaml
helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  -n secret
helm upgrade --install logs prometheus-community/kube-prometheus-stack \
  -n logs -f k8s/logs/values.yaml -f "k8s/environments/$HELM_ENV/logs.yaml"
helm upgrade --install jaeger jaegertracing/jaeger \
  -n logs -f k8s/logs/jaeger-values.yaml
helm upgrade --install k8up k8up/k8up \
  -n backup -f k8s/backup/values.yaml

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

kubectl apply -f k8s/secret/auth-reviewer.yaml
kubectl apply -f k8s/secret/vault-static-secrets.yaml

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
for entry in "${required_secrets[@]}"; do
  read -r namespace name <<<"$entry"
  if ! kubectl get secret "$name" -n "$namespace" >/dev/null 2>&1; then
    missing_secrets+=("$namespace/$name")
  fi
done
if ((${#missing_secrets[@]})); then
  printf 'Vault-synced Kubernetes secrets are missing:\n' >&2
  printf '  - %s\n' "${missing_secrets[@]}" >&2
  echo "Run bash scripts/configure-vault.sh if Vault auth is not configured." >&2
  echo "Add the corresponding KV values, wait for VSO, then rerun this script." >&2
  exit 1
fi

for manifest in \
  k8s/db/pg/config.yaml \
  k8s/db/pg/init-config.yaml \
  k8s/db/redis/config.yaml \
  k8s/db/ch/config.yaml \
  k8s/mb/config.yaml \
  k8s/llm/ollama/config.yaml \
  k8s/acl/config.yaml \
  k8s/logs/exporter-config.yaml \
  k8s/backup/minio-policy.yaml \
  k8s/vcs/registry-config.yaml
do
  kubectl apply -f "$manifest"
done

kubectl apply -f k8s/db/pg/postgres.yaml
kubectl apply -f k8s/db/redis/redis.yaml
kubectl apply -f k8s/db/ch/clickhouse.yaml
kubectl apply -f k8s/mb/kafka.yaml
kubectl apply -f k8s/llm/ollama/ollama.yaml
kubectl apply -f k8s/acl/keycloak.yaml
kubectl apply -f k8s/backup/minio.yaml
kubectl rollout status statefulset/postgresql -n db --timeout=10m
kubectl rollout status statefulset/redis -n db --timeout=5m
kubectl wait --for=condition=complete job/minio-init -n backup --timeout=5m

helm upgrade --install gitlab gitlab/gitlab -n vcs \
  -f k8s/vcs/values.yaml -f "k8s/environments/$HELM_ENV/gitlab.yaml"
kubectl apply -f k8s/vcs/registry.yaml
kubectl apply -f k8s/logs/exporters.yaml
kubectl apply -f k8s/logs/alerts.yaml
kubectl apply -f k8s/logs/dashboard.yaml
kubectl apply -f k8s/backup/schedule.yaml
kubectl apply -f k8s/hpa/ui.yaml
kubectl apply -f k8s/proxy/ingress.yaml

if kubectl get secret gitlab-runner-secret -n ci >/dev/null 2>&1; then
  helm upgrade --install gitlab-runner gitlab/gitlab-runner -n ci \
    -f k8s/ci/values.yaml
else
  echo "GitLab Runner skipped: add kv/ci/gitlab-runner and sync its secret to enable it."
fi

echo "Cluster deployment ($HELM_ENV) is complete. Use kubectl port-forward for localhost access."
