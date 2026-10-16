locals {
  allocated_cpu    = sum([for node in values(var.nodes) : node.cpu_cores])
  allocated_memory = sum([for node in values(var.nodes) : node.memory_gib])
  allocated_disk   = sum([for node in values(var.nodes) : node.disk_gib])
}

resource "terraform_data" "node_profile" {
  for_each = var.nodes

  input = {
    role       = each.key
    cpu_cores  = each.value.cpu_cores
    memory_gib = each.value.memory_gib
    disk_gib   = each.value.disk_gib
  }

  lifecycle {
    precondition {
      condition = (
        local.allocated_cpu <= var.host_cpu_cores &&
        local.allocated_memory < var.host_memory_gib &&
        local.allocated_disk <= var.host_storage_gib
      )
      error_message = "Kubernetes node allocations must fit within host CPU, RAM (leaving room for the OS), and storage."
    }
  }
}
