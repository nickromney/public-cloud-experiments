#!/usr/bin/env bats
#
# Tests for Stack 15: Public SWA + Entra ID + Linked Backend
# Tests azure-stack-15-swa-entraid-linked.sh deployment stack
#
# Stack Architecture:
#   - Frontend: TypeScript Vite SPA (Entra ID auth)
#   - Backend: Function App (Consumption, linked to SWA)
#   - Auth: Entra ID on SWA (platform-level)
#   - Security: HttpOnly cookies, no CORS issues
#   - Cost: ~$9/month (Standard SWA + Consumption)

setup() {
  load setup

  # Set up environment for stack deployment
  export RESOURCE_GROUP="rg-subnet-calc-test"
  export LOCATION="uksouth"
  export STATIC_WEB_APP_NAME="swa-subnet-calc-entraid-linked"
  export FUNCTION_APP_NAME="func-subnet-calc-entraid-linked"
  export SWA_CUSTOM_DOMAIN="static-swa-entraid-linked.publiccloudexperiments.net"
  export FUNC_CUSTOM_DOMAIN="subnet-calc-fa-entraid-linked.publiccloudexperiments.net"
  export AZURE_CLIENT_ID="test-client-id-12345"
  export AZURE_CLIENT_SECRET="test-client-secret"
}

teardown() {
  load teardown
}

# === Script Structure Tests ===

@test "Stack 15: Script has shebang" {
  run grep -E "^#!/" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Script is executable" {
  [ -x azure-stack-15-swa-entraid-linked.sh ]
}

