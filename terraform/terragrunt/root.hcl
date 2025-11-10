# Root terragrunt configuration

locals {
  # Common settings for all resources
  subscription_id = get_env("ARM_SUBSCRIPTION_ID")
  tenant_id       = get_env("ARM_TENANT_ID")
  region          = "westus2"  # Pluralsight sandbox: westus2 (supports all services)
  region_short    = "wus2"
  environment     = "dev"

  # Common naming
  project_name = "cloud-exp"
}

# Configure remote state
remote_state {
  backend = "azurerm"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    resource_group_name  = get_env("TF_BACKEND_RG")
    storage_account_name = get_env("TF_BACKEND_SA")
    container_name       = get_env("TF_BACKEND_CONTAINER")
    key                  = "${path_relative_to_include()}/terraform.tfstate"
    use_azuread_auth     = true
  }
}

# Generate provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents = <<EOF
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = "${get_env("ARM_SUBSCRIPTION_ID", "")}"
  tenant_id       = "${get_env("ARM_TENANT_ID", "")}"

  # Disable auto-registration for Pluralsight sandbox (limited permissions)
  resource_provider_registrations = "none"
}

provider "azuread" {
  tenant_id = "${get_env("ARM_TENANT_ID", "")}"
}
EOF
}

# Generate versions
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents = <<EOF
terraform {
  required_version = ">= 1.8"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}
EOF
}
