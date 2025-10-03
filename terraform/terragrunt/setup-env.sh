#!/usr/bin/env bash
#
# Set up environment variables for Terragrunt
# - Gets current Azure subscription and tenant IDs
# - Prompts for backend storage details
# - Prints export commands for you to run
#
# Usage: ./setup-env.sh [--group resource-group-name]
#
set -euo pipefail

# Parse arguments
RESOURCE_GROUP=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --group)
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./setup-env.sh [--group resource-group-name]"
      exit 1
      ;;
  esac
done

echo "Terragrunt Environment Setup"
echo "============================"
echo ""

# Check if all required variables are already set and valid
if [[ -n "${ARM_SUBSCRIPTION_ID:-}" ]] && \
   [[ -n "${ARM_TENANT_ID:-}" ]] && \
   [[ -n "${TF_BACKEND_RG:-}" ]] && \
   [[ -n "${TF_BACKEND_SA:-}" ]] && \
   [[ -n "${TF_BACKEND_CONTAINER:-}" ]]; then

  echo "✓ Environment variables already set:"
  echo "  ARM_SUBSCRIPTION_ID: ${ARM_SUBSCRIPTION_ID}"
  echo "  ARM_TENANT_ID: ${ARM_TENANT_ID}"
  echo "  TF_BACKEND_RG: ${TF_BACKEND_RG}"
  echo "  TF_BACKEND_SA: ${TF_BACKEND_SA}"
  echo "  TF_BACKEND_CONTAINER: ${TF_BACKEND_CONTAINER}"
  echo ""

  # Verify storage account exists
  if az storage account show --name "${TF_BACKEND_SA}" --resource-group "${TF_BACKEND_RG}" --only-show-errors &>/dev/null 2>&1; then
    echo "✓ Storage account verified"

    # Show storage account details
    echo ""
    echo "Storage account details:"
    az storage account show \
      --name "${TF_BACKEND_SA}" \
      --resource-group "${TF_BACKEND_RG}" \
      --query "{Name:name, Location:location, SKU:sku.name, Created:creationTime}" \
      -o table

    # List containers
    echo ""
    echo "Containers:"
    az storage container list \
      --account-name "${TF_BACKEND_SA}" \
      --auth-mode login \
      --query "[].[name]" \
      -o tsv | awk '{printf "  - %s\n", $1}'

    echo ""
    echo "Environment is ready! Next steps:"
    echo "  make check-env         # Verify variables"
    echo "  make app-a-init        # Initialize Terragrunt"
    echo "  make app-a-plan        # Plan deployment"
    echo ""
    read -r -p "Re-configure environment? (y/N): " reconfigure
    reconfigure=${reconfigure:-n}
    if [[ ! "${reconfigure}" =~ ^[Yy]$ ]]; then
      exit 0
    fi

    echo ""
    echo "Re-configuring..."
    unset ARM_SUBSCRIPTION_ID ARM_TENANT_ID TF_BACKEND_RG TF_BACKEND_SA TF_BACKEND_CONTAINER
  else
    echo "⚠️  Storage account '${TF_BACKEND_SA}' not found"
    echo "Re-running setup..."
    echo ""
    unset ARM_SUBSCRIPTION_ID ARM_TENANT_ID TF_BACKEND_RG TF_BACKEND_SA TF_BACKEND_CONTAINER
  fi
fi

# Check if Azure CLI is installed
if ! command -v az &>/dev/null; then
  echo "❌ Azure CLI is not installed"
  echo "On macOS install with: brew install azure-cli"
  exit 1
fi

# Check if logged in
if ! az account show --only-show-errors &>/dev/null; then
  echo "❌ Azure CLI: not logged in"
  echo "Please log in by running: az login"
  exit 1
fi

echo "✓ Azure CLI: logged in"
echo ""
az account show --query "{Name:name,SubscriptionId:id,User:user.name}" -o table
echo ""

# Get current subscription details
ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
ARM_TENANT_ID=$(az account show --query tenantId -o tsv)

echo "Current Azure context:"
echo "  Subscription ID: ${ARM_SUBSCRIPTION_ID}"
echo "  Tenant ID: ${ARM_TENANT_ID}"
echo ""

