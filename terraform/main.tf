resource "kubernetes_namespace_v1" "workloads" {
  metadata {
    name = var.workload_namespace

    labels = {
      "app.kubernetes.io/part-of"    = "devops-gitops-demo"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_secret_v1" "mysql_auth" {
  metadata {
    name      = "mysql-auth"
    namespace = kubernetes_namespace_v1.workloads.metadata[0].name

    labels = {
      "app.kubernetes.io/part-of"    = "devops-gitops-demo"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  type = "Opaque"

  data = {
    "mysql-root-password"        = var.mysql_root_password
    "mysql-password"             = var.mysql_app_password
    "mysql-replication-password" = var.mysql_app_password
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  namespace        = "argocd"
  create_namespace = true

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 900
  max_history     = 5

  values = [
    yamlencode({
      configs = {
        params = {
          "server.insecure" = "true"
        }
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]
}
