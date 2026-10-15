resource "kubernetes_ingress_v1" "this" {
  for_each = {
    pgadmin      = { ns = "db", svc = "pgadmin", port = 80, host = local.hosts.pgadmin, annotations = local.ddos_annotations }
    redisinsight = { ns = "db", svc = "redisinsight", port = 5540, host = local.hosts.redisinsight, annotations = local.ddos_annotations }
    clickhouse   = { ns = "db", svc = "clickhouse", port = 8123, host = local.hosts.clickhouse, annotations = local.ddos_annotations }
    kafka        = { ns = "mb", svc = "kafka-ui", port = 8080, host = local.hosts.kafka, annotations = local.ddos_annotations }
    ollama       = { ns = "llm", svc = "open-webui", port = 8080, host = local.hosts.ollama, annotations = local.ddos_annotations }
    vault        = { ns = "secret", svc = "vault", port = 8200, host = local.hosts.vault, annotations = local.ddos_annotations }
    keycloak     = { ns = "acl", svc = "keycloak", port = 8080, host = local.hosts.keycloak, annotations = local.ddos_annotations }
    registry     = { ns = "vcs", svc = "registry", port = 5000, host = local.hosts.registry, annotations = local.registry_annotations }
    grafana      = { ns = "logs", svc = "logs-grafana", port = 80, host = local.hosts.grafana, annotations = local.ddos_annotations }
    prometheus   = { ns = "logs", svc = "logs-prometheus", port = 9090, host = local.hosts.prometheus, annotations = local.ddos_annotations }
    alertmanager = { ns = "alert", svc = "alertmanager", port = 9093, host = local.hosts.alert, annotations = local.ddos_annotations }
    jaeger       = { ns = "tracing", svc = "jaeger", port = 16686, host = local.hosts.jaeger, annotations = local.ddos_annotations }
  }

  metadata {
    name        = each.key
    namespace   = each.value.ns
    annotations = each.value.annotations
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = each.value.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = each.value.svc
              port {
                number = each.value.port
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}
