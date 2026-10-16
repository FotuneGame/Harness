#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

for command in kubectl jq vault; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Не найдена команда $command. Сначала выполните bash scripts/prepare-host.sh." >&2
    exit 1
  fi
done

if [[ ! -t 0 || ! -t 1 ]]; then
  echo "Запустите скрипт из интерактивного терминала: bash scripts/bootstrap-vault.sh" >&2
  exit 1
fi

if ! kubectl get namespace secret >/dev/null 2>&1; then
  echo "Namespace secret не найден. Сначала установите Vault: bash scripts/start-cluster.sh." >&2
  exit 1
fi

if ! kubectl get pod vault-0 -n secret >/dev/null 2>&1; then
  echo "Pod vault-0 не найден. Сначала установите Vault: bash scripts/start-cluster.sh." >&2
  exit 1
fi

echo "Ожидание запуска pod vault-0..."
if ! kubectl wait --for=jsonpath='{.status.phase}'=Running pod/vault-0 \
  -n secret --timeout=5m; then
  echo "Pod vault-0 не запустился за 5 минут. Проверьте состояние командой:" >&2
  echo "  kubectl describe pod vault-0 -n secret" >&2
  exit 1
fi

read_vault_status() {
  local status
  status="$(kubectl exec -n secret vault-0 -- vault status -format=json 2>/dev/null || true)"
  if [[ -z "$status" ]] || ! jq -e '.initialized | type == "boolean"' <<<"$status" >/dev/null; then
    echo "Не удалось получить состояние Vault. Проверьте pod vault-0." >&2
    return 1
  fi
  printf '%s' "$status"
}

status_json="$(read_vault_status)"
initialized="$(jq -r '.initialized' <<<"$status_json")"
sealed="$(jq -r '.sealed' <<<"$status_json")"

if [[ "$initialized" == "false" ]]; then
  echo "Vault ещё не инициализирован. Сейчас будут созданы 5 ключей и root token."
  echo "Сохраните их вне репозитория: для разблокировки понадобятся любые 3 ключа."
  read -rp "Введите INIT для продолжения: " confirmation
  if [[ "$confirmation" != "INIT" ]]; then
    echo "Инициализация отменена."
    exit 1
  fi
  kubectl exec -it -n secret vault-0 -- vault operator init
  sealed="true"
fi

if [[ "$sealed" == "true" ]]; then
  echo "Нужно ввести три разных unseal key по очереди."
  for attempt in 1 2 3; do
    echo "Ключ $attempt из 3:"
    kubectl exec -it -n secret vault-0 -- vault operator unseal
  done
fi

status_json="$(read_vault_status)"
if ! jq -e '.initialized == true and .sealed == false' <<<"$status_json" >/dev/null; then
  echo "Vault остался запечатанным или не инициализирован." >&2
  exit 1
fi

kubectl port-forward --address 127.0.0.1 -n secret \
  service/vault 8200:8200 >/dev/null 2>&1 &
port_forward_pid=$!
cleanup() {
  kill "$port_forward_pid" 2>/dev/null || true
  wait "$port_forward_pid" 2>/dev/null || true
  unset VAULT_TOKEN
}
trap cleanup EXIT

export VAULT_ADDR=http://127.0.0.1:8200
connected=false
for attempt in $(seq 1 30); do
  if ! kill -0 "$port_forward_pid" 2>/dev/null; then
    echo "Не удалось запустить port-forward к Vault на 127.0.0.1:8200." >&2
    echo "Убедитесь, что порт 8200 свободен." >&2
    exit 1
  fi
  if vault status -format=json >/dev/null 2>&1; then
    connected=true
    break
  fi
  sleep 1
done
if [[ "$connected" != "true" ]]; then
  echo "Vault не ответил через port-forward за 30 секунд." >&2
  exit 1
fi

if [[ -z "${VAULT_TOKEN:-}" ]]; then
  read -rsp "Вставьте initial root token: " VAULT_TOKEN
  echo
fi
if [[ -z "$VAULT_TOKEN" ]]; then
  echo "Root token не может быть пустым." >&2
  exit 1
fi
export VAULT_TOKEN

bash scripts/configure-vault.sh

cat <<'EOF'

Первичная настройка Vault завершена.
Теперь внесите значения секретов приложений в KV v2 согласно README.md,
дождитесь их синхронизации VSO и запустите bash scripts/start-cluster.sh.
EOF
