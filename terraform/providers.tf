provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kubeconfig)
    config_context = var.kube_context
  }
}

provider "kubectl" {
  config_path    = pathexpand(var.kubeconfig)
  config_context = var.kube_context
}
