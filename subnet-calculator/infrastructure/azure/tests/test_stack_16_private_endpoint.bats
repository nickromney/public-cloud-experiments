#!/usr/bin/env bats
#
# Tests for Stack 16: Private Endpoint + Entra ID
# Tests azure-stack-16-swa-private-endpoint.sh deployment stack
#
# Stack Architecture:
#   - Frontend: TypeScript Vite SPA (Entra ID, custom domain primary)
#   - Backend: Function App (App Service Plan, private endpoint only)
#   - Auth: Entra ID on SWA (custom domain only)
#   - Network: VNet, private endpoints, no public backend access
#   - Security: Network-level isolation
#   - Cost: ~$22-293/month (SWA + B1/S1/P0V3/P1V3, private endpoints free)

setup() {
  load setup

  # Set up environment for stack deployment
  export RESOURCE_GROUP="rg-subnet-calc-test"
  export LOCATION="uksouth"
  export STATIC_WEB_APP_NAME="swa-subnet-calc-private-endpoint"
  export FUNCTION_APP_NAME="func-subnet-calc-private-endpoint"
  export APP_SERVICE_PLAN_NAME="plan-subnet-calc-private"
  export APP_SERVICE_PLAN_SKU="P0V3"
  export CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net"
  export VNET_NAME="vnet-subnet-calc-private"
  export VNET_ADDRESS_SPACE="10.100.0.0/24"
  export SUBNET_FUNCTION_PREFIX="10.100.0.0/28"
  export SUBNET_PE_PREFIX="10.100.0.16/28"
  export AZURE_CLIENT_ID="test-client-id-12345"
  export AZURE_CLIENT_SECRET="test-client-secret"
}

teardown() {
  load teardown
}

# === Script Structure Tests ===

@test "Stack 16: Script has shebang" {
  run grep -E "^#!/" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Script is executable" {
  [ -x azure-stack-16-swa-private-endpoint.sh ]
}

