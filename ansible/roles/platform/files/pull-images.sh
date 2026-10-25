#!/usr/bin/env bash
set -uo pipefail

PARALLEL=${PARALLEL:-3}
ATTEMPTS=${ATTEMPTS:-5}

retry() {
  local attempt
  for attempt in $(seq "$ATTEMPTS"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep $((attempt * 10))
  done
  return 1
}

docker_hub() {
  local registry=${1%%/*}
  [[ $1 != */* || $registry == docker.io || ($registry != *.* && $registry != *:* && $registry != localhost) ]]
}

pull() {
  local node=$1 image=$2
  docker exec "$node" docker image inspect "$image" >/dev/null 2>&1 && return 0
  if docker_hub "$image"; then
    retry docker exec "$node" docker pull -q "$image"
  else
    retry docker pull -q "$image" && docker save "$image" | docker exec -i "$node" docker load -q >/dev/null
  fi && { echo "скачан: $image ($node)"; return 0; }
  echo "не скачан за $ATTEMPTS попыток: $image ($node)" >&2
}
export -f retry docker_hub pull
export ATTEMPTS

declare -A nodes
while read -r name role; do
  nodes[$role]=$name
done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name} {.metadata.labels.platform\.node}{"\n"}{end}')

while read -r role image; do
  [ -n "${nodes[$role]:-}" ] && echo "${nodes[$role]} $image"
done | xargs -r -P "$PARALLEL" -n 2 bash -c 'pull "$1" "$2"' _
exit 0
