#!/usr/bin/env bash
# Publish Helm app repositories + ArgoCD GitOps repo to GitLab.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APPS_DIR="${APPS_DIR:-${REPO_ROOT}/apps}"
GITOPS_DIR="${GITOPS_DIR:-${REPO_ROOT}/gitops}"
GITOPS_PLATFORM_DIR="${GITOPS_PLATFORM_DIR:-${GITOPS_DIR}/platform}"
GITOPS_REPO_NAME="${GITOPS_REPO_NAME:-platform-gitops}"
GITLAB_URL="${GITLAB_URL:-http://gitlab.lab.local:8081}"
GITLAB_TOKEN="${GITLAB_TOKEN:-${TF_VAR_gitlab_token:-}}"
GITLAB_NAMESPACE_ID="${GITLAB_NAMESPACE_ID:-}"
GITLAB_NAMESPACE_PATH="${GITLAB_NAMESPACE_PATH:-root}"
GIT_USER_NAME="${GIT_USER_NAME:-Lab Bot}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-lab-bot@example.com}"
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: publish_git_repos.sh [--dry-run]

Publie chaque dossier d'app (infra/apps/<name>) vers GitLab sous la forme
<name>-<suffixe> (suffixe=helm par defaut) ainsi que le depot GitOps platform.

Variables utiles :
  GITLAB_URL            URL de l'instance GitLab (http://gitlab.lab.local:8081)
  GITLAB_TOKEN          PAT avec droits api/write_repository
  GITLAB_NAMESPACE_ID   (option) namespace_id cible pour la creation des projets
  APP_REPO_SUFFIX       suffixe du nom de repo pour les apps (par défaut: helm, laisser vide pour désactiver)
  GITOPS_REPO_NAME      nom du depot GitOps (platform-gitops)
EOF
}

log() { echo "[publish] $*"; }

die() { echo "[publish] ERROR: $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Commande '$1' introuvable"; }

url_with_token() {
  local base="$1"
  if [[ -z "${GITLAB_TOKEN}" ]]; then
    echo "$base"
    return
  fi
  case "$base" in
    https://*) echo "https://oauth2:${GITLAB_TOKEN}@${base#https://}" ;;
    http://*) echo "http://oauth2:${GITLAB_TOKEN}@${base#http://}" ;;
    *) echo "$base" ;;
  esac
}

api() {
  [[ -n "${GITLAB_TOKEN}" ]] || die "GITLAB_TOKEN requis pour utiliser l'API GitLab"
  local method="$1" endpoint="$2" data="$3"
  local url="${GITLAB_URL%/}/api/v4${endpoint}"
  if [[ -n "$data" ]]; then
    curl -sf -X "$method" -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
      -H 'Content-Type: application/json' -d "$data" "$url"
  else
    curl -sf -X "$method" -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" "$url"
  fi
}

ensure_project() {
  local full_path="$1"
  local encoded
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "${full_path}")
  if api GET "/projects/${encoded}" "" >/dev/null 2>&1; then
    log "Projet ${full_path} deja present"
    return
  fi
  log "Creation du projet ${full_path}"
  local payload="{\"name\":\"${full_path##*/}\",\"path\":\"${full_path##*/}\""
  if [[ -n "${GITLAB_NAMESPACE_ID}" ]]; then
    payload+=" ,\"namespace_id\":${GITLAB_NAMESPACE_ID}"
  fi
  payload+="}"
  api POST /projects "$payload" >/dev/null
}

stage_tree() {
  local src="$1" dest="$2"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src/." "$dest/"
  while IFS= read -r -d '' chart; do
    log "helm dependency update $(dirname "$chart")"
    helm dependency update "$(dirname "$chart")" >/dev/null
  done < <(find "$dest" -name Chart.yaml -print0)
}

push_repo() {
  local src="$1" name="$2"
  local remote="${GITLAB_URL%/}/${GITLAB_NAMESPACE_PATH}/${name}.git"
  if [[ "$DRY_RUN" == true ]]; then
    log "[dry-run] Preparations pour ${name} (source ${src})"
    return
  fi
  ensure_project "${GITLAB_NAMESPACE_PATH}/${name}"
  local tmpdi
  tmpdir="$(mktemp -d)"
  stage_tree "$src" "$tmpdir"
  (cd "$tmpdir" && git init >/dev/null && \
    git config user.name "${GIT_USER_NAME}" && \
    git config user.email "${GIT_USER_EMAIL}" && \
    git add . && git commit -m "Initial commit" >/dev/null && \
    git branch -M main)
  local push_url
  push_url=$(url_with_token "$remote")
  (cd "$tmpdir" && git remote add origin "$push_url" && git push -f origin main >/dev/null || \
    { log "Push refused (protected branch?). Try modifying GitLab branch protections."; rm -rf "$tmpdir"; exit 1; })
  rm -rf "$tmpdir"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=true
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Option inconnue: $1"
        ;;
    esac
    shift || true
  done
}

main() {
  parse_args "$@"
  require_cmd git
  require_cmd helm
  require_cmd python3
  if [[ "$DRY_RUN" == false && -z "${GITLAB_TOKEN}" ]]; then
    die "GITLAB_TOKEN requis (ou lancer en --dry-run)"
  fi
  for app_dir in "$APPS_DIR"/*; do
    [[ -d "$app_dir" ]] || continue
    local base repo_name suffix
    base="$(basename "$app_dir")"
    suffix="${APP_REPO_SUFFIX:-helm}"
    if [[ -n "${suffix}" ]]; then
      repo_name="${base}-${suffix}"
    else
      repo_name="${base}"
    fi
    log "Publication app ${base} => ${repo_name}"
    push_repo "$app_dir" "${repo_name}"
  done
  if [[ -d "$GITOPS_PLATFORM_DIR" ]]; then
    log "Publication GitOps => ${GITOPS_REPO_NAME}"
    push_repo "$GITOPS_PLATFORM_DIR" "${GITOPS_REPO_NAME}"
  else
    log "Ignore GitOps dir (absent)"
  fi
  log "Done. Pensez a enregistrer les depots dans Argo CD."
}

main "$@"
