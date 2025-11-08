#!/usr/bin/env bash

# Import existing DNS records into Terraform state
# Usage: ./import-dns-records.sh <zone-name>
#
# This script:
# 1. Fetches existing DNS records from Cloudflare
# 2. Generates terragrunt import commands
# 3. Executes the imports to populate Terraform state
#
# Example:
#   ./import-dns-records.sh publiccloudexperiments.net

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}ℹ${NC} $1" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
success() { echo -e "${GREEN}✓${NC} $1" >&2; }

# Check arguments
if [ $# -lt 1 ]; then
  error "Usage: $0 <zone-name> [terraform-dir]"
  error ""
  error "Example:"
  error "  $0 publiccloudexperiments.net"
  error "  $0 publiccloudexperiments.net dns-core"
  exit 1
fi

ZONE_NAME="$1"
TERRAFORM_DIR="${2:-.}"
DRY_RUN="${DRY_RUN:-false}"

# Change to terraform directory if specified
if [ "$TERRAFORM_DIR" != "." ]; then
  info "Changing to directory: $TERRAFORM_DIR"
  cd "$TERRAFORM_DIR"
fi

# Check for required tools
if ! command -v jq >/dev/null 2>&1; then
  error "jq is not installed. Install with: brew install jq"
  exit 1
fi

if ! command -v terragrunt >/dev/null 2>&1; then
  error "terragrunt is not installed. Install with: brew install terragrunt"
  exit 1
fi

# Check for required environment variables
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  error "CLOUDFLARE_API_TOKEN is not set"
  error "Run: eval \"\$(./setup-cloudflare-env.sh)\""
  exit 1
fi

info "Fetching zone information for: $ZONE_NAME"

# Get zone ID
ZONE_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")

if ! echo "$ZONE_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
  error "Failed to fetch zone information"
  error "Response: $(echo "$ZONE_RESPONSE" | jq -r '.errors[0].message' 2>/dev/null || echo "$ZONE_RESPONSE")"
  exit 1
fi

ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id')
if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
  error "Zone not found: $ZONE_NAME"
  exit 1
fi

success "Found zone: $ZONE_NAME (ID: $ZONE_ID)"

# Get DNS records
info "Fetching DNS records..."
ALL_RECORDS="[]"
PAGE=1
PER_PAGE=100

while true; do
  RECORDS_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=$PER_PAGE&page=$PAGE" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

  if ! echo "$RECORDS_RESPONSE" | jq -e '.success' >/dev/null 2>&1; then
    error "Failed to fetch DNS records"
    exit 1
  fi

  BATCH=$(echo "$RECORDS_RESPONSE" | jq '.result')
  BATCH_COUNT=$(echo "$BATCH" | jq 'length')

  if [ "$BATCH_COUNT" -eq 0 ]; then
    break
  fi

  ALL_RECORDS=$(echo "$ALL_RECORDS" | jq ". + $BATCH")

  TOTAL_PAGES=$(echo "$RECORDS_RESPONSE" | jq -r '.result_info.total_pages // 1')
  if [ "$PAGE" -ge "$TOTAL_PAGES" ]; then
    break
  fi

  PAGE=$((PAGE + 1))
done

RECORD_COUNT=$(echo "$ALL_RECORDS" | jq 'length')
success "Retrieved $RECORD_COUNT DNS records"

# Generate import commands
info "Generating import commands..."
echo ""

IMPORTED=0
FAILED=0

echo "$ALL_RECORDS" | jq -r '.[] | @json' | while IFS= read -r record; do
  RECORD_ID=$(echo "$record" | jq -r '.id')
  RECORD_NAME=$(echo "$record" | jq -r '.name')
  RECORD_TYPE=$(echo "$record" | jq -r '.type')

  # Generate Terraform resource key
  KEY="$RECORD_NAME"
  if [[ "$RECORD_NAME" == *".$ZONE_NAME" ]]; then
    KEY="${RECORD_NAME%."$ZONE_NAME"}"
  fi

  # Handle apex record
  if [ "$RECORD_NAME" = "$ZONE_NAME" ]; then
    KEY="@"
  fi

  # Cloudflare import format: zone_id/record_id
  IMPORT_ID="$ZONE_ID/$RECORD_ID"

  # Terraform resource address (direct resource, not module)
  RESOURCE_ADDRESS="cloudflare_dns_record.records[\"$KEY\"]"

  if [ "$DRY_RUN" = "true" ]; then
    echo "terragrunt import '$RESOURCE_ADDRESS' '$IMPORT_ID'"
  else
    info "Importing: $KEY ($RECORD_TYPE)"

    # Temporarily disable exit on error for import
    set +e
    IMPORT_OUTPUT=$(terragrunt import "$RESOURCE_ADDRESS" "$IMPORT_ID" 2>&1)
    IMPORT_EXIT_CODE=$?
    set -e

    if [ $IMPORT_EXIT_CODE -eq 0 ] || echo "$IMPORT_OUTPUT" | grep -q "Successfully imported\|Import successful"; then
      success "Imported: $KEY"
      IMPORTED=$((IMPORTED + 1))
    elif echo "$IMPORT_OUTPUT" | grep -q "Resource already managed\|already being managed"; then
      warning "Already imported: $KEY"
      FAILED=$((FAILED + 1))
    else
      error "Failed to import $KEY:"
      echo "$IMPORT_OUTPUT" >&2
      FAILED=$((FAILED + 1))
    fi
  fi
done

if [ "$DRY_RUN" = "false" ]; then
  echo ""
  echo "========================================="
  echo "Import Summary"
  echo "========================================="
  success "Successfully imported: $IMPORTED records"
  if [ "$FAILED" -gt 0 ]; then
    warning "Failed/already imported: $FAILED records"
  fi
  echo ""
  info "Run 'terragrunt plan' to verify state matches configuration"
fi
