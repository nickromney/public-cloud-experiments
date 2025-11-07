include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../../../../modules/secure-app"
}

locals {
  project      = "subnetcalc"
  environment  = "dev"
  location     = "uksouth"

  cloudflare_ips = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17"
  ]
}

inputs = {
  project_name          = local.project
  environment           = local.environment
  location              = local.location
  resource_group_name   = "${local.project}-${local.environment}-rg"
  create_resource_group = true
  tenant_id             = get_env("ARM_TENANT_ID", "")

  vnet_cidr = "10.120.0.0/22"

  subnets = {
    web_integration_cidr   = "10.120.0.0/24"
    private_endpoints_cidr = "10.120.1.0/24"
    apim_cidr              = "10.120.2.0/24"
  }

  cloudflare_ips = local.cloudflare_ips

  web_app = {
    plan_sku                    = "P1v3"
    runtime_version             = "18-lts"
    api_base_url                = "https://apim-${local.project}-${local.environment}.azure-api.net/api/subnet-calc"
    always_on                   = true
    cloudflare_only             = false
    enable_private_endpoint     = false
    app_settings                = {
      "STACK_NAME" = "Secure Subnet Calculator"
    }
  }

  function_app = {
    plan_sku                = "P1v3"
    runtime                 = "python"
    runtime_version         = "3.11"
    run_from_package        = true
    app_settings            = {}
    enable_private_endpoint = true
  }

  apim = {
    sku_name        = "Developer_1"
    publisher_name  = "Subnet Calculator"
    publisher_email = "ops@publiccloudexperiments.net"
    api_path        = "api/subnet-calc"
    identifier_uri  = ""
  }
}
