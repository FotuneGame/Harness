#!/usr/bin/env python3
"""Add *.local hostnames to /etc/hosts, detecting conflicting entries."""
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
    print("Исправьте эти записи вручную и запустите снова.", file=sys.stderr)
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
