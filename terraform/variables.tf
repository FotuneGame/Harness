variable "host" {
  description = "Сервер: Intel Core i5-11400F (6 ядер / 12 потоков), разрешено 42 ГиБ RAM из 48, диск 450 ГиБ, GTX 1650 (4 ГиБ VRAM)."
  type = object({
    cpus         = number
    memory_gib   = number
    disk_gib     = number
    gpu_vram_mib = number
  })
  default = {
    cpus         = 12
    memory_gib   = 42
    disk_gib     = 450
    gpu_vram_mib = 4096
  }
}

variable "nodes" {
  description = "Узлы Kubernetes: core — сервисы платформы и всех окружений, llms — llama.cpp окружений, apps — свои приложения окружений dev, stage, prod. vram_mib — доля VRAM видеокарты (HAMi)."
  type = map(object({
    cpus       = number
    memory_gib = number
    disk_gib   = number
    vram_mib   = optional(number, 0)
  }))
  default = {
    core = { cpus = 6, memory_gib = 20, disk_gib = 200, vram_mib = 0 }
    llms = { cpus = 4, memory_gib = 16, disk_gib = 200, vram_mib = 4096 }
    apps = { cpus = 2, memory_gib = 4, disk_gib = 50, vram_mib = 0 }
  }

  validation {
    condition     = toset(keys(var.nodes)) == toset(["core", "llms", "apps"])
    error_message = "Нужны ровно три узла: core, llms и apps."
  }

  validation {
    condition = alltrue([
      for node in values(var.nodes) :
      node.cpus >= 1 && node.memory_gib >= 1 && floor(node.memory_gib) == node.memory_gib
    ])
    error_message = "CPU и память узлов должны быть положительными, память — целым числом ГиБ."
  }

  validation {
    condition = alltrue([
      for node in values(var.nodes) : node.vram_mib >= 0 && floor(node.vram_mib) == node.vram_mib
    ])
    error_message = "vram_mib узлов — целое неотрицательное число МиБ."
  }
}

variable "gpu" {
  description = "Передать NVIDIA GeForce GTX 1650 (4 ГБ) в кластер, если Docker видит GPU."
  type        = bool
  default     = true
}

variable "registry_mirrors" {
  description = "Зеркала Docker Hub для узлов: прямая загрузка с Docker Hub очень медленная. Образ, которого нет в зеркале, скачивается с Docker Hub."
  type        = list(string)
  default     = ["https://mirror.gcr.io"]
}

variable "kubernetes_version" {
  description = "Версия Kubernetes; Ansible ставит kubectl этой же версии."
  type        = string
  default     = "v1.31.0"
}
