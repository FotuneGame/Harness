import sys

import yaml

seen = set()
for doc in yaml.safe_load_all(sys.stdin):
    if not isinstance(doc, dict):
        continue
    spec = doc.get("spec") or {}
    if doc.get("kind") == "Pod":
        pod = spec
    elif doc.get("kind") == "CronJob":
        pod = spec.get("jobTemplate", {}).get("spec", {}).get("template", {}).get("spec")
    else:
        pod = (spec.get("template") or {}).get("spec")
    if not isinstance(pod, dict):
        continue
    node = (pod.get("nodeSelector") or {}).get("platform.node")
    if not node:
        continue
    for container in (pod.get("initContainers") or []) + (pod.get("containers") or []):
        line = f"{node} {container.get('image')}"
        if container.get("image") and line not in seen:
            seen.add(line)
            print(line)
