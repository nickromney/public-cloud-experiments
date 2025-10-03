#!/usr/bin/env bash
#
# Generate state.yml from template using environment variables
#
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEMPLATE_FILE="${SCRIPT_DIR}/conf/state.yml.template"
OUTPUT_FILE="${SCRIPT_DIR}/conf/state.yml"

# Check required environment variables
required_vars=("ARM_SUBSCRIPTION_ID" "ARM_TENANT_ID" "TF_BACKEND_RG" "TF_BACKEND_SA")
missing_vars=()

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    missing_vars+=("$var")
  fi
done

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo "Error: Missing required environment variables:"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  echo ""
  echo "Run: source ./setup-env.sh"
  exit 1
fi

# Generate state.yml from template
sed -e "s/SUBSCRIPTION_ID_PLACEHOLDER/${ARM_SUBSCRIPTION_ID}/g" \
    -e "s/TENANT_ID_PLACEHOLDER/${ARM_TENANT_ID}/g" \
    -e "s/BACKEND_RG_PLACEHOLDER/${TF_BACKEND_RG}/g" \
    -e "s/BACKEND_SA_PLACEHOLDER/${TF_BACKEND_SA}/g" \
    "${TEMPLATE_FILE}" > "${OUTPUT_FILE}"

echo "Generated ${OUTPUT_FILE} with:"
echo "  Subscription ID: ${ARM_SUBSCRIPTION_ID}"
echo "  Tenant ID: ${ARM_TENANT_ID}"
echo "  Backend RG: ${TF_BACKEND_RG}"
echo "  Backend SA: ${TF_BACKEND_SA}"
echo ""
echo "Note: This file contains your backend configuration and should NOT be"
echo "committed to version control (it's in .gitignore)"
