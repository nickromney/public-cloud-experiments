# Network configuration
vnet_cidr = "10.120.0.0/22"

subnets = {
  web_integration_cidr   = "10.120.0.0/24"
  private_endpoints_cidr = "10.120.1.0/24"
  apim_cidr              = "10.120.2.0/24"
}

# Web App configuration
web_app = {
  plan_sku                = "P1v3"
  runtime_version         = "18-lts"
  api_base_url            = "https://apim-subnetcalc-dev.azure-api.net/api/subnet-calc"
  always_on               = true
  cloudflare_only         = false
  enable_private_endpoint = false
  app_settings = {
    "STACK_NAME" = "Subnet Calculator (Internal APIM)"
  }
}

# Function App configuration
function_app = {
  plan_sku                = "P1v3"
  runtime                 = "python"
  runtime_version         = "3.11"
  run_from_package        = true
  enable_private_endpoint = true
  app_settings            = {}
}

# API Management configuration
apim = {
  sku_name        = "Developer_1"
  publisher_name  = "Subnet Calculator"
  publisher_email = "ops@publiccloudexperiments.net"
  api_path        = "api/subnet-calc"
  identifier_uri  = ""
  policy_xml      = null
}
