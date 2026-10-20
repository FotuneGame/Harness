output "nodes" {
  description = "Узлы кластера: имя в Kubernetes, метка platform.node и выделенные ресурсы."
  value = {
    for role, node in var.nodes : local.node_names[role] => merge(node, { label = role })
  }
}

output "ansible" {
  description = "Параметры для Ansible: профиль, память WSL, версия Kubernetes, ключ etcd, доли VRAM."
  value       = local.ansible
}

output "allocated" {
  description = "Сумма ресурсов узлов и ресурсы сервера."
  value       = { nodes = local.allocated, host = var.host }
}
