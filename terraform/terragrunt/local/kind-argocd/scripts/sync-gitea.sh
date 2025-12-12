#!/usr/bin/env bash
set -euo pipefail

# Sync only the ArgoCD-relevant paths into the Gitea repos.
# - By default pushes the policies repo (apps/ + cluster-policies/).
# - Optionally pushes the azure-auth-sim repo (subnet-calculator sources + templates).
# - Requires a reachable Gitea remote (defaults to the local in-cluster instance).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

BRANCH="${GITEA_BRANCH:-main}"
DEFAULT_POLICIES_REMOTE="$(git -C "${REPO_ROOT}" config --get remote.gitea.url || true)"
DEFAULT_POLICIES_REMOTE="${DEFAULT_POLICIES_REMOTE:-http://127.0.0.1:30090/gitea-admin/policies.git}"
DEFAULT_AZURE_REMOTE="${GITEA_AZURE_REMOTE:-http://127.0.0.1:30090/gitea-admin/azure-auth-sim.git}"
GIT_USER="${GITEA_USER:-argocd}"
GIT_EMAIL="${GITEA_EMAIL:-argocd@gitea.local}"
DRY_RUN=0
RUN_POLICIES=0
RUN_AZURE=0

BASE_APPS_REL="terraform/terragrunt/local/kind-argocd/apps"
GENERATED_APPS_REL="terraform/terragrunt/local/kind-argocd/.run/generated-apps"
CLUSTER_POLICIES_REL="terraform/terragrunt/local/kind-argocd/cluster-policies"

AZURE_SOURCES=(
  "terraform/terragrunt/local/kind-argocd/gitea-repos/azure-auth-sim:."
  "subnet-calculator/api-apim-simulator:api-apim-simulator"
  "subnet-calculator/api-fastapi-azure-function:api-fastapi-azure-function"
  "subnet-calculator/frontend-react:frontend-react"
  "subnet-calculator/shared-frontend:shared-frontend"
)

RSYNC_EXCLUDES=(
  "--exclude=.terraform" "--exclude=.terragrunt-cache" "--exclude=.run"
  "--exclude=.git" "--exclude=.gitignore" "--exclude=.gitmodules"
  "--exclude=.venv" "--exclude=venv" "--exclude=node_modules"
  "--exclude=dist" "--exclude=build" "--exclude=.cache" "--exclude=.pytest_cache"
  "--exclude=__pycache__" "--exclude=.DS_Store" "--exclude=*.log"
  "--exclude=*.tfstate" "--exclude=*.tfstate.backup"
)

usage() {
  cat <<'EOF'
Usage: sync-gitea.sh [--policies] [--azure-auth-sim] [--all] [--dry-run]

Options:
  --policies        Sync apps/ and cluster-policies/ into the policies repo (default if nothing chosen)
  --azure-auth-sim  Sync azure-auth-sim repo (gitea-repos/azure-auth-sim + subnet-calculator sources)
  --all             Sync both repos
  --dry-run         Show what would change without pushing

Environment:
  GITEA_BRANCH          Branch to push (default: main)
  GITEA_USER/GITEA_PASSWORD
                        Used for HTTP auth if set (falls back to existing Git credentials/helpers)
  GITEA_EMAIL           Commit email (default: argocd@gitea.local)
  GITEA_POLICIES_REMOTE Remote URL for policies repo (default: gitea remote or localhost policies)
  GITEA_AZURE_REMOTE    Remote URL for azure-auth-sim repo (default: localhost azure-auth-sim)
  GITEA_SYNC_MESSAGE    Override commit message
  GITEA_USE_SIDECAR     Keep azure-auth-sim sidecar overlay (default: keep; set 0 to strip)
  GITEA_ENABLE_AZURE_AUTH_SIM
                        Set 0 to drop azure-auth-sim/entraid/apim from the policies sync
  GITEA_ENABLE_ACTIONS_RUNNER
                        Set 0 to drop gitea-actions-runner from the policies sync
EOF
}

log() { printf '==> %s\n' "$*"; }

die() { echo "Error: $*" >&2; exit 1; }

parse_args() {
  if [[ $# -eq 0 ]]; then
    RUN_POLICIES=1
    return
  fi
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --policies) RUN_POLICIES=1 ;;
      --azure-auth-sim) RUN_AZURE=1 ;;
      --all) RUN_POLICIES=1; RUN_AZURE=1 ;;
      --dry-run) DRY_RUN=1 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown flag: $1" ;;
    esac
    shift
  done
  if [[ "${RUN_POLICIES}" -eq 0 && "${RUN_AZURE}" -eq 0 ]]; then
    RUN_POLICIES=1
  fi
}

