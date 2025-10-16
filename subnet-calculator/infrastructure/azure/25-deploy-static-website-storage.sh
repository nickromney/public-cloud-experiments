#!/usr/bin/env bash
#
# Deploy static HTML frontend to Azure Storage Account static website
# - Uploads all files from frontend-html-static/
# - Configures API URL in JavaScript before upload
# - Supports custom domain configuration
#
# Usage:
#   STORAGE_ACCOUNT_NAME="stsubnetcalc123" ./25-deploy-static-website-storage.sh
#   STORAGE_ACCOUNT_NAME="stsubnetcalc123" API_URL="https://func-xxx.azurewebsites.net" ./25-deploy-static-website-storage.sh

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Get script directory and source location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/../../frontend-html-static"

# Source selection utilities
source "${SCRIPT_DIR}/lib/selection-utils.sh"

# Configuration
readonly CUSTOM_DOMAIN="${CUSTOM_DOMAIN:-publiccloudexperiments.net}"
readonly SUBDOMAIN="${SUBDOMAIN:-static}"
readonly AUTH_MODE="${AUTH_MODE:-auto}"  # auto, login, key

# Check Azure CLI
if ! az account show &>/dev/null; then
  log_error "Not logged in to Azure. Run 'az login'"
  exit 1
fi

# Auto-detect or prompt for RESOURCE_GROUP
if [[ -z "${RESOURCE_GROUP:-}" ]]; then
  log_info "RESOURCE_GROUP not set. Looking for resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    log_error "No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    log_info "Auto-detected single resource group: ${RESOURCE_GROUP}"
  else
    log_warn "Multiple resource groups found:"
    RESOURCE_GROUP=$(select_resource_group) || exit 1
    log_info "Selected: ${RESOURCE_GROUP}"
  fi
fi

# Auto-detect or prompt for STORAGE_ACCOUNT_NAME
if [[ -z "${STORAGE_ACCOUNT_NAME:-}" ]]; then
  log_info "STORAGE_ACCOUNT_NAME not set. Looking for storage accounts with static website enabled..."

  # Get all storage accounts in resource group
  STORAGE_ACCOUNTS=$(az storage account list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].name" -o tsv 2>/dev/null || echo "")

  if [[ -z "${STORAGE_ACCOUNTS}" ]]; then
    log_error "No storage accounts found in resource group ${RESOURCE_GROUP}"
    log_error "Run ./05-static-website-storage.sh first to create one"
    exit 1
  fi

  # Check which ones have static website enabled
  STATIC_ACCOUNTS=""
  for account in ${STORAGE_ACCOUNTS}; do
    STATIC_ENABLED=$(az storage blob service-properties show \
      --account-name "${account}" \
      --auth-mode login \
      --query "staticWebsite.enabled" -o tsv 2>/dev/null || echo "false")

    if [[ "${STATIC_ENABLED}" == "true" ]]; then
      STATIC_ACCOUNTS="${STATIC_ACCOUNTS}${account}\n"
    fi
  done

  if [[ -z "${STATIC_ACCOUNTS}" ]]; then
    log_error "No storage accounts with static website enabled found"
    log_error "Run ./05-static-website-storage.sh first"
    exit 1
  fi

  STATIC_ACCOUNT_COUNT=$(echo -e "${STATIC_ACCOUNTS}" | grep -c -v '^$')

  if [[ "${STATIC_ACCOUNT_COUNT}" -eq 1 ]]; then
    STORAGE_ACCOUNT_NAME=$(echo -e "${STATIC_ACCOUNTS}" | grep -v '^$')
    log_info "Auto-detected storage account: ${STORAGE_ACCOUNT_NAME}"
  else
    log_warn "Multiple storage accounts with static website found:"
    STORAGE_ACCOUNT_NAME=$(select_storage_account "${RESOURCE_GROUP}") || exit 1
    log_info "Selected: ${STORAGE_ACCOUNT_NAME}"
  fi
fi

# Verify source directory exists
if [[ ! -d "${SOURCE_DIR}" ]]; then
  log_error "Source directory not found: ${SOURCE_DIR}"
  exit 1
fi

