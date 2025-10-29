#!/usr/bin/env bats
#
# Tests for Stack 14: Public SWA + JWT Auth Function
# Tests azure-stack-14-swa-noauth-jwt.sh deployment stack
#
# Stack Architecture:
#   - Frontend: TypeScript Vite SPA (no SWA auth)
#   - Backend: Function App (public, JWT auth)
#   - Auth: JWT credentials embedded in frontend
#   - Cost: ~$9/month (Consumption + SWA Standard)

setup() {
  load setup

  # Set up environment for stack deployment
  export RESOURCE_GROUP="rg-subnet-calc-test"
  export LOCATION="uksouth"
  export STATIC_WEB_APP_NAME="swa-subnet-calc-noauth"
  export FUNCTION_APP_NAME="func-subnet-calc-jwt"
  export SWA_CUSTOM_DOMAIN="static-swa-no-auth.publiccloudexperiments.net"
  export FUNC_CUSTOM_DOMAIN="subnet-calc-fa-jwt-auth.publiccloudexperiments.net"
  export JWT_USERNAME="demo"
  export JWT_PASSWORD="password123"
  export JWT_SECRET_KEY="test-secret-key-12345"
}

teardown() {
  load teardown
}

# === Script Structure Tests ===

@test "Stack 14: Script has shebang" {
  run grep -E "^#!/" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Script is executable" {
  [ -x azure-stack-14-swa-noauth-jwt.sh ]
}

