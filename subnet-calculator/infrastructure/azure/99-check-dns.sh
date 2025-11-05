#!/usr/bin/env bash
#
# 99-check-dns.sh - Check DNS configuration for subnet calculator stacks
#
# Usage:
#   ./99-check-dns.sh                          # Check all domains
#   ./99-check-dns.sh static-swa-entraid-linked.publiccloudexperiments.net  # Check specific domain
#
# This script checks:
#   - CNAME records for custom domains
#   - TXT records for Azure validation (_dnsauth prefix)
#   - SSL/TLS certificate validity
#   - HTTP/HTTPS connectivity
#   - Azure resource configuration vs DNS reality

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }
log_ok() { echo -e "${GREEN}[✓]${NC} $*"; }
log_fail() { echo -e "${RED}[✗]${NC} $*"; }

# Check prerequisites
check_prerequisites() {
  local missing=0

  for cmd in dig curl jq az; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Missing required command: $cmd"
      missing=1
    fi
  done

  if [[ $missing -eq 1 ]]; then
    log_error "Install missing commands and try again"
    exit 1
  fi
}

# Check CNAME record
check_cname() {
  local domain="$1"
  local expected_target="${2:-}"

  log_step "Checking CNAME for ${domain}..."

  local cname
  cname=$(dig +short "$domain" CNAME | sed 's/\.$//' || echo "")

  if [[ -z "$cname" ]]; then
    log_fail "No CNAME record found"
    return 1
  fi

  log_ok "CNAME: ${domain} → ${cname}"

  if [[ -n "$expected_target" ]] && [[ "$cname" != "$expected_target" ]]; then
    log_warn "Expected target: ${expected_target}"
    log_warn "Actual target:   ${cname}"
    return 1
  fi

  return 0
}

# Check TXT validation record
check_txt_validation() {
  local domain="$1"

  log_step "Checking TXT validation record for ${domain}..."

  local txt_domain="_dnsauth.${domain}"
  local txt_value
  txt_value=$(dig +short "$txt_domain" TXT | tr -d '"' || echo "")

  if [[ -z "$txt_value" ]]; then
    log_warn "No TXT validation record found at ${txt_domain}"
    log_info "This is OK if domain is already validated"
    return 0
  fi

  log_ok "TXT record: ${txt_domain}"
  log_info "  Value: ${txt_value}"

  return 0
}

# Check HTTP/HTTPS connectivity
check_connectivity() {
  local domain="$1"
  local protocol="${2:-https}"

  log_step "Checking ${protocol}://${domain} connectivity..."

  local status_code
  local redirect_location

  # Get HTTP status and redirect location
  local response
  response=$(curl -sI -w "%{http_code}" -o /dev/null "${protocol}://${domain}" 2>&1 || echo "000")
  status_code="${response: -3}"

  if [[ "$status_code" == "000" ]]; then
    log_fail "Connection failed (DNS not resolving or network error)"
    return 1
  fi

  if [[ "$status_code" =~ ^2 ]]; then
    log_ok "HTTP ${status_code} - Success"
    return 0
  elif [[ "$status_code" =~ ^3 ]]; then
    redirect_location=$(curl -sI "${protocol}://${domain}" 2>&1 | grep -i "^location:" | awk '{print $2}' | tr -d '\r' || echo "")
    log_ok "HTTP ${status_code} - Redirect to: ${redirect_location}"
    return 0
  elif [[ "$status_code" == "401" ]] || [[ "$status_code" == "403" ]]; then
    log_ok "HTTP ${status_code} - Authentication required (expected for protected apps)"
    return 0
  else
    log_warn "HTTP ${status_code} - Unexpected status"
    return 1
  fi
}

