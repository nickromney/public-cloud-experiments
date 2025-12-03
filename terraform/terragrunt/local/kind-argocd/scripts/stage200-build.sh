#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${ROOT_DIR}/.run"
RUNNER_DATA_DIR="${RUN_DIR}/act-runner"
DIND_DATA_DIR="${RUN_DIR}/act-runner/docker"
GITEA_HTTP_HOST="${GITEA_HTTP_HOST:-https://localhost:3000}"
GITEA_HTTP_CONTAINER="${GITEA_HTTP_CONTAINER:-https://host.containers.internal:3000}"
GITEA_SSH_HOST_HOST="${GITEA_SSH_HOST_HOST:-127.0.0.1}"
GITEA_SSH_HOST="${GITEA_SSH_HOST:-host.containers.internal}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-30022}"
GITEA_SSH_USER="${GITEA_SSH_USER:-gitea-admin}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
GITEA_ADMIN_PASS="${GITEA_ADMIN_PASS:-ChangeMe123!}"
REGISTRY="${REGISTRY:-localhost:3000}"
SSH_KEY="${RUN_DIR}/argocd-repo.id_ed25519"
KNOWN_HOSTS="${RUN_DIR}/gitea_known_hosts"
RUNNER_IMAGE="${RUNNER_IMAGE:-ghcr.io/catthehacker/ubuntu:act-22.04}"
REGISTRY_HOST_INTERNAL="${REGISTRY_HOST_INTERNAL:-host.containers.internal:3000}"
HOST_DOCKER_SOCK="${HOST_DOCKER_SOCK:-/var/run/docker.sock}"
CONTAINER_DOCKER_SOCK="/run/podman/podman.sock"
ACT_RUNNER_VERSION="${ACT_RUNNER_VERSION:-0.2.13}"
ACT_RUNNER_BIN="${RUNNER_DATA_DIR}/act_runner"

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

ensure_runner_token() {
  for i in {1..10}; do
    # Use CA cert for TLS verification if available, otherwise fall back to insecure for local dev
    local curl_opts="-s"
    if [ -f "${ROOT_DIR}/certs/ca.crt" ]; then
      curl_opts="${curl_opts} --cacert ${ROOT_DIR}/certs/ca.crt"
    else
      curl_opts="${curl_opts} -k"
    fi
    token=$(curl ${curl_opts} -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" -X POST \
      "${GITEA_HTTP_HOST}/api/v1/admin/actions/runners/registration-token" | jq -r '.token // empty')
    if [ -n "${token}" ]; then
      echo "${token}"
      return 0
    fi
    sleep 3
  done
  echo "Failed to obtain runner registration token" >&2
  exit 1
}

resolve_host_docker_sock() {
  if [ -n "${HOST_DOCKER_SOCK}" ]; then
    echo "${HOST_DOCKER_SOCK}"
    return
  fi
  echo "/var/run/docker.sock"
}

write_runner_config() {
  local docker_sock="$1"
  local docker_sock_real="$2"
  mkdir -p "${RUNNER_DATA_DIR}"
  cat > "${RUNNER_DATA_DIR}/config.yaml" <<EOF
log:
  level: debug
runner:
  file: .runner
  capacity: 1
  executor: host
  envs:
    GIT_SSL_CAINFO: "${ROOT_DIR}/certs/ca.crt"
    CURL_CA_BUNDLE: "${ROOT_DIR}/certs/ca.crt"
    SSL_CERT_FILE: "${ROOT_DIR}/certs/ca.crt"
    DOCKER_HOST: "unix://${docker_sock_real}"
  timeout: 3h
  shutdown_timeout: 0s
  insecure: false
  fetch_timeout: 5s
  fetch_interval: 2s
  labels:
    - "self-hosted"
    - "local"
    - "darwin"
cache:
  enabled: true
EOF
}

download_runner() {
  if [ -x "${ACT_RUNNER_BIN}" ]; then
    return
  fi
  mkdir -p "${RUNNER_DATA_DIR}"
  echo "Downloading act_runner ${ACT_RUNNER_VERSION}..."
  curl -L -o "${ACT_RUNNER_BIN}" "https://dl.gitea.com/act_runner/${ACT_RUNNER_VERSION}/act_runner-${ACT_RUNNER_VERSION}-darwin-arm64"
  chmod +x "${ACT_RUNNER_BIN}"
  if command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "${ACT_RUNNER_BIN}" 2>/dev/null || true
    xattr -d com.apple.provenance "${ACT_RUNNER_BIN}" 2>/dev/null || true
  fi
}

stop_host_runner() {
  if [ -f "${RUNNER_DATA_DIR}/runner.pid" ]; then
    pid=$(cat "${RUNNER_DATA_DIR}/runner.pid" 2>/dev/null || true)
    if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}" 2>/dev/null || true
      sleep 1
    fi
    rm -f "${RUNNER_DATA_DIR}/runner.pid"
  fi
}

