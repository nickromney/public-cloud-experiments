#!/usr/bin/env bash

# Setup Cloudflare environment variables from 1Password
# Usage: source ./setup-cloudflare-env.sh
# Or: eval "$(./setup-cloudflare-env.sh)"

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}ℹ${NC} $1" >&2; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
success() { echo -e "${GREEN}✓${NC} $1" >&2; }

# Check if op is installed
if ! command -v op >/dev/null 2>&1; then
  error "1Password CLI (op) is not installed"
  error "Install with: brew install --cask 1password-cli"
  exit 1
fi

# Check if signed in to 1Password
if ! op account list >/dev/null 2>&1; then
  error "Not signed in to 1Password. Please sign in first:"
  error "  eval \$(op signin)"
  exit 1
fi

# Configuration
readonly VAULT="${VAULT:-Private}"
readonly OP_ITEM="CloudflareAPI_publiccloudexperiments"

info "Retrieving Cloudflare credentials from 1Password..."

# Get API token
CLOUDFLARE_API_TOKEN=$(op item get "$OP_ITEM" --vault="$VAULT" --fields label=CLOUDFLARE_API_TOKEN 2>/dev/null)
if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  error "Failed to retrieve CLOUDFLARE_API_TOKEN from 1Password"
  error "Check that item '$OP_ITEM' exists in vault '$VAULT' with field 'CLOUDFLARE_API_TOKEN'"
  exit 1
fi

# Get Account ID
CLOUDFLARE_ACCOUNT_ID=$(op item get "$OP_ITEM" --vault="$VAULT" --fields label=CLOUDFLARE_ACCOUNT_ID 2>/dev/null)
if [ -z "$CLOUDFLARE_ACCOUNT_ID" ]; then
  error "Failed to retrieve CLOUDFLARE_ACCOUNT_ID from 1Password"
  error "Check that item '$OP_ITEM' exists in vault '$VAULT' with field 'CLOUDFLARE_ACCOUNT_ID'"
  exit 1
fi

success "Retrieved Cloudflare credentials from 1Password"

# Output export statements
echo "export CLOUDFLARE_API_TOKEN='$CLOUDFLARE_API_TOKEN'"
echo "export CLOUDFLARE_ACCOUNT_ID='$CLOUDFLARE_ACCOUNT_ID'"

# Also need Azure backend variables
info "Note: You also need Azure backend variables:"
echo "# export TF_BACKEND_RG='rg-apim-experiment'"
echo "# export TF_BACKEND_SA='sttfstate202511061704'"
echo "# export TF_BACKEND_CONTAINER='terraform-states'"
