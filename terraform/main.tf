locals {
  profile = "minikube"

  node_names = { core = "minikube", llms = "minikube-m02", apps = "minikube-m03" }

  taints = { apps = "workload=apps:NoSchedule" }

  volumes = abspath("${path.root}/../volumes")

  encryption_config = "/var/lib/minikube/certs/encryption-config.yaml"

  admission_plugins = join(",", [
    "NamespaceLifecycle", "LimitRanger", "ServiceAccount", "DefaultStorageClass",
    "DefaultTolerationSeconds", "NodeRestriction", "MutatingAdmissionWebhook",
    "ValidatingAdmissionWebhook", "ResourceQuota", "PodNodeSelector", "PodTolerationRestriction",
  ])

  extra_config = [
    "apiserver.encryption-provider-config=${local.encryption_config}",
    "apiserver.enable-admission-plugins=${local.admission_plugins}",
    "kubelet.serialize-image-pulls=false",
  ]

  disk_gib = max([for node in values(var.nodes) : node.disk_gib]...)

  cni = "calico"

  allocated = {
    cpus       = sum([for node in values(var.nodes) : node.cpus])
    memory_gib = sum([for node in values(var.nodes) : node.memory_gib])
    disk_gib   = sum([for node in values(var.nodes) : node.disk_gib])
    vram_mib   = sum([for node in values(var.nodes) : node.vram_mib])
  }

  cluster_shape = {
    nodes              = length(var.nodes)
    core               = [var.nodes.core.cpus, var.nodes.core.memory_gib, local.disk_gib]
    gpu                = var.gpu
    kubernetes_version = var.kubernetes_version
    registry_mirrors   = var.registry_mirrors
    extra_config       = local.extra_config
    cni                = local.cni
  }

  ansible = {
    profile            = local.profile
    wsl_memory_gib     = var.host.memory_gib
    kubernetes_version = var.kubernetes_version
    encryption_config  = local.encryption_config
    gpu_nodes = {
      for role, node in var.nodes : local.node_names[role] => {
        role           = role
        vram_mib       = node.vram_mib
        memory_scaling = node.vram_mib / var.host.gpu_vram_mib
      } if node.vram_mib > 0
    }
  }
}

resource "terraform_data" "cluster" {
  triggers_replace = local.cluster_shape
  input            = local.profile

  lifecycle {
    precondition {
      condition = (
        local.allocated.cpus <= var.host.cpus &&
        local.allocated.memory_gib < var.host.memory_gib &&
        local.allocated.disk_gib <= var.host.disk_gib &&
        local.allocated.vram_mib <= var.host.gpu_vram_mib
      )
      error_message = "Узлы не помещаются в ресурсы сервера (RAM должна оставаться для ОС, VRAM — не больше видеокарты)."
    }
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      test -f "$HOME/.minikube/files${local.encryption_config}" || {
        echo "Нет ключа шифрования etcd: сначала выполните ./cluster.sh up" >&2; exit 1; }
      minikube delete --profile ${local.profile} >/dev/null 2>&1 || true
      stale='^${local.profile}(-m[0-9]+)?$'
      docker ps -a --filter label=created_by.minikube.sigs.k8s.io=true --format '{{.Names}}' \
        | { grep -E "$stale" || true; } | xargs -r docker rm -f
      docker volume ls --filter label=created_by.minikube.sigs.k8s.io=true --format '{{.Name}}' \
        | { grep -E "$stale" || true; } | xargs -r docker volume rm
      gpus=()
      if ${var.gpu} && docker run --rm --gpus all ubuntu:22.04 nvidia-smi -L >/dev/null 2>&1; then
        gpus=(--gpus all)
      fi
      minikube start --profile ${local.profile} --driver docker \
        --kubernetes-version ${var.kubernetes_version} \
        --nodes ${length(var.nodes)} --cni ${local.cni} \
        --cpus ${var.nodes.core.cpus} --memory ${var.nodes.core.memory_gib}g \
        --disk-size ${local.disk_gib}g \
        --mount --mount-string "${local.volumes}:/volumes" \
        ${join(" ", [for mirror in var.registry_mirrors : "--registry-mirror ${mirror}"])} \
        ${join(" ", [for option in local.extra_config : "--extra-config ${option}"])} \
        --wait-timeout 30m --addons metrics-server "$${gpus[@]}"
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "minikube delete --profile ${self.input}"
  }
}

resource "terraform_data" "node" {
  for_each         = var.nodes
  triggers_replace = [terraform_data.cluster.id, each.value]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      node=${local.node_names[each.key]}
      taint='${lookup(local.taints, each.key, "")}'
      docker update --cpus ${each.value.cpus} --memory ${each.value.memory_gib}g \
        --memory-swap ${each.value.memory_gib}g "$node"
      kubectl --context ${local.profile} wait --for=condition=Ready "node/$node" --timeout=30m
      kubectl --context ${local.profile} label node "$node" platform.node=${each.key} --overwrite
      kubectl --context ${local.profile} label node "$node" ${each.value.vram_mib > 0 ? "platform.gpu=on --overwrite" : "platform.gpu-"}
      if [ -n "$taint" ]; then
        kubectl --context ${local.profile} taint node "$node" "$taint" --overwrite
      fi
    EOT
  }
}
