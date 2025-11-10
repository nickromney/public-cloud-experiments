# Personal Subscription - React Web App + Function App + APIM
# Deploys: React SPA on App Service + FastAPI Function App + API Management
# Auth: APIM handles authentication (subscription key), Function App has AUTH_METHOD=none
# Security: Optional IP restrictions to enforce APIM-only access to Function App

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
  project_name = "subnetcalc"
  environment  = local.root_vars.environment

  # Use existing resource group
  resource_group_name   = "rg-subnet-calc"
  create_resource_group = false

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "subnet-calculator-react-webapp-apim"
  }

  # web_app, function_app, apim, observability, and security defined in terraform.tfvars
}
