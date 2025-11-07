# Personal Subscription - React Web App + Function (Easy Auth)
# Deploys: Azure App Service Plan + Linux Web App (React SPA) + Azure Function backend
# Auth: Azure AD Easy Auth configured via auth_settings_v2

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  root_vars        = include.root.locals
  preferred_region = get_env("PERSONAL_SUB_REGION", "uksouth")
}

inputs = {
  location     = local.preferred_region
  project_name = local.root_vars.project_name
  environment  = local.root_vars.environment

  resource_group_name   = "rg-subnet-calc-webapp"
  create_resource_group = true

  tenant_id = get_env("ARM_TENANT_ID", "")

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "subnet-calculator-react-webapp"
  }

  # Remaining inputs (web_app, function_app, etc.) are defined in terraform.tfvars
}
