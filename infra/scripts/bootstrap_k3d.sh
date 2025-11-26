#!/usr/bin/env bash
# Bootstrap a local k3d-based Kubernetes lab that mimics an on-prem cluster.
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-data-stack-lab}
REGISTRY_NAME=${REGISTRY_NAME:-${CLUSTER_NAME}-registry}
REGISTRY_PORT=${REGISTRY_PORT:-5001}
SERVER_COUNT=${SERVER_COUNT:-1}
AGENT_COUNT=${AGENT_COUNT:-2}
K3S_IMAGE=${K3S_IMAGE:-rancher/k3s:v1.29.4-k3s1}
HOST_HTTP_PORT=${HOST_HTTP_PORT:-8080}
HOST_HTTPS_PORT=${HOST_HTTPS_PORT:-8443}
K3D_WAIT_TIMEOUT=${K3D_WAIT_TIMEOUT:-120}
INSTALL_ADDONS=false
INSTALL_ADDONS_REPOS_ONLY=false

LOG_PREFIX="[k3d-bootstrap]"
CERT_MANAGER_CRDS_URL=${CERT_MANAGER_CRDS_URL:-https://github.com/cert-manager/cert-manager/releases/download/v1.14.5/cert-manager.crds.yaml}
TRAEFIK_CRDS_URL=${TRAEFIK_CRDS_URL:-https://raw.githubusercontent.com/traefik/traefik/v3.5/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml}
ARGOCD_CRDS_KUSTOMIZE=${ARGOCD_CRDS_KUSTOMIZE:-https://github.com/argoproj/argo-cd/manifests/crds?ref=v2.9.3}

usage() {
  cat <<'EOF'
Usage: bootstrap_k3d.sh <command> [options]

Commands:
  up [--with-addons]     Create (or reuse) the local registry and k3d cluster.
  down                   Delete the k3d cluster and the local registry.
  reset [--with-addons]  Recreate the cluster from scratch (down + up).
  status                 Show cluster and node status if the cluster exists.
  kubeconfig             Print the kubeconfig path for the cluster.
  help                   Show this message.

Environment variables (override defaults if needed):
  CLUSTER_NAME, REGISTRY_NAME, REGISTRY_PORT, SERVER_COUNT, AGENT_COUNT,
  K3S_IMAGE, HOST_HTTP_PORT, HOST_HTTPS_PORT, K3D_WAIT_TIMEOUT.

Pass --with-addons to 'up' pour installer Traefik/cert-manager/ArgoCD via Helm.
Pass --with-addons-repos-only pour ajouter uniquement les dépôts Helm (Terraform fera l'installation).
EOF
}

log() {
  echo "${LOG_PREFIX} $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log "Missing dependency '$1'. $2"
    exit 1
  fi
}

check_docker_access() {
  if ! command -v docker >/dev/null 2>&1; then
    log "Docker CLI not found. Installez Docker ou lancez infra/scripts/install_cluster_requirements.sh."
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    log "Impossible de contacter le daemon Docker. Vérifiez qu'il tourne et que votre utilisateur a les droits (ex. 'sudo usermod -aG docker $USER' puis nouvelle session, ou exécuter la commande via sudo)."
    exit 1
  fi
}

cluster_exists() {
  k3d cluster list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "${CLUSTER_NAME}"
}

registry_exists() {
  k3d registry list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "k3d-${REGISTRY_NAME}"
}

create_registry() {
  if registry_exists; then
    log "Registry ${REGISTRY_NAME} already exists."
    return
  fi
  log "Creating registry ${REGISTRY_NAME} on port ${REGISTRY_PORT}..."
  k3d registry create "${REGISTRY_NAME}" --port "0.0.0.0:${REGISTRY_PORT}"
}

create_cluster() {
  if cluster_exists; then
    log "Cluster ${CLUSTER_NAME} already exists."
    return
  fi
  log "Creating cluster ${CLUSTER_NAME}..."
  k3d cluster create "${CLUSTER_NAME}" \
    --image "${K3S_IMAGE}" \
    --servers "${SERVER_COUNT}" \
    --agents "${AGENT_COUNT}" \
    --registry-use "k3d-${REGISTRY_NAME}:5000" \
    --port "${HOST_HTTP_PORT}:80@loadbalancer" \
    --port "${HOST_HTTPS_PORT}:443@loadbalancer" \
    --k3s-arg "--disable=traefik@server:0" \
    --wait
  log "Cluster ${CLUSTER_NAME} created."
}

install_crds() {
  require_cmd kubectl "Install kubectl (https://kubernetes.io/docs/tasks/tools/)."
  log "Applying cert-manager CRDs (${CERT_MANAGER_CRDS_URL})..."
  kubectl apply -f "${CERT_MANAGER_CRDS_URL}"
  log "Applying Traefik CRDs (${TRAEFIK_CRDS_URL})..."
  kubectl apply -f "${TRAEFIK_CRDS_URL}"
  log "Applying Argo CD CRDs (${ARGOCD_CRDS_KUSTOMIZE})..."
  kubectl apply -k "${ARGOCD_CRDS_KUSTOMIZE}"
}

wait_for_cluster() {
  require_cmd kubectl "Install kubectl (https://kubernetes.io/docs/tasks/tools/)."
  log "Waiting for nodes to become Ready..."
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  kubectl wait --timeout="${K3D_WAIT_TIMEOUT}s" --for=condition=Ready node --all
}

install_addons() {
  local mode="${1:-install}" # install | repos

  require_cmd helm "Install helm (https://helm.sh/docs/intro/install/)."
  require_cmd kubectl "Install kubectl (https://kubernetes.io/docs/tasks/tools/)."

  if [[ "${mode}" == "repos" ]]; then
    log "Adding Helm repositories (Traefik, cert-manager, ArgoCD) for Terraform..."
    helm repo add traefik https://traefik.github.io/charts >/dev/null
    helm repo add jetstack https://charts.jetstack.io >/dev/null
    helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
    helm repo update >/dev/null
    log "Helm repositories configured."
    return
  fi

  log "Installing base addons (Traefik, cert-manager, ArgoCD)..."

  kubectl create namespace traefik --dry-run=client -o yaml | kubectl apply -f -
  helm repo add traefik https://traefik.github.io/charts >/dev/null

  kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
  helm repo add jetstack https://charts.jetstack.io >/dev/null

  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
  helm repo update >/dev/null

  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace cert-manager \
    --set installCRDs=true

  helm upgrade --install traefik traefik/traefik \
    --namespace traefik \
    --set service.type=LoadBalancer

  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd \
    --set server.service.type=ClusterIP \
    --values - <<EOF
configs:
  params:
    server.insecure: true
    server.disable.auth: "false"
server:
  extraArgs:
    - --insecure
EOF

  log "Base addons installed."
}

cmd_up() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --with-addons)
        INSTALL_ADDONS=true
        shift
        ;;
      --with-addons-repos-only)
        INSTALL_ADDONS_REPOS_ONLY=true
        shift
        ;;
      *)
        log "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done

  require_cmd k3d "Install k3d (https://k3d.io/)."
  check_docker_access
  create_registry
  create_cluster
  wait_for_cluster
  log "Ensuring cert-manager, Traefik and Argo CD CRDs are present..."
  install_crds
  if [[ "${INSTALL_ADDONS}" == "true" ]]; then
    install_addons "install"
  elif [[ "${INSTALL_ADDONS_REPOS_ONLY}" == "true" ]]; then
    install_addons "repos"
  fi
  log "Cluster ${CLUSTER_NAME} is ready."
}

