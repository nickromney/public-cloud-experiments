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

  # Display numbered list (to terminal, not captured by command substitution)
  local i=1
  for item in "${items[@]}"; do
    echo "  ${i}. ${item}" >/dev/tty
    ((i++))
  done
  echo "" >/dev/tty

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

# select_entra_app_registration - Specialized function for Entra ID app registration selection
#
# Usage:
#   AZURE_CLIENT_ID=$(select_entra_app_registration)
#
# Returns the application (client) ID of the selected app registration
#
select_entra_app_registration() {
  local -a items
  local -a app_ids
  local -a display_names

  # Get app registrations (filter for web apps that might be SWA registrations)
  while IFS=$'\t' read -r app_id display_name; do
    app_ids+=("${app_id}")
    display_names+=("${display_name}")
    items+=("${display_name} (${app_id:0:8}...)")
  done < <(az ad app list --query "[?web.redirectUris != null && web.redirectUris != \`[]\`].[appId,displayName]" -o tsv 2>/dev/null)

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "ERROR: No Entra ID app registrations found with redirect URIs" >&2
    return 1
  elif [[ ${#items[@]} -eq 1 ]]; then
    # Auto-select single app registration
    echo "${app_ids[0]}"
    return 0
  else
    # Multiple - prompt for selection
    echo "" >/dev/tty
    echo "Found ${#items[@]} Entra ID app registrations with redirect URIs:" >/dev/tty

    # Use select_from_list which returns the first field (which will be partial name due to awk)
    # Instead, we'll handle selection ourselves to properly parse display names with spaces
    local i=1
    for item in "${items[@]}"; do
      echo "  ${i}. ${item}" >/dev/tty
      ((i++))
    done
    echo "" >/dev/tty

    local selection
    while true; do
      read -r -p "Enter app registration (1-${#items[@]}) or app ID: " selection </dev/tty

      # Check if it's a number
      if [[ "${selection}" =~ ^[0-9]+$ ]]; then
        if [[ "${selection}" -ge 1 && "${selection}" -le "${#items[@]}" ]]; then
          echo "${app_ids[$((selection - 1))]}"
          return 0
        else
          echo "Invalid selection. Please enter a number between 1 and ${#items[@]}" >&2
          continue
        fi
      else
        # Check if it matches an app ID (full or partial)
        for idx in "${!app_ids[@]}"; do
          if [[ "${app_ids[$idx]}" == "${selection}"* ]]; then
            echo "${app_ids[$idx]}"
            return 0
          fi
        done
        echo "Invalid selection. Please enter a number (1-${#items[@]}) or app ID" >&2
        continue
      fi
    done
  fi
}
