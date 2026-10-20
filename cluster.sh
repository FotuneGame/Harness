#!/usr/bin/env bash
# Управление локальным Kubernetes-кластером. Справка: ./cluster.sh help
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "$0")")"

readonly PROFILE=minikube
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/platform"
readonly PORTS_PID="$STATE_DIR/ports.pid"
readonly PORTS_LOG="$STATE_DIR/ports.log"
export TF_CLI_CONFIG_FILE="$PWD/terraform/.terraformrc"

usage() {
  cat <<'EOF'
Использование: ./cluster.sh <команда>

  up [dev|stage|prod]   установка зависимостей, создание узлов и развёртывание (повторяемо)
  start                 запуск остановленного кластера и разблокировка Vault
  stop                  закрытие портов и остановка кластера
  restart               stop + start
  unseal                разблокировка Vault (3 unseal key)
  ports open [адрес]    проброс ingress 80/443 на адрес хоста (по умолчанию 127.0.0.1)
  ports close           закрытие проброса
  ports status          состояние проброса
  status                узлы, проблемные pod, Vault, проброс
  delete                удаление кластера (данные в volumes/ сохраняются)
EOF
}

log() { printf '\n==> %s\n' "$*"; }
kubectl() { command kubectl --context "$PROFILE" "$@"; }
cluster_exists() { docker container inspect "$PROFILE" >/dev/null 2>&1; }
cluster_running() { minikube status --profile "$PROFILE" >/dev/null 2>&1; }

require_cluster() {
  cluster_exists || { echo "Кластер не создан: выполните ./cluster.sh up" >&2; exit 1; }
}

install_ansible() {
  if ! command -v ansible-playbook >/dev/null; then
    log "Установка Ansible"
    sudo apt-get update
    sudo apt-get install -y software-properties-common
    sudo add-apt-repository -y --update ppa:ansible/ansible
    sudo apt-get install -y ansible
  fi
  ansible-doc community.general.ini_file >/dev/null 2>&1 \
    || ansible-galaxy collection install community.general
}

playbook() { ansible-playbook -i ansible/inventory.ini "$@"; }

# Узлы создаёт Terraform; остановленный кластер запускается с прежними параметрами.
provision() {
  log "Terraform: узлы кластера"
  terraform -chdir=terraform init -input=false >/dev/null
  local replace=()
  if terraform -chdir=terraform state list 2>/dev/null | grep -qx terraform_data.cluster && ! cluster_exists; then
    replace=(-replace=terraform_data.cluster)
  fi
  terraform -chdir=terraform apply -input=false -auto-approve "${replace[@]}"
  cluster_running || minikube start --profile "$PROFILE"
}

vault_status() {
  { kubectl exec -n secret vault-0 -- vault status -format=json 2>/dev/null || true; } | jq -r ".$1"
}

cmd_up() {
  local env=${1:-dev}
  [[ $env =~ ^(dev|stage|prod)$ ]] || { usage; exit 1; }
  install_ansible

  log "Ansible: подготовка сервера"
  local become=()
  sudo -n -k true 2>/dev/null || become=(--ask-become-pass)
  playbook ansible/host.yml "${become[@]}"

  provision

  log "Ansible: сервисы ($env)"
  playbook ansible/platform.yml -e "platform_env=$env"
}

cmd_start() {
  require_cluster
  log "Запуск кластера"
  minikube start --profile "$PROFILE"
  cmd_unseal
}

cmd_stop() {
  ports_close
  log "Остановка кластера"
  minikube stop --profile "$PROFILE"
}

cmd_restart() {
  cmd_stop
  cmd_start
}

# Vault запечатывается при каждом перезапуске pod: нужны 3 из 5 unseal key.
cmd_unseal() {
  kubectl wait pod/vault-0 -n secret --for=jsonpath='{.status.phase}'=Running --timeout=10m >/dev/null
  if [ "$(vault_status initialized)" != true ]; then
    echo "Vault ещё не инициализирован: его настроит ./cluster.sh up."
    return
  fi
  local key
  while [ "$(vault_status sealed)" = true ]; do
    read -rsp "Unseal key Vault: " key && echo
    # shellcheck disable=SC2016 # $key раскрывается внутри pod.
    printf '%s\n' "$key" | kubectl exec -i -n secret vault-0 -- sh -c 'read -r key; vault operator unseal "$key"' \
      >/dev/null || echo "Ключ не принят."
  done
  echo "Vault разблокирован."
}

# Проброс service/ingress-nginx-controller на хост; перезапускается при обрыве.
ports_open() {
  local address=${1:-127.0.0.1}
  require_cluster
  ports_close >/dev/null
  mkdir -p "$STATE_DIR"
  # shellcheck disable=SC2016 # аргументы передаются в bash -c позиционно.
  setsid bash -c 'echo $$ >"$1"; while true; do
      kubectl --context "$2" port-forward --address "$3" -n proxy service/ingress-nginx-controller 80:80 443:443
      sleep 2
    done' _ "$PORTS_PID" "$PROFILE" "$address" >"$PORTS_LOG" 2>&1 </dev/null &
  for _ in $(seq 30); do
    grep -q "Forwarding from" "$PORTS_LOG" && { echo "Проброс открыт: https://*.local → $address:443"; return; }
    sleep 1
  done
  cat "$PORTS_LOG" >&2
  ports_close >/dev/null
  exit 1
}

ports_close() {
  if [ -f "$PORTS_PID" ]; then
    kill -- "-$(cat "$PORTS_PID")" 2>/dev/null || true
    rm -f "$PORTS_PID"
    echo "Проброс закрыт."
  else
    echo "Проброс не запущен."
  fi
}

ports_status() {
  if [ -f "$PORTS_PID" ] && kill -0 "$(cat "$PORTS_PID")" 2>/dev/null; then
    echo "Проброс открыт (журнал: $PORTS_LOG)."
  else
    echo "Проброс не запущен."
  fi
}

cmd_status() {
  minikube status --profile "$PROFILE" || true
  if cluster_running; then
    kubectl get nodes -L platform.node
    kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
    echo "Vault: initialized=$(vault_status initialized), sealed=$(vault_status sealed)"
  fi
  ports_status
}

cmd_delete() {
  read -rp "Удалить кластер? Данные в volumes/ сохранятся. [y/N] " answer
  [ "$answer" = y ] || exit 0
  ports_close
  terraform -chdir=terraform init -input=false >/dev/null
  terraform -chdir=terraform destroy -input=false -auto-approve
}

case "${1:-help}" in
  up) cmd_up "${2:-dev}" ;;
  start | stop | restart | unseal | status | delete) "cmd_$1" ;;
  ports)
    case "${2:-}" in
      open) ports_open "${3:-}" ;;
      close) ports_close ;;
      status) ports_status ;;
      *) usage; exit 1 ;;
    esac
    ;;
  *) usage ;;
esac
