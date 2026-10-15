resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  namespace  = "ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  values     = [file("${path.module}/../k8s/proxy/values.yaml")]

  depends_on = [kubernetes_namespace.this]
}

resource "helm_release" "gitlab" {
  name       = "gitlab"
  namespace  = "vcs"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  timeout    = 1200

  values = [file("${path.module}/../k8s/vcs/values.yaml")]

  set {
    name  = "global.hosts.domain"
    value = var.domain
  }

  set {
    name  = "global.hosts.registry.name"
    value = local.hosts.registry
  }

  set {
    name  = "global.registry.host"
    value = local.hosts.registry
  }

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.gitlab_pg,
    kubernetes_persistent_volume.this,
    time_sleep.wait_for_databases,
  ]
}

resource "helm_release" "gitlab_runner" {
  name       = "gitlab-runner"
  namespace  = "ci"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab-runner"

  values = [file("${path.module}/../k8s/ci/values.yaml")]

  set {
    name  = "gitlabUrl"
    value = "http://${local.hosts.gitlab}/"
  }

  depends_on = [kubernetes_namespace.this, kubernetes_secret.gitlab_runner, helm_release.gitlab]
}

resource "helm_release" "vault" {
  name       = "vault"
  namespace  = "secret"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  values     = [file("${path.module}/../k8s/secret/values.yaml")]

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

resource "helm_release" "k8up" {
  name       = "k8up"
  namespace  = "backup"
  repository = "https://k8up-io.github.io/k8up"
  chart      = "k8up"
  values     = [file("${path.module}/../k8s/backup/values.yaml")]

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_secret.k8up_s3,
    kubernetes_secret.k8up_restic,
  ]
}

resource "helm_release" "alertmanager" {
  name       = "alertmanager"
  namespace  = "alert"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "alertmanager"

  values = [file("${path.module}/../k8s/alert/values.yaml")]

  depends_on = [kubernetes_namespace.this, kubernetes_persistent_volume.this]
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "logs"
  namespace  = "logs"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  timeout    = 900

  values = [file("${path.module}/../k8s/logs/values.yaml")]

  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  depends_on = [
    kubernetes_namespace.this,
    kubernetes_persistent_volume.this,
    helm_release.alertmanager,
  ]
}

resource "helm_release" "jaeger" {
  name       = "jaeger"
  namespace  = "tracing"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"

  values = [file("${path.module}/../k8s/tracing/values.yaml")]

  depends_on = [kubernetes_namespace.this]
}
