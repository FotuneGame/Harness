terraform {
  required_version = ">= 1.6"

  required_providers {
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.33" }
    kubectl    = { source = "alekc/kubectl", version = "~> 2.1" }
    time       = { source = "hashicorp/time", version = "~> 0.12" }
  }
}
