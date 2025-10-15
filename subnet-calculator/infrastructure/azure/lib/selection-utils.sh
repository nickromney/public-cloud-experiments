#!/usr/bin/env bash
#
# selection-utils.sh - Shared utilities for interactive selection prompts
#
# Provides numbered selection from lists with support for both
# number selection and full name input.

# select_from_list - Display numbered list and prompt for selection
#
# Usage:
#   result=$(select_from_list "prompt message" "${items[@]}")
#
# Arguments:
#   $1 - Prompt message (e.g., "Enter resource group")
#   $2+ - Array of items to select from (can include metadata after first field)
#
# Returns:
#   Selected item's first field (name)
#
# Example:
#   items=("rg-test (eastus)" "rg-prod (westus)")
#   result=$(select_from_list "Enter resource group" "${items[@]}")
#   # User sees:
#   #   1. rg-test (eastus)
#   #   2. rg-prod (westus)
#   # User enters: 1
#   # Result: "rg-test"
#
select_from_list() {
  local prompt="$1"
  shift
  local items=("$@")
  local count=${#items[@]}

  # Display numbered list
  local i=1
  for item in "${items[@]}"; do
    echo "  ${i}. ${item}"
    ((i++))
  done
  echo ""

  # Prompt for selection
  local selection
  while true; do
    read -r -p "${prompt} (1-${count}) or name: " selection

    # Check if empty
    if [[ -z "${selection}" ]]; then
      echo "Selection is required" >&2
      continue
    fi

    # Check if it's a number
    if [[ "${selection}" =~ ^[0-9]+$ ]]; then
      # Validate number is in range
      if [[ "${selection}" -ge 1 && "${selection}" -le "${count}" ]]; then
        # Get item at index (bash arrays are 0-indexed)
        local selected_item="${items[$((selection - 1))]}"
        # Extract first field (name) before any space or parenthesis
        local selected_name
        selected_name=$(echo "${selected_item}" | awk '{print $1}')
        echo "${selected_name}"
        return 0
      else
        echo "Invalid selection. Please enter a number between 1 and ${count}" >&2
        continue
      fi
    else
      # User entered a name - validate it exists in the list
      for item in "${items[@]}"; do
        local item_name
        item_name=$(echo "${item}" | awk '{print $1}')
        if [[ "${item_name}" == "${selection}" ]]; then
          echo "${selection}"
          return 0
        fi
      done

      # Name not found (loop completed without return)
      echo "Invalid selection '${selection}'. Please enter a number (1-${count}) or exact name" >&2
      continue
    fi
  done
}

# select_resource_group - Specialized function for resource group selection
#
# Usage:
#   RESOURCE_GROUP=$(select_resource_group)
#
# Automatically queries Azure for resource groups and prompts for selection
#
select_resource_group() {
  local -a items
  local -a names
  local -a locations

  # Get resource groups
  while IFS=$'\t' read -r name location; do
    names+=("${name}")
    locations+=("${location}")
    items+=("${name} (${location})")
  done < <(az group list --query "[].[name,location]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No resource groups found in subscription" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single resource group
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter resource group" "${items[@]}"
    return $?
  fi
}

# select_function_app - Specialized function for Function App selection
#
# Usage:
#   FUNCTION_APP_NAME=$(select_function_app "${RESOURCE_GROUP}")
#
# Arguments:
#   $1 - Resource group name
#
select_function_app() {
  local resource_group="$1"
  local -a items
  local -a names

  # Get function apps
  while IFS=$'\t' read -r name hostname; do
    names+=("${name}")
    items+=("${name} (https://${hostname})")
  done < <(az functionapp list --resource-group "${resource_group}" --query "[].[name,defaultHostName]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No Function Apps found in resource group ${resource_group}" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single function app
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter Function App" "${items[@]}"
    return $?
  fi
}

# select_static_web_app - Specialized function for Static Web App selection
#
# Usage:
#   STATIC_WEB_APP_NAME=$(select_static_web_app "${RESOURCE_GROUP}")
#
# Arguments:
#   $1 - Resource group name
#
select_static_web_app() {
  local resource_group="$1"
  local -a items
  local -a names

  # Get static web apps
  while IFS=$'\t' read -r name hostname; do
    names+=("${name}")
    items+=("${name} (https://${hostname})")
  done < <(az staticwebapp list --resource-group "${resource_group}" --query "[].[name,defaultHostname]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No Static Web Apps found in resource group ${resource_group}" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single static web app
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter Static Web App" "${items[@]}"
    return $?
  fi
}

# select_storage_account - Specialized function for Storage Account selection
#
# Usage:
#   STORAGE_ACCOUNT_NAME=$(select_storage_account "${RESOURCE_GROUP}")
#
# Arguments:
#   $1 - Resource group name
#
select_storage_account() {
  local resource_group="$1"
  local -a items
  local -a names

  # Get storage accounts
  while IFS=$'\t' read -r name location; do
    names+=("${name}")
    items+=("${name} (${location})")
  done < <(az storage account list --resource-group "${resource_group}" --query "[].[name,location]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No storage accounts found in resource group ${resource_group}" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single storage account
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter storage account" "${items[@]}"
    return $?
  fi
}

# select_apim_instance - Specialized function for API Management instance selection
#
# Usage:
#   APIM_NAME=$(select_apim_instance "${RESOURCE_GROUP}")
#
# Arguments:
#   $1 - Resource group name
#
select_apim_instance() {
  local resource_group="$1"
  local -a items
  local -a names

  # Get APIM instances
  while IFS=$'\t' read -r name gateway_url; do
    names+=("${name}")
    items+=("${name} (${gateway_url})")
  done < <(az apim list --resource-group "${resource_group}" --query "[].[name,gatewayUrl]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No API Management instances found in resource group ${resource_group}" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single APIM instance
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter API Management instance" "${items[@]}"
    return $?
  fi
}

# select_app_service_plan - Specialized function for App Service Plan selection
#
# Usage:
#   PLAN_NAME=$(select_app_service_plan "${RESOURCE_GROUP}")
#
# Arguments:
#   $1 - Resource group name
#
select_app_service_plan() {
  local resource_group="$1"
  local -a items
  local -a names

  # Get app service plans
  while IFS=$'\t' read -r name sku location; do
    names+=("${name}")
    items+=("${name} (${sku}, ${location})")
  done < <(az appservice plan list --resource-group "${resource_group}" --query "[].[name,sku.name,location]" -o tsv)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No App Service Plans found in resource group ${resource_group}" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single plan
    echo "${names[0]}"
    return 0
  else
    # Multiple - prompt for selection
    select_from_list "Enter App Service Plan" "${items[@]}"
    return $?
  fi
}
