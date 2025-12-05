#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${ROOT_DIR}/external-gitea-compose.yaml"
RUN_DIR="${ROOT_DIR}/.run"
POLICIES_DIR="${ROOT_DIR}/policies"
APPS_DIR="${ROOT_DIR}/apps"
AZ_REPO_DIR="${ROOT_DIR}/gitea-repos/azure-auth-sim"
SUBNET_ROOT="$(cd "${ROOT_DIR}/../../../../subnet-calculator" && pwd)"
GITEA_HTTP="${GITEA_HTTP:-https://host.docker.internal:3000}"
GITEA_SSH_HOST="${GITEA_SSH_HOST:-127.0.0.1}"
GITEA_SSH_PORT="${GITEA_SSH_PORT:-30022}"
GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea-admin}"
GITEA_ADMIN_PASS="${GITEA_ADMIN_PASS:-ChangeMe123!}"
GITEA_ADMIN_EMAIL="${GITEA_ADMIN_EMAIL:-admin@gitea.local}"
GITEA_CERT_HOSTS="${GITEA_CERT_HOSTS:-localhost,host.docker.internal,host.containers.internal,127.0.0.1}"
USE_HOMEBREW_GITEA="${USE_HOMEBREW_GITEA:-auto}"
SSH_KEY="${RUN_DIR}/argocd-repo.id_ed25519"
KNOWN_HOSTS="${RUN_DIR}/gitea_known_hosts"
HOMEBREW_GITEA_WORK="${HOMEBREW_GITEA_WORK:-/opt/homebrew/var/gitea}"
HOMEBREW_GITEA_CUSTOM="${HOMEBREW_GITEA_CUSTOM:-${HOMEBREW_GITEA_WORK}/custom}"
HOMEBREW_GITEA_CONFIG="${HOMEBREW_GITEA_CONFIG:-${HOMEBREW_GITEA_CUSTOM}/conf/app.ini}"
HOMEBREW_GITEA_CERT="${HOMEBREW_GITEA_CERT:-${HOMEBREW_GITEA_CUSTOM}/https/gitea.crt}"
HOMEBREW_GITEA_KEY="${HOMEBREW_GITEA_KEY:-${HOMEBREW_GITEA_CUSTOM}/https/gitea.key}"
HOMEBREW_GITEA_RUN_USER="${HOMEBREW_GITEA_RUN_USER:-$(python3 - <<'PY'
import os
from pathlib import Path

path = os.environ.get("HOMEBREW_GITEA_CONFIG")
fallback = os.environ.get("USER", "git")
if not path:
    print(fallback)
    raise SystemExit
cfg_path = Path(path)
if not cfg_path.exists():
    print(fallback)
    raise SystemExit
run_user = fallback
for line in cfg_path.read_text().splitlines():
    if line.strip().startswith("RUN_USER"):
        parts = line.split("=", 1)
        if len(parts) == 2 and parts[1].strip():
            run_user = parts[1].strip()
        break
print(run_user)
PY
)}"
GITEA_SSH_USER="${GITEA_SSH_USER:-${GITEA_ADMIN_USER}}"
GITEA_RUNTIME="compose"

mkdir -p "${RUN_DIR}"

start_compose() {
  local compose_bin
  if command -v podman-compose >/dev/null 2>&1; then
    compose_bin="podman-compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    compose_bin="docker-compose"
  elif command -v docker >/dev/null 2>&1; then
    compose_bin="docker compose"
  else
    echo "podman-compose or docker compose is required." >&2
    exit 1
  fi
  echo "Starting external Gitea..."
  (cd "${ROOT_DIR}" && ${compose_bin} -f "${COMPOSE_FILE}" up -d)
}

homebrew_gitea_available() {
  if [ "${USE_HOMEBREW_GITEA}" = "false" ]; then
    return 1
  fi
  if command -v gitea >/dev/null 2>&1 && [ -f "${HOMEBREW_GITEA_CONFIG}" ]; then
    return 0
  fi
  return 1
}

homebrew_gitea_running() {
  command -v brew >/dev/null 2>&1 && brew services list 2>/dev/null | grep -Eq "^gitea\\s+started"
}