setup_auth() {
  if [[ -n "${GITEA_USER:-}" && -n "${GITEA_PASSWORD:-}" ]]; then
    local askpass="${TMP_ROOT}/git-askpass.sh"
    cat > "${askpass}" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  *Username*) echo "${GITEA_USER}" ;;
  *Password*) echo "${GITEA_PASSWORD}" ;;
esac
EOF
    chmod +x "${askpass}"
    export GIT_ASKPASS="${askpass}"
    export GIT_TERMINAL_PROMPT=0
  fi
}

ensure_branch() {
  local dest="$1"
  if git -C "${dest}" rev-parse --verify "origin/${BRANCH}" >/dev/null 2>&1; then
    git -C "${dest}" checkout -q "${BRANCH}"
    git -C "${dest}" reset -q --hard "origin/${BRANCH}"
  else
    git -C "${dest}" checkout -q -B "${BRANCH}"
  fi
}

clone_repo() {
  local url="$1" dest="$2"
  GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT:-0} git clone --depth 1 --branch "${BRANCH}" "${url}" "${dest}" 2>/dev/null || {
    GIT_TERMINAL_PROMPT=${GIT_TERMINAL_PROMPT:-0} git clone --depth 1 "${url}" "${dest}" || die "Clone failed for ${url}. Set GITEA_USER/GITEA_PASSWORD or configure credentials."
  }
  ensure_branch "${dest}"
}

