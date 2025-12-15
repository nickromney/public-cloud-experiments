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

# Hard fail (stop immediately) for fundamental problems.
fail() { echo "${RED}✖${NC} $*" >&2; exit 1; }

# Soft fail (continue collecting results) for workload/app readiness.
FAILURES=0
fail_soft() { echo "${RED}✖${NC} $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "${YELLOW}⚠${NC} $*"; }
ok() { echo "${GREEN}✔${NC} $*"; }

# Collect extra debug output and print it AFTER the summary.
FAILED_ARGO_APPS=()
FAILED_ARGO_SYNC=()
FAILED_ARGO_HEALTH=()
FAILED_ARGO_MESSAGE=()
FAILED_ARGO_PHASE=()
FAILED_DEPLOY_NS=()
FAILED_DEPLOYMENTS=() # entries: "<ns>|<deployment>|<ready>|<desired>"

add_unique_ns() {
  local ns="$1"
  for existing in "${FAILED_DEPLOY_NS[@]:-}"; do
    if [[ "${existing}" == "${ns}" ]]; then
      return 0
    fi
  done
  FAILED_DEPLOY_NS+=("${ns}")
}

print_events() {
  local ns="$1"
  local n="${2:-12}"
  warn "Recent events (ns=${ns}, last ${n}):"
  # Events can be empty; don't hard-fail.
  kubectl -n "${ns}" get events --sort-by=.lastTimestamp 2>/dev/null | tail -n "${n}" || true
}

print_argocd_events_for_app() {
  local app="$1"
  local n="${2:-10}"
  warn "Recent events (ns=argocd, app=${app}, last ${n}):"
  # Filter to the application to avoid noisy cross-app event streams.
  kubectl -n argocd get events --sort-by=.lastTimestamp 2>/dev/null | grep -F "application/${app}" | tail -n "${n}" || true
}

print_pods() {
  local ns="$1"
  warn "Pods (ns=${ns}):"
  kubectl -n "${ns}" get pods -o wide 2>/dev/null || true
}

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

check_node_arch() {
  # Azure-auth-sim uses an Azure Functions base image that is linux/amd64-only.
  # If the Kind nodes are arm64 (Apple Silicon default), the workload images will not pull/run.
  local archs
  archs=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.architecture}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ' | xargs || true)
  if [[ -z "${archs}" ]]; then
    warn "Unable to detect node architectures"
    return
  fi
  ok "Node architectures: ${archs}"
  if echo " ${archs} " | grep -q " arm64 "; then
    warn "Detected arm64 Kind nodes; azure-auth-sim images are amd64. If pods stay Pending/CrashLoop with exec format errors, recreate with an amd64 kindest/node image or add binfmt/qemu."
  fi
}

check_namespaces() {
  # This script is primarily meant for post-stage-700 checks, but it's also useful during earlier stages.
  # We auto-detect when to be strict: once app-of-apps exists, we expect the full set of namespaces.
  local strict=0
  if kubectl -n argocd get app app-of-apps >/dev/null 2>&1; then
    strict=1
  fi

  local required_namespaces=(
    argocd
  )
  local optional_namespaces=(
    gitea
    gitea-runner
    dev
    uat
    azure-auth-gateway
    azure-apim-sim
    azure-entraid-sim
    kyverno
    nginx-gateway
  )

  for ns in "${required_namespaces[@]}"; do
    if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
      fail "Required namespace missing: ${ns}"
    fi
    ok "Namespace present: ${ns}"
  done

  local missing_optional=0
  for ns in "${optional_namespaces[@]}"; do
    if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
      warn "Namespace missing: ${ns}"
      missing_optional=1
    else
      ok "Namespace present: ${ns}"
    fi
  done

  if [[ "${strict}" -eq 1 && "${missing_optional}" -eq 1 ]]; then
    fail_soft "One or more namespaces missing (strict mode: app-of-apps exists)"
  fi
}

check_cilium() {
  local desired ready attempts=0 max_attempts=6
  while true; do
    desired=$(kubectl -n kube-system get ds -l k8s-app=cilium -o jsonpath='{.items[0].status.desiredNumberScheduled}' 2>/dev/null || echo 0)
    ready=$(kubectl -n kube-system get ds -l k8s-app=cilium -o jsonpath='{.items[0].status.numberReady}' 2>/dev/null || echo 0)
    if [[ "${desired}" -eq 0 ]]; then
      warn "Cilium DaemonSet not found (stage 200 not applied yet?)"
      return
    fi
    if [[ "${desired}" -eq "${ready}" ]]; then
      ok "Cilium ready (${ready}/${desired})"
      return
    fi
    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${max_attempts}" ]]; then
      fail_soft "Cilium not ready (${ready}/${desired}); check kube-system cilium pods/events"
      return
    fi
    sleep 5
  done
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
    fail_soft "ArgoCD app ${app} not healthy (sync=${sync}, health=${health})"

    # Collect details for later output.
    local message phase
    message=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.operationState.message}' 2>/dev/null || echo "")
    phase=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
    FAILED_ARGO_APPS+=("${app}")
    FAILED_ARGO_SYNC+=("${sync}")
    FAILED_ARGO_HEALTH+=("${health}")
    FAILED_ARGO_MESSAGE+=("${message}")
    FAILED_ARGO_PHASE+=("${phase}")
    return 1
  fi
  ok "ArgoCD app ${app} is Synced/Healthy"
}