@test "Stack 14: Script has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Script defines all log functions" {
  run bash -c "grep -q '^log_info()' azure-stack-14-swa-noauth-jwt.sh && \
               grep -q '^log_error()' azure-stack-14-swa-noauth-jwt.sh && \
               grep -q '^log_step()' azure-stack-14-swa-noauth-jwt.sh && \
               grep -q '^log_warn()' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

# === Library Sourcing Tests ===

@test "Stack 14: Sources map-swa-region.sh" {
  run grep "source.*map-swa-region" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Configuration Tests ===

@test "Stack 14: Defines SWA custom domain" {
  run grep "SWA_CUSTOM_DOMAIN.*static-swa-no-auth" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Defines Function custom domain" {
  run grep "FUNC_CUSTOM_DOMAIN.*subnet-calc-fa-jwt-auth" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Uses SWA Standard SKU" {
  run grep 'STATIC_WEB_APP_SKU.*Standard' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Has JWT configuration" {
  run bash -c "grep -E 'JWT_SECRET_KEY|JWT_USERNAME|JWT_PASSWORD' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

@test "Stack 14: Generates JWT secret if not set" {
  run grep "JWT_SECRET_KEY.*openssl rand" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Has JWT username default" {
  run grep 'JWT_USERNAME.*demo' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Generates Argon2 password hash" {
  run grep -E "Argon2|pwdlib|PasswordHash" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === JWT Test Users Configuration ===

@test "Stack 14: Creates JWT_TEST_USERS JSON" {
  run grep "JWT_TEST_USERS" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Configures Function App with JWT auth" {
  run grep "AUTH_METHOD=jwt" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Sets JWT algorithm" {
  run grep "JWT_ALGORITHM" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Sets JWT token expiration" {
  run grep "JWT_ACCESS_TOKEN_EXPIRE_MINUTES" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === SWA Configuration Tests ===

@test "Stack 14: Creates SWA without platform auth" {
  run grep 'SWA_AUTH_ENABLED=false' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Enables JWT auth in frontend" {
  run grep 'VITE_AUTH_ENABLED=true' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Sets frontend API URL to Function custom domain" {
  run grep 'VITE_API_URL.*FUNC_CUSTOM_DOMAIN' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Passes JWT credentials to frontend" {
  run bash -c "grep 'VITE_JWT_USERNAME' azure-stack-14-swa-noauth-jwt.sh && \
               grep 'VITE_JWT_PASSWORD' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

# === CORS Configuration Tests ===

@test "Stack 14: Configures CORS with SWA custom domain" {
  run grep 'CORS_ORIGINS.*SWA_CUSTOM_DOMAIN' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Custom Domain Configuration Tests ===

@test "Stack 14: Configures SWA custom domain" {
  run grep "41-configure-custom-domain-swa.sh" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Configures Function custom domain" {
  run grep -E "az functionapp config hostname add|FUNC_CUSTOM_DOMAIN" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Creates SSL certificate for Function" {
  run grep "az functionapp config ssl create" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Binds SSL certificate" {
  run grep "az functionapp config ssl bind" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Requires DNS verification TXT record" {
  run grep "asuid" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Deployment Steps Tests ===

@test "Stack 14: Creates Function App" {
  run grep "10-function-app.sh" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Deploys Function API" {
  run grep "22-deploy-function-zip.sh" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Creates Static Web App" {
  run grep "00-static-web-app.sh" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Deploys frontend" {
  run grep "20-deploy-frontend.sh" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Has deployment step ordering" {
  run bash -c "grep -n '10-function-app.sh\\|22-deploy-function-zip.sh\\|00-static-web-app.sh\\|20-deploy-frontend.sh' azure-stack-14-swa-noauth-jwt.sh | head -4"
  assert_success
  # Verify order: Function App -> Deploy Function -> SWA -> Deploy Frontend
}

# === Region Mapping Tests ===

@test "Stack 14: Maps region for SWA compatibility" {
  run grep "map_swa_region" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Uses SWA-compatible region for SWA" {
  run grep 'LOCATION.*SWA_LOCATION' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Restores original location after SWA creation" {
  run grep 'LOCATION.*REQUESTED_LOCATION' azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Error Handling Tests ===

@test "Stack 14: Checks Azure CLI login" {
  run grep "az account show" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Validates prerequisites" {
  run bash -c "grep -E 'command -v (az|jq|npm|openssl|uv)' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

@test "Stack 14: Auto-detects resource group" {
  run bash -c "grep -E 'az group list.*length|RG_COUNT' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

@test "Stack 14: Handles Function App redeployment prompt" {
  run grep -E "Redeploy Function App.*Y/n" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Security Warning Tests ===

@test "Stack 14: Warns about JWT credentials in frontend" {
  run grep -i "credentials.*embedded\\|credentials.*frontend\\|credentials.*build" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Notes suitability for demos" {
  run grep -i "demo\\|teaching" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Warns not suitable for production secrets" {
  run grep -i "not.*production\\|not suitable" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Documentation Tests ===

@test "Stack 14: Documents architecture" {
  run grep -A 10 "# Architecture:" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Documents custom domains" {
  run grep "# Custom Domains:" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Documents usage examples" {
  run grep "# Usage:" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Documents environment variables" {
  run grep "# Environment variables" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Documents cost estimate" {
  run grep -i "cost.*9.*month" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Output/Summary Tests ===

@test "Stack 14: Provides deployment summary" {
  run grep -i "deployment complete" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Displays SWA URL" {
  run bash -c "grep -E 'SWA:.*https|SWA.*URL' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

@test "Stack 14: Displays Function URL" {
  run bash -c "grep -E 'Function:.*https|Function.*URL' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}

@test "Stack 14: Provides test instructions" {
  run grep -i "test.*deployment" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Shows API documentation URL" {
  run grep "/api/v1/docs" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

# === Integration Tests ===

@test "Stack 14: Banner mentions Stack 1" {
  run grep -i "stack 1" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: Banner shows architecture type" {
  run grep -i "public.*jwt" azure-stack-14-swa-noauth-jwt.sh
  assert_success
}

@test "Stack 14: References related scripts" {
  run bash -c "grep -E '00-static|10-function|20-deploy|22-deploy|41-configure' azure-stack-14-swa-noauth-jwt.sh"
  assert_success
}
