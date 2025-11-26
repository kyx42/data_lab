locals {
  argocd_repo_secret_enabled = var.argocd_platform_repo_username != "" && var.argocd_platform_repo_password != ""
}

resource "kubernetes_secret" "argocd_gitlab_repo_creds" {
  count = local.argocd_repo_secret_enabled ? 1 : 0

  metadata {
    name      = "repo-creds-gitlab"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  type = "Opaque"

  data = {
    url      = "http://host.k3d.internal:8081"
    username = var.argocd_platform_repo_username
    password = var.argocd_platform_repo_password
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_gitops_app" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "platform-gitops"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.argocd_platform_repo_url
        targetRevision = var.argocd_platform_repo_revision
        path           = var.argocd_platform_repo_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }
}
