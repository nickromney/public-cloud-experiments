#!/usr/bin/env bash
#
# Test script for updating Entra ID redirect URIs
# Run this repeatedly until it works

set -euo pipefail

AZURE_CLIENT_ID="370b8618-a252-442e-9941-c47a9f7da89e"
SWA_URL="lemon-river-042bdc103.3.azurestaticapps.net"
SWA_CUSTOM_DOMAIN="static-swa-entraid-linked.publiccloudexperiments.net"

NEW_URI_1="https://${SWA_URL}/.auth/login/aad/callback"
NEW_URI_2="https://${SWA_CUSTOM_DOMAIN}/.auth/login/aad/callback"

echo "=== Getting current redirect URIs ==="
REDIRECT_URIS=$(az ad app show \
  --id "${AZURE_CLIENT_ID}" \
  --query "web.redirectUris[]" -o tsv 2>/dev/null | cat)

echo "Current URIs:"
echo "${REDIRECT_URIS}"
echo ""

echo "=== Building URI array ==="
mapfile -t URI_ARRAY < <(printf '%s\n%s\n%s\n' "${REDIRECT_URIS}" "${NEW_URI_1}" "${NEW_URI_2}" | grep -v '^$' | sort -u)

echo "Array has ${#URI_ARRAY[@]} elements:"
for i in "${!URI_ARRAY[@]}"; do
  echo "  [$i]: '${URI_ARRAY[$i]}'"
done
echo ""

echo "=== Converting to JSON ==="
URI_JSON=$(printf '%s\n' "${URI_ARRAY[@]}" | jq -R . | jq -s -c .)
echo "JSON (compact): ${URI_JSON}"
echo ""

echo "=== Attempting update with --web-redirect-uris (literal args) ==="
# shellcheck disable=SC2046
az ad app update \
  --id "${AZURE_CLIENT_ID}" \
  --web-redirect-uris $(printf '%s ' "${URI_ARRAY[@]}") \
  --output json 2>&1 | head -20

echo ""
echo "=== Verifying update ==="
az ad app show --id "${AZURE_CLIENT_ID}" --query "web.redirectUris" -o json
