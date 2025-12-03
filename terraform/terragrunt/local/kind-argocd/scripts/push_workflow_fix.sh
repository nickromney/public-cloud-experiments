#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${ROOT_DIR}/.run"
GITEA_SSH_HOST_HOST="${GITEA_SSH_HOST_HOST:-127.0.0.1}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-30022}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
SSH_KEY="${RUN_DIR}/argocd-repo.id_ed25519"
echo "SSH_KEY: ${SSH_KEY}"
ls -l "${SSH_KEY}"
KNOWN_HOSTS="${RUN_DIR}/gitea_known_hosts"
SOURCE_WORKFLOW="${ROOT_DIR}/gitea-repos/azure-auth-sim/.gitea/workflows/azure-auth-sim.yaml"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

echo "Cloning azure-auth-sim..."
GIT_SSH_COMMAND="ssh -v -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=yes" \
  git clone "ssh://${GITEA_ADMIN_USER}@${GITEA_SSH_HOST_HOST}:${GITEA_SSH_PORT}/${GITEA_ADMIN_USER}/azure-auth-sim.git" "${WORK_DIR}/azure-auth-sim"

echo "Updating workflow file..."
cp "${SOURCE_WORKFLOW}" "${WORK_DIR}/azure-auth-sim/.gitea/workflows/azure-auth-sim.yaml"

cd "${WORK_DIR}/azure-auth-sim"
if [ -z "$(git status --porcelain)" ]; then
  echo "No changes to push."
  exit 0
fi

git config user.email "admin@gitea.local"
git config user.name "Gitea Admin"
git add .
git commit -m "fix: update workflow shell to bash"

echo "Pushing changes..."
GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=yes" \
  git push origin main

echo "Workflow updated and pushed."
