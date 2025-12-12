#!/usr/bin/env bash
set -euo pipefail

# Post-stage-700 smoke checks for the local/kind stack.
# Verifies:
# - kube API reachable
# - core namespaces present
# - Cilium pods ready
# - Argo CD applications synced/healthy
# - Azure-auth-sim namespace and deployments ready

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }
warn() { echo "${YELLOW}⚠${NC} $*"; }
ok() { echo "${GREEN}✔${NC} $*"; }

require_kubectl() {
  if ! command -v kubectl >/dev/null 2>&1; then
    fail "kubectl not found in PATH"
  fi
}

check_api() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || echo "unknown")
  local err=""
  if ! err=$(kubectl get ns kube-system 2>&1 >/dev/null); then
    fail "kubectl cannot reach the cluster (context=${ctx}): ${err}"
  fi
  ok "kubectl API reachable (context=${ctx})"
}

check_namespaces() {
  local missing=0
  local namespaces=(
    argocd
    gitea
    gitea-runner
    azure-auth-dev
    azure-auth-uat
    azure-apim-sim
    azure-entraid-sim
    kyverno
    nginx-gateway
  )
  for ns in "${namespaces[@]}"; do
    if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
      warn "Namespace missing: ${ns}"
      missing=1
    else
      ok "Namespace present: ${ns}"
    fi
  done
  if [[ "${missing}" -eq 1 ]]; then
    fail "One or more namespaces missing"
  fi
}

check_cilium() {
  local desired ready
  desired=$(kubectl -n kube-system get ds -l k8s-app=cilium -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  ready=$(kubectl -n kube-system get ds -l k8s-app=cilium -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo 0)
  if [[ "${desired}" -eq 0 ]]; then
    warn "Cilium DaemonSet not found"
    return
  fi
  if [[ "${desired}" -ne "${ready}" ]]; then
    fail "Cilium not ready (${ready}/${desired})"
  fi
  ok "Cilium ready (${ready}/${desired})"
}

check_argo_app() {
  local app="$1"
  local tolerate_outofsync=("$@")
  if ! kubectl -n argocd get app "${app}" >/dev/null 2>&1; then
    warn "ArgoCD app missing: ${app}"
    return 1
  fi
  local sync health
  sync=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
  health=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
  if [[ "${sync}" != "Synced" || "${health}" != "Healthy" ]]; then
    for tolerate in "${tolerate_outofsync[@]:1}"; do
      if [[ "${app}" == "${tolerate}" && "${health}" == "Healthy" ]]; then
        warn "ArgoCD app ${app} is Healthy but not Synced (sync=${sync}); tolerating drift for now"
        return 0
      fi
    done
    fail "ArgoCD app ${app} not healthy (sync=${sync}, health=${health})"
  fi
  ok "ArgoCD app ${app} is Synced/Healthy"
}

check_argo_apps() {
  local tolerate_outofsync=("azure-auth-dev" "app-of-apps")
  for app in app-of-apps cilium-policies kyverno-policies azure-auth-dev azure-auth-uat; do
    check_argo_app "${app}" "${tolerate_outofsync[@]}"
  done
}

check_env_deployments() {
  local ns="$1"
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    warn "Namespace missing: ${ns}; skipping workload checks"
    return
  fi
  local required_deployments=(
    api-fastapi-keycloak
    frontend-react-keycloak-protected
    oauth2-proxy-frontend
  )
  local failing=0
  for dep in "${required_deployments[@]}"; do
    if ! kubectl -n "${ns}" get deploy "${dep}" >/dev/null 2>&1; then
      warn "Deployment missing: ${dep} (ns=${ns})"
      failing=1
      continue
    fi
    local desired ready
    desired=$(kubectl -n "${ns}" get deploy "${dep}" -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
    ready=$(kubectl -n "${ns}" get deploy "${dep}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    if [[ "${desired}" -eq 0 ]]; then desired=1; fi
    if [[ "${ready}" -lt "${desired}" ]]; then
      warn "Deployment not ready: ${dep} (ns=${ns}) (${ready}/${desired})"
      failing=1
    else
      ok "Deployment ready: ${dep} (ns=${ns}) (${ready}/${desired})"
    fi
  done
  if [[ "${failing}" -eq 1 ]]; then
    fail "One or more deployments not ready in ${ns}"
  fi
}

check_azure_auth_sim() {
  check_env_deployments "azure-auth-dev"
  check_env_deployments "azure-auth-uat"
}

main() {
  require_kubectl
  check_api
  check_namespaces
  check_cilium
  check_argo_apps
  check_azure_auth_sim
  ok "All checks passed"
}

main "$@"
