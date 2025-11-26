#!/usr/bin/env bash
# Start the Docker services required by the lab (Postgres, Vault, GitLab).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Defaults (override via env)
POSTGRES_IMAGE=${POSTGRES_IMAGE:-postgres:15}
POSTGRES_USER=${POSTGRES_USER:-gitlab}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-gitlab-password}
POSTGRES_DB=${POSTGRES_DB:-gitlabhq_production}
POSTGRES_HOST_PORT=${POSTGRES_HOST_PORT:-5433}

VAULT_IMAGE=${VAULT_IMAGE:-hashicorp/vault:1.15.4}
VAULT_HOST_PORT=${VAULT_HOST_PORT:-8200}
VAULT_ROOT_TOKEN=${VAULT_ROOT_TOKEN:-labroot}

GITLAB_IMAGE=${GITLAB_IMAGE:-gitlab/gitlab-ce:16.11.1-ce.0}
GITLAB_HTTP_PORT=${GITLAB_HTTP_PORT:-8081}
GITLAB_HTTPS_PORT=${GITLAB_HTTPS_PORT:-8444}
GITLAB_SSH_PORT=${GITLAB_SSH_PORT:-2224}
GITLAB_EXTERNAL_URL=${GITLAB_EXTERNAL_URL:-http://gitlab.lab.local:8081}
GITLAB_ROOT_PASSWORD=${GITLAB_ROOT_PASSWORD:-ChangeMe123!}
GITLAB_ROOT_TOKEN_NAME=${GITLAB_ROOT_TOKEN_NAME:-terraform-bot}
GITLAB_ROOT_TOKEN_FILE=${GITLAB_ROOT_TOKEN_FILE:-${REPO_ROOT}/docker/gitlab/root_pat.txt}
GITLAB_ROOT_TOKEN_DAYS=${GITLAB_ROOT_TOKEN_DAYS:-365}

DOCKER_NETWORK=${DOCKER_NETWORK:-data-stack-lab-net}

POSTGRES_DATA_DIR=${POSTGRES_DATA_DIR:-${REPO_ROOT}/docker/postgres-data}
GITLAB_BASE_DIR=${GITLAB_BASE_DIR:-${REPO_ROOT}/docker/gitlab}
GITLAB_CONFIG_DIR="${GITLAB_BASE_DIR}/config"
GITLAB_LOGS_DIR="${GITLAB_BASE_DIR}/logs"
GITLAB_DATA_DIR="${GITLAB_BASE_DIR}/data"

ensure_dirs() {
  mkdir -p "${POSTGRES_DATA_DIR}"
  mkdir -p "${GITLAB_CONFIG_DIR}" "${GITLAB_LOGS_DIR}" "${GITLAB_DATA_DIR}"
}

ensure_network() {
  if ! docker network inspect "${DOCKER_NETWORK}" >/dev/null 2>&1; then
    echo "[lab] Creating docker network ${DOCKER_NETWORK}..."
    docker network create "${DOCKER_NETWORK}" >/dev/null
  fi
}

start_postgres() {
  if docker ps -a --format '{{.Names}}' | grep -q '^gitlab-postgres$'; then
    echo "[postgres] Container exists. Starting..."
    docker start gitlab-postgres >/dev/null
    return
  fi
  echo "[postgres] Pulling ${POSTGRES_IMAGE}..."
  docker pull "${POSTGRES_IMAGE}" >/dev/null
  echo "[postgres] Launching container..."
  docker run -d \
    --name gitlab-postgres \
    --network "${DOCKER_NETWORK}" \
    -p "${POSTGRES_HOST_PORT}:5432" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -v "${POSTGRES_DATA_DIR}:/var/lib/postgresql/data" \
    "${POSTGRES_IMAGE}" >/dev/null
}

start_vault() {
  if docker ps -a --format '{{.Names}}' | grep -q '^vault-dev$'; then
    echo "[vault] Container exists. Starting..."
    docker start vault-dev >/dev/null
    return
  fi
  echo "[vault] Pulling ${VAULT_IMAGE}..."
  docker pull "${VAULT_IMAGE}" >/dev/null
  echo "[vault] Launching container..."
  docker run -d \
    --name vault-dev \
    --network "${DOCKER_NETWORK}" \
    -p "${VAULT_HOST_PORT}:8200" \
    -e VAULT_DEV_ROOT_TOKEN_ID="${VAULT_ROOT_TOKEN}" \
    -e VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200 \
    --cap-add IPC_LOCK \
    "${VAULT_IMAGE}" >/dev/null
}

start_gitlab() {
  if docker ps -a --format '{{.Names}}' | grep -q '^gitlab-ce$'; then
    echo "[gitlab] Container exists. Starting..."
    docker start gitlab-ce >/dev/null
    return
  fi
  echo "[gitlab] Pulling ${GITLAB_IMAGE}..."
  docker pull "${GITLAB_IMAGE}" >/dev/null
  echo "[gitlab] Launching container..."
  docker run -d \
    --name gitlab-ce \
    --hostname gitlab.lab.local \
    --network "${DOCKER_NETWORK}" \
    -p "${GITLAB_HTTP_PORT}:80" \
    -p "${GITLAB_HTTPS_PORT}:443" \
    -p "${GITLAB_SSH_PORT}:22" \
    -v "${GITLAB_CONFIG_DIR}:/etc/gitlab" \
    -v "${GITLAB_LOGS_DIR}:/var/log/gitlab" \
    -v "${GITLAB_DATA_DIR}:/var/opt/gitlab" \
    -e GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PASSWORD}" \
    -e GITLAB_OMNIBUS_CONFIG="external_url '${GITLAB_EXTERNAL_URL}';
gitlab_rails['db_adapter'] = 'postgresql';
gitlab_rails['db_encoding'] = 'utf8';
gitlab_rails['db_database'] = '${POSTGRES_DB}';
gitlab_rails['db_username'] = '${POSTGRES_USER}';
gitlab_rails['db_password'] = '${POSTGRES_PASSWORD}';
gitlab_rails['db_host'] = 'gitlab-postgres';
gitlab_rails['db_port'] = 5432;
postgresql['enable'] = false;
nginx['listen_port'] = 80;
nginx['listen_https'] = false;" \
    "${GITLAB_IMAGE}" >/dev/null
}