cmd_down() {
  require_cmd k3d "Install k3d (https://k3d.io/)."
  check_docker_access
  if cluster_exists; then
    log "Deleting cluster ${CLUSTER_NAME}..."
    k3d cluster delete "${CLUSTER_NAME}"
  else
    log "Cluster ${CLUSTER_NAME} not found."
  fi
  if registry_exists; then
    log "Deleting registry ${REGISTRY_NAME}..."
    k3d registry delete "${REGISTRY_NAME}"
  fi
}

cmd_status() {
  require_cmd k3d "Install k3d (https://k3d.io/)."
  check_docker_access
  if cluster_exists; then
    k3d cluster list "${CLUSTER_NAME}"
    if command -v kubectl >/dev/null 2>&1; then
      echo
      kubectl --context "k3d-${CLUSTER_NAME}" get nodes -o wide
    fi
  else
    log "Cluster ${CLUSTER_NAME} not found."
  fi
}

cmd_kubeconfig() {
  require_cmd k3d "Install k3d (https://k3d.io/)."
  if cluster_exists; then
    k3d kubeconfig get "${CLUSTER_NAME}"
  else
    log "Cluster ${CLUSTER_NAME} not found."
    exit 1
  fi
}

cmd_reset() {
  log "Resetting cluster ${CLUSTER_NAME}..."
  cmd_down
  cmd_up "$@"
}

COMMAND=${1:-}
shift || true

case "${COMMAND}" in
  up) cmd_up "$@" ;;
  down) cmd_down ;;
  reset) cmd_reset "$@" ;;
  status) cmd_status ;;
  kubeconfig) cmd_kubeconfig ;;
  help|"")
    usage
    ;;
  *)
    log "Unknown command: ${COMMAND}"
    usage
    exit 1
    ;;
esac
