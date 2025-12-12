#!/usr/bin/env bash
set -euo pipefail

# Lightweight stub test for sync-gitea.sh
# - Spins up two local bare repos (policies, azure-auth-sim)
# - Clones this repo into a temp workspace
# - Runs sync-gitea.sh --all pointing at the bare repos
# - Asserts expected files land in each bare repo

ORIG_ROOT="$(git rev-parse --show-toplevel)"
export GIT_CONFIG_GLOBAL=/dev/null
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

BARE_POLICIES="${WORKDIR}/policies.git"
BARE_AZURE="${WORKDIR}/azure-auth-sim.git"

log() { printf '==> %s\n' "$*"; }

seed_bare() {
  local bare="$1"
  local name="$2"
  local tmp
  tmp="$(mktemp -d)"
  git init --quiet --bare "${bare}"
  git -C "${tmp}" init --quiet
  echo "seed ${name}" > "${tmp}/README.md"
  git -C "${tmp}" add README.md
  git -C "${tmp}" \
    -c user.email=test@example.com \
    -c user.name=test \
    -c commit.gpgsign=false \
    -c gpg.format=ssh \
    commit -q -m "seed ${name}"
  git -C "${tmp}" branch -M main
  git -C "${tmp}" push -q "${bare}" main
  rm -rf "${tmp}"
}

clone_workspace() {
  local dest="$1"
  rsync -a --delete --exclude='.git' --exclude='.cache' --exclude='.runner' "${ORIG_ROOT}/" "${dest}/"
  git -C "${dest}" init --quiet
  git -C "${dest}" config user.email test@example.com
  git -C "${dest}" config user.name test
}

assert_in_repo() {
  local bare="$1"
  local path="$2"
  git -C "${bare}" ls-tree -r --name-only main | grep -qx "${path}" || {
    echo "Expected path '${path}' in ${bare}, but not found" >&2
    exit 1
  }
}

main() {
  log "Seeding bare repos"
  seed_bare "${BARE_POLICIES}" "policies"
  seed_bare "${BARE_AZURE}" "azure-auth-sim"

  local ws="${WORKDIR}/workspace"
  clone_workspace "${ws}"

  log "Running sync-gitea.sh against bare repos"
  (
    cd "${ws}"
    GITEA_POLICIES_REMOTE="${BARE_POLICIES}" \
    GITEA_AZURE_REMOTE="${BARE_AZURE}" \
    GITEA_BRANCH=main \
    GITEA_SYNC_MESSAGE="test sync" \
    terraform/terragrunt/local/kind-argocd/scripts/sync-gitea.sh --all
  )

  log "Asserting policies content was pushed"
  assert_in_repo "${BARE_POLICIES}" "cluster-policies/README.md"
  assert_in_repo "${BARE_POLICIES}" "apps/_applications/kyverno.yaml"

  log "Asserting azure-auth-sim content was pushed"
  assert_in_repo "${BARE_AZURE}" "shared-frontend/package.json"
  assert_in_repo "${BARE_AZURE}" "api-apim-simulator/pyproject.toml"

  log "All assertions passed"
}

main "$@"
