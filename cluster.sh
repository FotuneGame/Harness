#!/usr/bin/env bash
# Управление локальным Kubernetes-кластером. Справка: ./cluster.sh help
set -Eeuo pipefail
cd "$(dirname "$(readlink -f "$0")")"

readonly PROFILE=minikube
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/platform"
readonly PORTS_PID="$STATE_DIR/ports.pid"
readonly PORTS_LOG="$STATE_DIR/ports.log"
readonly ALL_ENVS=(dev stage prod)
# Аннотации: число реплик остановленного окружения и закрытый маршрут ingress.
readonly REPLICAS=platform/replicas
readonly DENY=nginx.ingress.kubernetes.io/denylist-source-range
export TF_CLI_CONFIG_FILE="$PWD/terraform/.terraformrc"

usage() {
  cat <<'EOF'
Использование: ./cluster.sh <команда> [--dev] [--stage] [--prod]

Без флагов команда относится ко всем окружениям и кластеру целиком, с флагами —
только к выбранным окружениям (namespace db, mb, llm, acl, app этого окружения);
общие сервисы (GitLab, Argo CD, Vault, мониторинг и т. д.) продолжают работать.

  up                    установка зависимостей, создание узлов и развёртывание (повторяемо)
  start                 запуск кластера, разблокировка Vault и окружений
  stop                  остановка кластера (с флагами — подов окружений)
  restart               stop + start
  unseal                разблокировка Vault (3 unseal key)
  ports open [адрес]    проброс ingress 80/443 на адрес хоста (по умолчанию 127.0.0.1)
                        и открытие веб-интерфейсов окружений
  ports close           закрытие проброса (с флагами — веб-интерфейсов окружений)
  ports status          состояние проброса
  status                узлы, окружения, проблемные pod, Vault, проброс
  delete                удаление кластера (с флагами — сервисов окружений);
                        данные в volumes/ сохраняются
  backups               список резервных копий
  restore <namespace> <pvc> [ID]
                        восстановление PVC из копии (без ID — последняя)
EOF
}

log() { printf '\n==> %s\n' "$*"; }
kubectl() { command kubectl --context "$PROFILE" "$@"; }
helm() { command helm --kube-context "$PROFILE" "$@"; }
cluster_exists() { docker container inspect "$PROFILE" >/dev/null 2>&1; }
cluster_running() { minikube status --profile "$PROFILE" >/dev/null 2>&1; }

require_cluster() {
  cluster_exists || { echo "Кластер не создан: выполните ./cluster.sh up" >&2; exit 1; }
}

require_running() {
  require_cluster
  cluster_running || { echo "Кластер остановлен: выполните ./cluster.sh start" >&2; exit 1; }
}