configure_homebrew_gitea_https() {
  local root_url="${GITEA_HTTP%/}/"
  local need_restart=0

  mkdir -p "$(dirname "${HOMEBREW_GITEA_CERT}")"
  local regenerate=0
  if [ ! -f "${HOMEBREW_GITEA_CERT}" ] || [ ! -f "${HOMEBREW_GITEA_KEY}" ]; then
    regenerate=1
  else
  if ! openssl x509 -in "${HOMEBREW_GITEA_CERT}" -noout -text 2>/dev/null | grep -q "DNS:host.docker.internal"; then
      regenerate=1
    fi
  fi
  if [ "${regenerate}" -eq 1 ]; then
    gitea --work-path "${HOMEBREW_GITEA_WORK}" --custom-path "${HOMEBREW_GITEA_CUSTOM}" --config "${HOMEBREW_GITEA_CONFIG}" \
      cert --host "${GITEA_CERT_HOSTS}" --out "${HOMEBREW_GITEA_CERT}" --keyout "${HOMEBREW_GITEA_KEY}"
    need_restart=1
  fi

  local update_status
  update_status=$(
    GITEA_ROOT_URL="${root_url}" \
      GITEA_SSH_PORT="${GITEA_SSH_PORT}" \
      HOMEBREW_GITEA_CONFIG="${HOMEBREW_GITEA_CONFIG}" \
      HOMEBREW_GITEA_CERT="${HOMEBREW_GITEA_CERT}" \
      HOMEBREW_GITEA_KEY="${HOMEBREW_GITEA_KEY}" \
      python3 <<'PY'
import os
from pathlib import Path
from urllib.parse import urlparse

config_path = Path(os.environ["HOMEBREW_GITEA_CONFIG"])
root_url = os.environ["GITEA_ROOT_URL"]
cert_file = os.environ["HOMEBREW_GITEA_CERT"]
key_file = os.environ["HOMEBREW_GITEA_KEY"]
ssh_port = os.environ["GITEA_SSH_PORT"]

parsed = urlparse(root_url)
http_port = parsed.port or (443 if parsed.scheme == "https" else 80)
domain = parsed.hostname or "localhost"

updates = {
    "PROTOCOL": "https",
    "ROOT_URL": root_url,
    "DOMAIN": domain,
    "HTTP_PORT": str(http_port),
    "CERT_FILE": cert_file,
    "KEY_FILE": key_file,
    "START_SSH_SERVER": "true",
    "SSH_PORT": ssh_port,
    "SSH_LISTEN_PORT": ssh_port,
    "DISABLE_SSH": "false",
}

lines = config_path.read_text().splitlines()
section_start = None
for idx, line in enumerate(lines):
    if line.strip().lower() == "[server]":
        section_start = idx
        break

if section_start is None:
    lines.append("[server]")
    section_start = len(lines) - 1

section_end = len(lines)
for idx in range(section_start + 1, len(lines)):
    line = lines[idx].strip()
    if line.startswith("[") and line.endswith("]"):
        section_end = idx
        break

existing = {}
for idx in range(section_start + 1, section_end):
    stripped = lines[idx].strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        continue
    key = stripped.split("=", 1)[0].strip()
    existing[key] = idx

changed = False
for key, value in updates.items():
    new_line = f"{key} = {value}"
    if key in existing:
        target_idx = existing[key]
        if lines[target_idx].strip() != new_line:
            lines[target_idx] = new_line
            changed = True
    else:
        lines.insert(section_end, new_line)
        section_end += 1
        changed = True

if changed:
    config_path.write_text("\n".join(lines) + "\n")

print("changed" if changed else "unchanged")
PY
  )
  if [[ "${update_status}" == "changed" ]]; then
    need_restart=1
  fi

  # Ensure PASSWORD_HASH_ALGO is set to argon2 (pbkdf2 has issues with basic auth)
  if grep -q "PASSWORD_HASH_ALGO = pbkdf2" "${HOMEBREW_GITEA_CONFIG}"; then
    sed -i '' 's/PASSWORD_HASH_ALGO = pbkdf2/PASSWORD_HASH_ALGO = argon2/' "${HOMEBREW_GITEA_CONFIG}"
    need_restart=1
  elif ! grep -q "PASSWORD_HASH_ALGO" "${HOMEBREW_GITEA_CONFIG}"; then
    # Add PASSWORD_HASH_ALGO to [security] section if not present
    if grep -q "^\[security\]" "${HOMEBREW_GITEA_CONFIG}"; then
      sed -i '' '/^\[security\]/a\
PASSWORD_HASH_ALGO = argon2' "${HOMEBREW_GITEA_CONFIG}"
    fi
    need_restart=1
  fi

  if homebrew_gitea_running; then
    if [ "${need_restart}" -eq 1 ]; then
      brew services restart gitea >/dev/null
    fi
  else
    brew services start gitea >/dev/null
  fi
}