# Check SSL/TLS certificate
check_ssl() {
  local domain="$1"

  log_step "Checking SSL/TLS certificate for ${domain}..."

  local cert_info
  cert_info=$(echo | openssl s_client -servername "$domain" -connect "${domain}:443" 2>/dev/null | openssl x509 -noout -dates -subject 2>/dev/null || echo "")

  if [[ -z "$cert_info" ]]; then
    log_fail "Could not retrieve SSL certificate"
    return 1
  fi

  local not_before
  local not_after
  not_before=$(echo "$cert_info" | grep "notBefore=" | cut -d= -f2)
  not_after=$(echo "$cert_info" | grep "notAfter=" | cut -d= -f2)

  log_ok "Certificate valid"
  log_info "  Valid from: ${not_before}"
  log_info "  Valid to:   ${not_after}"

  # Check if certificate is expiring soon (within 30 days)
  local expiry_epoch
  expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null || date -d "$not_after" +%s 2>/dev/null || echo "0")
  local now_epoch
  now_epoch=$(date +%s)
  local days_remaining=$(( (expiry_epoch - now_epoch) / 86400 ))

  if [[ $days_remaining -lt 30 ]] && [[ $days_remaining -gt 0 ]]; then
    log_warn "Certificate expires in ${days_remaining} days"
  elif [[ $days_remaining -le 0 ]]; then
    log_fail "Certificate has expired!"
    return 1
  fi

  return 0
}

# Check Azure SWA custom domain configuration
check_azure_swa() {
  local swa_name="$1"
  local domain="$2"
  local resource_group="${3:-}"

  log_step "Checking Azure Static Web App configuration..."

  if [[ -z "$resource_group" ]]; then
    log_warn "Resource group not provided, skipping Azure checks"
    return 0
  fi

  # Check if SWA exists
  if ! az staticwebapp show --name "$swa_name" --resource-group "$resource_group" &>/dev/null; then
    log_fail "Static Web App '${swa_name}' not found in resource group '${resource_group}'"
    return 1
  fi

  # Check custom domain status
  local domain_status
  domain_status=$(az staticwebapp hostname show \
    --name "$swa_name" \
    --resource-group "$resource_group" \
    --hostname "$domain" \
    --query "status" -o tsv 2>/dev/null || echo "NotFound")

  if [[ "$domain_status" == "NotFound" ]]; then
    log_fail "Custom domain not configured in Azure"
    return 1
  elif [[ "$domain_status" == "Ready" ]]; then
    log_ok "Azure custom domain status: Ready"
  else
    log_warn "Azure custom domain status: ${domain_status}"
  fi

  # Check if it's set as default
  local default_hostname
  default_hostname=$(az staticwebapp show \
    --name "$swa_name" \
    --resource-group "$resource_group" \
    --query "defaultHostname" -o tsv)

  log_info "Default hostname: ${default_hostname}"

  return 0
}

# Check Azure Function App custom domain
check_azure_function() {
  local func_name="$1"
  local domain="$2"
  local resource_group="${3:-}"

  log_step "Checking Azure Function App configuration..."

  if [[ -z "$resource_group" ]]; then
    log_warn "Resource group not provided, skipping Azure checks"
    return 0
  fi

  # Check if Function App exists
  if ! az webapp show --name "$func_name" --resource-group "$resource_group" &>/dev/null; then
    log_fail "Function App '${func_name}' not found in resource group '${resource_group}'"
    return 1
  fi

  # Check custom domain configuration
  local hostnames
  hostnames=$(az webapp config hostname list \
    --webapp-name "$func_name" \
    --resource-group "$resource_group" \
    --query "[].name" -o tsv 2>/dev/null || echo "")

  if [[ "$hostnames" == *"$domain"* ]]; then
    log_ok "Custom domain configured in Azure Function App"
  else
    log_fail "Custom domain not configured in Azure Function App"
    log_info "Configured hostnames: ${hostnames}"
    return 1
  fi

  # Check SSL binding
  local ssl_state
  ssl_state=$(az webapp config hostname list \
    --webapp-name "$func_name" \
    --resource-group "$resource_group" \
    --query "[?name=='${domain}'].sslState" -o tsv 2>/dev/null || echo "")

  if [[ "$ssl_state" == "SniEnabled" ]]; then
    log_ok "SSL/TLS enabled (SNI)"
  else
    log_warn "SSL state: ${ssl_state}"
  fi

  return 0
}

