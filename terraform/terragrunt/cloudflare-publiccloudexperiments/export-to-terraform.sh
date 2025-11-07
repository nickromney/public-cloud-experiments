#!/usr/bin/env bash

# Export DNS records from Cloudflare zone
# Usage: ./export-dns-records.sh <zone-name> [output-format]
# Output formats: json (default), yaml, tfvars
#
# Example:
#   ./export-dns-records.sh publiccloudexperiments.net
#   ./export-dns-records.sh publiccloudexperiments.net yaml
#   ./export-dns-records.sh publiccloudexperiments.net tfvars > dns-core/terraform.tfvars

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}ℹ${NC} $1" >&2; }
warning() { echo -e "${YELLOW}⚠${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
success() { echo -e "${GREEN}✓${NC} $1" >&2; }
debug() { echo -e "${BLUE}DEBUG:${NC} $1" >&2; }

# Check arguments
if [ $# -lt 1 ]; then
  error "Usage: $0 <zone-name> [output-format]"
  error "Output formats: json (default), yaml, tfvars"
  error ""
  error "Example:"
  error "  $0 publiccloudexperiments.net"
  error "  $0 publiccloudexperiments.net yaml"
  error "  $0 publiccloudexperiments.net tfvars > dns-core/terraform.tfvars"
  exit 1
fi

ZONE_NAME="$1"
OUTPUT_FORMAT="${2:-json}"

# Validate output format
case "$OUTPUT_FORMAT" in
  json|yaml|tfvars)
    ;;
  *)
    error "Invalid output format: $OUTPUT_FORMAT"
    error "Valid formats: json, yaml, tfvars"
    exit 1
    ;;
esac

# Check for required tools
if ! command -v jq >/dev/null 2>&1; then
  error "jq is not installed. Install with: brew install jq"
  exit 1
fi

if [ "$OUTPUT_FORMAT" = "yaml" ] && ! command -v yq >/dev/null 2>&1; then
  error "yq is not installed. Install with: brew install yq"
  exit 1
fi

# Check for required environment variables
if [ -z "${CLOUDFLARE_API_TOKEN:-}" ]; then
  error "CLOUDFLARE_API_TOKEN is not set"
  error "Run: eval \"\$(./setup-cloudflare-env.sh)\""
  exit 1
fi

if [ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
  error "CLOUDFLARE_ACCOUNT_ID is not set"
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

# Get SSL settings
info "Fetching SSL settings..."
SSL_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/settings/ssl" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")

SSL_MODE=$(echo "$SSL_RESPONSE" | jq -r '.result.value // "unknown"')
info "SSL Mode: $SSL_MODE"

# Get DNS records (paginated)
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
    error "Response: $(echo "$RECORDS_RESPONSE" | jq -r '.errors[0].message' 2>/dev/null || echo "$RECORDS_RESPONSE")"
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

# Filter and transform records for Terraform
info "Processing records..."

PROCESSED_RECORDS=$(echo "$ALL_RECORDS" | jq '[
  .[] |
  {
    name: .name,
    type: .type,
    content: .content,
    ttl: .ttl,
    proxied: (if .proxied != null then .proxied else false end),
    priority: .priority,
    comment: .comment
  }
]')

# Output based on format
case "$OUTPUT_FORMAT" in
  json)
    echo "$PROCESSED_RECORDS" | jq '{
      zone_name: "'"$ZONE_NAME"'",
      zone_id: "'"$ZONE_ID"'",
      ssl_mode: "'"$SSL_MODE"'",
      records: .
    }'
    ;;

  yaml)
    echo "$PROCESSED_RECORDS" | jq '{
      zone_name: "'"$ZONE_NAME"'",
      zone_id: "'"$ZONE_ID"'",
      ssl_mode: "'"$SSL_MODE"'",
      records: .
    }' | yq -P
    ;;

  tfvars)
    # Generate Terraform tfvars format
    echo "# DNS records for $ZONE_NAME"
    echo "# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "# Zone ID: $ZONE_ID"
    echo "# SSL Mode: $SSL_MODE"
    echo ""
    echo "zone_name = \"$ZONE_NAME\""
    echo ""
    echo "records = {"

    # Process each record
    echo "$PROCESSED_RECORDS" | jq -r '.[] |
      @json' | while IFS= read -r record; do
      NAME=$(echo "$record" | jq -r '.name')
      TYPE=$(echo "$record" | jq -r '.type')
      CONTENT=$(echo "$record" | jq -r '.content')
      TTL=$(echo "$record" | jq -r '.ttl')
      PROXIED=$(echo "$record" | jq -r '.proxied')
      PRIORITY=$(echo "$record" | jq -r '.priority // empty')
      COMMENT=$(echo "$record" | jq -r '.comment // empty')

      # Escape quotes in content for HCL
      CONTENT="${CONTENT//\"/\\\"}"

      # Use the full name as key for uniqueness
      # Remove the zone name suffix for cleaner keys
      KEY="$NAME"
      if [[ "$NAME" == *".$ZONE_NAME" ]]; then
        KEY="${NAME%."$ZONE_NAME"}"
      fi

      # Handle apex record
      if [ "$NAME" = "$ZONE_NAME" ]; then
        KEY="@"
      fi

      echo "  \"$KEY\" = {"
      echo "    type    = \"$TYPE\""
      echo "    value   = \"$CONTENT\""

      # Only include TTL if not auto (1)
      if [ "$TTL" != "1" ]; then
        echo "    ttl     = $TTL"
      fi

      # Only include proxied if true
      if [ "$PROXIED" = "true" ]; then
        echo "    proxied = true"
      fi

      # Only include priority if present (for MX, SRV)
      if [ -n "$PRIORITY" ] && [ "$PRIORITY" != "null" ]; then
        echo "    priority = $PRIORITY"
      fi

      # Only include comment if present
      if [ -n "$COMMENT" ] && [ "$COMMENT" != "null" ]; then
        echo "    comment = \"$COMMENT\""
      fi

      echo "  }"
      echo ""
    done

    echo "}"
    ;;
esac

success "Export complete!" >&2
