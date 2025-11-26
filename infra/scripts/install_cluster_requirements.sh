#!/usr/bin/env bash
# Install the local tooling required by infra/scripts/bootstrap_k3d.sh.
set -euo pipefail

LOG_PREFIX="[k3d-deps]"
SKIP_DOCKER=${SKIP_DOCKER:-false}
K3D_VERSION=${K3D_VERSION:-}
KUBECTL_VERSION=${KUBECTL_VERSION:-}
HELM_VERSION=${HELM_VERSION:-}
ARGOCD_CLI_VERSION=${ARGOCD_CLI_VERSION:-}
TERRAFORM_VERSION=${TERRAFORM_VERSION:-}

if [[ "${SKIP_DOCKER}" != "true" && "${SKIP_DOCKER}" != "false" ]]; then
  echo "SKIP_DOCKER must be 'true' or 'false' (got '${SKIP_DOCKER}')." >&2
  exit 1
fi

log() {
  echo "${LOG_PREFIX} $*"
}

usage() {
  cat <<'EOF'
Usage: install_cluster_requirements.sh [options]

Options:
  --skip-docker        Do not attempt to install Docker (default: install if missing).
  --help               Show this help message.

Environment overrides:
  SKIP_DOCKER=true|false   Skip or force Docker installation.
  K3D_VERSION=vX.Y.Z       Install a specific k3d release (default: upstream latest).
  KUBECTL_VERSION=vX.Y.Z   Install a specific kubectl release (default: upstream stable).
  HELM_VERSION=vX.Y.Z      Install a specific Helm release (default: upstream latest).
  ARGOCD_CLI_VERSION=vX.Y  Install a specific argocd CLI release (default: upstream latest).
  TERRAFORM_VERSION=vX.Y.Z Install a specific Terraform release (default: upstream latest).

This script targets Debian/Ubuntu or WSL environments with apt-get available.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --skip-docker)
        SKIP_DOCKER=true
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        log "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not found. This installer currently supports Debian/Ubuntu-like systems."
    exit 1
  fi
}

SUDO=""
if [[ $(id -u) -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    log "This script must run as root when sudo is unavailable."
    exit 1
  fi
fi

apt_update() {
  require_apt
  log "Updating apt package index..."
  ${SUDO} apt-get update
}

ensure_base_packages() {
  local pkgs=(ca-certificates curl gnupg lsb-release unzip jq)
  apt_update
  log "Installing base packages: ${pkgs[*]}"
  ${SUDO} apt-get install -y "${pkgs[@]}"
}

detect_arch() {
  local arch
  arch=$(uname -m)
  case "${arch}" in
    x86_64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      log "Unsupported architecture '${arch}'."
      exit 1
      ;;
  esac
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
    return
  fi

  log "Installing Docker Engine..."
  ensure_base_packages
  ${SUDO} install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | ${SUDO} gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  fi
  ${SUDO} chmod a+r /etc/apt/keyrings/docker.gpg

  local codename
  codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME}}")
  echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
${codename} stable" | ${SUDO} tee /etc/apt/sources.list.d/docker.list >/dev/null

  apt_update
  ${SUDO} apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  log "Docker installed. Run 'sudo usermod -aG docker $USER' and re-login to use Docker without sudo."
}

install_k3d() {
  if command -v k3d >/dev/null 2>&1; then
    log "k3d already installed."
    return
  fi

  local installer="https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh"
  local runner=""
  if [[ -n "${SUDO}" ]]; then
    runner="${SUDO}"
  fi

  if [[ -n "${K3D_VERSION}" ]]; then
    log "Installing k3d ${K3D_VERSION}..."
    if [[ -n "${runner}" ]]; then
      curl -fsSL "${installer}" | ${runner} env TAG="${K3D_VERSION}" bash
    else
      curl -fsSL "${installer}" | TAG="${K3D_VERSION}" bash
    fi
  else
    log "Installing latest k3d release..."
    if [[ -n "${runner}" ]]; then
      curl -fsSL "${installer}" | ${runner} bash
    else
      curl -fsSL "${installer}" | bash
    fi
  fi
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    log "kubectl already installed."
    return
  fi

  local arch version tmp_file
  arch=$(detect_arch)
  if [[ -z "${KUBECTL_VERSION}" ]]; then
    log "Fetching latest kubectl version..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
  fi
  log "Installing kubectl ${KUBECTL_VERSION}..."
  tmp_file=$(mktemp)
  curl -fsSLo "${tmp_file}" "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${arch}/kubectl"
  chmod +x "${tmp_file}"
  ${SUDO} mv "${tmp_file}" /usr/local/bin/kubectl
}

install_helm() {
  if command -v helm >/dev/null 2>&1; then
    log "Helm already installed."
    return
  fi

  log "Installing Helm ${HELM_VERSION:-latest}..."
  local script
  script=$(mktemp)
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o "${script}"
  chmod +x "${script}"
  if [[ -n "${HELM_VERSION}" ]]; then
    env DESIRED_VERSION="${HELM_VERSION}" "${script}"
  else
    "${script}"
  fi
  rm -f "${script}"
}

install_terraform() {
  if command -v terraform >/dev/null 2>&1; then
    log "Terraform already installed."
    return
  fi

  local version arch tmp_file
  arch=$(detect_arch)
  if [ -z "${TERRAFORM_VERSION}" ]; then
    log "Fetching latest Terraform version..."
    TERRAFORM_VERSION=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r '.current_version')
  fi
  log "Installing Terraform ${TERRAFORM_VERSION}..."
  tmp_file=$(mktemp)
  curl -fsSLo "${tmp_file}" "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
  unzip -q "${tmp_file}" -d /tmp
  ${SUDO} mv /tmp/terraform /usr/local/bin/terraform
  rm -f "${tmp_file}"
}

install_argocd_cli() {
  if command -v argocd >/dev/null 2>&1; then
    log "argocd CLI already installed."
    return
  fi

  local version arch tmp_file desired="${ARGOCD_CLI_VERSION:-}"
  arch=$(detect_arch)
  if [ -z "${desired}" ]; then
    log "Fetching latest argocd CLI version..."
    desired=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r '.tag_name')
  fi
  log "Installing argocd ${desired}..."
  tmp_file=$(mktemp)
  curl -fsSLo "${tmp_file}" "https://github.com/argoproj/argo-cd/releases/download/${desired}/argocd-linux-${arch}"
  chmod +x "${tmp_file}"
  ${SUDO} mv "${tmp_file}" /usr/local/bin/argocd
}

install_argocd_cli() {
  if command -v argocd >/dev/null 2>&1; then
    log "argocd CLI already installed."
    return
  end
  

main() {
  parse_args "$@"
  ensure_base_packages

  if [[ "${SKIP_DOCKER}" == "false" ]]; then
    install_docker
  else
    log "Skipping Docker installation as requested."
  fi

  install_k3d
  install_kubectl
  install_helm
  install_terraform
  install_argocd_cli

  log "All dependencies installed. You can now run infra/scripts/bootstrap_k3d.sh."
}

main "$@"
