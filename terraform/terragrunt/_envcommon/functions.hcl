# Common configuration for Azure Functions

locals {
  # Common Function App settings
  function_app_settings = {
    runtime_version        = "~4"
    dotnet_version         = "8.0"
    use_32_bit_worker      = false
    always_on              = false # Not available on Consumption plan
    ftps_state            = "Disabled"
    http2_enabled         = true
    min_tls_version       = "1.2"
  }

  # Common App Service Plan (Consumption)
  app_service_plan_config = {
    sku_name = "Y1" # Consumption plan
    os_type  = "Linux"
  }

  # Common storage account settings for Functions
  storage_config = {
    account_tier             = "Standard"
    account_replication_type = "LRS"
    min_tls_version         = "TLS1_2"
    enable_https_traffic_only = true
  }

  # Common tags
  common_tags = {
    managed_by = "terragrunt"
    component  = "compute"
  }
}

# This is a pattern file - include it in actual terragrunt.hcl files