# Verify storage account exists
if ! az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
  log_error "Storage account ${STORAGE_ACCOUNT_NAME} not found"
  log_error "Run ./05-static-website-storage.sh first"
  exit 1
fi

# Get API URL
API_URL="${API_URL:-}"
if [[ -z "${API_URL}" ]]; then
  log_warn "API_URL not set. Looking for Function Apps..."
  FUNC_COUNT=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "length(@)" -o tsv 2>/dev/null || echo "0")

  if [[ "${FUNC_COUNT}" -eq 1 ]]; then
    FUNCTION_APP_NAME=$(az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[0].name" -o tsv)
    API_URL="https://$(az functionapp show \
      --name "${FUNCTION_APP_NAME}" \
      --resource-group "${RESOURCE_GROUP}" \
      --query defaultHostName -o tsv)"
    log_info "Auto-detected Function App API: ${API_URL}"
  elif [[ "${FUNC_COUNT}" -gt 1 ]]; then
    log_warn "Multiple Function Apps found:"
    az functionapp list --resource-group "${RESOURCE_GROUP}" --query "[].[name,defaultHostName]" -o tsv | \
      awk '{printf "  - %s (https://%s)\n", $1, $2}'
    log_warn "Using default API URL (http://localhost:8090)"
    log_warn "Set API_URL environment variable to override"
    API_URL="http://localhost:8090"
  else
    log_warn "No Function App found. Using default API URL (http://localhost:8090)"
    API_URL="http://localhost:8090"
  fi
fi

log_info "Configuration:"
log_info "  Resource Group: ${RESOURCE_GROUP}"
log_info "  Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "  Source Directory: ${SOURCE_DIR}"
log_info "  API URL: ${API_URL}"
log_info "  Custom Domain: ${CUSTOM_DOMAIN}"
log_info "  Subdomain: ${SUBDOMAIN}"
log_info "  Auth Mode: ${AUTH_MODE}"

# Create temporary directory for deployment
TEMP_DIR=$(mktemp -d)
log_info "Creating deployment package in ${TEMP_DIR}..."

# Copy only production files (whitelist approach for security)
# SECURITY: Do NOT use "cp -r ${SOURCE_DIR}/* ${TEMP_DIR}/" as it would expose:
#   - Dockerfile, Makefile (infrastructure details)
#   - test_frontend.py, conftest.py (test code)
#   - pyproject.toml, uv.lock (build configuration)
#   - compose.yml, nginx.conf (deployment configuration)
#   - __pycache__, .venv, .pytest_cache (build artifacts)
# Only deploy what users need: HTML, CSS, JS, and favicon
log_info "Copying production files only (index.html, favicon.svg, css/, js/)..."

# Verify required files exist before copying
MISSING_FILES=()
for required_file in index.html favicon.svg css js; do
  if [[ ! -e "${SOURCE_DIR}/${required_file}" ]]; then
    MISSING_FILES+=("${required_file}")
  fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
  log_error "Required files/directories not found in ${SOURCE_DIR}:"
  for missing in "${MISSING_FILES[@]}"; do
    log_error "  - ${missing}"
  done
  rm -rf "${TEMP_DIR}"
  exit 1
fi

# Copy only production files (whitelist)
cp "${SOURCE_DIR}/index.html" "${TEMP_DIR}/"
cp "${SOURCE_DIR}/favicon.svg" "${TEMP_DIR}/"
cp -r "${SOURCE_DIR}/css" "${TEMP_DIR}/"
cp -r "${SOURCE_DIR}/js" "${TEMP_DIR}/"

log_info "Production files copied successfully"

# Inject API URL into index.html
if [[ -f "${TEMP_DIR}/index.html" ]]; then
  log_info "Configuring API URL: ${API_URL}"

  # Insert script tag before config.js to set window.API_BASE_URL
  # config.js checks for window.API_BASE_URL and overrides BASE_URL
  sed -i.bak "s|<script src=\"js/config.js\"></script>|<script>window.API_BASE_URL = '${API_URL}';</script>\n    <script src=\"js/config.js\"></script>|" "${TEMP_DIR}/index.html"
  rm "${TEMP_DIR}/index.html.bak"
fi

# Deploy to storage account
log_info "Uploading files to \$web container..."

# Function to upload with specific auth mode
upload_files() {
  local auth_mode=$1
  az storage blob upload-batch \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode "${auth_mode}" \
    --source "${TEMP_DIR}" \
    --destination "\$web" \
    --overwrite \
    --output none 2>&1
}

# Determine which auth mode to use
UPLOAD_SUCCESS=false

if [[ "${AUTH_MODE}" == "auto" ]]; then
  # Try login first (RBAC), fall back to key if it fails
  log_info "Attempting upload with Azure AD authentication..."

  if upload_result=$(upload_files "login"); then
    UPLOAD_SUCCESS=true
    log_info "Upload successful with Azure AD authentication"
  else
    if echo "$upload_result" | grep -q "required permissions"; then
      log_warn "Azure AD authentication failed (missing RBAC permissions)"
      log_info "Falling back to storage account key authentication..."

      if upload_result=$(upload_files "key"); then
        UPLOAD_SUCCESS=true
        log_info "Upload successful with storage account key"
      else
        log_error "Upload failed with both authentication methods"
        echo "$upload_result"
        rm -rf "${TEMP_DIR}"
        exit 1
      fi
    else
      log_error "Upload failed:"
      echo "$upload_result"
      rm -rf "${TEMP_DIR}"
      exit 1
    fi
  fi
elif [[ "${AUTH_MODE}" == "login" ]]; then
  # Use Azure AD authentication only
  if ! upload_files "login"; then
    log_error "Upload failed with Azure AD authentication"
    log_error "You may need one of these roles:"
    log_error "  - Storage Blob Data Owner"
    log_error "  - Storage Blob Data Contributor"
    log_error ""
    log_error "Or try: AUTH_MODE=key ./25-deploy-static-website-storage.sh"
    rm -rf "${TEMP_DIR}"
    exit 1
  fi
  UPLOAD_SUCCESS=true
elif [[ "${AUTH_MODE}" == "key" ]]; then
  # Use storage account key only
  if ! upload_files "key"; then
    log_error "Upload failed with storage account key authentication"
    rm -rf "${TEMP_DIR}"
    exit 1
  fi
  UPLOAD_SUCCESS=true
else
  log_error "Invalid AUTH_MODE: ${AUTH_MODE}"
  log_error "Valid options: auto, login, key"
  rm -rf "${TEMP_DIR}"
  exit 1
fi

if [[ "${UPLOAD_SUCCESS}" != "true" ]]; then
  log_error "Upload failed"
  rm -rf "${TEMP_DIR}"
  exit 1
fi

# Cleanup temp directory
rm -rf "${TEMP_DIR}"

# Get static website URL
STATIC_WEBSITE_URL=$(az storage account show \
  --name "${STORAGE_ACCOUNT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "primaryEndpoints.web" -o tsv)

# Get primary web endpoint for DNS
PRIMARY_WEB_ENDPOINT=$(echo "${STATIC_WEBSITE_URL}" | sed 's|https://||' | sed 's|/$||')

log_info ""
log_info "========================================="
log_info "Static website deployed successfully!"
log_info "========================================="
log_info "Storage Account: ${STORAGE_ACCOUNT_NAME}"
log_info "Website URL: ${STATIC_WEBSITE_URL}"
log_info "API URL: ${API_URL}"
log_info ""
log_info "DNS Configuration:"
log_info "  Subdomain: ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info "  CNAME Record: ${SUBDOMAIN}.${CUSTOM_DOMAIN} → ${PRIMARY_WEB_ENDPOINT}"
log_info ""
log_info "After DNS configuration, configure custom domain on storage account:"
log_info "  az storage account update \\"
log_info "    --name ${STORAGE_ACCOUNT_NAME} \\"
log_info "    --resource-group ${RESOURCE_GROUP} \\"
log_info "    --custom-domain ${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
log_info "Test your deployment:"
log_info "  # Via Azure URL"
log_info "  open ${STATIC_WEBSITE_URL}"
log_info ""
log_info "  # Via custom domain (after DNS propagation)"
log_info "  open https://${SUBDOMAIN}.${CUSTOM_DOMAIN}"
log_info ""
