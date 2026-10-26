import json
import os
import ssl
import subprocess
import threading
import time
import urllib.request
from datetime import datetime
from hashlib import sha1
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = os.environ["MODE"]
INTERVAL = int(os.environ.get("INTERVAL", "30"))
VOLUMES = "/volumes"
VOLUMES_INTERVAL = int(os.environ.get("VOLUMES_INTERVAL", "300"))
ENV_FOLDERS = set(os.environ.get("ENV_FOLDERS", "").split(","))
NAMESPACES = json.loads(os.environ.get("NAMESPACES", "{}"))
SKIP = set(os.environ.get("SKIP", "").split(","))
NODE = os.environ.get("NODE_NAME", "")
NODES = json.loads(os.environ.get("NODES", "{}"))

metrics = {}


def label(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def render(name, help_text, rows):
    lines = [f"# HELP {name} {help_text}", f"# TYPE {name} gauge"]
    for labels, value in rows:
        text = ",".join(f'{k}="{label(v)}"' for k, v in labels.items())
        lines.append(f"{name}{{{text}}} {value}")
    return "\n".join(lines)


# Имя veth пода на узле — так его задаёт Calico CNI.
def pod_interfaces():
    sa = "/var/run/secrets/kubernetes.io/serviceaccount"
    request = urllib.request.Request(
        f"https://{os.environ['KUBERNETES_SERVICE_HOST']}:{os.environ['KUBERNETES_SERVICE_PORT']}/api/v1/pods",
        headers={"Authorization": "Bearer " + open(f"{sa}/token").read()},
    )
    context = ssl.create_default_context(cafile=f"{sa}/ca.crt")
    pods = json.load(urllib.request.urlopen(request, context=context, timeout=20))["items"]
    rows = []
    for pod in pods:
        if pod["spec"].get("hostNetwork"):
            continue
        namespace, name = pod["metadata"]["namespace"], pod["metadata"]["name"]
        device = "cali" + sha1(f"{namespace}.{name}".encode()).hexdigest()[:11]
        rows.append(({"device": device, "namespace": namespace, "pod": name}, 1))
    return render("platform_pod_interface", "Calico interface of a pod", rows)


def volume_dirs():
    for top in sorted(os.listdir(VOLUMES)):
        top_path = os.path.join(VOLUMES, top)
        if top in SKIP or not os.path.isdir(top_path):
            continue
        if top in ENV_FOLDERS:
            for env in sorted(os.listdir(top_path)):
                env_path = os.path.join(top_path, env)
                if os.path.isdir(env_path):
                    for child in sorted(os.listdir(env_path)):
                        yield f"{top}/{env}/{child}", f"{top}-{env}"
        else:
            for child in sorted(os.listdir(top_path)):
                yield f"{top}/{child}", NAMESPACES.get(top, top)


def volumes():
    rows = []
    for path, namespace in volume_dirs():
        full = os.path.join(VOLUMES, path)
        if not os.path.isdir(full):
            continue
        out = subprocess.run(["du", "-sb", full], capture_output=True, text=True).stdout.split()
        if out:
            rows.append(({"namespace": namespace, "path": path}, out[0]))
    return render("platform_volume_used_bytes", "Disk usage of a volumes/ directory", rows)


def node_limits():
    return "\n".join([
        render("platform_node_cpu_limit", "Node CPU limit from Terraform",
               [({"node": name, "limit": f'{node["cpus"]} CPU'}, node["cpus"]) for name, node in NODES.items()]),
        render("platform_node_memory_limit_bytes", "Node memory limit from Terraform",
               [({"node": name, "limit": f'{node["memory_gib"]} GiB'}, node["memory_gib"] * 1073741824)
                for name, node in NODES.items()]),
    ])


# Тревоги Alertmanager, в том числе отправленные вручную (amtool alert add), — для истории в Grafana.
def alerts():
    url = os.environ["ALERTMANAGER_URL"] + "/api/v2/alerts?silenced=false&inhibited=false"
    items = json.load(urllib.request.urlopen(url, timeout=20))
    groups = {}
    for alert in items:
        key = tuple(alert["labels"].get(k, "") for k in ("alertname", "severity", "namespace"))
        started = int(datetime.fromisoformat(alert["startsAt"].replace("Z", "+00:00")).timestamp())
        count, first = groups.get(key, (0, started))
        groups[key] = (count + 1, min(first, started))
    # alert_namespace: пустая метка namespace заменилась бы namespace пода сборщика.
    rows = [(dict(zip(("alertname", "severity", "alert_namespace"), key)), value) for key, value in groups.items()]
    return "\n".join([
        render("platform_alertmanager_alert", "Active Alertmanager alerts", [(r, v[0]) for r, v in rows]),
        render("platform_alertmanager_alert_start_seconds", "Earliest start of the alerts", [(r, v[1]) for r, v in rows]),
    ])


def gpus():
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=index,name,utilization.gpu,memory.used,memory.total",
         "--format=csv,noheader,nounits"],
        capture_output=True, text=True, check=True,
    ).stdout
    util, used, total = [], [], []
    for line in out.strip().splitlines():
        index, name, u, m_used, m_total = [x.strip() for x in line.split(",")]
        labels = {"node": NODE, "gpu": index, "name": name}
        util.append((labels, u))
        used.append((labels, int(m_used) * 1048576))
        total.append((labels, int(m_total) * 1048576))
    return "\n".join([
        render("platform_gpu_utilization_percent", "GPU utilization", util),
        render("platform_gpu_memory_used_bytes", "GPU memory used", used),
        render("platform_gpu_memory_total_bytes", "GPU memory total", total),
    ])


def loop(key, collect, interval):
    while True:
        try:
            metrics[key] = collect()
        except Exception as error:
            print(f"{key}: {error}", flush=True)
        time.sleep(interval)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = ("\n".join(metrics.values()) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if MODE == "cluster":
    metrics["nodes"] = node_limits()
    threading.Thread(target=loop, args=("pods", pod_interfaces, INTERVAL), daemon=True).start()
    threading.Thread(target=loop, args=("volumes", volumes, VOLUMES_INTERVAL), daemon=True).start()
    threading.Thread(target=loop, args=("alerts", alerts, 15), daemon=True).start()
else:
    threading.Thread(target=loop, args=("gpu", gpus, INTERVAL), daemon=True).start()
ThreadingHTTPServer(("", 9100), Handler).serve_forever()
