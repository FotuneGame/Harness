variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "minikube"
}

variable "domain" {
  type    = string
  default = "local"
}

variable "postgres_password" {
  type      = string
  sensitive = true
  default   = "postgres"
}

variable "gitlab_db_password" {
  type      = string
  sensitive = true
  default   = "gitlab"
}

variable "keycloak_db_password" {
  type      = string
  sensitive = true
  default   = "keycloak"
}

variable "keycloak_admin_password" {
  type      = string
  sensitive = true
  default   = "admin"
}

variable "pgadmin_password" {
  type      = string
  sensitive = true
  default   = "admin"
}

variable "gitlab_runner_token" {
  type      = string
  sensitive = true
  default   = "CHANGE_ME"
}

variable "minio_password" {
  type      = string
  sensitive = true
  default   = "minio123"
}

variable "restic_password" {
  type      = string
  sensitive = true
  default   = "restic"
}

variable "grafana_admin_password" {
  type      = string
  sensitive = true
  default   = "admin"
}
