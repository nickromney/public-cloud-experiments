# Personal Subscription - Shared Components
# Deploys: Key Vault + Log Analytics Workspace for shared observability and secrets

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars        = include.root.locals
  preferred_region = get_env("PERSONAL_SUB_REGION", "uksouth")
}

inputs = {
  location       = local.preferred_region
  project_name   = "subnetcalc"
  component_name = "shared"
  environment    = local.root_vars.environment

  # Create resource group for shared components
  resource_group_name   = "rg-subnet-calc"
  create_resource_group = true

  # Log Analytics configuration
  log_retention_days = 30

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "shared-components"
    purpose     = "observability-and-secrets"
  }
}
