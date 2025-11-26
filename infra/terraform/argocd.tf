resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  create_namespace = true
  skip_crds        = true

  values = [
    yamlencode({
      crds = {
        install = false
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
      server = {
        service = {
          type = var.argocd_server_service_type
        }
      }
    })
  ]
}