start_host_runner() {
  local token="$1"
  local docker_sock="$2"
  local docker_sock_real="$3"
  stop_host_runner
  write_runner_config "${docker_sock}" "${docker_sock_real}"
  download_runner
  # Ensure existing runner also has quarantine removed if strictly necessary
  if [ -x "${ACT_RUNNER_BIN}" ] && command -v xattr >/dev/null 2>&1; then
    xattr -d com.apple.quarantine "${ACT_RUNNER_BIN}" 2>/dev/null || true
    xattr -d com.apple.provenance "${ACT_RUNNER_BIN}" 2>/dev/null || true
  fi
  SSL_CERT_FILE="${ROOT_DIR}/certs/ca.crt" \
    DOCKER_HOST="unix://${docker_sock_real}" \
    "${ACT_RUNNER_BIN}" register \
      --config "${RUNNER_DATA_DIR}/config.yaml" \
      --instance "${GITEA_HTTP_HOST}" \
      --token "${token}" \
      --name "local-host-runner" \
      --no-interactive >/dev/null
  SSL_CERT_FILE="${ROOT_DIR}/certs/ca.crt" \
    DOCKER_HOST="unix://${docker_sock_real}" \
    nohup "${ACT_RUNNER_BIN}" daemon --config "${RUNNER_DATA_DIR}/config.yaml" \
      > "${RUNNER_DATA_DIR}/runner.log" 2>&1 &
  echo $! > "${RUNNER_DATA_DIR}/runner.pid"
}

trigger_workflow() {
  local repo="${1}"
  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=yes" \
    git clone "ssh://${GITEA_SSH_USER}@${GITEA_SSH_HOST_HOST}:${GITEA_SSH_PORT}/${GITEA_ADMIN_USER}/${repo}.git" "${WORK_DIR}/${repo}"
  pushd "${WORK_DIR}/${repo}" >/dev/null
  git config user.email "argocd@gitea.local"
  git config user.name "argocd"
  git config commit.gpgsign false
  # Remove explicit shell definitions (more precise pattern to match YAML shell: directives)
  if [ "$(uname)" = "Darwin" ]; then
      sed -i '' '/^[[:space:]]*shell:[[:space:]]*\(sh\|bash\)[[:space:]]*$/d' .gitea/workflows/azure-auth-sim.yaml || true
  else
      sed -i '/^[[:space:]]*shell:[[:space:]]*\(sh\|bash\)[[:space:]]*$/d' .gitea/workflows/azure-auth-sim.yaml || true
  fi
  git add .gitea/workflows/azure-auth-sim.yaml
  date > .gitea/workflows/.ci-trigger
  git add .gitea/workflows/.ci-trigger
  git commit -q -m "ci: trigger build"
  GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=yes" \
    git push origin main
  popd >/dev/null
}

ensure_repo_secrets() {
  ssh_key_b64=$(base64 -i "${SSH_KEY}" | tr -d '\n')
  known_hosts_b64=$(base64 -i "${KNOWN_HOSTS}" | tr -d '\n')
  registry_ca_b64=$(base64 -i "${ROOT_DIR}/certs/ca.crt" | tr -d '\n')
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${GITEA_ADMIN_USER}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/REGISTRY_USERNAME" >/dev/null
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${GITEA_ADMIN_PASS}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/REGISTRY_PASSWORD" >/dev/null
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${REGISTRY_HOST_INTERNAL}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/REGISTRY_HOST" >/dev/null
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${ssh_key_b64}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/CHECKOUT_SSH_KEY_B64" >/dev/null
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${known_hosts_b64}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/CHECKOUT_KNOWN_HOSTS_B64" >/dev/null
  curl -sk -o /dev/null -w "%{http_code}" -X PUT \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"data\":\"${registry_ca_b64}\"}" \
    "${GITEA_HTTP_HOST}/api/v1/repos/${GITEA_ADMIN_USER}/azure-auth-sim/actions/secrets/REGISTRY_CA_B64" >/dev/null
}

main() {
  if ! curl -sfk -o /dev/null "${GITEA_HTTP_HOST}/api/healthz"; then
    echo "Gitea not reachable at ${GITEA_HTTP_HOST}" >&2
    exit 1
  fi
  if [ ! -f "${SSH_KEY}" ]; then
    echo "SSH key ${SSH_KEY} not found; run stage 100 first." >&2
    exit 1
  fi
  local docker_sock
  docker_sock=$(resolve_host_docker_sock)
  local docker_sock_real
  docker_sock_real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${docker_sock}")
  if [ ! -S "${docker_sock}" ]; then
    # On macOS the path is inside the Podman VM; tolerate missing socket on the host filesystem.
    if command -v podman >/dev/null 2>&1 && podman machine ssh -- test -S "${docker_sock}"; then
      :
    else
      echo "Docker/Podman socket not found at ${docker_sock}. Set HOST_DOCKER_SOCK to your socket path." >&2
      exit 1
    fi
  fi
  if command -v podman >/dev/null 2>&1 && [ "${docker_sock}" = "/run/podman/podman.sock" ]; then
    podman machine ssh -- sudo chmod 666 "${docker_sock}" >/dev/null 2>&1 || true
  fi
  echo "Using host Docker socket at ${docker_sock_real} (no DinD)."
  ensure_repo_secrets
  token=$(ensure_runner_token)
  start_host_runner "${token}" "${docker_sock}" "${docker_sock_real}"
  trigger_workflow "azure-auth-sim"
  echo "Stage 200 triggered workflow; monitor Gitea Actions for build/push to ${REGISTRY}."
}

main "$@"
