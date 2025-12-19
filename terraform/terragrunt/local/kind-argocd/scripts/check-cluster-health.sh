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

MESH_AUTH_ENABLED=0
MESH_AUTH_MUTUAL_ENABLED=""
MESH_AUTH_TRUST_DOMAIN=""
MESH_AUTH_SPIRE_SERVER_ADDRESS=""

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
    ok "arm64 Kind nodes detected (note: some azure-auth-sim images may be amd64-only; if you hit exec format errors, recreate with an amd64 kindest/node image or add binfmt/qemu)"
  fi
}

print_useful_urls() {
  echo ""
  ok "Useful URLs"

  # Fixed defaults from stages/700-azure-auth-sim.tfvars (best-effort; don't fail if absent).
  echo "  • Subnet calculator (dev): https://subnetcalc.dev.127.0.0.1.sslip.io/"
  echo "  • Subnet calculator (uat): https://subnetcalc.uat.127.0.0.1.sslip.io/"
  echo "  • Argo CD UI:              https://argocd.127.0.0.1.sslip.io/ (fallback: http://localhost:30080)"
  echo "  • Argo CD admin password:  argocd admin initial-password -n argocd"
  echo "  • Hubble UI:               https://hubble.127.0.0.1.sslip.io/ (fallback: http://localhost:31235)"
  echo "  • Gitea UI:                https://gitea.127.0.0.1.sslip.io/ (fallback: http://localhost:30090)"

  # SigNoz is deployed via Helm charts into the observability namespace.
  if kubectl get ns observability >/dev/null 2>&1; then
    echo "  • SigNoz UI:               https://signoz.127.0.0.1.sslip.io/"
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

  if [[ "${MESH_AUTH_ENABLED}" -eq 1 ]]; then
    optional_namespaces+=(cilium-spire)
  fi

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

detect_mesh_auth() {
  # mesh-auth is configured via the Cilium agent ConfigMap.
  # When disabled, these keys may be missing.
  local enabled
  enabled=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.mesh-auth-enabled}' 2>/dev/null || echo "")
  if [[ "${enabled}" == "true" ]]; then
    MESH_AUTH_ENABLED=1
    MESH_AUTH_MUTUAL_ENABLED=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.mesh-auth-mutual-enabled}' 2>/dev/null || echo "")
    MESH_AUTH_TRUST_DOMAIN=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.mesh-auth-spiffe-trust-domain}' 2>/dev/null || echo "")
    MESH_AUTH_SPIRE_SERVER_ADDRESS=$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.mesh-auth-spire-server-address}' 2>/dev/null || echo "")
    ok "Cilium mesh-auth enabled (mutual=${MESH_AUTH_MUTUAL_ENABLED:-unknown}, trustDomain=${MESH_AUTH_TRUST_DOMAIN:-unknown})"
    if [[ -n "${MESH_AUTH_SPIRE_SERVER_ADDRESS}" ]]; then
      ok "Cilium mesh-auth SPIRE server: ${MESH_AUTH_SPIRE_SERVER_ADDRESS}"
    fi
  else
    ok "Cilium mesh-auth disabled"
  fi
}