check_argo_apps() {
  local tolerate_outofsync=("azure-auth-sim-dev" "app-of-apps")
  for app in app-of-apps cilium-policies kyverno-policies azure-auth-gateway azure-auth-sim-dev azure-auth-sim-uat; do
    # Don't abort the whole script on a single app failure.
    check_argo_app "${app}" "${tolerate_outofsync[@]}" || true
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
      add_unique_ns "${ns}"
      FAILED_DEPLOYMENTS+=("${ns}|${dep}|0|1")
      continue
    fi
    local desired ready
    desired=$(kubectl -n "${ns}" get deploy "${dep}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
    ready=$(kubectl -n "${ns}" get deploy "${dep}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
    if [[ -z "${desired}" ]]; then desired=1; fi
    if [[ -z "${ready}" ]]; then ready=0; fi

    if [[ "${ready}" -lt "${desired}" ]]; then
      warn "Deployment not ready: ${dep} (ns=${ns}) (${ready}/${desired})"
      failing=1
      add_unique_ns "${ns}"
      FAILED_DEPLOYMENTS+=("${ns}|${dep}|${ready}|${desired}")
    else
      ok "Deployment ready: ${dep} (ns=${ns}) (${ready}/${desired})"
    fi
  done
  if [[ "${failing}" -eq 1 ]]; then
    fail_soft "One or more deployments not ready in ${ns}"
  fi
}

check_gateway_namespace() {
  local ns="azure-auth-gateway"
  if ! kubectl get ns "${ns}" >/dev/null 2>&1; then
    warn "Namespace missing: ${ns}; skipping gateway checks"
    return
  fi

  local failing=0
  if ! kubectl -n "${ns}" get gateway azure-auth-gateway >/dev/null 2>&1; then
    warn "Gateway missing: azure-auth-gateway (ns=${ns})"
    failing=1
    add_unique_ns "${ns}"
  else
    ok "Gateway present: azure-auth-gateway (ns=${ns})"
  fi

  if ! kubectl -n "${ns}" get svc azure-auth-gateway-nginx >/dev/null 2>&1; then
    warn "Service missing: azure-auth-gateway-nginx (ns=${ns})"
    failing=1
    add_unique_ns "${ns}"
  else
    ok "Service present: azure-auth-gateway-nginx (ns=${ns})"
  fi

  if [[ "${failing}" -eq 1 ]]; then
    fail_soft "Gateway namespace resources not ready in ${ns}"
  fi
}

print_failure_details() {
  if [[ "${#FAILED_ARGO_APPS[@]}" -gt 0 ]]; then
    echo ""
    warn "Details: ArgoCD apps"
    for i in "${!FAILED_ARGO_APPS[@]}"; do
      local app sync health message phase
      app="${FAILED_ARGO_APPS[$i]}"
      sync="${FAILED_ARGO_SYNC[$i]}"
      health="${FAILED_ARGO_HEALTH[$i]}"
      message="${FAILED_ARGO_MESSAGE[$i]}"
      phase="${FAILED_ARGO_PHASE[$i]}"

      warn "ArgoCD app ${app} (sync=${sync}, health=${health})"
      if [[ -n "${message}" ]]; then
        warn "ArgoCD app ${app} message: ${message}"
      fi
      if [[ -n "${phase}" ]]; then
        warn "ArgoCD app ${app} operation phase: ${phase}"
      fi
      print_argocd_events_for_app "${app}" 10
    done
  fi

  if [[ "${#FAILED_DEPLOY_NS[@]}" -gt 0 ]]; then
    echo ""
    warn "Details: Namespaces"
    for ns in "${FAILED_DEPLOY_NS[@]}"; do
      warn "Namespace ${ns} failing deployments:"
      for entry in "${FAILED_DEPLOYMENTS[@]}"; do
        IFS='|' read -r entry_ns dep ready desired <<<"${entry}"
        if [[ "${entry_ns}" == "${ns}" ]]; then
          warn "  - ${dep} (${ready}/${desired})"
        fi
      done
      print_pods "${ns}"
      print_events "${ns}" 12
    done
  fi
}

check_azure_auth_sim() {
  check_env_deployments "dev"
  check_env_deployments "uat"
  check_gateway_namespace
}

main() {
  require_kubectl
  check_api
  check_node_arch
  check_cilium
  check_namespaces
  check_argo_apps
  check_azure_auth_sim

  # Print details after the summary lines above.
  print_failure_details

  if [[ "${FAILURES}" -gt 0 ]]; then
    fail "Health checks failed (${FAILURES} issue(s))"
  fi

  ok "All checks passed"
}

main "$@"
