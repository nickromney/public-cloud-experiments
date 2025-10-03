#!/usr/bin/env bash
#
# Set up environment variables for tfwrapper
# - Gets current Azure subscription and tenant IDs
# - Prompts for backend storage details
#
set -euo pipefail

# Check if Azure CLI is installed
if ! command -v az &>/dev/null; then
  echo "Azure CLI is not installed"
  echo "On macOS install with 'brew install azure-cli'"
  exit 1
fi

# Check if logged in
if ! az account show --only-show-errors &>/dev/null; then
  echo "Azure CLI: not logged in"
  echo "Please log in by running: az login --use-device-code"
  exit 1
fi

echo "Azure CLI: logged in"
az account show --query "{Name:name,SubscriptionId:id,User:user.name}" -o table
echo ""

# Get current subscription details
ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ARM_TENANT_ID=$(az account show --query tenantId -o tsv)
export ARM_SUBSCRIPTION_ID
export ARM_TENANT_ID

echo "Current Azure context:"
echo "  Subscription ID: ${ARM_SUBSCRIPTION_ID}"
echo "  Tenant ID: ${ARM_TENANT_ID}"
echo ""

# Backend storage configuration
echo "Backend storage configuration:"
echo "You need an existing storage account for Terraform state."
echo "Ensure you have the 'Storage Blob Data Owner' role on the storage account."
echo ""

# Check if environment variables are already set
if [[ -n "${TF_BACKEND_RG:-}" ]] && [[ -n "${TF_BACKEND_SA:-}" ]]; then
  echo "Using existing backend configuration:"
  echo "  Resource Group: ${TF_BACKEND_RG}"
  echo "  Storage Account: ${TF_BACKEND_SA}"
else
  echo "Enter backend storage details (or press Ctrl+C to set them manually):"
  read -r -p "Resource Group name for state storage: " TF_BACKEND_RG
  read -r -p "Storage Account name for state storage: " TF_BACKEND_SA

  export TF_BACKEND_RG
  export TF_BACKEND_SA
fi

echo ""
echo "Environment variables set (for state.yml generation):"
echo "  ARM_SUBSCRIPTION_ID='${ARM_SUBSCRIPTION_ID}'"
echo "  ARM_TENANT_ID='${ARM_TENANT_ID}'"
echo "  TF_BACKEND_RG='${TF_BACKEND_RG}'"
echo "  TF_BACKEND_SA='${TF_BACKEND_SA}'"
echo ""
echo "Next step: Run ./generate-state-config.sh to create conf/state.yml"
