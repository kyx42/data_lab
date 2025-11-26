variable "kubeconfig_path" {
  description = "Path to the kubeconfig file used to connect to the lab cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context pointing at the k3d lab cluster."
  type        = string
  default     = "k3d-data-stack-lab"
}

variable "argocd_chart_version" {
  description = "Helm chart version for Argo CD."
  type        = string
  default     = "5.51.6"
}

variable "argocd_server_service_type" {
  description = "Kubernetes service type for the Argo CD server (ClusterIP, LoadBalancer, etc.)."
  type        = string
  default     = "ClusterIP"
}

variable "argocd_hostname" {
  description = "Hostname exposed via Traefik for Argo CD."
  type        = string
  default     = "argocd.lab.local"
}

variable "argocd_platform_repo_url" {
  description = "Git repository containing the Argo CD AppProject/Application definitions (app-of-apps)."
  type        = string
  default     = "http://host.k3d.internal:8081/root/platform-gitops.git"
}

variable "argocd_platform_repo_path" {
  description = "Path inside the GitOps repository that contains the manifests (kustomization)."
  type        = string
  default     = "."
}

variable "argocd_platform_repo_revision" {
  description = "Git revision (branch/tag) for the GitOps repository."
  type        = string
  default     = "main"
}

variable "argocd_platform_repo_username" {
  description = "Optional username used by Argo CD to authenticate against the GitOps repository."
  type        = string
  default     = ""
}

variable "argocd_platform_repo_password" {
  description = "Optional password/PAT used by Argo CD to authenticate against the GitOps repository."
  type        = string
  default     = ""
}
