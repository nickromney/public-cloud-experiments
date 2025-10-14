#!/usr/bin/env bash
#
# Set up environment variables for subnet calculator Azure deployment
# - Detects Azure subscription and resource group
# - Supports single RG auto-detection (Pluralsight sandbox pattern)
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

echo "Subnet Calculator - Azure Deployment Setup"
echo "==========================================="
echo ""

# Check if all required variables are already set and valid
if [[ -n "${RESOURCE_GROUP:-}" ]]; then
  echo "✓ RESOURCE_GROUP already set: ${RESOURCE_GROUP}"
  echo ""

  # Verify resource group exists
  if az group show --name "${RESOURCE_GROUP}" --only-show-errors &>/dev/null 2>&1; then
    echo "✓ Resource group verified"

    # Show resource group details
    echo ""
    echo "Resource group details:"
    az group show \
      --name "${RESOURCE_GROUP}" \
      --query "{Name:name, Location:location, ID:id}" \
      -o table

    echo ""
    echo "Environment is ready! Next steps:"
    echo "  make create-all        # Create infrastructure"
    echo "  make deploy-all        # Deploy application"
    echo "  make show-urls         # Show deployment URLs"
    echo ""
    read -r -p "Re-configure environment? (y/N): " reconfigure
    reconfigure=${reconfigure:-n}
    if [[ ! "${reconfigure}" =~ ^[Yy]$ ]]; then
      exit 0
    fi

    echo ""
    echo "Re-configuring..."
    unset RESOURCE_GROUP
  else
    echo "⚠️  Resource group '${RESOURCE_GROUP}' not found"
    echo "Re-running setup..."
    echo ""
    unset RESOURCE_GROUP
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

# Detect or prompt for resource group
if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "Detecting resource groups..."
  RG_COUNT=$(az group list --query "length(@)" -o tsv)

  if [[ "${RG_COUNT}" -eq 0 ]]; then
    echo "❌ No resource groups found in subscription"
    echo ""
    echo "This script requires at least one resource group."
    echo "In a Pluralsight sandbox, a resource group is pre-created."
    echo "In your own subscription, create one with:"
    echo "  az group create --name rg-subnet-calc --location eastus"
    exit 1
  elif [[ "${RG_COUNT}" -eq 1 ]]; then
    # Auto-select the only resource group (Pluralsight sandbox pattern)
    RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)
    RG_LOCATION=$(az group list --query "[0].location" -o tsv)
    echo "✓ Found single resource group: ${RESOURCE_GROUP} (${RG_LOCATION})"
    echo ""
    echo "This appears to be a Pluralsight sandbox or constrained environment."
    echo "Using the only available resource group for all deployments."
    echo ""
    read -r -p "Use this resource group? (Y/n): " confirm
    confirm=${confirm:-y}
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      echo "Cancelled"
      exit 1
    fi
  else
    # Multiple resource groups - show list and prompt
    echo "Available resource groups:"
    az group list --query "[].[name,location]" -o tsv | awk '{printf "  - %s (%s)\n", $1, $2}'
    echo ""
    read -r -p "Enter resource group name to use: " RESOURCE_GROUP

    # Verify the selected resource group exists
    if ! az group show --name "${RESOURCE_GROUP}" --only-show-errors &>/dev/null 2>&1; then
      echo "❌ Resource group '${RESOURCE_GROUP}' not found"
      exit 1
    fi
  fi
fi

# Get resource group location for reference
RG_LOCATION=$(az group show --name "${RESOURCE_GROUP}" --query location -o tsv)

# Auto-detect PUBLISHER_EMAIL from Azure account (required for APIM)
PUBLISHER_EMAIL=$(az account show --query user.name -o tsv)

echo ""
echo "✓ Configuration complete!"
echo ""
echo "================================================================"
echo "Copy and paste these commands into your shell:"
echo "================================================================"
echo ""
echo "export RESOURCE_GROUP='${RESOURCE_GROUP}'"
echo "export PUBLISHER_EMAIL='${PUBLISHER_EMAIL}'"
echo ""
echo "================================================================"
echo ""
echo "Or add it to your shell profile (~/.zshrc or ~/.bashrc)"
echo ""
echo "Configuration:"
echo "  Resource Group: ${RESOURCE_GROUP}"
echo "  Location: ${RG_LOCATION}"
echo "  Publisher Email: ${PUBLISHER_EMAIL}"
echo ""
echo "Next steps:"
echo "  1. Run the export command above"
echo "  2. make create-all         # Create Static Web App + Function App"
echo "  3. make deploy-all         # Deploy TypeScript frontend + API"
echo "  4. make show-urls          # Show deployment URLs"
echo "  5. make test-api           # Test Function API (after deployment)"
echo ""
echo "Quick deployment for sandboxes:"
echo "  make sandbox-deploy        # One command to deploy everything"
echo ""
echo "Note: All scripts will use RESOURCE_GROUP='${RESOURCE_GROUP}'"
echo "      Location will be detected from the resource group (${RG_LOCATION})"
echo ""
