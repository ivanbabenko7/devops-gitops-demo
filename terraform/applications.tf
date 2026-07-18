locals {
  root_applications = {
    applications = {
      name = "applications-root"
      path = "applications"
    }

    infrastructure = {
      name = "infrastructure-root"
      path = "infrastructure"
    }
  }
}

resource "kubectl_manifest" "root_application" {
  for_each = local.root_applications

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"

    metadata = {
      name      = each.value.name
      namespace = "argocd"

      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]

      labels = {
        "app.kubernetes.io/part-of"    = "devops-gitops-demo"
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }

    spec = {
      project = "default"

      source = {
        repoURL        = var.git_repo_url
        targetRevision = var.git_revision
        path           = each.value.path

        helm = {
          parameters = [
            {
              name  = "repoURL"
              value = var.git_repo_url
            },
            {
              name  = "targetRevision"
              value = var.git_revision
            },
            {
              name  = "destination.namespace"
              value = var.workload_namespace
            }
          ]
        }
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }

      syncPolicy = {
        automated = {
          enabled    = true
          prune      = true
          selfHeal   = true
          allowEmpty = false
        }

        syncOptions = [
          "CreateNamespace=true",
          "ApplyOutOfSyncOnly=true"
        ]

        retry = {
          limit = 5

          backoff = {
            duration    = "10s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })

  validate_schema  = false
  wait_for_rollout = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.mysql_auth
  ]
}
