module "postgres" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/db/pg/postgres.yaml"

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.postgres,
    kubernetes_config_map.postgres_init,
    kubernetes_secret.pgadmin,
    kubernetes_persistent_volume.this,
  ]
}

module "redis" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/db/redis/redis.yaml"

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

module "clickhouse" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/db/ch/clickhouse.yaml"

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

module "kafka" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/mb/kafka.yaml"

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

module "ollama" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/llm/ollama/ollama.yaml"

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

module "keycloak" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/acl/keycloak.yaml"

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.keycloak,
    kubernetes_persistent_volume.this,
    module.postgres,
    time_sleep.wait_for_databases,
  ]
}

module "backup" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/backup/minio.yaml"

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.minio,
    kubernetes_persistent_volume.this,
  ]
}

module "backup_schedules" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/backup/schedule.yaml"

  depends_on = [helm_release.k8up, module.backup]
}

module "registry" {
  source = "./modules/manifests"
  path   = "${path.module}/../k8s/vcs/registry.yaml"

  vars = { gitlab_host = local.hosts.gitlab }

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_persistent_volume.this,
    helm_release.gitlab,
  ]
}

resource "time_sleep" "wait_for_databases" {
  create_duration = "90s"

  depends_on = [module.postgres, module.redis]
}
