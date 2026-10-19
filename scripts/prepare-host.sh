#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v ansible-playbook >/dev/null 2>&1; then
  if ! command -v apt-get >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    echo "Установите Ansible вручную; автоматическая установка поддерживается в Ubuntu/WSL." >&2
    exit 1
  fi
  sudo apt-get update
  sudo apt-get install -y ansible
fi

sudo -- ansible-playbook -i ansible/inventory.ini ansible/site.yml \
  -e '{"ansible_become": false}'
