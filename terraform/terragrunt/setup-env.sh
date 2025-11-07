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

# ---------------------------------------------------------------------------
# Selection helpers (borrowed from subnet-calculator selection utilities)
# ---------------------------------------------------------------------------

select_from_list() {
  local prompt="$1"
  shift
  local items=("$@")
  local count=${#items[@]}

  if [[ "${count}" -eq 0 ]]; then
    return 1
  fi

  local i=1
  for item in "${items[@]}"; do
    echo "  ${i}. ${item}" >/dev/tty
    ((i++))
  done
  echo "" >/dev/tty

  local selection
  while true; do
    read -r -p "${prompt} (1-${count}) or name: " selection

    if [[ -z "${selection}" ]]; then
      echo "Selection is required" >&2
      continue
    fi

    if [[ "${selection}" =~ ^[0-9]+$ ]]; then
      if [[ "${selection}" -ge 1 && "${selection}" -le "${count}" ]]; then
        local selected_item="${items[$((selection - 1))]}"
        local selected_name
        selected_name=$(echo "${selected_item}" | awk '{print $1}')
        printf "%s" "${selected_name}"
        return 0
      else
        echo "Invalid selection. Enter a number between 1 and ${count}" >&2
        continue
      fi
    else
      for item in "${items[@]}"; do
        local item_name
        item_name=$(echo "${item}" | awk '{print $1}')
        if [[ "${item_name}" == "${selection}" ]]; then
          printf "%s" "${selection}"
          return 0
        fi
      done
      echo "Invalid selection '${selection}'. Enter number (1-${count}) or exact name" >&2
    fi
  done
}

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
    declare -a rg_items=()
    while IFS=$'\t' read -r name location; do
      rg_items+=("${name} (${location})")
    done < <(az group list --query "[].[name,location]" -o tsv)
    RESOURCE_GROUP=$(select_from_list "Select resource group for state storage" "${rg_items[@]}")
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
  mapfile -t TFSTATE_ROWS < <(az storage account list \
    --resource-group "${TF_BACKEND_RG}" \
    --query "[?tags.purpose=='terraform-state'].[name,location]" \
    -o tsv)

  TFSTATE_COUNT=${#TFSTATE_ROWS[@]}

  if [[ "${TFSTATE_COUNT}" -eq 1 ]]; then
    IFS=$'\t' read -r TF_BACKEND_SA _ <<<"${TFSTATE_ROWS[0]}"
    TF_BACKEND_CONTAINER="terraform-states"
    echo "✓ Found terraform state storage account: ${TF_BACKEND_SA} (tag purpose=terraform-state)"
  elif [[ "${TFSTATE_COUNT}" -gt 1 ]]; then
    echo "Found ${TFSTATE_COUNT} storage accounts tagged purpose=terraform-state:"
    declare -a sa_items=()
    for row in "${TFSTATE_ROWS[@]}"; do
      IFS=$'\t' read -r name location <<<"${row}"
      sa_items+=("${name} (${location})")
    done
    TF_BACKEND_SA=$(select_from_list "Select storage account" "${sa_items[@]}")
    TF_BACKEND_CONTAINER="terraform-states"
  else
    echo "No storage account tagged purpose=terraform-state found. Creating one..."

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

  # Ensure container exists for selected storage account
  if [[ -n "${TF_BACKEND_SA:-}" ]]; then
    if ! az storage container show --name "${TF_BACKEND_CONTAINER}" --account-name "${TF_BACKEND_SA}" --auth-mode login &>/dev/null 2>&1; then
      echo "→ Creating container: ${TF_BACKEND_CONTAINER}"
      az storage container create \
        --name "${TF_BACKEND_CONTAINER}" \
        --account-name "${TF_BACKEND_SA}" \
        --auth-mode login
    fi
  fi
fi

# Check data-plane RBAC on storage account
STORAGE_SCOPE=$(az storage account show --name "${TF_BACKEND_SA}" --resource-group "${TF_BACKEND_RG}" --query id -o tsv)
CURRENT_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)

if [[ -n "${CURRENT_OBJECT_ID}" ]]; then
  ROLE_MATCH=$(az role assignment list \
    --assignee "${CURRENT_OBJECT_ID}" \
    --scope "${STORAGE_SCOPE}" \
    --query "[?roleDefinitionName=='Storage Blob Data Contributor' || roleDefinitionName=='Storage Blob Data Owner' || roleDefinitionName=='Owner'].roleDefinitionName" \
    -o tsv)

  if [[ -n "${ROLE_MATCH}" ]]; then
    echo "✓ Storage data-plane role detected for current identity: ${ROLE_MATCH}"
  else
    echo "⚠️  Current identity is missing Storage Blob Data permissions on ${TF_BACKEND_SA}."
    read -r -p "Grant Storage Blob Data Contributor role to this identity now? (y/N): " grant_role
    grant_role=${grant_role:-n}
    if [[ "${grant_role}" =~ ^[Yy]$ ]]; then
      echo "→ Assigning Storage Blob Data Contributor role..."
      az role assignment create \
        --role "Storage Blob Data Contributor" \
        --assignee "${CURRENT_OBJECT_ID}" \
        --scope "${STORAGE_SCOPE}" \
        --only-show-errors >/dev/null
      echo "✓ Role assignment requested. Propagation can take up to a minute."
    else
      echo "    Skipped automatic role assignment."
      echo "    You can run:"
      echo "      az role assignment create --role \"Storage Blob Data Contributor\" \\"
      echo "        --assignee ${CURRENT_OBJECT_ID} --scope ${STORAGE_SCOPE}"
      echo ""
    fi
  fi
else
  echo "⚠️  Unable to resolve signed-in user object ID (skipping storage RBAC check)."
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
echo "Copy and paste these commands into your shell (bash or zsh):"
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
echo "Or add them to your shell profile:"
echo "  • Bash: ~/.bashrc"
echo "  • Zsh:  ~/.zshrc"
echo ""
echo "NuShell equivalent (add to ~/.config/nushell/env.nu):"
echo "================================================================"
echo ""
echo "let-env ARM_SUBSCRIPTION_ID '${ARM_SUBSCRIPTION_ID}'"
echo "let-env ARM_TENANT_ID '${ARM_TENANT_ID}'"
echo "let-env TF_BACKEND_RG '${TF_BACKEND_RG}'"
echo "let-env TF_BACKEND_SA '${TF_BACKEND_SA}'"
echo "let-env TF_BACKEND_CONTAINER '${TF_BACKEND_CONTAINER}'"
echo ""
echo "================================================================"
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
