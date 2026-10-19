#!/usr/bin/env python3
"""Ensure /etc/wsl.conf enables metadata mounts and sets the default WSL user."""
import os
import re
import stat
import sys
import tempfile
from pathlib import Path

cluster_user = sys.argv[1] if len(sys.argv) > 1 else "cluster"

path = Path("/etc/wsl.conf")
exists = path.exists()
if exists:
    with path.open(encoding="utf-8", newline="") as source:
        content = source.read()
else:
    content = ""
lines = content.splitlines(keepends=True)
newline = "\r\n" if "\r\n" in content else "\n"
section_start = None
section_end = len(lines)

for index, line in enumerate(lines):
    match = re.match(r"^\s*\[([^]]+)\]", line)
    if match and match.group(1).strip().lower() == "automount":
        section_start = index
        for end in range(index + 1, len(lines)):
            if re.match(r"^\s*\[[^]]+\]", lines[end]):
                section_end = end
                break
        break

changed = False
if section_start is None:
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += newline
    if lines and lines[-1].strip():
        lines.append(newline)
    lines.extend(["[automount]" + newline, "options = metadata" + newline])
    changed = True
else:
    options_index = None
    for index in range(section_start + 1, section_end):
        if re.match(r"^\s*options\s*=", lines[index], re.IGNORECASE):
            options_index = index
            break

    if options_index is None:
        lines.insert(section_end, "options = metadata" + newline)
        changed = True
    else:
        line = lines[options_index]
        match = re.match(
            r"^(\s*options\s*=\s*)([^#\r\n]*?)(\s*(?:#.*)?)(\r?\n)?$",
            line,
            re.IGNORECASE,
        )
        if not match:
            raise SystemExit("Не удалось безопасно разобрать automount.options в /etc/wsl.conf.")
        value = match.group(2)
        stripped_value = value.strip()
        quote = (
            stripped_value[0]
            if len(stripped_value) >= 2
            and stripped_value[0] == stripped_value[-1]
            and stripped_value[0] in "\"'"
            else ""
        )
        options_value = stripped_value[1:-1] if quote else stripped_value
        if "metadata" not in re.split(r"[,;\s]+", options_value.lower()):
            leading_space = value[: len(value) - len(value.lstrip())]
            trailing_space = value[len(value.rstrip()) :]
            separator = "" if not options_value else ","
            lines[options_index] = (
                match.group(1)
                + leading_space
                + (quote if quote else "")
                + options_value
                + separator
                + "metadata"
                + (quote if quote else "")
                + trailing_space
                + match.group(3)
                + (match.group(4) or "")
            )
            changed = True

user_section_start = None
user_section_end = len(lines)
for index, line in enumerate(lines):
    match = re.match(r"^\s*\[([^]]+)\]", line)
    if match and match.group(1).strip().lower() == "user":
        user_section_start = index
        for end in range(index + 1, len(lines)):
            if re.match(r"^\s*\[[^]]+\]", lines[end]):
                user_section_end = end
                break
        break

if user_section_start is None:
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += newline
    if lines and lines[-1].strip():
        lines.append(newline)
    lines.extend(["[user]" + newline, "default=" + cluster_user + newline])
    changed = True
else:
    default_index = None
    for index in range(user_section_start + 1, user_section_end):
        if re.match(r"^\s*default\s*=", lines[index], re.IGNORECASE):
            default_index = index
            break

    if default_index is None:
        lines.insert(user_section_end, "default=" + cluster_user + newline)
        changed = True
    else:
        line = lines[default_index]
        match = re.match(
            r"^(\s*default\s*=\s*)([^#\r\n]*?)(\s*(?:#.*)?)(\r?\n)?$",
            line,
            re.IGNORECASE,
        )
        if not match:
            raise SystemExit("Не удалось безопасно разобрать user.default в /etc/wsl.conf.")
        if match.group(2).strip().strip("\"'") != cluster_user:
            lines[default_index] = (
                match.group(1)
                + cluster_user
                + match.group(3)
                + (match.group(4) or "")
            )
            changed = True

if changed:
    mode = stat.S_IMODE(path.stat().st_mode) if exists else 0o644
    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        newline="",
        dir=path.parent,
        delete=False,
    ) as output:
        output.writelines(lines)
        temporary_path = output.name
    os.chmod(temporary_path, mode)
    os.replace(temporary_path, path)
    print("updated")
else:
    print("unchanged")