setup_docker_registry_certs() {
  # Set up Docker registry certs for both Docker Desktop and Podman
  # Docker uses ~/.docker/certs.d/<registry>/ca.crt
  local cert_source
  if [ "${GITEA_RUNTIME}" = "homebrew" ]; then
    cert_source="${HOMEBREW_GITEA_CERT}"
  else
    # For container-based Gitea, cert would be in a different location
    cert_source="${ROOT_DIR}/certs/ca.crt"
  fi

  if [ ! -f "${cert_source}" ]; then
    echo "Warning: Gitea cert not found at ${cert_source}, skipping Docker cert setup" >&2
    return 0
  fi

  local docker_certs_base="${HOME}/.docker/certs.d"
  local parsed_port
  parsed_port=$(echo "${GITEA_HTTP}" | sed -n 's|.*:\([0-9]*\).*|\1|p')
  parsed_port="${parsed_port:-3000}"

  # Set up certs for all hostnames that might be used to access the registry
  local registry_hosts=("localhost:${parsed_port}" "host.docker.internal:${parsed_port}" "host.containers.internal:${parsed_port}" "127.0.0.1:${parsed_port}")

  for host in "${registry_hosts[@]}"; do
    mkdir -p "${docker_certs_base}/${host}"
    cp "${cert_source}" "${docker_certs_base}/${host}/ca.crt"
  done

  # Also copy to the project certs directory for reference
  mkdir -p "${ROOT_DIR}/certs"
  cp "${cert_source}" "${ROOT_DIR}/certs/ca.crt"

  echo "Docker registry certs installed for: ${registry_hosts[*]}"
}

wait_health() {
  for i in {1..20}; do
    if curl -sfk -o /dev/null "${GITEA_HTTP}/api/healthz"; then
      return 0
    fi
    sleep 3
  done
  echo "Gitea not healthy at ${GITEA_HTTP}" >&2
  exit 1
}

ensure_admin_container() {
  podman exec kind-argocd_gitea_1 su-exec git gitea admin user create \
    --username "${GITEA_ADMIN_USER}" \
    --password "${GITEA_ADMIN_PASS}" \
    --email "${GITEA_ADMIN_EMAIL}" \
    --admin >/dev/null 2>&1 || true
  podman exec kind-argocd_gitea_1 su-exec git gitea admin user change-password \
    --username "${GITEA_ADMIN_USER}" \
    --password "${GITEA_ADMIN_PASS}" \
    --must-change-password=false >/dev/null 2>&1 || true
}

ensure_admin_homebrew() {
  local gitea_cli
  gitea_cli=(gitea --work-path "${HOMEBREW_GITEA_WORK}" --custom-path "${HOMEBREW_GITEA_CUSTOM}" --config "${HOMEBREW_GITEA_CONFIG}")
  "${gitea_cli[@]}" admin user create \
    --username "${GITEA_ADMIN_USER}" \
    --password "${GITEA_ADMIN_PASS}" \
    --email "${GITEA_ADMIN_EMAIL}" \
    --admin >/dev/null 2>&1 || true
  "${gitea_cli[@]}" admin user change-password \
    --username "${GITEA_ADMIN_USER}" \
    --password "${GITEA_ADMIN_PASS}" \
    --must-change-password=false >/dev/null 2>&1 || true
}

ensure_admin() {
  if [ "${GITEA_RUNTIME}" = "homebrew" ]; then
    ensure_admin_homebrew
  else
    ensure_admin_container
  fi
}

ensure_admin_ssh_key() {
  local pubkey
  pubkey=$(cat "${SSH_KEY}.pub")
  local status
  status=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"title\":\"seed-key\",\"key\":\"${pubkey}\"}" \
    "${GITEA_HTTP}/api/v1/user/keys")
  if ! echo "${status}" | grep -Eq "200|201|422"; then
    echo "Adding admin SSH key returned HTTP ${status}" >&2
    exit 1
  fi
}

ensure_ssh_material() {
  if [ ! -f "${SSH_KEY}" ]; then
    ssh-keygen -t ed25519 -N "" -f "${SSH_KEY}" >/dev/null
  fi
  : > "${KNOWN_HOSTS}"
  local targets=("${GITEA_SSH_HOST}" "host.docker.internal")
  local ok=0
  for host in "${targets[@]}"; do
    [ -z "${host}" ] && continue
    local added=0
    for i in {1..5}; do
      if ssh-keyscan -t rsa -p "${GITEA_SSH_PORT}" "${host}" >> "${KNOWN_HOSTS}" 2>/dev/null; then
        added=1
        ok=1
        break
      fi
      sleep 2
    done
  done
  if [ "${ok}" -eq 0 ]; then
    echo "Failed to capture SSH host keys for Gitea" >&2
    exit 1
  fi
}

