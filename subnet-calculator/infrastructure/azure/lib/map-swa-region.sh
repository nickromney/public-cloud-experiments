#!/usr/bin/env bash
#
# Map Azure region to Static Web Apps compatible region
#
# Azure Static Web Apps managed functions are only available in specific regions:
#   - westus2, centralus, eastus2, westeurope, eastasia
#
# This utility maps common regions to the nearest SWA-compatible region.
#
# Usage:
#   source ./lib/map-swa-region.sh
#   SWA_REGION=$(map_swa_region "uksouth")
#   echo "${SWA_REGION}"  # Output: westeurope
#
# Parameters:
#   $1 - Input region (e.g., uksouth, northeurope, eastus, etc.)
#
# Output:
#   Mapped region that is compatible with Static Web Apps
#

map_swa_region() {
  local input_region="${1:?Region required}"

  # Normalize: lowercase and remove spaces
  local normalized_region
  normalized_region=$(echo "${input_region}" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

  # Map to SWA-compatible region
  # Available SWA regions: westus2, centralus, eastus2, westeurope, eastasia
  case "${normalized_region}" in
    # Western US regions → westus2
    westus|westus3)
      echo "westus2"
      ;;

    # Eastern US regions → eastus2
    eastus|eastus3)
      echo "eastus2"
      ;;

    # Already compatible with SWA
    centralus|westus2|eastus2|eastasia)
      echo "${normalized_region}"
      ;;

    # European regions (including UK) → westeurope
    # westeurope is default for EU/UK deployments
    westeurope|uksouth|ukwest|northeurope|francecentral|francesouth|\
    germanywestcentral|norwayeast|norwaywest|swedencentral|\
    switzerlandnorth|switzerlandwest)
      echo "westeurope"
      ;;

    # Asian regions → eastasia
    southeastasia|japaneast|japanwest|koreacentral)
      echo "eastasia"
      ;;

    # Default: westeurope (good for EU/UK deployments)
    *)
      echo "westeurope"
      ;;
  esac
}

# If sourced and called directly (not sourced as a library), execute the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 REGION"
    echo "Examples:"
    echo "  $0 uksouth      # Output: westeurope"
    echo "  $0 eastus       # Output: eastus2"
    echo "  $0 centralus    # Output: centralus"
    exit 1
  fi
  map_swa_region "$1"
fi
