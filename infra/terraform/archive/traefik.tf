# NOTE: Historical reference only. Traefik is now managed via Argo CD Applications.
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  create_namespace = true

  values = [
    yamlencode({
      ports = {
        web = {
          port = 8000
        }
        websecure = {
          port = 8443
        }
      }
      service = {
        type = "LoadBalancer"
      }
      ingressRoute = {
        dashboard = {
          enabled = false
        }
      }
      logs = {
        general = {
          level = "INFO"
        }
      }
      additionalArguments = [
        "--entrypoints.web.http.redirections.entryPoint.to=websecure",
        "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      ]
    })
  ]
}

resource "null_resource" "configure_traefik_dashboard" {
  count = var.use_script_config ? 1 : 0

  depends_on = [
    helm_release.traefik,
    helm_release.cert_manager
  ]

  triggers = {
    script_hash   = filesha256("${local.repo_root}/scripts/configure_traefik_dashboard.sh")
    manifest_hash = filesha256("${local.repo_root}/k8s/traefik/dashboard.yaml")
    chart_version = var.traefik_chart_version
  }

  provisioner "local-exec" {
    command = "bash ${local.repo_root}/scripts/configure_traefik_dashboard.sh"
    environment = {
      KUBECTL_CONTEXT = var.kube_context
    }
  }
}

resource "kubernetes_manifest" "traefik_dashboard_certificate" {
  count = var.use_script_config ? 0 : 1

  depends_on = [helm_release.cert_manager]

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "traefik-dashboard-cert"
      namespace = "traefik"
    }
    spec = {
      secretName = "traefik-dashboard-tls"
      duration   = "2160h"
      renewBefore = "720h"
      privateKey = {
        algorithm = "RSA"
        size      = 2048
      }
      dnsNames = ["traefik.lab.local"]
      issuerRef = {
        name = "internal-ca-issuer"
        kind = "ClusterIssuer"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_dashboard_root_redirect" {
  count = var.use_script_config ? 0 : 1

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "traefik-dashboard-root-redirect"
      namespace = "traefik"
    }
    spec = {
      redirectRegex = {
        regex       = "^https?://traefik\\.lab\\.local(:\\d+)?/?$"
        replacement = "/dashboard/"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_dashboard_http_redirect" {
  count = var.use_script_config ? 0 : 1

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "traefik-dashboard-http-redirect"
      namespace = "traefik"
    }
    spec = {
      redirectRegex = {
        regex       = "^http://traefik\\.lab\\.local(:\\d+)?(.*)$"
        replacement = "https://traefik.lab.local:8443$2"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_dashboard_ingressroute_https" {
  count = var.use_script_config ? 0 : 1

  depends_on = [
    helm_release.traefik,
    kubernetes_manifest.traefik_dashboard_certificate
  ]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = "Host(`traefik.lab.local`) && Path(`/`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "traefik-dashboard-root-redirect"
              namespace = "traefik"
            }
          ]
          services = [
            {
              kind = "TraefikService"
              name = "api@internal"
            }
          ]
        },
        {
          match = "Host(`traefik.lab.local`) && PathPrefix(`/`)"
          kind  = "Rule"
          services = [
            {
              kind = "TraefikService"
              name = "api@internal"
            }
          ]
        }
      ]
      tls = {
        secretName = "traefik-dashboard-tls"
      }
    }
  }
}

resource "kubernetes_manifest" "traefik_dashboard_ingressroute_http" {
  count = var.use_script_config ? 0 : 1

  depends_on = [helm_release.traefik]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "traefik-dashboard-http"
      namespace = "traefik"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = "Host(`traefik.lab.local`) && PathPrefix(`/`)"
          kind  = "Rule"
          middlewares = [
            {
              name      = "traefik-dashboard-http-redirect"
              namespace = "traefik"
            }
          ]
          services = [
            {
              kind = "TraefikService"
              name = "api@internal"
            }
          ]
        }
      ]
    }
  }
}
