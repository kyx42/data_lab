# NOTE: Historical reference only. cert-manager is now managed via Argo CD Applications.
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}
