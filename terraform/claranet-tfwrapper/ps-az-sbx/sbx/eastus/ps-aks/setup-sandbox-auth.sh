#!/bin/bash

# Setup script for Pluralsight sandbox authentication and state storage
# Run this from within a stack directory (alongside main.tf)

set -e

echo "Pluralsight Azure Sandbox Setup"
echo "================================"
echo ""

# Get the script's directory (should be the stack directory)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STACK_DIR="$SCRIPT_DIR"

# Validate we're in a stack directory with main.tf
if [ ! -f "$STACK_DIR/main.tf" ]; then
    echo "❌ ERROR: No main.tf found in current directory"
    echo ""
    echo "This script must be run from within a Terraform stack directory"
    echo "that contains main.tf (e.g., ps-az-sbx/sbx/eastus/ps-aks/)"
    echo ""
    echo "Current directory: $SCRIPT_DIR"
    echo ""
    exit 1
fi

# Extract account, environment, region, and stack from the path
# Expected structure: .../account/environment/region/stack/
STACK_NAME=$(basename "$STACK_DIR")
REGION_NAME=$(basename "$(dirname "$STACK_DIR")")
ENV_NAME=$(basename "$(dirname "$(dirname "$STACK_DIR")")")
ACCOUNT_NAME=$(basename "$(dirname "$(dirname "$(dirname "$STACK_DIR")")")")

# Validate the structure looks correct
if [ -z "$STACK_NAME" ] || [ -z "$REGION_NAME" ] || [ -z "$ENV_NAME" ] || [ -z "$ACCOUNT_NAME" ]; then
    echo "⚠️  WARNING: Could not determine full tfwrapper structure"
    echo "   Expected: account/environment/region/stack/"
    echo "   Found: $ACCOUNT_NAME/$ENV_NAME/$REGION_NAME/$STACK_NAME"
    echo ""
fi

echo "✓ Found Terraform stack:"
echo "  Account: $ACCOUNT_NAME"
echo "  Environment: $ENV_NAME"
echo "  Region: $REGION_NAME"
echo "  Stack: $STACK_NAME"
echo "  Path: $STACK_DIR"
echo ""

echo "You'll need the following from your sandbox credentials:"
echo "  - Subscription ID"
echo "  - Application Client ID (Service Principal)"
echo "  - Client Secret (Password)"
echo "  - Resource Group Name (provided by sandbox)"
echo ""
echo "Note: We'll get the Tenant ID automatically after login"
echo ""

# Prompt for credentials
read -r -p "Enter Subscription ID: " SUBSCRIPTION_ID
read -r -p "Enter Application Client ID: " CLIENT_ID
read -r -s -p "Enter Client Secret (password): " CLIENT_SECRET
echo ""
read -r -p "Enter the sandbox Resource Group name: " RESOURCE_GROUP
echo ""

# Try to login with just the domain name first (common for Pluralsight)
echo "→ Attempting to discover Tenant ID..."
TENANT_DOMAIN="realhandsonlabs.com"

# Login using Service Principal with domain name
echo "→ Logging in with Service Principal..."
az login --service-principal \
    --username "$CLIENT_ID" \
    --password "$CLIENT_SECRET" \
    --tenant "$TENANT_DOMAIN" 2>/dev/null || {
    # If domain doesn't work, prompt for tenant ID
    echo "Domain login failed. Please enter the Tenant ID manually."
    read -r -p "Enter Tenant ID (GUID format): " TENANT_ID
    az login --service-principal \
        --username "$CLIENT_ID" \
        --password "$CLIENT_SECRET" \
        --tenant "$TENANT_ID"
}

# Get the tenant ID from the login
echo "→ Getting Tenant ID from subscription..."
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "   Tenant ID: $TENANT_ID"

# Export environment variables for Terraform
echo "→ Setting up Azure authentication environment..."
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"
export ARM_CLIENT_ID="$CLIENT_ID"
export ARM_CLIENT_SECRET="$CLIENT_SECRET"

# Set subscription
az account set --subscription "$SUBSCRIPTION_ID"

# Use the vended resource group - no creation needed!
echo "→ Using sandbox resource group: $RESOURCE_GROUP"

# Create storage for Terraform state in the existing resource group
STORAGE_ACCOUNT="sttfstateps$(date +%Y%m%d%H%M)"
CONTAINER_NAME="terraform-states"
LOCATION="eastus"

