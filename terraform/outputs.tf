output "urls" {
  value = { for k, h in local.hosts : k => "http://${h}" }
}

output "ingress_hint" {
  value = "minikube ip"
}
