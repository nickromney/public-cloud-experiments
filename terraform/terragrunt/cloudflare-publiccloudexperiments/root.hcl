# Cloudflare Terragrunt root configuration

locals {
  subscription_id = get_env("ARM_SUBSCRIPTION_ID", "")
  tenant_id       = get_env("ARM_TENANT_ID", "")
}

# Remote state stored alongside other stacks
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

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents = <<EOF
terraform {
  required_version = ">= 1.8"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {
  api_token = "${get_env("CLOUDFLARE_API_TOKEN", "")}"
  account_id = "${get_env("CLOUDFLARE_ACCOUNT_ID", "")}"
}
EOF
}