create_repo() {
  local name="$1" desc="$2"
  local status
  status=$(curl -sk -o /dev/null -w "%{http_code}" -X POST \
    -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"${name}\",\"private\":false,\"default_branch\":\"main\",\"auto_init\":true,\"description\":\"${desc}\"}" \
    "${GITEA_HTTP}/api/v1/user/repos")
  if ! echo "${status}" | grep -Eq "200|201|409"; then
    echo "Repo ${name} create returned HTTP ${status}" >&2
    exit 1
  fi
}

seed_repo() {
  local source_dir="$1" name="$2"
  local tmp
  tmp="$(mktemp -d)"
  cp -r "${source_dir}/." "${tmp}/"
  (cd "${tmp}" && \
    git init -q && \
    git config user.email "argocd@gitea.local" && \
    git config user.name "argocd" && \
    git config commit.gpgsign false && \
    git add . && git commit -q -m "Seed ${name}" && \
    git branch -M main && \
    GIT_SSH_COMMAND="ssh -i ${SSH_KEY} -o IdentitiesOnly=yes -o UserKnownHostsFile=${KNOWN_HOSTS} -o StrictHostKeyChecking=yes -o HostKeyAlgorithms=ssh-rsa,rsa-sha2-256,rsa-sha2-512 -o PubkeyAcceptedAlgorithms=ssh-ed25519,ssh-rsa,rsa-sha2-256,rsa-sha2-512" \
      git push -f "ssh://${GITEA_SSH_USER}@${GITEA_SSH_HOST}:${GITEA_SSH_PORT}/${GITEA_ADMIN_USER}/${name}.git" main)
  rm -rf "${tmp}"
}

build_azure_auth_tree() {
  local tmp="$1"
  mkdir -p "${tmp}"
  cp -r "${AZ_REPO_DIR}/." "${tmp}/"
  for dir in api-apim-simulator api-fastapi-azure-function frontend-react shared-frontend; do
    mkdir -p "${tmp}/${dir}"
    cp -r "${SUBNET_ROOT}/${dir}/." "${tmp}/${dir}/"
  done
}

build_policies_tree() {
  local tmp="$1"
  mkdir -p "${tmp}"
  cp -r "${ROOT_DIR}/apps" "${tmp}/"
  cp -r "${ROOT_DIR}/policies" "${tmp}/"
  # ensure no terraform state or other files hitch a ride
  find "${tmp}" -maxdepth 1 -type f ! -name "README.md" -delete || true
}

check_etc_hosts() {
  # Docker Desktop on macOS automatically provides host.docker.internal resolution.
  # On Linux without Docker Desktop, /etc/hosts must be manually configured.
  if ! grep -q "host.docker.internal" /etc/hosts 2>/dev/null; then
    echo "WARNING: /etc/hosts does not contain 'host.docker.internal'" >&2
    echo "On Linux (or macOS without Docker Desktop), add this line to /etc/hosts:" >&2
    echo "  127.0.0.1 host.docker.internal" >&2
    echo "(Docker Desktop on macOS handles this automatically)" >&2
    echo "" >&2
    return 1
  fi
  return 0
}

main() {
  check_etc_hosts || true
  if homebrew_gitea_available; then
    echo "Using Homebrew Gitea at ${HOMEBREW_GITEA_CONFIG}"
    GITEA_RUNTIME="homebrew"
    configure_homebrew_gitea_https
  else
    if curl -sfk -o /dev/null "${GITEA_HTTP}/api/healthz"; then
      echo "External Gitea already running at ${GITEA_HTTP}; skipping compose bootstrap."
    else
      start_compose
    fi
  fi
  if [ -z "${GITEA_SSH_USER}" ]; then
    GITEA_SSH_USER="${GITEA_ADMIN_USER}"
  fi
  wait_health
  setup_docker_registry_certs
  ensure_ssh_material
  ensure_admin
  ensure_admin_ssh_key
  create_repo "policies" "Policies for Cilium/Kyverno"
  create_repo "azure-auth-sim" "Azure auth simulation"
  local tmp
  tmp="$(mktemp -d)"
  build_policies_tree "${tmp}"
  seed_repo "${tmp}" "policies"
  rm -rf "${tmp}"
  tmp="$(mktemp -d)"
  build_azure_auth_tree "${tmp}"
  seed_repo "${tmp}" "azure-auth-sim"
  rm -rf "${tmp}"
  echo "Stage 100 complete: external Gitea running, repos seeded."
}

main "$@"
