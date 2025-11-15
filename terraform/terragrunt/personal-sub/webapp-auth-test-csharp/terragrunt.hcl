# Personal Subscription - C# .NET 9.0 Testing Stack for Easy Auth + Managed Identity
# Deploys: C# Web App + C# Function App (baseline - no auth configured yet)
# Auth: Testing Azure Easy Auth patterns with Managed Identity (future iterations)

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

  tenant_id = get_env("ARM_TENANT_ID", "")

  tags = {
    environment = local.root_vars.environment
    managed_by  = "terragrunt"
    workload    = "webapp-auth-test-csharp"
  }

  # web_app, function_app, and entra_id_app defined in terraform.tfvars
}