# Detect or prompt for resource group
if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "Detecting resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    echo "❌ No resource groups found in subscription"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    # Auto-select the only resource group
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    echo "✓ Found single resource group: ${RESOURCE_GROUP}"
    echo ""
    read -r -p "Use this resource group for backend storage? (Y/n): " confirm
    confirm=${confirm:-y}  # Default to yes if empty
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      echo "Cancelled"
      exit 1
    fi
  else
    # Multiple resource groups - show list
    echo "Available resource groups:"
    az group list --query "[].[name,location]" -o tsv | awk '{printf "  - %s (%s)\n", $1, $2}'
    echo ""
    read -r -p "Enter resource group name for state storage: " RESOURCE_GROUP
  fi
fi

TF_BACKEND_RG="${RESOURCE_GROUP}"

# Backend storage configuration
echo ""
echo "Backend storage configuration:"
echo "Resource Group: ${TF_BACKEND_RG}"
echo ""

# Check if environment variables are already set
if [[ -n "${TF_BACKEND_SA:-}" ]] && [[ -n "${TF_BACKEND_CONTAINER:-}" ]]; then
  # Verify the storage account exists
  if az storage account show --name "${TF_BACKEND_SA}" --resource-group "${TF_BACKEND_RG}" --only-show-errors &>/dev/null; then
    echo "✓ Found existing storage account: ${TF_BACKEND_SA}"
    echo "  Container: ${TF_BACKEND_CONTAINER}"
    echo ""
    read -r -p "Use this configuration? (Y/n): " use_existing
    use_existing=${use_existing:-y}
    if [[ "${use_existing}" =~ ^[Yy]$ ]]; then
      # Keep the existing values
      :
    else
      unset TF_BACKEND_SA TF_BACKEND_CONTAINER
    fi
  else
    echo "⚠️  Storage account '${TF_BACKEND_SA}' not found"
    unset TF_BACKEND_SA TF_BACKEND_CONTAINER
  fi
fi

# Auto-detect storage if not set
if [[ -z "${TF_BACKEND_SA:-}" ]]; then
  # Check for storage accounts matching our pattern (sttfstate*)
  TFSTATE_ACCOUNTS=$(az storage account list --resource-group "${TF_BACKEND_RG}" --query "[?starts_with(name, 'sttfstate')].name" -o tsv)
  TFSTATE_COUNT=$(echo "${TFSTATE_ACCOUNTS}" | grep -c "^sttfstate" || true)

  if [[ "${TFSTATE_COUNT}" -eq 1 ]]; then
    # Found exactly one matching storage account
    TF_BACKEND_SA=$(echo "${TFSTATE_ACCOUNTS}" | head -n 1)
    TF_BACKEND_CONTAINER="terraform-states"

    echo "✓ Found terraform state storage account: ${TF_BACKEND_SA}"

    # Check if container exists
    if az storage container show --name "${TF_BACKEND_CONTAINER}" --account-name "${TF_BACKEND_SA}" --auth-mode login &>/dev/null 2>&1; then
      echo "✓ Container exists: ${TF_BACKEND_CONTAINER}"
      echo ""
      read -r -p "Use this storage account? (Y/n): " use_storage
      use_storage=${use_storage:-y}
      if [[ ! "${use_storage}" =~ ^[Yy]$ ]]; then
        unset TF_BACKEND_SA TF_BACKEND_CONTAINER
      fi
    else
      echo "→ Creating container: ${TF_BACKEND_CONTAINER}"
      az storage container create \
        --name "${TF_BACKEND_CONTAINER}" \
        --account-name "${TF_BACKEND_SA}" \
        --auth-mode login
    fi
  elif [[ "${TFSTATE_COUNT}" -gt 1 ]]; then
    # Multiple matching accounts - let user choose
    echo "Found ${TFSTATE_COUNT} terraform state storage accounts:"
    echo "${TFSTATE_ACCOUNTS}" | awk '{printf "  - %s\n", $1}'
    echo ""
    read -r -p "Enter storage account name: " TF_BACKEND_SA
    TF_BACKEND_CONTAINER="terraform-states"

    # Ensure container exists
    if ! az storage container show --name "${TF_BACKEND_CONTAINER}" --account-name "${TF_BACKEND_SA}" --auth-mode login &>/dev/null 2>&1; then
      echo "→ Creating container: ${TF_BACKEND_CONTAINER}"
      az storage container create \
        --name "${TF_BACKEND_CONTAINER}" \
        --account-name "${TF_BACKEND_SA}" \
        --auth-mode login
    fi
  else
    # No matching storage accounts - create one
    echo "No terraform state storage account found. Creating one..."

    TF_BACKEND_SA="sttfstate$(date +%Y%m%d%H%M)"
    TF_BACKEND_CONTAINER="terraform-states"
    RG_LOCATION=$(az group show --name "${TF_BACKEND_RG}" --query location -o tsv)

    echo "→ Creating storage account: ${TF_BACKEND_SA}"
    az storage account create \
      --name "${TF_BACKEND_SA}" \
      --resource-group "${TF_BACKEND_RG}" \
      --location "${RG_LOCATION}" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --allow-blob-public-access false \
      --min-tls-version TLS1_2 \
      --tags "purpose=terraform-state" "managed_by=terragrunt"

    echo "→ Creating container: ${TF_BACKEND_CONTAINER}"
    az storage container create \
      --name "${TF_BACKEND_CONTAINER}" \
      --account-name "${TF_BACKEND_SA}" \
      --auth-mode login

    echo "✓ Storage created successfully"
  fi
