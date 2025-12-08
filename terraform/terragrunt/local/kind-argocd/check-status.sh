#!/usr/bin/env bash
#
# check-status.sh - Verify Kind-ArgoCD cluster health
#
# Usage: ./check-status.sh [component]
#   Components: all, kind, cilium, hubble, argocd, gitea, policies, azure-auth, runner
#
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

pass() { echo -e "${GREEN}[PASS]${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; FAIL=$((FAIL + 1)); }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; WARN=$((WARN + 1)); }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
header() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

# Check if command exists
check_cmd() {
    command -v "$1" &>/dev/null
}

# Check Kind cluster
check_kind() {
    header "Kind Cluster (Stage 100)"

    if docker ps --filter "name=kind-local-control-plane" --format '{{.Names}}' | grep -q kind-local; then
        pass "Kind control-plane container running"
    else
        fail "Kind control-plane not found"
        return
    fi

    if kubectl get nodes &>/dev/null; then
        local ready_nodes
        ready_nodes=$(kubectl get nodes --no-headers | grep -c " Ready" || echo 0)
        local total_nodes
        total_nodes=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
        if [[ "$ready_nodes" -eq "$total_nodes" ]]; then
            pass "All nodes ready ($ready_nodes/$total_nodes)"
        else
            warn "Not all nodes ready ($ready_nodes/$total_nodes)"
        fi
    else
        fail "Cannot connect to cluster"
    fi

    # Check key port mappings
    local ports
    ports=$(docker inspect kind-local-control-plane 2>/dev/null | jq -r '.[0].NetworkSettings.Ports | keys[]' 2>/dev/null || echo "")
    if echo "$ports" | grep -q "30090"; then
        pass "Gitea port (30090) mapped"
    else
        warn "Gitea port (30090) not mapped"
    fi
    if echo "$ports" | grep -q "30070"; then
        pass "OAuth2 Proxy port (30070->3007) mapped"
    else
        warn "OAuth2 Proxy port not mapped"
    fi
}

# Check Cilium
check_cilium() {
    header "Cilium CNI (Stage 200)"

    local cilium_pods
    cilium_pods=$(kubectl get pods -n kube-system -l k8s-app=cilium --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$cilium_pods" -gt 0 ]]; then
        pass "Cilium agents running ($cilium_pods pods)"
    else
        fail "No Cilium agents running"
        return
    fi

    local cilium_operator
    cilium_operator=$(kubectl get pods -n kube-system -l name=cilium-operator --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$cilium_operator" -gt 0 ]]; then
        pass "Cilium operator running"
    else
        warn "Cilium operator not running"
    fi
}

# Check Hubble
check_hubble() {
    header "Hubble Observability (Stage 300)"

    local hubble_relay
    hubble_relay=$(kubectl get pods -n kube-system -l k8s-app=hubble-relay --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$hubble_relay" -gt 0 ]]; then
        pass "Hubble relay running"
    else
        warn "Hubble relay not running"
    fi

    local hubble_ui
    hubble_ui=$(kubectl get pods -n kube-system -l k8s-app=hubble-ui --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$hubble_ui" -gt 0 ]]; then
        pass "Hubble UI running"
    else
        warn "Hubble UI not running"
    fi
}

# Check ArgoCD
check_argocd() {
    header "ArgoCD (Stage 400)"

    local argocd_pods
    argocd_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$argocd_pods" -ge 4 ]]; then
        pass "ArgoCD pods running ($argocd_pods)"
    else
        fail "ArgoCD pods not fully running ($argocd_pods)"
        return
    fi

    local app_of_apps
    app_of_apps=$(kubectl get app -n argocd app-of-apps -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "NotFound")
    if [[ "$app_of_apps" == "Synced" ]]; then
        pass "app-of-apps synced"
    else
        warn "app-of-apps status: $app_of_apps"
    fi

    # List all apps
    info "ArgoCD Applications:"
    kubectl get app -n argocd --no-headers 2>/dev/null | while read -r name sync health _; do
        local status_color=$GREEN
        [[ "$sync" != "Synced" ]] && status_color=$YELLOW
        [[ "$health" != "Healthy" ]] && status_color=$YELLOW
        echo -e "  ${status_color}${name}${NC}: $sync / $health"
    done
}

# Check Gitea
check_gitea() {
    header "Gitea (Stage 500)"

    local gitea_pods
    gitea_pods=$(kubectl get pods -n gitea --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$gitea_pods" -gt 0 ]]; then
        pass "Gitea pods running ($gitea_pods)"
    else
        fail "Gitea not running"
        return
    fi

    # Test HTTP access
    local gitea_version
    gitea_version=$(curl -s --max-time 5 http://localhost:30090/api/v1/version 2>/dev/null | jq -r '.version' 2>/dev/null || echo "")
    if [[ -n "$gitea_version" ]]; then
        pass "Gitea HTTP accessible (v$gitea_version)"
    else
        warn "Gitea HTTP not accessible on localhost:30090"
    fi

    # List repos
    local repos
    repos=$(curl -s --max-time 5 -u gitea-admin:ChangeMe123! http://localhost:30090/api/v1/user/repos 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")
    if [[ -n "$repos" ]]; then
        info "Repositories: $(echo "$repos" | tr '\n' ' ')"
    fi
}

# Check Policies
check_policies() {
    header "Network Policies (Stage 600)"

    local cilium_policies
    cilium_policies=$(kubectl get ciliumnetworkpolicies -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$cilium_policies" -gt 0 ]]; then
        pass "Cilium policies applied ($cilium_policies)"
        kubectl get ciliumnetworkpolicies -A --no-headers 2>/dev/null | while read -r ns name _; do
            echo "  - $ns/$name"
        done
    else
        warn "No Cilium policies found"
    fi

    # Check Kyverno policies (only if CRD exists)
    if kubectl api-resources --api-group=kyverno.io 2>/dev/null | grep -q clusterpolicies; then
        local kyverno_policies
        kyverno_policies=$(kubectl get clusterpolicies --no-headers 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$kyverno_policies" -gt 0 ]]; then
            pass "Kyverno policies applied ($kyverno_policies)"
        else
            info "No Kyverno cluster policies"
        fi
    else
        info "Kyverno not installed (CRD not found)"
    fi
}

# Check Azure Auth Sim
check_azure_auth() {
    header "Azure Auth Simulation (Stage 700)"

    local azure_pods
    azure_pods=$(kubectl get pods -n azure-auth-sim --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$azure_pods" -ge 5 ]]; then
        pass "Azure auth sim pods running ($azure_pods)"
    else
        warn "Azure auth sim pods: $azure_pods (expected 5)"
    fi

    # Show pod status
    info "Pods:"
    kubectl get pods -n azure-auth-sim --no-headers 2>/dev/null | while read -r name ready status _; do
        local status_color=$GREEN
        [[ "$status" != "Running" ]] && status_color=$RED
        echo -e "  ${status_color}${name}${NC}: $ready $status"
    done

    # Test endpoints
    info "Endpoint tests:"

    local oauth_status
    oauth_status=$(curl -sI --max-time 3 http://localhost:3007 2>/dev/null | head -1 || echo "Connection failed")
    if echo "$oauth_status" | grep -qE "HTTP.*[234][0-9][0-9]"; then
        pass "OAuth2 Proxy (localhost:3007): responding"
    else
        fail "OAuth2 Proxy (localhost:3007): $oauth_status"
    fi

    local keycloak_status
    keycloak_status=$(curl -sI --max-time 3 http://localhost:8180 2>/dev/null | head -1 || echo "Connection failed")
    if echo "$keycloak_status" | grep -qE "HTTP.*[234][0-9][0-9]"; then
        pass "Keycloak (localhost:8180): responding"
    else
        warn "Keycloak (localhost:8180): $keycloak_status"
    fi

    local api_status
    api_status=$(curl -sI --max-time 3 http://localhost:8081 2>/dev/null | head -1 || echo "Connection failed")
    if echo "$api_status" | grep -qE "HTTP.*[234][0-9][0-9]"; then
        pass "API (localhost:8081): responding"
    else
        warn "API (localhost:8081): $api_status"
    fi

    local apim_status
    apim_status=$(curl -sI --max-time 3 http://localhost:8082 2>/dev/null | head -1 || echo "Connection failed")
    if echo "$apim_status" | grep -qE "HTTP.*[234][0-9][0-9]"; then
        pass "APIM Simulator (localhost:8082): responding"
    else
        warn "APIM Simulator (localhost:8082): $apim_status"
    fi
}

# Check Actions Runner
check_runner() {
    header "Gitea Actions Runner"

    local runner_pods
    runner_pods=$(kubectl get pods -n gitea-runner --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    if [[ "$runner_pods" -gt 0 ]]; then
        pass "Actions runner running"
    else
        warn "Actions runner not running"
        return
    fi

    # Check registration
    local runners
    runners=$(curl -s --max-time 5 -u gitea-admin:ChangeMe123! http://localhost:30090/api/v1/admin/runners 2>/dev/null | jq -r '.data[].name' 2>/dev/null || echo "")
    if [[ -n "$runners" ]]; then
        pass "Runner registered: $runners"
    else
        warn "Runner not registered in Gitea"
    fi
}

# Summary
summary() {
    header "Summary"
    echo -e "Passed: ${GREEN}$PASS${NC}"
    echo -e "Failed: ${RED}$FAIL${NC}"
    echo -e "Warnings: ${YELLOW}$WARN${NC}"

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
}

# Main
main() {
    local component="${1:-all}"

    echo -e "${BLUE}Kind-ArgoCD Status Check${NC}"
    echo "========================="

    if ! check_cmd kubectl; then
        fail "kubectl not found"
        exit 1
    fi

    if ! check_cmd docker; then
        fail "docker not found"
        exit 1
    fi

    case "$component" in
        all)
            check_kind
            check_cilium
            check_hubble
            check_argocd
            check_gitea
            check_policies
            check_azure_auth
            check_runner
            ;;
        kind)       check_kind ;;
        cilium)     check_cilium ;;
        hubble)     check_hubble ;;
        argocd)     check_argocd ;;
        gitea)      check_gitea ;;
        policies)   check_policies ;;
        azure-auth) check_azure_auth ;;
        runner)     check_runner ;;
        *)
            echo "Unknown component: $component"
            echo "Usage: $0 [all|kind|cilium|hubble|argocd|gitea|policies|azure-auth|runner]"
            exit 1
            ;;
    esac

    summary
}

main "$@"
