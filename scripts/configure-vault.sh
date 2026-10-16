#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -z "${VAULT_ADDR:-}" || -z "${VAULT_TOKEN:-}" ]]; then
  echo "Set VAULT_ADDR and VAULT_TOKEN in the environment; do not put them in files." >&2
  exit 1
fi
for command in vault kubectl jq; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

vault status -format=json | jq -e '.initialized == true and .sealed == false' >/dev/null
kubectl apply -f k8s/secret/auth-reviewer.yaml

if ! vault auth list -format=json | jq -e 'has("kubernetes/")' >/dev/null; then
  vault auth enable kubernetes
fi
vault write auth/kubernetes/config kubernetes_host=https://kubernetes.default.svc

if ! vault secrets list -format=json | jq -e 'has("kv/")' >/dev/null; then
  vault secrets enable -path=kv kv-v2
fi

for policy in k8s/secret/policies/*.hcl; do
  policy_name="$(basename "$policy" .hcl)"
  vault policy write "$policy_name" "$policy"
done

for namespace in db vcs acl ci backup logs; do
  vault write "auth/kubernetes/role/platform-$namespace" \
    bound_service_account_names=default \
    bound_service_account_namespaces="$namespace" \
    policies="platform-$namespace" ttl=1h
done

kubectl apply -f k8s/secret/vault-static-secrets.yaml
echo "Vault auth, policies, roles and VSO resources are configured."
echo "Add the required secret values to Vault, then run bash scripts/start-cluster.sh."