@test "Stack 16: Script has set -euo pipefail" {
  run grep -E "set -(e|.*e.*o.*)" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Script defines all log functions" {
  run bash -c "grep -q '^log_info()' azure-stack-16-swa-private-endpoint.sh && \
               grep -q '^log_error()' azure-stack-16-swa-private-endpoint.sh && \
               grep -q '^log_step()' azure-stack-16-swa-private-endpoint.sh && \
               grep -q '^log_warn()' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Library Sourcing Tests ===

@test "Stack 16: Sources map-swa-region.sh" {
  run grep "source.*map-swa-region" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Sources selection-utils.sh" {
  run grep "source.*selection-utils" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Configuration Tests ===

@test "Stack 16: Defines custom domain" {
  run grep "CUSTOM_DOMAIN.*static-swa-private-endpoint" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses SWA Standard SKU" {
  run grep 'STATIC_WEB_APP_SKU.*Standard' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Defines VNet name" {
  run grep "VNET_NAME.*vnet-subnet-calc-private" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses sensible VNet CIDR" {
  run grep "VNET_ADDRESS_SPACE.*10.100.0.0/24" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Defines function subnet" {
  run grep "SUBNET_FUNCTION_PREFIX.*10.100.0.0/28" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Defines private endpoint subnet" {
  run grep "SUBNET_PE_PREFIX.*10.100.0.16/28" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Defines App Service Plan name" {
  run grep "APP_SERVICE_PLAN_NAME.*plan-subnet-calc-private" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Supports multiple SKU options" {
  run bash -c "grep -E 'B1|S1|P0V3|P1V3' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Required Environment Variables Tests ===

@test "Stack 16: Requires AZURE_CLIENT_ID" {
  run bash -c "grep -E 'AZURE_CLIENT_ID.*required' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Requires AZURE_CLIENT_SECRET" {
  run bash -c "grep -E 'AZURE_CLIENT_SECRET.*required' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Validates credentials are set" {
  run bash -c "grep -A 3 'if.*AZURE_CLIENT_ID' azure-stack-16-swa-private-endpoint.sh | grep -q exit"
  assert_success
}

# === Cost Calculation Tests ===

@test "Stack 16: Calculates cost based on SKU" {
  run grep "case.*APP_SERVICE_PLAN_SKU" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has B1 cost calculation" {
  run grep 'B1)' azure-stack-16-swa-private-endpoint.sh
  assert_success
  run grep '\$13.*B1\|\$22.*B1' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has S1 cost calculation" {
  run grep 'S1)' azure-stack-16-swa-private-endpoint.sh
  assert_success
  run grep '\$70.*S1\|\$79.*S1' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has P0V3 cost calculation" {
  run grep 'P0V3)' azure-stack-16-swa-private-endpoint.sh
  assert_success
  run grep '\$142.*P0V3\|\$151.*P0V3' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has P1V3 cost calculation" {
  run grep 'P1V3)' azure-stack-16-swa-private-endpoint.sh
  assert_success
  run grep '\$284.*P1V3\|\$293.*P1V3' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Notes private endpoints are free" {
  run grep -i "private endpoints.*free" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Storage Account Tagging Tests ===

@test "Stack 16: Uses tag-based storage account discovery" {
  run grep "STORAGE_TAG.*purpose=func-subnet-calc-private-endpoint" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Queries existing storage by tag" {
  run grep "tags.purpose=='func-subnet-calc-private-endpoint'" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Generates random suffix for new storage" {
  run bash -c "grep 'STORAGE_SUFFIX.*openssl rand' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Exports storage tag for creation" {
  run grep "STORAGE_ACCOUNT_TAG.*STORAGE_TAG" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === VNet Infrastructure Tests ===

@test "Stack 16: Creates VNet infrastructure" {
  run grep "11-create-vnet-infrastructure.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Exports VNet configuration" {
  run bash -c "grep 'export VNET_NAME' azure-stack-16-swa-private-endpoint.sh && \
               grep 'export VNET_ADDRESS_SPACE' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Exports subnet configuration" {
  run bash -c "grep 'export SUBNET_FUNCTION_NAME' azure-stack-16-swa-private-endpoint.sh && \
               grep 'export SUBNET_PE_NAME' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === App Service Plan Tests ===

@test "Stack 16: Creates App Service Plan" {
  run grep "12-create-app-service-plan.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Exports plan name correctly" {
  run grep 'export PLAN_NAME.*APP_SERVICE_PLAN_NAME' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Exports plan SKU correctly" {
  run grep 'export PLAN_SKU.*APP_SERVICE_PLAN_SKU' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Function App Tests ===

@test "Stack 16: Creates Function App on App Service Plan" {
  run grep "13-create-function-app-on-app-service-plan.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Exports APP_SERVICE_PLAN correctly" {
  run grep 'export APP_SERVICE_PLAN.*APP_SERVICE_PLAN_NAME' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Sets AUTH_METHOD to none" {
  run grep "AUTH_METHOD=none" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Configures CORS with custom domain" {
  run grep 'CORS_ORIGINS.*CUSTOM_DOMAIN' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Disables auth on Function App" {
  run grep "DISABLE_AUTH=true" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === VNet Integration Tests ===

@test "Stack 16: Enables VNet integration" {
  run grep "14-configure-function-vnet-integration.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Exports correct subnet for VNet integration" {
  run grep 'export SUBNET_NAME.*SUBNET_FUNCTION_NAME' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Private Endpoint Tests ===

@test "Stack 16: Creates Function App private endpoint" {
  run grep "46-create-private-endpoint.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Creates SWA private endpoint" {
  run grep "48-create-private-endpoint-swa.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses private endpoint subnet for both" {
  run bash -c "grep -B 5 '46-create-private-endpoint.sh' azure-stack-16-swa-private-endpoint.sh | grep 'SUBNET_PE_NAME' && \
               grep -B 5 '48-create-private-endpoint-swa.sh' azure-stack-16-swa-private-endpoint.sh | grep 'SUBNET_PE_NAME'"
  assert_success
}

@test "Stack 16: Notes Function accessible only via private network" {
  run grep -i "accessible only via private" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === SWA Configuration Tests ===

@test "Stack 16: Creates Static Web App" {
  run grep "00-static-web-app.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Configures Entra ID on SWA" {
  run grep "42-configure-entraid-swa.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Enables SWA auth" {
  run grep 'SWA_AUTH_ENABLED=true' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Enables frontend auth" {
  run grep 'VITE_AUTH_ENABLED=true' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Sets auth method to entraid" {
  run grep 'VITE_AUTH_METHOD=entraid' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses empty API URL for SWA proxy" {
  run grep 'VITE_API_URL=""' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Custom Domain Tests ===

@test "Stack 16: Configures SWA custom domain" {
  run grep "41-configure-custom-domain-swa.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Explains DNS configuration workflow" {
  # Script should explain DNS setup steps rather than prompting prematurely
  run grep -i "will now\|Display.*TXT record\|Display.*CNAME" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Disables default hostname" {
  run grep "47-disable-default-hostname.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Checks if disable script exists" {
  run bash -c "grep -B 1 '47-disable-default-hostname.sh' azure-stack-16-swa-private-endpoint.sh | grep -q 'if.*-f'"
  assert_success
}

@test "Stack 16: Warns if disable script missing" {
  run bash -c "grep -A 3 'else' azure-stack-16-swa-private-endpoint.sh | grep -q '47-disable-default-hostname.sh not found'"
  assert_success
}

# === Backend Linking Tests ===

@test "Stack 16: Links Function App to SWA" {
  run grep "az staticwebapp backends link" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses Function resource ID for linking" {
  run grep "FUNC_RESOURCE_ID.*az functionapp show" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Specifies backend region" {
  run grep "backend-region" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Entra ID Configuration Tests ===

@test "Stack 16: Configures custom domain only redirect URI" {
  run grep "NEW_URI.*CUSTOM_DOMAIN.*auth/login/aad/callback" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Updates app registration via Microsoft Graph API" {
  run grep "graph.microsoft.com/v1.0/applications" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Sets logout URL" {
  run grep "logoutUrl" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Enables implicit grant settings" {
  run grep "implicitGrantSettings" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Gets current redirect URIs and combines" {
  run bash -c "grep 'REDIRECT_URIS.*az ad app show' azure-stack-16-swa-private-endpoint.sh && \
               grep 'mapfile.*URI_ARRAY' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Application Gateway Tests ===

@test "Stack 16: Checks for existing Application Gateway" {
  run grep "az network application-gateway show" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Offers to create Application Gateway" {
  run grep "Create Application Gateway.*Y/n" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Calls Application Gateway creation script" {
  run grep "49-create-application-gateway.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Warns about private endpoint only" {
  run grep -i "private endpoint only" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Notes Application Gateway cost" {
  run grep -E "320.*month|425.*month" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Gets public IP for Application Gateway" {
  run grep "PUBLIC_IP_NAME.*pip-" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has conditional summary based on AppGW" {
  run bash -c "grep 'if.*APPGW_EXISTS.*true' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Deployment Steps Tests ===

@test "Stack 16: Has 11 deployment steps" {
  run bash -c "grep -c 'Step [0-9]*/1[01]' azure-stack-16-swa-private-endpoint.sh"
  assert_success
  [[ "${output}" -ge 11 ]]
}

@test "Stack 16: Creates VNet first" {
  run bash -c "grep -n 'Step.*VNet' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Creates App Service Plan before Function" {
  run bash -c "LINE_PLAN=\$(grep -n '12-create-app-service-plan.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               LINE_FUNC=\$(grep -n '13-create-function-app-on-app-service-plan.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               [[ \${LINE_PLAN} -lt \${LINE_FUNC} ]]"
  assert_success
}

@test "Stack 16: Enables VNet integration before private endpoint" {
  run bash -c "LINE_VNET=\$(grep -n '14-configure-function-vnet-integration.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               LINE_PE=\$(grep -n '46-create-private-endpoint.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               [[ \${LINE_VNET} -lt \${LINE_PE} ]]"
  assert_success
}

@test "Stack 16: Creates SWA before private endpoint" {
  run bash -c "LINE_SWA=\$(grep -n '00-static-web-app.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               LINE_PE_SWA=\$(grep -n '48-create-private-endpoint-swa.sh' azure-stack-16-swa-private-endpoint.sh | cut -d: -f1) && \
               [[ \${LINE_SWA} -lt \${LINE_PE_SWA} ]]"
  assert_success
}

@test "Stack 16: Deploys Function API" {
  run grep "22-deploy-function-zip.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Deploys frontend" {
  run grep "20-deploy-frontend.sh" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Region Mapping Tests ===

@test "Stack 16: Maps region for SWA compatibility" {
  run grep "map_swa_region" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Uses SWA-compatible region for SWA" {
  run grep 'LOCATION.*SWA_LOCATION' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Restores original location after SWA creation" {
  run grep 'LOCATION.*REQUESTED_LOCATION' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Error Handling Tests ===

@test "Stack 16: Checks Azure CLI login" {
  run grep "az account show" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Validates prerequisites" {
  run bash -c "grep -E 'command -v (az|jq|npm|uv)' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Auto-detects resource group" {
  run bash -c "grep -E 'az group list.*length|RG_COUNT' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Security Features Tests ===

@test "Stack 16: Notes custom domain is PRIMARY" {
  run grep -i "custom domain.*primary" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Notes azurestaticapps.net disabled" {
  run grep -i "azurestaticapps.net.*disabled" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Notes no public IP on Function" {
  run grep -i "no public.*function" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Notes network-level isolation" {
  run grep -i "network.*isolation" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Marked as high security setup" {
  run grep -i "high security" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Documentation Tests ===

@test "Stack 16: Documents architecture" {
  run grep -A 10 "# Architecture:" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Has ASCII architecture diagram" {
  run grep -E "┌|└|│|─|▼" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents custom domain" {
  run grep "# Custom Domain:" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents redirect URI" {
  run grep "# Redirect URI" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents usage" {
  run grep "# Usage:" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents environment variables" {
  run grep "# Environment variables" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents cost range" {
  run grep -E "cost.*22-293.*month|22.*293" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents key security features" {
  run grep "# Key Security Features:" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Documents VNet CIDR" {
  run bash -c "grep -E '10.100.0.0/24|VNet.*10.100' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Output/Summary Tests ===

@test "Stack 16: Provides deployment summary" {
  run grep -i "deployment complete" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Displays custom domain URL" {
  run bash -c "grep -E 'SWA.*PRIMARY.*CUSTOM_DOMAIN' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Displays network architecture" {
  run grep -i "network architecture" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Lists VNet and subnets in summary" {
  run bash -c "grep 'VNet:' azure-stack-16-swa-private-endpoint.sh && \
               grep 'Subnet:' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Displays authentication info" {
  run bash -c "grep -E 'Authentication:|Login URL:|Logout URL:' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Lists security features in summary" {
  run grep -i "security features" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Provides test instructions" {
  run grep -i "test.*deployment" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Displays redirect URI in summary" {
  run grep -i "redirect uri configured" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Displays monthly cost breakdown" {
  run bash -c "grep 'Monthly Cost:' azure-stack-16-swa-private-endpoint.sh && \
               grep 'SWA Standard:' azure-stack-16-swa-private-endpoint.sh && \
               grep 'Private Endpoints: Free' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Integration Tests ===

@test "Stack 16: Banner mentions Stack 3" {
  run grep -i "stack 3" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Banner shows architecture type" {
  run grep -i "private endpoint.*entra" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: References related scripts" {
  run bash -c "grep -E '00-static|11-create|12-create|13-create|14-configure|20-deploy|22-deploy|41-configure|42-configure|46-create|47-disable|48-create|49-create' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

# === Sleep/Wait Pattern Tests ===

@test "Stack 16: Sleeps after Function deployment" {
  run bash -c "grep -A 3 '22-deploy-function-zip.sh' azure-stack-16-swa-private-endpoint.sh | grep -q 'sleep'"
  assert_success
}

# === Y/n Prompt Pattern Tests ===

@test "Stack 16: Uses Y/n prompt for Application Gateway creation" {
  run grep "Create Application Gateway.*Y/n" azure-stack-16-swa-private-endpoint.sh
  assert_success
}

@test "Stack 16: Checks reply pattern for Y/n" {
  run grep -E 'REPLY.*\^\[Nn\]\$' azure-stack-16-swa-private-endpoint.sh
  assert_success
}

# === Conditional Output Tests ===

@test "Stack 16: Has different summary for with/without AppGW" {
  run bash -c "grep 'if.*APPGW_EXISTS.*true' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Shows public IP when AppGW exists" {
  run bash -c "grep -A 5 'APPGW_EXISTS.*true' azure-stack-16-swa-private-endpoint.sh | grep -q 'Public Access'"
  assert_success
}

@test "Stack 16: Warns about VNet-only access when no AppGW" {
  run bash -c "grep 'From a VM in the VNet' azure-stack-16-swa-private-endpoint.sh"
  assert_success
}

@test "Stack 16: Offers to run again to create AppGW" {
  run grep -i "run this script again" azure-stack-16-swa-private-endpoint.sh
  assert_success
}
