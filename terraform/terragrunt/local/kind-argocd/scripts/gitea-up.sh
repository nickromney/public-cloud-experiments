#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/external-gitea-compose.yaml"

if command -v podman-compose >/dev/null 2>&1; then
  COMPOSE_BIN="podman-compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_BIN="docker-compose"
elif command -v docker >/dev/null 2>&1; then
  COMPOSE_BIN="docker compose"
else
  echo "podman-compose or docker compose is required to start external Gitea." >&2
  exit 1
fi

echo "Starting external Gitea via ${COMPOSE_BIN}..."
${COMPOSE_BIN} -f "${COMPOSE_FILE}" up -d

echo "External Gitea listening on HTTP 3000, SSH 30022"
