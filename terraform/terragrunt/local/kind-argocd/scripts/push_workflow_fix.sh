#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITEA_HTTP_HOST_HOST="${GITEA_HTTP_HOST_HOST:-https://localhost:3000}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
GITEA_ADMIN_PASS="${GITEA_ADMIN_PASS:-ChangeMe123!}"
SOURCE_WORKFLOW="${ROOT_DIR}/gitea-repos/azure-auth-sim/.gitea/workflows/azure-auth-sim.yaml"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

echo "Cloning azure-auth-sim (HTTPS)..."
HOST_BASE="${GITEA_HTTP_HOST_HOST#https://}"
HOST_BASE="${HOST_BASE#http://}"
CLONE_URL="https://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}@${HOST_BASE}/${GITEA_ADMIN_USER}/azure-auth-sim.git"
if [[ "${GITEA_HTTP_HOST_HOST}" == http://* ]]; then
  CLONE_URL="http://${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}@${HOST_BASE}/${GITEA_ADMIN_USER}/azure-auth-sim.git"
fi
git -c http.sslCAInfo="${ROOT_DIR}/certs/ca.crt" clone "${CLONE_URL}" "${WORK_DIR}/azure-auth-sim"

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
git commit -m "fix: use /bin/sh for actions runner"

echo "Pushing changes..."
git -c http.sslCAInfo="${ROOT_DIR}/certs/ca.crt" push origin main

echo "Workflow updated and pushed."
