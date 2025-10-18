#!/usr/bin/env bash
#
# Test deployed static website and API configuration
# Usage:
#   ./test-static-deployment.sh https://stsubnetcalc43187.z33.web.core.windows.net
#   ./test-static-deployment.sh https://static.publiccloudexperiments.net

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
log_test() { echo -e "${BLUE}[TEST]${NC} $*"; }

# Check for HTTP client
HTTP_CLIENT=""
if command -v xh &>/dev/null; then
  HTTP_CLIENT="xh"
  log_info "Using xh (httpie) for requests"
elif command -v curl &>/dev/null; then
  HTTP_CLIENT="curl"
  log_info "Using curl for requests"
else
  log_error "Neither xh nor curl found. Install one:"
  log_error "  brew install xh"
  log_error "  or curl (usually pre-installed)"
  exit 1
fi

# Get site URL from argument or use default
SITE_URL="${1:-https://stsubnetcalc43187.z33.web.core.windows.net}"
log_info "Testing site: ${SITE_URL}"
echo ""

# Test 1: Fetch the main page
log_test "Test 1: Fetching main page..."
echo ""

if [[ "${HTTP_CLIENT}" == "xh" ]]; then
  HTML_CONTENT=$(xh --print=b --ignore-stdin "${SITE_URL}" 2>&1) || {
    log_error "Failed to fetch ${SITE_URL}"
    exit 1
  }
else
  HTML_CONTENT=$(curl -sSL "${SITE_URL}" 2>&1) || {
    log_error "Failed to fetch ${SITE_URL}"
    exit 1
  }
fi

log_info "✓ Main page loaded (${#HTML_CONTENT} bytes)"
echo ""

# Test 2: Extract API_BASE_URL from HTML
log_test "Test 2: Checking API configuration..."
echo ""

# Look for window.API_BASE_URL = 'xxx' in the HTML
if echo "${HTML_CONTENT}" | grep -q "window.API_BASE_URL"; then
  API_URL=$(echo "${HTML_CONTENT}" | grep -o "window.API_BASE_URL = '[^']*'" | sed "s/window.API_BASE_URL = '//;s/'//")
  log_info "✓ Found API_BASE_URL: ${API_URL}"

  if [[ "${API_URL}" == "http://localhost"* ]]; then
    log_error "❌ API is configured for localhost!"
    log_error "   This means the deployment script couldn't find your API."
    log_error "   API calls from browsers will fail (CORS/unreachable)."
    echo ""
    log_warn "To fix, redeploy with explicit API URL:"
    log_warn "  STORAGE_ACCOUNT_NAME=\"stsubnetcalc43187\" \\"
    log_warn "  API_URL=\"https://func-xxx.azurewebsites.net\" \\"
    log_warn "  ./25-deploy-static-website-storage.sh"
    echo ""
  else
    log_info "✓ API URL looks good (not localhost)"
  fi
else
  log_warn "⚠ No window.API_BASE_URL found in HTML"
  log_warn "  Frontend will use nginx proxy config (relative URLs)"
  log_warn "  This won't work with Azure Storage static websites!"
  API_URL=""
fi
echo ""

# Test 3: Check static assets
log_test "Test 3: Checking static assets..."
echo ""

ASSETS=("favicon.svg" "css/style.css" "js/config.js" "js/app.js")
for asset in "${ASSETS[@]}"; do
  if [[ "${HTTP_CLIENT}" == "xh" ]]; then
    STATUS=$(xh --print=h --ignore-stdin "${SITE_URL}/${asset}" 2>&1 | grep -E "^HTTP" | awk '{print $2}' || echo "000")
  else
    STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "${SITE_URL}/${asset}" 2>&1)
  fi

  if [[ "${STATUS}" == "200" ]]; then
    log_info "✓ ${asset} (${STATUS})"
  else
    log_error "✗ ${asset} (${STATUS})"
  fi
done
echo ""

# Test 4: Test API endpoints (if we have an API URL)
if [[ -n "${API_URL}" ]] && [[ "${API_URL}" != "http://localhost"* ]]; then
  log_test "Test 4: Testing API endpoints..."
  echo ""

  # Health check
  log_info "Testing: GET ${API_URL}/api/v1/health"
  if [[ "${HTTP_CLIENT}" == "xh" ]]; then
    xh --print=HhBb --ignore-stdin GET "${API_URL}/api/v1/health" || log_error "Health check failed"
  else
    curl -v "${API_URL}/api/v1/health" 2>&1 | grep -E "(^< HTTP|^< |^{)" || log_error "Health check failed"
  fi
  echo ""

  # Validate IP
  log_info "Testing: POST ${API_URL}/api/v1/ipv4/validate"
  if [[ "${HTTP_CLIENT}" == "xh" ]]; then
    xh --print=HhBb --ignore-stdin POST "${API_URL}/api/v1/ipv4/validate" \
      Content-Type:application/json \
      address="192.168.1.0/24" || log_error "Validate failed"
  else
    curl -v -X POST "${API_URL}/api/v1/ipv4/validate" \
      -H "Content-Type: application/json" \
      -d '{"address":"192.168.1.0/24"}' 2>&1 | grep -E "(^< HTTP|^< |^{)" || log_error "Validate failed"
  fi
  echo ""

  # Subnet info
  log_info "Testing: POST ${API_URL}/api/v1/ipv4/subnet-info"
  if [[ "${HTTP_CLIENT}" == "xh" ]]; then
    xh --print=HhBb --ignore-stdin POST "${API_URL}/api/v1/ipv4/subnet-info" \
      Content-Type:application/json \
      network="10.0.0.0/24" \
      mode="Azure" || log_error "Subnet info failed"
  else
    curl -v -X POST "${API_URL}/api/v1/ipv4/subnet-info" \
      -H "Content-Type: application/json" \
      -d '{"network":"10.0.0.0/24","mode":"Azure"}' 2>&1 | grep -E "(^< HTTP|^< |^{)" || log_error "Subnet info failed"
  fi
  echo ""
else
  log_test "Test 4: Skipping API tests (no valid API URL configured)"
  echo ""
fi

# Summary
echo "========================================="
log_info "Test Summary"
echo "========================================="
log_info "Site URL: ${SITE_URL}"
if [[ -n "${API_URL}" ]]; then
  log_info "API URL: ${API_URL}"

  if [[ "${API_URL}" == "http://localhost"* ]]; then
    log_error "STATUS: ❌ API configured for localhost (won't work in browsers)"
    echo ""
    log_warn "Next steps:"
    log_warn "  1. Find your API URL (Function App or Container App)"
    log_warn "  2. Redeploy with: API_URL=https://your-api.azurewebsites.net ./25-deploy-static-website-storage.sh"
  else
    log_info "STATUS: ✓ Configuration looks good"
  fi
else
  log_warn "STATUS: ⚠ No API URL configured (using relative URLs - won't work)"
fi
echo ""
