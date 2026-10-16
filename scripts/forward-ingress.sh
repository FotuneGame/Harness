#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Команда kubectl не найдена. Установите kubectl и повторите запуск." >&2
  exit 1
fi

context="$(kubectl config current-context)"
if [[ "$context" != "minikube" ]]; then
  echo "Активный kubectl context: ${context:-не задан}; ожидался minikube." >&2
  echo "Сначала запустите Minikube: bash scripts/start-minikube.sh" >&2
  exit 1
fi

if ! kubectl get service ingress-nginx-controller -n proxy >/dev/null 2>&1; then
  echo "Ingress controller не найден. Сначала разверните сервисы:" >&2
  echo "  bash scripts/start-cluster.sh" >&2
  exit 1
fi

hostnames=(
  gitlab.local
  registry.local
  pg.local
  redis.local
  clickhouse.local
  kafka.local
  ollama.local
  keycloak.local
  vault.local
  grafana.local
  prometheus.local
  alert.local
  jaeger.local
  argocd.local
)

if grep -qi microsoft /proc/version 2>/dev/null && command -v powershell.exe >/dev/null 2>&1; then
  if ! command -v wslpath >/dev/null 2>&1; then
    echo "Команда wslpath не найдена; невозможно разрешить путь Windows hosts." >&2
    exit 1
  fi
  powershell_path="$(wslpath -w "$SCRIPT_DIR/update-windows-hosts.ps1")"
  names_argument="$(printf '%s,' "${hostnames[@]}")"
  names_argument="${names_argument%,}"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$powershell_path" -Names "$names_argument"
else
  sudo python3 - "${hostnames[@]}" <<'PY'
from pathlib import Path
import sys

hosts_path = Path("/etc/hosts")
hostnames = sys.argv[1:]
lines = hosts_path.read_text(encoding="utf-8").splitlines()
addresses = {}

for line in lines:
    content = line.split("#", 1)[0].split()
    if len(content) < 2:
        continue
    address, *aliases = content
    for alias in aliases:
        addresses.setdefault(alias.lower(), set()).add(address)

conflicts = [
    hostname
    for hostname in hostnames
    if addresses.get(hostname.lower(), set()) - {"127.0.0.1"}
]
if conflicts:
    print(
        "В /etc/hosts уже есть другие адреса для: " + ", ".join(conflicts),
        file=sys.stderr,
    )
    print("Исправьте эти записи вручную и запустите скрипт снова.", file=sys.stderr)
    raise SystemExit(1)

missing = [
    hostname
    for hostname in hostnames
    if "127.0.0.1" not in addresses.get(hostname.lower(), set())
]
if missing:
    with hosts_path.open("a", encoding="utf-8") as hosts_file:
        hosts_file.write("\n127.0.0.1 " + " ".join(missing) + "\n")
    print("Добавлены имена в /etc/hosts: " + ", ".join(missing))
else:
    print("Все имена *.local уже сопоставлены с 127.0.0.1 в /etc/hosts.")
PY
fi

echo "Ingress доступен на http://*.local:8080 и https://*.local:8443."
echo "Остановите проброс клавишами Ctrl+C."
exec kubectl port-forward --address 127.0.0.1 -n proxy \
  service/ingress-nginx-controller 8080:80 8443:443