rsync_pair() {
  local src_rel="$1" dest_rel="$2" dest_root="$3"
  local src="${REPO_ROOT}/${src_rel}"
  local dest="${dest_root}/${dest_rel}"

  if [[ ! -e "${src}" ]]; then
    log "Skipping missing path: ${src_rel}"
    return
  fi

  mkdir -p "${dest}"
  if [[ -d "${src}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${src}/" "${dest}/"
  else
    rsync -a "${RSYNC_EXCLUDES[@]}" "${src}" "${dest}/"
  fi
}

build_policies_stage() {
  local stage="${TMP_ROOT}/policies-stage"
  local base_apps="${REPO_ROOT}/${BASE_APPS_REL}"
  local generated_apps="${REPO_ROOT}/${GENERATED_APPS_REL}"
  local cluster_policies="${REPO_ROOT}/${CLUSTER_POLICIES_REL}"

  mkdir -p "${stage}/apps"
  if [[ -d "${base_apps}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${base_apps}/" "${stage}/apps/"
  fi

  # Place top-level Application manifests under apps/_applications for app-of-apps
  mkdir -p "${stage}/apps/_applications"
  if compgen -G "${stage}/apps/*.yaml" >/dev/null; then
    for appfile in "${stage}/apps/"*.yaml; do
      mv "${appfile}" "${stage}/apps/_applications/" || true
    done
  fi

  # Bring in templated outputs (with URLs baked in) if present
  if [[ -d "${generated_apps}" ]] && [[ -n "$(ls -A "${generated_apps}" 2>/dev/null || true)" ]]; then
    mkdir -p "${stage}/apps/_applications"
    shopt -s nullglob
    for appfile in "${generated_apps}"/*.yaml; do
      rsync -a "${RSYNC_EXCLUDES[@]}" "${appfile}" "${stage}/apps/_applications/"
    done
    for appdir in "${generated_apps}"/*/; do
      # Keep any hand-authored scaffolding (e.g., kustomization.yaml) from the base
      # apps directory while layering in the generated manifests.
      rsync -a "${RSYNC_EXCLUDES[@]}" "${appdir}" "${stage}/apps/$(basename "${appdir}")/"
    done
    shopt -u nullglob
  fi

  # Optional trims to match typical Terraform seeding
  if [[ "${GITEA_USE_SIDECAR:-1}" != "1" ]]; then
    rm -rf "${stage}/apps/azure-auth-sim/overlays"
  fi
  if [[ "${GITEA_ENABLE_AZURE_AUTH_SIM:-1}" != "1" ]]; then
    rm -rf "${stage}/apps/azure-auth-sim" "${stage}/apps/azure-auth-sim.yaml"
    rm -rf "${stage}/apps/azure-entraid-sim" "${stage}/apps/azure-entraid-sim.yaml"
    rm -rf "${stage}/apps/azure-apim-sim" "${stage}/apps/azure-apim-sim.yaml"
  fi
  if [[ "${GITEA_ENABLE_ACTIONS_RUNNER:-1}" != "1" ]]; then
    rm -rf "${stage}/apps/gitea-actions-runner" "${stage}/apps/gitea-actions-runner.yaml"
  fi

  if [[ -d "${cluster_policies}" ]]; then
    rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${cluster_policies}/" "${stage}/cluster-policies/"
  fi

  echo "${stage}"
}

collect_sources() {
  local result=()
  for entry in "$@"; do
    result+=("${entry%%:*}")
  done
  printf '%s\n' "${result[@]}"
}

has_workspace_changes() {
  local target="$1"; shift
  local -a paths=("$@")
  local status
  status="$(cd "${REPO_ROOT}" && git status --porcelain -- "${paths[@]}" || true)"
  if [[ -z "${status// }" ]]; then
    log "No workspace changes for ${target}; skipping."
    return 1
  fi
  return 0
}

sync_policies() {
  local remote="${GITEA_POLICIES_REMOTE:-${DEFAULT_POLICIES_REMOTE}}"
  local stage
  stage="$(build_policies_stage)"
  local tmp_dest="${TMP_ROOT}/policies"

  log "Cloning ${remote} -> ${tmp_dest}"
  clone_repo "${remote}" "${tmp_dest}"
  git -C "${tmp_dest}" config core.fileMode false >/dev/null

  rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${stage}/" "${tmp_dest}/"

  if ! git -C "${tmp_dest}" status --short --untracked-files=all | grep -q .; then
    log "No diff after sync for policies; nothing to push."
    return 0
  fi

  git -C "${tmp_dest}" config user.name "${GIT_USER}"
  git -C "${tmp_dest}" config user.email "${GIT_EMAIL}"
  git -C "${tmp_dest}" add .

  local message="${GITEA_SYNC_MESSAGE:-sync(policies): $(date -Iseconds)}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] Would commit with message: ${message}"
    git -C "${tmp_dest}" status --short
    return 0
  fi

  git -C "${tmp_dest}" commit -m "${message}" >/dev/null
  log "Pushing policies to ${remote} (${BRANCH})"
  git -C "${tmp_dest}" push origin "${BRANCH}"
}

sync_target() {
  local target="$1" remote="$2"
  shift 2
  local -a source_pairs=("$@")
  local tmp_dest="${TMP_ROOT}/${target}"

  local sources=()
  while IFS= read -r line; do
    [[ -n "${line}" ]] && sources+=("${line}")
  done < <(collect_sources "${source_pairs[@]}")
  has_workspace_changes "${target}" "${sources[@]}" || return 0

  log "Cloning ${remote} -> ${tmp_dest}"
  clone_repo "${remote}" "${tmp_dest}"
  git -C "${tmp_dest}" config core.fileMode false >/dev/null

  for pair in "${source_pairs[@]}"; do
    rsync_pair "${pair%%:*}" "${pair##*:}" "${tmp_dest}"
  done

  if ! git -C "${tmp_dest}" status --short --untracked-files=all | grep -q .; then
    log "No diff after sync for ${target}; nothing to push."
    return 0
  fi

  git -C "${tmp_dest}" config user.name "${GIT_USER}"
  git -C "${tmp_dest}" config user.email "${GIT_EMAIL}"

  git -C "${tmp_dest}" add .
  local message="${GITEA_SYNC_MESSAGE:-sync(${target}): $(date -Iseconds)}"
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    log "[dry-run] Would commit with message: ${message}"
    git -C "${tmp_dest}" status --short
    return 0
  fi

  git -C "${tmp_dest}" commit -m "${message}" >/dev/null
  log "Pushing ${target} to ${remote} (${BRANCH})"
  git -C "${tmp_dest}" push origin "${BRANCH}"
}

main() {
  parse_args "$@"
  setup_auth

  if [[ "${RUN_POLICIES}" -eq 1 ]]; then
    sync_policies
  fi

  if [[ "${RUN_AZURE}" -eq 1 ]]; then
    sync_target "azure-auth-sim" "${GITEA_AZURE_REMOTE:-${DEFAULT_AZURE_REMOTE}}" "${AZURE_SOURCES[@]}"
  fi
}

main "$@"
