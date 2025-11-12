# Personal Subscription - Shared Components
# Deploys: Resource Group + Log Analytics + Key Vault for shared observability and secrets
# Uses map-based (0-to-n) pattern

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars        = include.root.locals
  preferred_region = get_env("PERSONAL_SUB_REGION", "uksouth")
}

inputs = {
  environment = local.root_vars.environment

  # -----------------------------------------------------------------------------
  # Resource Groups (map-based)
  # -----------------------------------------------------------------------------
  # Create new resource group
  resource_groups = {
    main = {
      name     = "rg-subnet-calc"
      location = local.preferred_region
    }
  }

  # Use existing resource group (set resource_groups = {} and uncomment this)
  # existing_resource_group_name = "rg-subnet-calc"

  # -----------------------------------------------------------------------------
  # Log Analytics Workspaces (map-based)
  # -----------------------------------------------------------------------------
  log_analytics_workspaces = {
    shared = {
      name              = "log-subnetcalc-shared-dev"
      sku               = "PerGB2018"
      retention_in_days = 30
    }
  }

  # -----------------------------------------------------------------------------
  # Key Vaults (map-based)
  # -----------------------------------------------------------------------------
  key_vaults = {
    shared = {
      name                        = "kv-sc-shared-dev"
      sku                         = "standard"
      use_random_suffix           = true
      purge_protection_enabled    = false
      soft_delete_retention_days  = 90
      enable_rbac_authorization   = true
      log_analytics_workspace_key = "shared" # Link to Log Analytics workspace
    }
  }

  # Grant current user Key Vault access
  grant_current_user_key_vault_access = true

  # -----------------------------------------------------------------------------
  # Tags
  # -----------------------------------------------------------------------------
  tags = {
    managed_by = "terragrunt"
    workload   = "shared-components"
    purpose    = "observability-and-secrets"
  }
}
