resource "kubernetes_namespace" "this" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
  }
}
