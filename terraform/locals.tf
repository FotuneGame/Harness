locals {
  namespaces = ["ingress", "vcs", "ci", "db", "mb", "llm", "secret", "acl", "backup", "logs", "alert", "tracing"]

  hosts = {
    gitlab       = "gitlab.${var.domain}"
    registry     = "registry.${var.domain}"
    pgadmin      = "pg.${var.domain}"
    redisinsight = "redis.${var.domain}"
    clickhouse   = "clickhouse.${var.domain}"
    kafka        = "kafka.${var.domain}"
    ollama       = "ollama.${var.domain}"
    vault        = "vault.${var.domain}"
    keycloak     = "keycloak.${var.domain}"
    grafana      = "grafana.${var.domain}"
    prometheus   = "prometheus.${var.domain}"
    alert        = "alert.${var.domain}"
    jaeger       = "jaeger.${var.domain}"
  }

  ddos_annotations = {
    "nginx.ingress.kubernetes.io/limit-rps"              = "20"
    "nginx.ingress.kubernetes.io/limit-burst-multiplier" = "5"
    "nginx.ingress.kubernetes.io/limit-connections"      = "30"
    "nginx.ingress.kubernetes.io/limit-rate"             = "5242880"
    "nginx.ingress.kubernetes.io/limit-rate-after"       = "10485760"
    "nginx.ingress.kubernetes.io/proxy-body-size"        = "100m"
  }

  registry_annotations = {
    "nginx.ingress.kubernetes.io/proxy-body-size"         = "0"
    "nginx.ingress.kubernetes.io/proxy-request-buffering" = "off"
    "nginx.ingress.kubernetes.io/proxy-read-timeout"      = "900"
    "nginx.ingress.kubernetes.io/proxy-send-timeout"      = "900"
  }

  volumes = {
    "db/pg"           = { namespace = "db", claim = "data-postgresql-0", size = "5Gi", labels = {} }
    "db/redis"        = { namespace = "db", claim = "data-redis-0", size = "2Gi", labels = {} }
    "db/ch"           = { namespace = "db", claim = "data-clickhouse-0", size = "10Gi", labels = {} }
    "mb"              = { namespace = "mb", claim = "data-kafka-0", size = "5Gi", labels = {} }
    "llm/ollama"      = { namespace = "llm", claim = "models-ollama-0", size = "30Gi", labels = {} }
    "vcs/gitaly"      = { namespace = "vcs", claim = null, size = "10Gi", labels = { volume = "gitaly" } }
    "vcs/minio"       = { namespace = "vcs", claim = null, size = "5Gi", labels = { volume = "minio" } }
    "vcs/registry"    = { namespace = "vcs", claim = "data-registry-0", size = "10Gi", labels = {} }
    "secret"          = { namespace = "secret", claim = "data-vault-0", size = "2Gi", labels = {} }
    "acl"             = { namespace = "acl", claim = "data-keycloak-0", size = "2Gi", labels = {} }
    "backups"         = { namespace = "backup", claim = "data-minio-0", size = "20Gi", labels = {} }
    "logs/grafana"    = { namespace = "logs", claim = "logs-grafana", size = "2Gi", labels = {} }
    "logs/prometheus" = { namespace = "logs", claim = null, size = "10Gi", labels = {} }
    "alert"           = { namespace = "alert", claim = "storage-alertmanager-0", size = "1Gi", labels = {} }
  }
}

