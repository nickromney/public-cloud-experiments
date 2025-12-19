#!/usr/bin/env bash
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

ok() { echo "${GREEN}✔${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*"; }
fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

tfvar_get() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  local line
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "$file" 2>/dev/null | tail -n 1 || true)
  if [ -z "$line" ]; then
    echo ""
    return 0
  fi
  echo "$line" | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

yaml_get() {
  local file="$1"
  local key="$2"
  if [ ! -f "$file" ]; then
    echo ""
    return 0
  fi
  grep -E "^[[:space:]]*${key}:" "$file" 2>/dev/null | head -n 1 | sed -E "s/^[[:space:]]*${key}:[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs
}

github_latest_release_tag() {
  local repo="$1" # e.g. argoproj/argo-helm
  local auth=()
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  curl -sSL "${auth[@]}" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${repo}/releases/latest" | jq -r '.tag_name // empty' 2>/dev/null || true
}

helm_latest_chart_version() {
  local repo_name="$1"
  local repo_url="$2"
  local chart="$3"

  if ! command -v helm >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  helm repo add "${repo_name}" "${repo_url}" --force-update >/dev/null 2>&1 || true
  helm repo update "${repo_name}" >/dev/null 2>&1 || true
  helm search repo "${repo_name}/${chart}" --versions -o json 2>/dev/null | jq -r '.[0].version // empty' || true
}

print_row() {
  local name="$1"
  local pinned="$2"
  local latest="$3"
  local status

  if [ -z "$pinned" ]; then
    status="${YELLOW}unknown (pinned missing)${NC}"
  elif [ -z "$latest" ]; then
    status="${YELLOW}unknown (latest unavailable)${NC}"
  elif [ "$pinned" = "$latest" ]; then
    status="${GREEN}up-to-date${NC}"
  else
    status="${YELLOW}update available${NC}"
  fi

  printf "%-22s %-16s %-16s %s\n" "$name" "$pinned" "$latest" "$status"
}

echo ""
ok "Local/kind pinned version check"
echo ""

STAGES_DIR="${STACK_DIR}/stages"

PIN_ARGOCD=$(tfvar_get "${STAGES_DIR}/100-kind.tfvars" "argocd_chart_version")
PIN_GITEA=$(tfvar_get "${STAGES_DIR}/500-gitea.tfvars" "gitea_chart_version")
PIN_CILIUM=$(tfvar_get "${STAGES_DIR}/200-cilium.tfvars" "cilium_version")

PIN_SIGNOZ=$(yaml_get "${STACK_DIR}/apps/_applications/signoz.yaml" "targetRevision")
PIN_SIGNOZ_K8S_INFRA=$(yaml_get "${STACK_DIR}/templates/apps/signoz-k8s-infra.yaml.tpl" "targetRevision")

PIN_NGX_FABRIC=$(
  sed -nE 's/.*image:[[:space:]]*ghcr\.io\/nginx\/nginx-gateway-fabric:([^@[:space:]]+).*/\1/p' \
    "${STACK_DIR}/templates/apps/nginx-gateway-fabric/deploy.yaml.tpl" 2>/dev/null | head -n 1
)

LATEST_ARGOCD=$(helm_latest_chart_version "argo" "https://argoproj.github.io/argo-helm" "argo-cd")

LATEST_GITEA=$(helm_latest_chart_version "gitea" "https://dl.gitea.io/charts/" "gitea")
LATEST_SIGNOZ=$(helm_latest_chart_version "signoz" "https://charts.signoz.io" "signoz")
LATEST_SIGNOZ_K8S_INFRA=$(helm_latest_chart_version "signoz" "https://charts.signoz.io" "k8s-infra")

if command -v github-release-version-checker >/dev/null 2>&1; then
  # Uses your local caching + policy-aware checker if installed.
  LATEST_NGX_FABRIC_TAG=$(github-release-version-checker --repo nginxinc/nginx-gateway-fabric 2>/dev/null | head -n 1 | xargs || true)
else
  LATEST_NGX_FABRIC_TAG=$(github_latest_release_tag "nginxinc/nginx-gateway-fabric")
fi
LATEST_NGX_FABRIC=$(echo "$LATEST_NGX_FABRIC_TAG" | sed -E 's/^v//' | xargs)

echo "Pinned component versions (vs latest)"
printf "%-22s %-16s %-16s %s\n" "Component" "Pinned" "Latest" "Status"
printf "%-22s %-16s %-16s %s\n" "---------" "------" "------" "------"
print_row "argo-cd chart" "${PIN_ARGOCD}" "${LATEST_ARGOCD}"
print_row "gitea chart" "${PIN_GITEA}" "${LATEST_GITEA}"
print_row "nginx-fabric" "${PIN_NGX_FABRIC}" "${LATEST_NGX_FABRIC}"
print_row "signoz chart" "${PIN_SIGNOZ}" "${LATEST_SIGNOZ}"
print_row "signoz k8s-infra" "${PIN_SIGNOZ_K8S_INFRA}" "${LATEST_SIGNOZ_K8S_INFRA}"
echo ""

if [ -n "${PIN_CILIUM}" ]; then
  echo "Note: cilium pinned version (no upstream check in this command): ${PIN_CILIUM}"
  echo ""
fi

check_consistent_tfvars() {
  local key="$1"
  local value
  local uniq

  uniq=$(grep -hE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*" "${STAGES_DIR}"/*.tfvars 2>/dev/null | \
    sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs -n1 | sort -u || true)

  if [ -z "$uniq" ]; then
    return 0
  fi

  local count
  count=$(echo "$uniq" | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    warn "Inconsistent ${key} across stages:"
    echo "$uniq" | sed 's/^/  - /'
    echo ""
  fi
}

check_consistent_tfvars "argocd_chart_version"
check_consistent_tfvars "gitea_chart_version"
check_consistent_tfvars "cilium_version"

ok "Done"