fi

# Configure terraform.tfvars
TFVARS_FILE="ps-az-sbx/app-a/terraform.tfvars"
TFVARS_EXAMPLE="ps-az-sbx/app-a/terraform.tfvars.example"

if [[ ! -f "${TFVARS_FILE}" ]] && [[ -f "${TFVARS_EXAMPLE}" ]]; then
  echo ""
  echo "→ Creating ${TFVARS_FILE} from example"
  cp "${TFVARS_EXAMPLE}" "${TFVARS_FILE}"
fi

# Only auto-update RG if single resource group (Pluralsight pattern)
# For test subscriptions with multiple RGs, user must manually set workload RG
if [[ "${RG_COUNT}" -eq 1 ]] && [[ -f "${TFVARS_FILE}" ]]; then
  echo "→ Updating resource group in ${TFVARS_FILE}"
  sed -i.bak "s/existing_resource_group_name = \".*\"/existing_resource_group_name = \"${TF_BACKEND_RG}\"/" "${TFVARS_FILE}"
  rm -f "${TFVARS_FILE}.bak"
  echo "✓ Updated: existing_resource_group_name = \"${TF_BACKEND_RG}\""
elif [[ -f "${TFVARS_FILE}" ]]; then
  echo "→ terraform.tfvars created (update existing_resource_group_name for your workload)"
fi

echo ""
echo "✓ Configuration complete!"
echo ""
echo "================================================================"
echo "Copy and paste these commands into your shell:"
echo "================================================================"
echo ""
echo "export ARM_SUBSCRIPTION_ID='${ARM_SUBSCRIPTION_ID}'"
echo "export ARM_TENANT_ID='${ARM_TENANT_ID}'"
echo "export TF_BACKEND_RG='${TF_BACKEND_RG}'"
echo "export TF_BACKEND_SA='${TF_BACKEND_SA}'"
echo "export TF_BACKEND_CONTAINER='${TF_BACKEND_CONTAINER}'"
echo ""
echo "================================================================"
echo ""
echo "Or add them to your shell profile (~/.zshrc or ~/.bashrc)"
echo ""
echo "Next steps:"
echo "  1. Run the export commands above"
echo "  2. make check-env               # Verify variables are set"
if [[ "${RG_COUNT}" -gt 1 ]]; then
  echo "  3. Edit ps-az-sbx/app-a/terraform.tfvars with your workload resource group"
  echo "  4. make app-a-init              # Initialize"
  echo "  5. make app-a-plan              # Plan"
else
  echo "  3. make app-a-init              # Initialize"
  echo "  4. make app-a-plan              # Plan"
fi
