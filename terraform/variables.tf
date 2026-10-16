variable "host_cpu_cores" {
  description = "Количество физических ядер процессора на сервере."
  type        = number
  default     = 6

  validation {
    condition     = var.host_cpu_cores > 0 && floor(var.host_cpu_cores) == var.host_cpu_cores
    error_message = "Количество ядер процессора должно быть положительным целым числом."
  }
}

variable "host_memory_gib" {
  description = "Объём оперативной памяти сервера в ГиБ."
  type        = number
  default     = 32

  validation {
    condition     = var.host_memory_gib > 0 && floor(var.host_memory_gib) == var.host_memory_gib
    error_message = "Объём оперативной памяти должен быть положительным целым числом ГиБ."
  }
}

variable "host_storage_gib" {
  description = "Объём дискового пространства сервера в ГиБ."
  type        = number
  default     = 450

  validation {
    condition     = var.host_storage_gib > 0 && floor(var.host_storage_gib) == var.host_storage_gib
    error_message = "Объём дискового пространства должен быть положительным целым числом ГиБ."
  }
}

variable "gpu" {
  description = "Графический процессор, доступный платформенному узлу."
  type = object({
    model  = string
    memory = number
  })
  default = {
    model  = "NVIDIA GeForce GTX 1650"
    memory = 4
  }
}

variable "nodes" {
  description = "Ресурсы логических узлов Kubernetes, выделенные на физическом сервере."
  type = map(object({
    cpu_cores  = number
    memory_gib = number
    disk_gib   = number
  }))

  default = {
    platform = {
      cpu_cores  = 4
      memory_gib = 20
      disk_gib   = 100
    }
    applications = {
      cpu_cores  = 2
      memory_gib = 8
      disk_gib   = 100
    }
  }

  validation {
    condition = (
      length(var.nodes) == 2 &&
      contains(keys(var.nodes), "platform") &&
      contains(keys(var.nodes), "applications")
    )
    error_message = "Определите ровно два узла: platform и applications."
  }

  validation {
    condition = alltrue([
      for node in values(var.nodes) :
      node.cpu_cores > 0 &&
      floor(node.cpu_cores) == node.cpu_cores &&
      node.memory_gib > 0 &&
      floor(node.memory_gib) == node.memory_gib &&
      node.disk_gib > 0 &&
      floor(node.disk_gib) == node.disk_gib
    ])
    error_message = "CPU, память и диск узлов должны быть положительными целыми числами; память и диск задаются в ГиБ."
  }

  validation {
    condition     = try(var.nodes.platform.disk_gib == var.nodes.applications.disk_gib, false)
    error_message = "Для двухузлового профиля Minikube укажите одинаковый размер диска обоих узлов."
  }
}