check_mesh_auth() {
  if [[ "${MESH_AUTH_ENABLED}" -ne 1 ]]; then
    return
  fi

  if ! kubectl get ns cilium-spire >/dev/null 2>&1; then
    fail_soft "mesh-auth enabled but namespace missing: cilium-spire"
    return
  fi
  ok "Namespace present: cilium-spire"

  local server_desired server_ready
  server_desired=$(kubectl -n cilium-spire get sts spire-server -o jsonpath='{.status.replicas}' 2>/dev/null || echo 0)
  server_ready=$(kubectl -n cilium-spire get sts spire-server -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [[ -z "${server_desired}" ]]; then server_desired=1; fi
  if [[ -z "${server_ready}" ]]; then server_ready=0; fi
  if [[ "${server_ready}" -lt "${server_desired}" ]]; then
    fail_soft "SPIRE server not ready (${server_ready}/${server_desired})"
  else
    ok "SPIRE server ready (${server_ready}/${server_desired})"
  fi

  local agent_desired agent_ready
  agent_desired=$(kubectl -n cilium-spire get ds spire-agent -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  agent_ready=$(kubectl -n cilium-spire get ds spire-agent -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  if [[ "${agent_desired}" -eq 0 ]]; then
    fail_soft "SPIRE agent DaemonSet not found"
  elif [[ "${agent_ready}" -lt "${agent_desired}" ]]; then
    fail_soft "SPIRE agent not ready (${agent_ready}/${agent_desired})"
  else
    ok "SPIRE agent ready (${agent_ready}/${agent_desired})"
  fi
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
    if [[ "${app}" == "app-of-apps" ]]; then
      # app-of-apps can remain Progressing/OutOfSync while pruning optional child Applications.
      # This is noisy but not usually a blocker for the workload health checks below.
      local phase pruning
      phase=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "")
      pruning=$(kubectl -n argocd get app "${app}" -o jsonpath='{range .status.resources[?(@.requiresPruning==true)]}{.name}{" "}{end}' 2>/dev/null || echo "")
      if [[ -n "${pruning// }" ]]; then
        ok "ArgoCD app ${app} has pending prunes (${pruning}); sync=${sync}, health=${health}, phase=${phase:-unknown} (tolerated)"
        return 0
      fi
    fi
    for tolerate in "${tolerate_outofsync[@]:1}"; do
      if [[ "${app}" == "${tolerate}" && "${health}" == "Healthy" ]]; then
        ok "ArgoCD app ${app} is Healthy but not Synced (sync=${sync}) (tolerated)"
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
  local apps=(app-of-apps cilium-policies kyverno-policies azure-auth-gateway)

  # azure-auth-sim-dev/uat are only present when the subnet calculator stack is enabled.
  # Stage 900 can legitimately omit them.
  if kubectl -n argocd get app azure-auth-sim-dev >/dev/null 2>&1; then
    apps+=(azure-auth-sim-dev)
  fi
  if kubectl -n argocd get app azure-auth-sim-uat >/dev/null 2>&1; then
    apps+=(azure-auth-sim-uat)
  fi

  local tolerate_outofsync=("app-of-apps" "azure-auth-gateway" "azure-auth-sim-dev" "azure-auth-sim-uat")
  for app in "${apps[@]}"; do
    # Don't abort the whole script on a single app failure.
    check_argo_app "${app}" "${tolerate_outofsync[@]}" || true
  done
}

wait_for_argo_app_healthy() {
  local app="$1"
  local max_attempts="${2:-18}" # ~3 minutes
  local sleep_seconds="${3:-10}"

  local attempt=0
  while true; do
    if ! kubectl -n argocd get app "${app}" >/dev/null 2>&1; then
      attempt=$((attempt + 1))
      if [[ "${attempt}" -ge "${max_attempts}" ]]; then
        fail_soft "ArgoCD app missing: ${app}"
        return 1
      fi
      sleep "${sleep_seconds}"
      continue
    fi

    local sync health
    sync=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
    health=$(kubectl -n argocd get app "${app}" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

    if [[ "${sync}" == "Synced" && "${health}" == "Healthy" ]]; then
      ok "ArgoCD app ${app} is Synced/Healthy"
      return 0
    fi

    attempt=$((attempt + 1))
    if [[ "${attempt}" -ge "${max_attempts}" ]]; then
      fail_soft "ArgoCD app ${app} not ready after waiting (sync=${sync}, health=${health})"
      return 1
    fi
    sleep "${sleep_seconds}"
  done
}

check_signoz() {
  # SigNoz is optional, but if the app exists (or observability namespace exists), we expect it to become ready.
  local has_ns=0
  local has_app=0
  if kubectl get ns observability >/dev/null 2>&1; then has_ns=1; fi
  if kubectl -n argocd get app signoz >/dev/null 2>&1; then has_app=1; fi
  if kubectl -n argocd get app signoz-k8s-infra >/dev/null 2>&1; then has_app=1; fi
  if [[ "${has_ns}" -eq 0 && "${has_app}" -eq 0 ]]; then
    return
  fi

  # On newer Kubernetes versions, Argo CD can report sync=Unknown for some Helm apps due to
  # schema/diff issues (ComparisonError) while the workload is actually healthy.
  # Since SigNoz is optional and non-critical for the local demo, do not block health checks on it.
  if kubectl -n argocd get app signoz-k8s-infra >/dev/null 2>&1; then
    local sync health comparison_error
    sync=$(kubectl -n argocd get app signoz-k8s-infra -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
    health=$(kubectl -n argocd get app signoz-k8s-infra -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
    comparison_error=$(kubectl -n argocd get app signoz-k8s-infra -o jsonpath='{range .status.conditions[?(@.type=="ComparisonError")]}{.message}{end}' 2>/dev/null || echo "")

    if [[ "${health}" == "Healthy" && "${sync}" == "Unknown" && -n "${comparison_error}" ]]; then
      ok "ArgoCD app signoz-k8s-infra is Healthy (sync=Unknown due to ComparisonError; tolerated)"
    else
      wait_for_argo_app_healthy "signoz-k8s-infra" 6 5 || true
    fi
  fi

  if kubectl -n argocd get app signoz >/dev/null 2>&1; then
    wait_for_argo_app_healthy "signoz" 12 5 || true
  fi

  if kubectl -n observability get svc signoz-frontend >/dev/null 2>&1; then
    ok "SigNoz service present: observability/signoz-frontend"
  elif kubectl -n observability get svc signoz >/dev/null 2>&1; then
    ok "SigNoz service present: observability/signoz"
  else
    fail_soft "SigNoz service missing: expected observability/signoz or observability/signoz-frontend"
  fi

  # Local UX: expose SigNoz on a stable localhost port without requiring kubectl port-forward.
  if kubectl -n observability get svc signoz-ui >/dev/null 2>&1; then
    ok "SigNoz NodePort service present: observability/signoz-ui"
  else
    fail_soft "SigNoz NodePort service missing: expected observability/signoz-ui"
  fi
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
  # The subnet calculator's "azure-auth-sim" apps are optional (can be disabled in stage 800/900).
  if kubectl -n argocd get app azure-auth-sim-dev >/dev/null 2>&1 || kubectl -n argocd get app azure-auth-sim-uat >/dev/null 2>&1; then
    check_env_deployments "dev"
    check_env_deployments "uat"
  fi
  check_gateway_namespace
}

main() {
  require_kubectl
  check_api
  check_node_arch
  check_cilium
  detect_mesh_auth
  check_mesh_auth
  check_namespaces
  check_argo_apps
  check_signoz
  check_azure_auth_sim

  # Print details after the summary lines above.
  print_failure_details

  print_useful_urls

  if [[ "${FAILURES}" -gt 0 ]]; then
    fail "Health checks failed (${FAILURES} issue(s))"
  fi

  ok "All checks passed"
}

main "$@"