# Окружения из флагов; без флагов — все.
selected_envs() { if [ ${#ENVS[@]} -gt 0 ]; then echo "${ENVS[@]}"; else echo "${ALL_ENVS[@]}"; fi; }
is_selected() { [[ " ${ENVS[*]} " == *" $1 "* ]]; }
env_namespaces() { kubectl get namespace -l "platform.env=$1" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true; }
# Сервисы namespace, которыми пользуются общие сервисы (k8s/foundation usedBy,
# db-prod — PostgreSQL и Redis GitLab): stop и delete окружения их не трогают.
# Печатает аргументы kubectl для отбора остальных объектов.
env_own_selector() {
  local shared
  shared=$(kubectl get namespace "$1" -o json | jq -r '.metadata.annotations["platform/shared-services"] // ""')
  [ -z "$shared" ] || printf '%s\n' -l "app.kubernetes.io/name notin ($shared)"
}

confirm() {
  local answer
  read -rp "$1 [y/N] " answer
  answer=${answer// /}
  # «у» — кириллическая буква, в терминале неотличима от латинской y.
  case "${answer,,}" in
    y | yes | у | д | да) ;;
    "") echo "Отменено."; exit 0 ;;
    *) echo "Отменено: ответ «$answer» не y/да."; exit 0 ;;
  esac
}

# apt ждёт освобождения блокировки (после старта WSL её держит unattended-upgrades).
apt_get() { sudo apt-get -o DPkg::Lock::Timeout=600 "$@"; }

install_ansible() {
  if ! command -v ansible-playbook >/dev/null; then
    log "Установка Ansible"
    apt_get update
    apt_get install -y software-properties-common
    sudo add-apt-repository -y ppa:ansible/ansible
    apt_get update
    apt_get install -y ansible
  fi
  ansible-doc community.general.ini_file >/dev/null 2>&1 \
    || ansible-galaxy collection install community.general
}

# Вывод с ходом долгих задач: ansible/callback_plugins/progress.py.
playbook() { ANSIBLE_STDOUT_CALLBACK=progress ansible-playbook -i ansible/inventory.ini "$@"; }

# State Terraform — в volumes/terraform; прежний terraform/terraform.tfstate
# переносится туда при первом запуске.
tf_init() {
  terraform -chdir=terraform init -input=false -migrate-state -force-copy >/dev/null
  if [ -f volumes/terraform/terraform.tfstate ]; then
    rm -f terraform/terraform.tfstate terraform/terraform.tfstate.backup
  fi
}

# Узлы создаёт Terraform; остановленный кластер запускается с прежними параметрами.
provision() {
  log "Terraform: узлы кластера"
  tf_init
  local replace=()
  if terraform -chdir=terraform state list 2>/dev/null | grep -qx terraform_data.cluster && ! cluster_exists; then
    replace=(-replace=terraform_data.cluster)
  fi
  terraform -chdir=terraform apply -input=false -auto-approve "${replace[@]}"
  cluster_running || start_minikube
}

# Запуск остановленного кластера. Поды GitLab пересоздаются: после перезапуска
# узла их init-контейнер configure падает на файлах, оставшихся в emptyDir от
# прошлого запуска (cp: Permission denied), и Gitaly не стартует.
start_minikube() {
  minikube start --profile "$PROFILE"
  kubectl delete pod -n vcs --all --wait=false >/dev/null 2>&1 || true
}

vault_status() {
  { kubectl exec -n secret vault-0 -- vault status -format=json 2>/dev/null || true; } | jq -r ".$1"
}

# Автосинхронизация Argo CD вернула бы реплики приложений остановленного окружения.
argo_autosync() {
  local app
  { kubectl get applications.argoproj.io -n cicd -o json 2>/dev/null || echo '{"items":[]}'; } |
    jq -r --arg ns "$1" '.items[] | select(.spec.destination.namespace == $ns and .spec.syncPolicy.automated != null)
      | .metadata.name' |
    while read -r app; do
      kubectl patch applications.argoproj.io -n cicd "$app" --type merge \
        -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"enabled\":$2}}}}" >/dev/null
    done
}

# Остановка окружения: Deployment и StatefulSet — 0 реплик, прежнее число — в аннотации.
env_stop() {
  local ns kind name replicas own
  for ns in $(env_namespaces "$1"); do
    mapfile -t own < <(env_own_selector "$ns")
    argo_autosync "$ns" false
    kubectl get deployment,statefulset -n "$ns" "${own[@]}" -o json |
      jq -r '.items[] | select(.spec.replicas > 0) | "\(.kind) \(.metadata.name) \(.spec.replicas)"' |
      while read -r kind name replicas; do
        kubectl annotate -n "$ns" "$kind/$name" "$REPLICAS=$replicas" --overwrite >/dev/null
        kubectl scale -n "$ns" "$kind/$name" --replicas=0 >/dev/null
      done
  done
  echo "Окружение $1 остановлено."
}

env_start() {
  local ns kind name replicas
  for ns in $(env_namespaces "$1"); do
    kubectl get deployment,statefulset -n "$ns" -o json |
      jq -r --arg key "$REPLICAS" '.items[] | .metadata.annotations[$key] as $replicas | select($replicas)
        | "\(.kind) \(.metadata.name) \($replicas)"' |
      while read -r kind name replicas; do
        kubectl scale -n "$ns" "$kind/$name" --replicas="$replicas" >/dev/null
        kubectl annotate -n "$ns" "$kind/$name" "$REPLICAS-" >/dev/null
      done
    argo_autosync "$ns" true
  done
  echo "Окружение $1 запущено (ход запуска: ./cluster.sh status --$1)."
}

# Веб-интерфейсы окружения: Ingress его namespace закрыты для всех адресов (403).
env_routes() {
  local ns
  for ns in $(env_namespaces "$1"); do
    if [ "$2" = close ]; then
      kubectl annotate ingress -n "$ns" --all "$DENY=0.0.0.0/0,::/0" --overwrite >/dev/null 2>&1 || true
    else
      kubectl annotate ingress -n "$ns" --all "$DENY-" >/dev/null 2>&1 || true
    fi
  done
}

# Удаление сервисов окружения: релизы Helm, приложения Argo CD и PVC. PV
# (Retain) освобождаются для PVC с тем же именем: данные в volumes/ остаются и
# подключатся снова при ./cluster.sh up. Релиз namespace с сервисами общих
# сервисов (db-prod) не удаляется, а остаётся только с ними (allServices=false).
env_delete() {
  local ns app release pv own used claims
  for ns in $(env_namespaces "$1"); do
    mapfile -t own < <(env_own_selector "$ns")
    kubectl get applications.argoproj.io -n cicd -o json 2>/dev/null |
      jq -r --arg ns "$ns" '.items[] | select(.spec.destination.namespace == $ns) | .metadata.name' |
      while read -r app; do
        # С finalizer Argo CD удаляет и ресурсы приложения.
        kubectl patch applications.argoproj.io -n cicd "$app" --type merge \
          -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' >/dev/null
        kubectl delete applications.argoproj.io -n cicd "$app" --wait=true
      done
    # Завершённые поды резервных копий K8up держат PVC (pvc-protection): без
    # этого helm uninstall --wait и удаление PVC ждали бы бесконечно.
    kubectl delete backups.k8up.io -n "$ns" --all --wait=true >/dev/null 2>&1 || true
    kubectl delete jobs -n "$ns" --all --wait=true >/dev/null
    kubectl delete pods -n "$ns" --field-selector=status.phase!=Running --wait=true >/dev/null
    for release in $(helm list -n "$ns" -q); do
      if [ ${#own[@]} -gt 0 ]; then
        helm upgrade -n "$ns" "$release" "k8s/${ns%-*}" --reuse-values --set allServices=false --wait >/dev/null
        echo "$ns: оставлены сервисы общих сервисов (${own[1]})."
      else
        helm uninstall -n "$ns" "$release" --wait
      fi
    done
    [ ${#own[@]} -gt 0 ] || kubectl delete pods -n "$ns" --all --wait=true >/dev/null
    # PVC, которые не смонтированы ни одним подом (у общих сервисов — смонтированы).
    used=$(kubectl get pods -n "$ns" -o json | jq -r '[.items[].spec.volumes[]?.persistentVolumeClaim.claimName // empty] | join(" ")')
    claims=$(kubectl get pvc -n "$ns" -o json |
      jq -r --arg used " $used " '[.items[].metadata.name | select(. as $name | $used | contains(" \($name) ") | not)] | join(" ")')
    # shellcheck disable=SC2086 # список имён PVC.
    [ -z "$claims" ] || kubectl delete pvc -n "$ns" $claims --wait=true >/dev/null
    kubectl get pv -o json |
      jq -r --arg ns "$ns" --arg claims " $claims " '.items[]
        | select(.spec.claimRef.namespace == $ns and (.spec.claimRef.name as $name | $claims | contains(" \($name) ")))
        | .metadata.name' |
      while read -r pv; do
        kubectl patch pv "$pv" --type merge -p '{"spec":{"claimRef":{"uid":null,"resourceVersion":null}}}' >/dev/null
      done
  done
  echo "Окружение $1 удалено. Установка заново: ./cluster.sh up --$1"
}

# K8up делает копии по расписанию (k8s/backup), но пропущенный запуск
# (сервер был выключен) не повторяет: копия создаётся, если за сутки не было
# успешной или идущей.
backups_catch_up() {
  local schedule namespace
  { kubectl get schedules.k8up.io -A -o json 2>/dev/null || echo '{"items":[]}'; } | jq -c '.items[]' |
    while read -r schedule; do
      namespace=$(jq -r .metadata.namespace <<<"$schedule")
      kubectl get backups.k8up.io -n "$namespace" -o json | jq -e '[.items[]
        | select(now - (.metadata.creationTimestamp | fromdateiso8601) < 86400)
        | select(any(.status.conditions[]?; .reason == "Failed") | not)] | length > 0' >/dev/null && continue
      jq '{apiVersion: "k8up.io/v1", kind: "Backup",
           metadata: {generateName: "catch-up-", namespace: .metadata.namespace},
           spec: {backend: .spec.backend, podSecurityContext: .spec.backup.podSecurityContext}}' <<<"$schedule" |
        kubectl create -f - >/dev/null && echo "Резервная копия $namespace запущена (не было за сутки)."
    done
}

# Копии K8up: namespace, PVC, дата и ID (первые 8 символов).
snapshots_list() {
  {
    printf 'NAMESPACE\tPVC\tДАТА\tID\n'
    kubectl get snapshots.k8up.io -A -o json | jq -r '.items[]
      | [.metadata.namespace, (.spec.paths[0] | sub("^/data/"; "")), .spec.date, .spec.id[0:8]] | @tsv' | sort
  } | column -t -s $'\t'
}

pods_with_pvc() {
  kubectl get pods -n "$1" -o json | jq -r --arg pvc "$2" '.items[]
    | select(.status.phase == "Pending" or .status.phase == "Running")
    | select(any(.spec.volumes[]?; .persistentVolumeClaim.claimName == $pvc)) | .metadata.name'
}

# Восстановление PVC из копии (k8s/backup/restore/*.yaml): сервисы с этим PVC
# останавливаются, текущие данные переносятся в .before-restore-<время> в том же
# томе, файлы копии ложатся на их место, сервисы запускаются снова.
restore_pvc() {
  local ns=$1 pvc=$2 id=${3:-} snapshot bucket name keep pod owner kind replicas
  local -a stopped=()
  snapshot=$(kubectl get snapshots.k8up.io -n "$ns" -o json | jq -r --arg path "/data/$pvc" --arg id "$id" '
    [.items[] | select(.spec.paths | index($path)) | select(.spec.id | startswith($id))]
    | sort_by(.spec.date) | last | .spec.id // empty')
  [ -n "$snapshot" ] || { echo "Нет копии $ns/$pvc${id:+ с ID $id}. Список: ./cluster.sh backups" >&2; exit 1; }
  bucket=$(kubectl get schedules.k8up.io -n "$ns" backup -o jsonpath='{.spec.backend.s3.bucket}')
  name="restore-$pvc-$(date +%Y%m%d%H%M%S)"
  keep=".before-restore-$(date +%Y%m%d-%H%M%S)"
  confirm "Восстановить $ns/$pvc из копии ${snapshot:0:8}? Сервисы с этим PVC остановятся, текущие данные перенесутся в $keep в том же томе."

  argo_autosync "$ns" false
  for pod in $(pods_with_pvc "$ns" "$pvc"); do
    owner=$(kubectl get pod -n "$ns" "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')
    if [[ $owner == ReplicaSet/* ]]; then
      owner=Deployment/$(kubectl get -n "$ns" "$owner" -o jsonpath='{.metadata.ownerReferences[0].name}')
    fi
    # Поды Job (копия K8up) не останавливаются — их окончания ждёт цикл ниже.
    [[ $owner == Deployment/* || $owner == StatefulSet/* ]] || continue
    [[ " ${stopped[*]} " == *" $owner="* ]] && continue
    replicas=$(kubectl get -n "$ns" "$owner" -o jsonpath='{.spec.replicas}')
    kubectl scale -n "$ns" "$owner" --replicas=0 >/dev/null
    stopped+=("$owner=$replicas")
    echo "Остановлен $owner"
  done
  while [ -n "$(pods_with_pvc "$ns" "$pvc")" ]; do sleep 2; done

  export NAME=$name NAMESPACE=$ns PVC=$pvc SNAPSHOT=$snapshot BUCKET=$bucket KEEP=$keep
  render() { envsubst '${NAME} ${NAMESPACE} ${PVC} ${SNAPSHOT} ${BUCKET} ${KEEP}' <"k8s/backup/restore/$1.yaml"; }
  render prepare | kubectl apply -f - >/dev/null
  kubectl wait pod -n "$ns" "$name-prepare" --for=jsonpath='{.status.phase}'=Succeeded --timeout=10m >/dev/null
  kubectl delete pod -n "$ns" "$name-prepare" >/dev/null
  echo "Текущие данные перенесены в $keep."

  render restore | kubectl apply -f - >/dev/null
  echo "Восстановление ${snapshot:0:8} (ход: kubectl get restore -n $ns $name)..."
  kubectl wait restore.k8up.io -n "$ns" "$name" --for=jsonpath='{.status.finished}'=true --timeout=60m >/dev/null
  kubectl get restore.k8up.io -n "$ns" "$name" -o json |
    jq -e 'any(.status.conditions[]?; .type == "Completed" and .reason == "Succeeded")' >/dev/null ||
    echo "Восстановление завершилось с ошибкой: kubectl describe restore -n $ns $name" >&2

  for owner in "${stopped[@]}"; do
    kubectl scale -n "$ns" "${owner%=*}" --replicas="${owner#*=}" >/dev/null
    echo "Запущен ${owner%=*}"
  done
  argo_autosync "$ns" true
  echo "Готово. Прежние данные — в $keep внутри тома (volumes/...): удалите их, когда убедитесь в результате."
}

cmd_backups() {
  require_running
  snapshots_list
  echo
  echo "Восстановить: ./cluster.sh restore <namespace> <pvc> [ID] (без ID — последняя копия)"
}

cmd_restore() {
  [ $# -ge 2 ] || { echo "Использование: ./cluster.sh restore <namespace> <pvc> [ID]; список копий — ./cluster.sh backups" >&2; exit 1; }
  require_running
  restore_pvc "$@"
}

cmd_up() {
  install_ansible

  log "Ansible: подготовка сервера"
  local become=()
  # Ubuntu 25.10+: sudo — это sudo-rs, его запрос пароля Ansible не распознаёт.
  # Тогда become идёт через классический sudo (sudo.ws из пакета sudo).
  if [[ $(readlink -f "$(command -v sudo)") == */cargo/* ]]; then
    command -v sudo.ws >/dev/null || apt_get install -y sudo
    become+=(-e ansible_become_exe=sudo.ws)
  fi
  sudo -n -k true 2>/dev/null || become+=(--ask-become-pass)
  playbook ansible/host.yml "${become[@]}"

  provision

  local envs env
  read -ra envs <<<"$(selected_envs)"
  log "Ansible: общие сервисы и окружения ${envs[*]}"
  playbook ansible/platform.yml -e "{\"platform_envs\": $(printf '%s\n' "${envs[@]}" | jq -R . | jq -sc .)}"
  # Helm вернул реплики остановленных окружений: снимаются и отметки остановки.
  for env in "${envs[@]}"; do env_start "$env" >/dev/null; done
  backups_catch_up
}

cmd_start() {
  require_cluster
  local running=true env
  cluster_running || running=false
  if ! $running; then
    log "Запуск кластера"
    start_minikube
  fi
  unseal_vault
  # Запуск кластера с флагами: остальные окружения остаются остановленными.
  for env in "${ALL_ENVS[@]}"; do
    if [ ${#ENVS[@]} -eq 0 ] || is_selected "$env"; then
      env_start "$env"
    elif ! $running; then
      env_stop "$env"
    fi
  done
  backups_catch_up
}

cmd_stop() {
  local env
  if [ ${#ENVS[@]} -gt 0 ]; then
    require_running
    for env in "${ENVS[@]}"; do env_stop "$env"; done
    return
  fi
  ports_close
  log "Остановка кластера"
  minikube stop --profile "$PROFILE"
}

cmd_restart() {
  cmd_stop
  cmd_start
}

# Vault работает в кластере (pod vault-0) и запечатывается при каждом
# перезапуске pod: нужны 3 из 5 unseal key.
cmd_unseal() {
  require_running
  unseal_vault
}

unseal_vault() {
  kubectl wait pod/vault-0 -n secret --for=jsonpath='{.status.phase}'=Running --timeout=10m >/dev/null
  if [ "$(vault_status initialized)" != true ]; then
    echo "Vault ещё не инициализирован: его настроит ./cluster.sh up."
    return
  fi
  if [ "$(vault_status sealed)" != true ]; then
    echo "Vault уже разблокирован."
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

ports_running() { [ -f "$PORTS_PID" ] && kill -0 "$(cat "$PORTS_PID")" 2>/dev/null; }

# Проброс service/ingress-nginx-controller на хост; перезапускается при обрыве.
forward_start() {
  forward_stop >/dev/null
  mkdir -p "$STATE_DIR"
  # shellcheck disable=SC2016 # аргументы передаются в bash -c позиционно.
  setsid bash -c 'echo $$ >"$1"; while true; do
      kubectl --context "$2" port-forward --address "$3" -n proxy service/ingress-nginx-controller 80:80 443:443
      sleep 2
    done' _ "$PORTS_PID" "$PROFILE" "$1" >"$PORTS_LOG" 2>&1 </dev/null &
  for _ in $(seq 30); do
    grep -q "Forwarding from" "$PORTS_LOG" && { echo "Проброс открыт: https://*.local → $1:443"; return; }
    sleep 1
  done
  cat "$PORTS_LOG" >&2
  forward_stop >/dev/null
  exit 1
}

forward_stop() {
  if [ -f "$PORTS_PID" ]; then
    kill -- "-$(cat "$PORTS_PID")" 2>/dev/null || true
    rm -f "$PORTS_PID"
    echo "Проброс закрыт."
  else
    echo "Проброс не запущен."
  fi
}

# Проброс общий (запускается, если ещё не запущен); открываются адреса выбранных
# окружений, остальные не меняются.
ports_open() {
  local address=$1 env
  require_running
  if ! ports_running || [ -n "$address" ]; then
    forward_start "${address:-127.0.0.1}"
  fi
  for env in $(selected_envs); do
    env_routes "$env" open
    echo "Веб-интерфейсы $env открыты: https://platform.local/$env/<сервис>"
  done
}

ports_close() {
  local env
  if [ ${#ENVS[@]} -gt 0 ]; then
    require_running
    for env in "${ENVS[@]}"; do
      env_routes "$env" close
      echo "Веб-интерфейсы $env закрыты."
    done
    return
  fi
  forward_stop
}

ports_status() {
  if ports_running; then
    echo "Проброс открыт (журнал: $PORTS_LOG)."
  else
    echo "Проброс не запущен."
  fi
}

# Узлы: метка platform.node, потребление (metrics-server), готовые поды и namespace.
nodes_status() {
  local pods top
  pods=$(kubectl get pods -A -o json)
  top=$(kubectl top nodes --no-headers 2>/dev/null || true)
  {
    echo "УЗЕЛ МЕТКА CPU RAM ПОДЫ NAMESPACE"
    kubectl get nodes -o json | jq -r '.items[] | [.metadata.name, .metadata.labels["platform.node"] // "-"] | @tsv' |
      while IFS=$'\t' read -r node label; do
        usage=$(awk -v node="$node" '$1 == node { print $2, $4 }' <<<"$top")
        pods_on_node=$(jq -r --arg node "$node" '
          [.items[] | select(.spec.nodeName == $node)
            | select(.status.phase != "Failed" or all(.metadata.ownerReferences[]?; .kind != "ReplicaSet"))]
          | "\(map(select(.status.phase == "Succeeded" or ((.status.containerStatuses // []) | length > 0 and all(.ready)))) | length)/\(length)"
            + " \(map(.metadata.namespace) | unique | join(","))"' <<<"$pods")
        echo "$node $label ${usage:-- -} $pods_on_node"
      done
  } | column -t
}

# Окружения: состояние (по отметкам остановки), готовые поды, веб-интерфейсы.
envs_status() {
  local resources ports=off env
  resources=$(kubectl get namespace,deployment,statefulset,pod,ingress -A -o json)
  ports_running && ports=on
  {
    printf 'ОКРУЖЕНИЕ\tСОСТОЯНИЕ\tПОДЫ\tВЕБ-ИНТЕРФЕЙСЫ\n'
    for env in $(selected_envs); do
      jq -r --arg env "$env" --arg ports "$ports" --arg replicas "$REPLICAS" --arg deny "$DENY" '
        [.items[] | select(.kind == "Namespace" and .metadata.labels["platform.env"] == $env)
          | .metadata.name] as $namespaces
        | [.items[] | select(.kind != "Namespace" and (.metadata.namespace | IN($namespaces[])))] as $items
        | ($items | map(select(.kind == "Deployment" or .kind == "StatefulSet"))) as $workloads
        | ($items | map(select(.kind == "Pod" and .status.phase != "Succeeded"))) as $pods
        | [$env,
           (if ($workloads | length) == 0 then "не установлено"
            elif any($workloads[]; .metadata.annotations[$replicas]) then "остановлено"
            else "работает" end),
           "\($pods | map(select((.status.containerStatuses // []) | length > 0 and all(.ready))) | length)/\($pods | length)",
           (if any($items[]; .kind == "Ingress" and .metadata.annotations[$deny]) then "закрыты"
            elif $ports == "on" then "https://platform.local/\($env)/" else "проброс не запущен" end)]
        | @tsv' <<<"$resources"
    done
  } | column -t -s $'\t'
}

# Поды, которые не готовы: узел и причина (ожидание контейнера, ошибка, фаза).
# Упавшие поды Deployment (например, после перезапуска узла) не показываются:
# вместо них уже создан новый под. Аргумент — namespace через пробел (пусто — все).
pods_not_ready() {
  local rows
  rows=$(kubectl get pods -A -o json | jq -r --arg namespaces "${1:-}" '.items[]
    | select($namespaces == "" or (.metadata.namespace | IN($namespaces | split(" ") | .[])))
    | select(.status.phase != "Succeeded")
    | select(.status.phase != "Failed" or all(.metadata.ownerReferences[]?; .kind != "ReplicaSet"))
    | select(((.status.containerStatuses // []) | length == 0) or any(.status.containerStatuses[]; .ready | not))
    | [.metadata.namespace + "/" + .metadata.name, .spec.nodeName // "-",
       ((.status.containerStatuses // []) | map(.state.waiting.reason // .state.terminated.reason // empty) | .[0])
         // .status.reason // .status.phase] | @tsv')
  if [ -z "$rows" ]; then
    echo "Все поды готовы."
  else
    echo "Не готовы:"
    { echo "ПОД УЗЕЛ ПРИЧИНА"; echo "$rows"; } | column -t
  fi
}

cmd_status() {
  local namespaces="" env
  minikube status --profile "$PROFILE" || true
  if cluster_running; then
    if [ ${#ENVS[@]} -eq 0 ]; then
      log "Узлы"
      nodes_status
    else
      for env in "${ENVS[@]}"; do namespaces+="$(env_namespaces "$env") "; done
      # Окружение не установлено: под нет.
      namespaces=$(xargs <<<"$namespaces")
      namespaces=${namespaces:--}
    fi
    log "Окружения"
    envs_status
    log "Поды"
    pods_not_ready "$namespaces"
    echo
    echo "Vault: initialized=$(vault_status initialized), sealed=$(vault_status sealed)"
  fi
  ports_status
}

cmd_delete() {
  local env
  if [ ${#ENVS[@]} -gt 0 ]; then
    require_running
    confirm "Удалить сервисы окружений ${ENVS[*]}? Данные в volumes/ сохранятся."
    for env in "${ENVS[@]}"; do
      log "Удаление окружения $env"
      env_delete "$env"
    done
    return
  fi
  confirm "Удалить кластер? Данные в volumes/ сохранятся."
  forward_stop
  log "Удаление кластера"
  tf_init
  terraform -chdir=terraform destroy -input=false -auto-approve
  # Кластер, которого нет в state Terraform (например, state удалён).
  if cluster_exists; then
    minikube delete --profile "$PROFILE"
  fi
  echo "Кластер удалён. Данные в volumes/ сохранены."
}

# Флаги окружений --dev, --stage, --prod — в любом месте командной строки.
ENVS=()
args=()
for arg in "$@"; do
  case "$arg" in
    --dev | --stage | --prod) is_selected "${arg#--}" || ENVS+=("${arg#--}") ;;
    -*) usage; exit 1 ;;
    *) args+=("$arg") ;;
  esac
done
set -- "${args[@]}"

case "${1:-help}" in
  up | start | stop | restart | status | delete) "cmd_$1" ;;
  unseal) [ ${#ENVS[@]} -eq 0 ] || { usage; exit 1; }; cmd_unseal ;;
  restore) shift; cmd_restore "$@" ;;
  backups) cmd_backups ;;
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
