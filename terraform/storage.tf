resource "kubernetes_storage_class" "local" {
  metadata {
    name = "local"
  }

  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "Immediate"
}

resource "kubernetes_persistent_volume" "this" {
  for_each = local.volumes

  metadata {
    name   = "pv-${replace(each.key, "/", "-")}"
    labels = each.value.labels
  }

  spec {
    capacity           = { storage = each.value.size }
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class.local.metadata[0].name

    persistent_volume_source {
      host_path {
        path = "/volumes/${each.key}"
        type = "DirectoryOrCreate"
      }
    }

    dynamic "claim_ref" {
      for_each = each.value.claim == null ? [] : [each.value.claim]

      content {
        namespace = each.value.namespace
        name      = claim_ref.value
      }
    }
  }
}
