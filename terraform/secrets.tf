resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "postgres-secret"
    namespace = "db"
  }

  data = {
    POSTGRES_PASSWORD = var.postgres_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_config_map" "postgres_init" {
  metadata {
    name      = "postgres-init"
    namespace = "db"
  }

  data = {
    "init.sql" = <<-SQL
      CREATE ROLE gitlab   LOGIN PASSWORD '${var.gitlab_db_password}';
      CREATE ROLE keycloak LOGIN PASSWORD '${var.keycloak_db_password}';

      CREATE DATABASE gitlabhq_production OWNER gitlab;
      CREATE DATABASE keycloak            OWNER keycloak;

      \connect gitlabhq_production
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE EXTENSION IF NOT EXISTS btree_gist;
    SQL
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "pgadmin" {
  metadata {
    name      = "pgadmin-secret"
    namespace = "db"
  }

  data = {
    PGADMIN_DEFAULT_EMAIL    = "admin@${var.domain}"
    PGADMIN_DEFAULT_PASSWORD = var.pgadmin_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "gitlab_pg" {
  metadata {
    name      = "gitlab-postgresql-password"
    namespace = "vcs"
  }

  data = {
    postgresql-password = var.gitlab_db_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "keycloak" {
  metadata {
    name      = "keycloak-secret"
    namespace = "acl"
  }

  data = {
    KEYCLOAK_ADMIN          = "admin"
    KEYCLOAK_ADMIN_PASSWORD = var.keycloak_admin_password
    KC_DB_PASSWORD          = var.keycloak_db_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "gitlab_runner" {
  metadata {
    name      = "gitlab-runner-secret"
    namespace = "ci"
  }

  data = {
    runner-token              = var.gitlab_runner_token
    runner-registration-token = var.gitlab_runner_token
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "minio" {
  metadata {
    name      = "minio-secret"
    namespace = "backup"
  }

  data = {
    MINIO_ROOT_USER     = "minio"
    MINIO_ROOT_PASSWORD = var.minio_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "k8up_s3" {
  metadata {
    name      = "k8up-s3"
    namespace = "backup"
  }

  data = {
    accessKeyID     = "minio"
    secretAccessKey = var.minio_password
  }

  depends_on = [kubernetes_namespace.this]
}

resource "kubernetes_secret" "k8up_restic" {
  metadata {
    name      = "k8up-restic"
    namespace = "backup"
  }

  data = {
    password = var.restic_password
  }

  depends_on = [kubernetes_namespace.this]
}