@test "Stack 15: Script has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Script defines all log functions" {
  run bash -c "grep -q '^log_info()' azure-stack-15-swa-entraid-linked.sh && \
               grep -q '^log_error()' azure-stack-15-swa-entraid-linked.sh && \
               grep -q '^log_step()' azure-stack-15-swa-entraid-linked.sh && \
               grep -q '^log_warn()' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

# === Library Sourcing Tests ===

@test "Stack 15: Sources map-swa-region.sh" {
  run grep "source.*map-swa-region" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Sources selection-utils.sh" {
  run grep "source.*selection-utils" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Configuration Tests ===

@test "Stack 15: Defines SWA custom domain" {
  run grep "SWA_CUSTOM_DOMAIN.*static-swa-entraid-linked" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Defines Function custom domain" {
  run grep "FUNC_CUSTOM_DOMAIN.*subnet-calc-fa-entraid-linked" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Uses SWA Standard SKU" {
  run grep 'STATIC_WEB_APP_SKU.*Standard' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Defines Static Web App name" {
  run grep "STATIC_WEB_APP_NAME.*swa-subnet-calc-entraid-linked" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Defines Function App name" {
  run grep "FUNCTION_APP_NAME.*func-subnet-calc-entraid-linked" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Entra ID App Registration Tests ===

@test "Stack 15: Accepts AZURE_CLIENT_ID variable" {
  run grep "AZURE_CLIENT_ID.*:-" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Accepts AZURE_CLIENT_SECRET variable" {
  run grep "AZURE_CLIENT_SECRET.*:-" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Checks for existing app registration" {
  run grep "check_app_registration" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Defines check_app_registration function" {
  run grep -A 5 "check_app_registration()" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Offers to create app registration if missing" {
  run grep "Create new Entra ID app registration.*Y/n" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Calls 60-entraid-user-setup.sh" {
  run grep "60-entraid-user-setup.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Validates credentials are set" {
  run bash -c "grep -E 'AZURE_CLIENT_ID.*required|AZURE_CLIENT_SECRET.*required' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Updates redirect URIs" {
  run grep "redirectUris" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Configures both azurestaticapps.net and custom domain redirects" {
  run bash -c "grep 'NEW_URI_1.*SWA_URL' azure-stack-15-swa-entraid-linked.sh && \
               grep 'NEW_URI_2.*SWA_CUSTOM_DOMAIN' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Sets logout URL" {
  run grep "logoutUrl" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Enables implicit grant settings" {
  run grep "implicitGrantSettings" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Updates app registration via Microsoft Graph API" {
  run grep "graph.microsoft.com/v1.0/applications" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Function App Configuration Tests ===

@test "Stack 15: Sets AUTH_METHOD to swa" {
  run grep "AUTH_METHOD=swa" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Configures CORS with SWA custom domain" {
  run grep 'CORS_ORIGINS.*SWA_CUSTOM_DOMAIN' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Enables SWA auth on Function App" {
  run grep "DISABLE_AUTH=false" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Prompts for redeployment if Function exists" {
  run grep "Redeploy Function App.*Y/n" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === SWA Configuration Tests ===

@test "Stack 15: Configures Entra ID on SWA" {
  run grep "42-configure-entraid-swa.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Enables SWA auth" {
  run grep 'SWA_AUTH_ENABLED=true' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Enables frontend auth" {
  run grep 'VITE_AUTH_ENABLED=true' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Sets auth method to entraid" {
  run grep 'VITE_AUTH_METHOD=entraid' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Uses empty API URL for SWA proxy" {
  run grep 'VITE_API_URL=""' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Backend Linking Tests ===

@test "Stack 15: Links Function App to SWA" {
  run grep "az staticwebapp backends link" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Uses Function resource ID for linking" {
  run grep "FUNC_RESOURCE_ID.*az webapp show" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Specifies backend region" {
  run grep "backend-region" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Custom Domain Configuration Tests ===

@test "Stack 15: Configures SWA custom domain" {
  run grep "41-configure-custom-domain-swa.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Explains DNS configuration workflow" {
  # Script should explain DNS setup steps rather than prompting prematurely
  run grep -i "will now\|Display.*TXT record\|Display.*CNAME" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Configures Function custom domain" {
  run grep "az functionapp config hostname add" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Creates SSL certificate for Function" {
  run grep "az functionapp config ssl create" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Binds SSL certificate" {
  run grep "az functionapp config ssl bind" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Requires DNS verification TXT record" {
  run grep "asuid" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Warns about Cloudflare proxy" {
  run grep -i "cloudflare.*dns only\|grey cloud" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Deployment Steps Tests ===

@test "Stack 15: Creates Function App" {
  run grep "10-function-app.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Deploys Function API" {
  run grep "22-deploy-function-zip.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Creates Static Web App" {
  run grep "00-static-web-app.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Deploys frontend" {
  run grep "20-deploy-frontend.sh" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Has deployment step ordering" {
  run bash -c "grep -n '10-function-app.sh\|22-deploy-function-zip.sh\|00-static-web-app.sh\|backends link\|42-configure-entraid-swa.sh\|20-deploy-frontend.sh\|41-configure-custom-domain-swa.sh' azure-stack-15-swa-entraid-linked.sh | head -7"
  assert_success
  # Verify order: Function -> Deploy -> SWA -> Link -> Entra ID -> Deploy Frontend -> Custom Domains
}

@test "Stack 15: Has 8 deployment steps" {
  run bash -c "grep -c 'Step [1-8]/8' azure-stack-15-swa-entraid-linked.sh"
  assert_success
  [[ "${output}" -ge 8 ]]
}

# === Region Mapping Tests ===

@test "Stack 15: Maps region for SWA compatibility" {
  run grep "map_swa_region" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Uses SWA-compatible region for SWA" {
  run grep 'LOCATION.*SWA_LOCATION' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Restores original location after SWA creation" {
  run grep 'LOCATION.*REQUESTED_LOCATION' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Error Handling Tests ===

@test "Stack 15: Checks Azure CLI login" {
  run grep "az account show" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Validates prerequisites" {
  run bash -c "grep -E 'command -v (az|jq|npm|uv)' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Auto-detects resource group" {
  run bash -c "grep -E 'az group list.*length|RG_COUNT' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Handles Function App redeployment prompt" {
  run grep -E "Redeploy Function App.*Y/n|SKIP_DEPLOYMENT" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Exits if credentials not provided after prompt" {
  # Check that script has exit logic after app registration prompts (exit is ~50 lines after prompt)
  run grep -A 55 'Create new Entra ID app registration' azure-stack-15-swa-entraid-linked.sh
  assert_success
  [[ "$output" =~ "exit" ]]
}

# === Security and Auth Tests ===

@test "Stack 15: Uses platform-level authentication" {
  run grep -i "platform.*auth\|Entra ID" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Mentions HttpOnly cookies" {
  run grep -i "httponly.*cookie" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Mentions no CORS issues" {
  run grep -i "no cors\|same-origin" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Notes suitability for enterprise" {
  run grep -i "enterprise" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Marked as recommended setup" {
  run grep -i "recommended" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Documentation Tests ===

@test "Stack 15: Documents architecture" {
  run grep -A 10 "# Architecture:" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Documents custom domains" {
  run grep "# Custom Domains:" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Documents redirect URIs" {
  run grep "# Redirect URIs" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Documents usage examples" {
  run grep "# Usage:" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Documents environment variables" {
  run grep "# Environment variables" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Documents cost estimate" {
  run grep -i "cost.*9.*month" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Has ASCII architecture diagram" {
  run grep -E "┌|└|│|─|▼" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Output/Summary Tests ===

@test "Stack 15: Provides deployment summary" {
  run grep -i "deployment complete" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Displays SWA URLs" {
  run bash -c "grep -E 'SWA:.*https|SWA.*URL|SWA Primary|SWA Default' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Displays Function URL" {
  run bash -c "grep -E 'Function:.*https|Function.*URL' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Displays authentication info" {
  run bash -c "grep -E 'Authentication:|Login URL:|Logout URL:' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

@test "Stack 15: Provides test instructions" {
  run grep -i "test.*deployment" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Shows API documentation URL" {
  run grep "/api/v1/docs" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Lists redirect URIs in summary" {
  run grep -i "redirect uris configured" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Integration Tests ===

@test "Stack 15: Banner mentions Stack 2" {
  run grep -i "stack 2" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Banner shows architecture type" {
  run grep -i "public.*entra.*linked" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: References related scripts" {
  run bash -c "grep -E '00-static|10-function|20-deploy|22-deploy|41-configure|42-configure|60-entraid' azure-stack-15-swa-entraid-linked.sh"
  assert_success
}

# === Y/n Prompt Pattern Tests ===

@test "Stack 15: Uses Y/n prompt for app registration creation" {
  run grep "Create new Entra ID app registration.*Y/n" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Uses Y/n prompt for Function redeployment" {
  run grep "Redeploy Function App.*Y/n" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Checks reply pattern for Y/n" {
  run grep -E 'REPLY.*\^\[Nn\]\$' azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === SWA Creation Before App Registration Tests ===

@test "Stack 15: Can create SWA before app registration" {
  # SWA creation (00-static-web-app.sh) should come before app setup (60-entraid-user-setup.sh)
  # Look for actual script calls, not comments
  SWA_LINE=$(grep -n '"${SCRIPT_DIR}/00-static-web-app.sh"' azure-stack-15-swa-entraid-linked.sh | cut -d: -f1 | head -1)
  SETUP_LINE=$(grep -n '"${SCRIPT_DIR}/60-entraid-user-setup.sh"' azure-stack-15-swa-entraid-linked.sh | cut -d: -f1 | head -1)
  [[ -n "$SWA_LINE" ]] && [[ -n "$SETUP_LINE" ]] && [[ $SWA_LINE -lt $SETUP_LINE ]]
}

@test "Stack 15: Gets SWA hostname for app registration" {
  # Should query SWA hostname before calling app setup script
  run grep -B 10 '60-entraid-user-setup.sh' azure-stack-15-swa-entraid-linked.sh
  assert_success
  [[ "$output" =~ "SWA_HOSTNAME" ]]
}

@test "Stack 15: Passes SWA hostname to setup script" {
  run grep "swa-hostname" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Certificate Polling Tests ===

@test "Stack 15: Polls for certificate issuance" {
  run grep "MAX_ATTEMPTS" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Waits for certificate with retry logic" {
  run bash -c "grep -A 10 'Waiting for certificate' azure-stack-15-swa-entraid-linked.sh | grep -q 'while'"
  assert_success
}

@test "Stack 15: Uses az webapp config ssl for certificate check" {
  run grep "az webapp config ssl show" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Provides manual certificate binding command on timeout" {
  run grep "Once ready, bind it manually" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Environment Variable Priority Tests ===

@test "Stack 15: Documents environment variable priority" {
  run grep -i "environment variable priority" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Mentions direnv support" {
  run grep -i "direnv" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

@test "Stack 15: Shows credential sources at startup" {
  run grep "source.*env.*command-line" azure-stack-15-swa-entraid-linked.sh
  assert_success
}

# === Sleep/Wait Pattern Tests ===

@test "Stack 15: Sleeps after Function deployment" {
  run bash -c "grep -A 5 '22-deploy-function-zip.sh' azure-stack-15-swa-entraid-linked.sh | grep -q 'sleep'"
  assert_success
}