echo "→ Creating storage account: $STORAGE_ACCOUNT in existing resource group..."
az storage account create \
    --name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --tags "purpose=terraform-state" "environment=sandbox"

echo "→ Creating container: $CONTAINER_NAME..."
az storage container create \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT" \
    --auth-mode login

echo ""

# Clean up old Terraform state from previous sandbox
echo "→ Cleaning up old Terraform state..."
if [ -d "${STACK_DIR}/.terraform" ]; then
    rm -rf "${STACK_DIR}/.terraform"
    echo "   ✓ Removed .terraform directory"
fi
if [ -f "${STACK_DIR}/.terraform.lock.hcl" ]; then
    rm -f "${STACK_DIR}/.terraform.lock.hcl"
    echo "   ✓ Removed .terraform.lock.hcl"
fi
if [ -f "${STACK_DIR}/terraform.tfstate" ]; then
    rm -f "${STACK_DIR}/terraform.tfstate"
    echo "   ✓ Removed local terraform.tfstate"
fi
if [ -f "${STACK_DIR}/terraform.tfstate.backup" ]; then
    rm -f "${STACK_DIR}/terraform.tfstate.backup"
    echo "   ✓ Removed terraform.tfstate.backup"
fi

# Automatically create state.tf
echo "→ Creating state.tf..."
cat > "${STACK_DIR}/state.tf" << EOF

terraform {
  backend "azurerm" {
    resource_group_name  = "$RESOURCE_GROUP"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "$CONTAINER_NAME"
    key                  = "${ACCOUNT_NAME}/${ENV_NAME}/${REGION_NAME}/${STACK_NAME}/terraform.state"
    use_azuread_auth     = false  # Using Service Principal
    subscription_id      = "$SUBSCRIPTION_ID"
    tenant_id            = "$TENANT_ID"
    client_id            = "$CLIENT_ID"
    client_secret        = "$CLIENT_SECRET"
  }
}
EOF
echo "   ✓ state.tf created"

# Update terraform.tfvars with subscription_id and resource group
echo "→ Updating terraform.tfvars..."
if [ -f "${STACK_DIR}/terraform.tfvars" ]; then
    # Update subscription_id
    sed -i.bak "s/subscription_id.*=.*/subscription_id = \"$SUBSCRIPTION_ID\"/" "${STACK_DIR}/terraform.tfvars"

    # Update existing_resource_groups
    sed -i.bak "/existing_resource_groups = {/,/}/ s/\"sandbox\".*=.*/  \"sandbox\" = \"$RESOURCE_GROUP\"/" "${STACK_DIR}/terraform.tfvars"

    # Clean up backup file
    rm -f "${STACK_DIR}/terraform.tfvars.bak"
    echo "   ✓ terraform.tfvars updated"
else
    echo "   ⚠ terraform.tfvars not found. Creating from example..."
    cp "${STACK_DIR}/terraform.tfvars.example" "${STACK_DIR}/terraform.tfvars"
    sed -i.bak "s/YOUR_SANDBOX_SUBSCRIPTION_ID/$SUBSCRIPTION_ID/" "${STACK_DIR}/terraform.tfvars"
    sed -i.bak "s/YOUR_SANDBOX_RESOURCE_GROUP_NAME/$RESOURCE_GROUP/" "${STACK_DIR}/terraform.tfvars"
    rm -f "${STACK_DIR}/terraform.tfvars.bak"
fi

echo ""
echo "✅ Setup complete! All files have been configured."
echo ""
echo "Export these environment variables (or add to ~/.bashrc or ~/.zshrc):"
echo "======================================================================"
cat << EOF
export ARM_SUBSCRIPTION_ID="$SUBSCRIPTION_ID"
export ARM_TENANT_ID="$TENANT_ID"
export ARM_CLIENT_ID="$CLIENT_ID"
export ARM_CLIENT_SECRET="$CLIENT_SECRET"
EOF

echo ""
echo "Then run the following commands:"
echo "================================"
echo "cd ../../../../                                       # Return to tfwrapper root directory"
echo "make ${STACK_NAME} init ${ENV_NAME} ${REGION_NAME}   # Initialize Terraform"
echo "make ${STACK_NAME} plan ${ENV_NAME} ${REGION_NAME}   # Review what will be created"
echo "make ${STACK_NAME} apply ${ENV_NAME} ${REGION_NAME}  # Create the resources"
