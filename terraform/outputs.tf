output "host_profile" {
  description = "Ресурсы физического сервера. Terraform сохраняет этот профиль, но не выделяет оборудование."
  value = {
    cpu_cores   = var.host_cpu_cores
    memory_gib  = var.host_memory_gib
    storage_gib = var.host_storage_gib
    gpu         = var.gpu
  }
}

output "node_profiles" {
  description = "Ресурсы логических узлов Kubernetes: платформенные сервисы, LLM и приложения."
  value       = { for role, node in terraform_data.node_profile : role => node.output }
}

