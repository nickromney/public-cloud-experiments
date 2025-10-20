#!/usr/bin/env bash
#
# Test Azure Static Web App Authentication Endpoints
#
# This script tests the authentication flow for a SWA with Entra ID

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

SWA_URL="${SWA_URL:-https://proud-bay-05b7e1c03.1.azurestaticapps.net}"

echo -e "${BLUE}Testing SWA Authentication Endpoints${NC}"
echo "SWA URL: ${SWA_URL}"
echo ""

# Test 1: Root URL (should redirect to login or return 401)
echo -e "${BLUE}[TEST 1]${NC} Testing root URL (/)..."
echo "curl -I ${SWA_URL}/"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SWA_URL}/")
echo "HTTP Status: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" == "302" || "${HTTP_CODE}" == "401" ]]; then
  echo -e "${GREEN}✓ Root requires authentication (expected)${NC}"
else
  echo -e "${RED}✗ Unexpected status code${NC}"
fi
echo ""

# Test 2: Auth login endpoint (should redirect to Entra ID)
echo -e "${BLUE}[TEST 2]${NC} Testing auth login endpoint..."
echo "curl -I ${SWA_URL}/.auth/login/aad"
REDIRECT_URL=$(curl -s -I "${SWA_URL}/.auth/login/aad" | grep -i "location:" | awk '{print $2}' | tr -d '\r')
if [[ "${REDIRECT_URL}" == *"login.microsoftonline.com"* ]]; then
  echo -e "${GREEN}✓ Login redirects to Entra ID${NC}"
  echo "  Redirect URL: ${REDIRECT_URL}"
else
  echo -e "${RED}✗ Login does not redirect to Entra ID${NC}"
  echo "  Got: ${REDIRECT_URL}"
fi
echo ""

# Test 3: Auth me endpoint (should return 401 when not authenticated)
echo -e "${BLUE}[TEST 3]${NC} Testing /.auth/me endpoint (unauthenticated)..."
echo "curl -I ${SWA_URL}/.auth/me"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SWA_URL}/.auth/me")
echo "HTTP Status: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" == "401" ]]; then
  echo -e "${GREEN}✓ Correctly returns 401 for unauthenticated request${NC}"
else
  echo "  Got: ${HTTP_CODE}"
  # Try to get response body
  RESPONSE=$(curl -s "${SWA_URL}/.auth/me")
  echo "  Response: ${RESPONSE}"
fi
echo ""

# Test 4: Static assets (should be accessible without auth based on navigationFallback)
echo -e "${BLUE}[TEST 4]${NC} Testing static asset access..."
echo "curl -I ${SWA_URL}/favicon.svg"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${SWA_URL}/favicon.svg")
echo "HTTP Status: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" == "200" || "${HTTP_CODE}" == "404" ]]; then
  echo -e "${GREEN}✓ Static assets accessible${NC}"
else
  echo "  Got: ${HTTP_CODE} (might need auth - check navigationFallback config)"
fi
echo ""

# Test 5: Check if config file is deployed
echo -e "${BLUE}[TEST 5]${NC} Checking SWA configuration..."
CONFIG_URL="${SWA_URL}/.auth/me"
echo "Attempting to access /.auth/me to verify auth is configured..."
RESPONSE=$(curl -s -w "\n%{http_code}" "${CONFIG_URL}")
HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
BODY=$(echo "${RESPONSE}" | head -n -1)

echo "HTTP Status: ${HTTP_CODE}"
if [[ "${HTTP_CODE}" == "401" ]]; then
  echo -e "${GREEN}✓ Auth is configured (returns 401)${NC}"
elif [[ "${BODY}" == *"clientPrincipal"* ]]; then
  echo -e "${GREEN}✓ Auth configured and user authenticated${NC}"
else
  echo "Response: ${BODY}"
fi
echo ""

echo -e "${BLUE}Summary${NC}"
echo "========================================="
echo "If all tests show expected results, the SWA auth is configured correctly."
echo ""
echo "Next steps:"
echo "1. Open ${SWA_URL} in a private/incognito browser"
echo "2. Open Developer Tools (F12) → Network tab"
echo "3. Try to access the site and observe the redirect chain"
echo "4. Look for any errors in the Console tab"
echo ""
echo "Common issues:"
echo "- Redirect URI mismatch: Check Entra ID app registration"
echo "- Cookie/cache issues: Clear browser cache and cookies"
echo "- Config not deployed: Redeploy with VITE_AUTH_ENABLED=true"
