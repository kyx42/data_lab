locals {
  argocd_redirect_middleware_name = "argocd-https-redirect"
}

resource "tls_private_key" "argocd_ca" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "argocd_ca" {
  private_key_pem       = tls_private_key.argocd_ca.private_key_pem
  validity_period_hours = 8760
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment"
  ]

  subject {
    common_name  = "data-stack-lab-internal-root"
    organization = "data-stack"
  }
  is_ca_certificate = true
}

resource "tls_private_key" "argocd_server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "argocd_server" {
  private_key_pem = tls_private_key.argocd_server.private_key_pem
  dns_names       = [var.argocd_hostname]

  subject {
    common_name  = var.argocd_hostname
    organization = "data-stack"
  }
}

resource "tls_locally_signed_cert" "argocd_server" {
  cert_request_pem      = tls_cert_request.argocd_server.cert_request_pem
  ca_private_key_pem    = tls_private_key.argocd_ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.argocd_ca.cert_pem
  validity_period_hours = 2160
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

resource "kubernetes_secret" "argocd_ca" {
  metadata {
    name      = "argocd-root-ca"
    namespace = "argocd"
  }

  data = {
    "ca.crt" = tls_self_signed_cert.argocd_ca.cert_pem
    "ca.key" = tls_private_key.argocd_ca.private_key_pem
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_secret" "argocd_tls" {
  metadata {
    name      = "argocd-server-tls"
    namespace = "argocd"
  }

  data = {
    "tls.crt" = tls_locally_signed_cert.argocd_server.cert_pem
    "tls.key" = tls_private_key.argocd_server.private_key_pem
  }

  type = "kubernetes.io/tls"

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_https_ingressroute" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "argocd"
      namespace = "argocd"
    }
    spec = {
      entryPoints = ["websecure"]
      routes = [
        {
          match = format("Host(`%s`)", var.argocd_hostname)
          kind  = "Rule"
          services = [
            {
              name = "argocd-server"
              port = 80
            }
          ]
        }
      ]
      tls = {
        secretName = kubernetes_secret.argocd_tls.metadata[0].name
      }
    }
  }
}

resource "kubernetes_manifest" "argocd_http_ingressroute" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRoute"
    metadata = {
      name      = "argocd-http"
      namespace = "argocd"
    }
    spec = {
      entryPoints = ["web"]
      routes = [
        {
          match = format("Host(`%s`)", var.argocd_hostname)
          kind  = "Rule"
          middlewares = [
            {
              name      = local.argocd_redirect_middleware_name
              namespace = "argocd"
            }
          ]
          services = [
            {
              name = "argocd-server"
              port = 80
            }
          ]
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "argocd_redirect" {
  depends_on = [helm_release.argocd]

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = local.argocd_redirect_middleware_name
      namespace = "argocd"
    }
    spec = {
      redirectScheme = {
        scheme = "https"
        port   = "8443"
      }
    }
  }
}
