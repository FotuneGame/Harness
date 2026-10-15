variable "path" {
  description = "Path to a multi-document Kubernetes YAML manifest."
  type        = string
}

variable "vars" {
  description = "Optional values substituted into dollar-brace placeholders in the manifest."
  type        = map(string)
  default     = null
}