wait_for_gitlab() {
  echo "[gitlab] Waiting for GitLab to accept connections..."
  for _ in {1..60}; do
    if curl -sk --fail "http://localhost:${GITLAB_HTTP_PORT}/users/sign_in" >/dev/null 2>&1; then
      echo "[gitlab] GitLab is reachable."
      return 0
    fi
    sleep 10
  done
  echo "[gitlab] GitLab did not become ready in time." >&2
  exit 1
}

configure_gitlab_root() {
  wait_for_gitlab

  local token_value="${GITLAB_ROOT_TOKEN_VALUE:-$(openssl rand -hex 32)}"
  echo "[gitlab] Creating Personal Access Token '${GITLAB_ROOT_TOKEN_NAME}'..."
  docker exec gitlab-ce /bin/bash -lc "cat <<'RUBY' >/tmp/create_pat.rb
user = User.find_by_username('root')
existing = user.personal_access_tokens.find_by(name: ENV['PAT_NAME'])
existing&.destroy
token = user.personal_access_tokens.create!(name: ENV['PAT_NAME'], scopes: [:api, :read_api, :write_repository], expires_at: Time.zone.today + ENV['PAT_DAYS'].to_i)
token.set_token(ENV['PAT_TOKEN'])
token.save!
RUBY"
  docker exec \
    -e PAT_TOKEN="${token_value}" \
    -e PAT_NAME="${GITLAB_ROOT_TOKEN_NAME}" \
    -e PAT_DAYS="${GITLAB_ROOT_TOKEN_DAYS}" \
    gitlab-ce gitlab-rails runner /tmp/create_pat.rb
  docker exec gitlab-ce rm -f /tmp/create_pat.rb

  mkdir -p "$(dirname "${GITLAB_ROOT_TOKEN_FILE}")"
  printf '%s' "${token_value}" > "${GITLAB_ROOT_TOKEN_FILE}"
  echo "[gitlab] Root PAT stored in ${GITLAB_ROOT_TOKEN_FILE}"
  echo "[gitlab] Export with: export TF_VAR_gitlab_token=\$(cat ${GITLAB_ROOT_TOKEN_FILE})"
  echo "[gitlab] Terraform repo access:"
  echo "  export TF_VAR_argocd_platform_repo_username=root"
  echo "  export TF_VAR_argocd_platform_repo_password=\$(cat ${GITLAB_ROOT_TOKEN_FILE})"
}

echo "[lab] Ensuring directories..."
ensure_dirs
echo "[lab] Ensuring docker network..."
ensure_network

start_postgres
start_vault
start_gitlab
configure_gitlab_root

cat <<EOF
[lab] Services starting:
  - PostgreSQL : localhost:${POSTGRES_HOST_PORT}
  - Vault      : http://localhost:${VAULT_HOST_PORT} (token=${VAULT_ROOT_TOKEN})
  - GitLab CE  : http://localhost:${GITLAB_HTTP_PORT} (root pwd=${GITLAB_ROOT_PASSWORD})
PAT root stocké dans : ${GITLAB_ROOT_TOKEN_FILE}
Exportez-le avec  : export TF_VAR_gitlab_token=\$(cat ${GITLAB_ROOT_TOKEN_FILE})
Pour Terraform/ArgoCD :
  export TF_VAR_argocd_platform_repo_username=root
  export TF_VAR_argocd_platform_repo_password=\$(cat ${GITLAB_ROOT_TOKEN_FILE})
Premier démarrage GitLab : ~10 minutes. Surveillez les logs via 'docker logs -f gitlab-ce'.
EOF