# Main check function for a domain
check_domain() {
  local domain="$1"
  local expected_target="${2:-}"
  local resource_name="${3:-}"
  local resource_type="${4:-swa}"  # swa or function
  local resource_group="${5:-}"

  echo ""
  log_info "========================================="
  log_info "Checking: ${domain}"
  log_info "========================================="
  echo ""

  local checks_passed=0
  local checks_failed=0

  # DNS checks
  if check_cname "$domain" "$expected_target"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  echo ""

  check_txt_validation "$domain"
  echo ""

  # Connectivity checks
  if check_connectivity "$domain" "https"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  echo ""

  # SSL check
  if check_ssl "$domain"; then
    ((checks_passed++))
  else
    ((checks_failed++))
  fi
  echo ""

  # Azure resource checks
  if [[ -n "$resource_name" ]] && [[ -n "$resource_group" ]]; then
    if [[ "$resource_type" == "swa" ]]; then
      if check_azure_swa "$resource_name" "$domain" "$resource_group"; then
        ((checks_passed++))
      else
        ((checks_failed++))
      fi
    elif [[ "$resource_type" == "function" ]]; then
      if check_azure_function "$resource_name" "$domain" "$resource_group"; then
        ((checks_passed++))
      else
        ((checks_failed++))
      fi
    fi
    echo ""
  fi

  # Summary
  log_info "========================================="
  if [[ $checks_failed -eq 0 ]]; then
    log_ok "All checks passed (${checks_passed}/${checks_passed})"
  else
    log_warn "Some checks failed (${checks_passed} passed, ${checks_failed} failed)"
  fi
  log_info "========================================="

  return $checks_failed
}

# Predefined domains for subnet calculator stacks
check_all_stacks() {
  local resource_group="${1:-rg-subnet-calc}"

  log_info "Checking all subnet calculator stack domains..."
  log_info "Resource Group: ${resource_group}"
  echo ""

  local total_failed=0

  # Stack 14: JWT auth
  if check_domain \
    "static-swa-no-auth.publiccloudexperiments.net" \
    "" \
    "swa-subnet-calc-noauth" \
    "swa" \
    "$resource_group"; then
    :
  else
    ((total_failed++))
  fi

  if check_domain \
    "subnet-calc-fa-jwt-auth.publiccloudexperiments.net" \
    "func-subnet-calc-jwt.azurewebsites.net" \
    "func-subnet-calc-jwt" \
    "function" \
    "$resource_group"; then
    :
  else
    ((total_failed++))
  fi

  # Stack 15: Entra ID linked
  if check_domain \
    "static-swa-entraid-linked.publiccloudexperiments.net" \
    "lemon-river-042bdc103.3.azurestaticapps.net" \
    "swa-subnet-calc-entraid-linked" \
    "swa" \
    "$resource_group"; then
    :
  else
    ((total_failed++))
  fi

  if check_domain \
    "subnet-calc-fa-entraid-linked.publiccloudexperiments.net" \
    "func-subnet-calc-entraid-linked.azurewebsites.net" \
    "func-subnet-calc-entraid-linked" \
    "function" \
    "$resource_group"; then
    :
  else
    ((total_failed++))
  fi

  # Stack 16: Private endpoint
  if check_domain \
    "static-swa-private-endpoint.publiccloudexperiments.net" \
    "" \
    "swa-subnet-calc-private-endpoint" \
    "swa" \
    "$resource_group"; then
    :
  else
    ((total_failed++))
  fi

  echo ""
  log_info "========================================="
  log_info "Summary: All Stacks"
  log_info "========================================="
  if [[ $total_failed -eq 0 ]]; then
    log_ok "All domains configured correctly"
  else
    log_warn "${total_failed} domain(s) have issues"
  fi

  return $total_failed
}

# Main script
main() {
  check_prerequisites

  if [[ $# -eq 0 ]]; then
    # No arguments - check all stacks with default resource group
    check_all_stacks "rg-subnet-calc"
  elif [[ $# -eq 1 ]]; then
    # Single domain provided
    check_domain "$1"
  else
    # Multiple arguments: domain, target, resource_name, resource_type, resource_group
    check_domain "$@"
  fi
}

main "$@"
