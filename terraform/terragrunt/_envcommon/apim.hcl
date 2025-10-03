# Common configuration for Azure API Management

locals {
  # APIM Configuration
  apim_config = {
    sku_name = "Developer_1" # Developer tier (no SLA, for dev/test only)

    # Publisher details (required)
    publisher_name  = "Cloud Experiments"
    publisher_email = "admin@example.com" # Change to your email
  }

  # Common APIM policies
  apim_policies = {
    # Global policy example
    enable_cors = true

    # Rate limiting
    rate_limit = {
      calls               = 100
      renewal_period      = 60
    }
  }

  # Common tags
  common_tags = {
    managed_by = "terragrunt"
    component  = "api-gateway"
  }
}

# This is a pattern file - include it in actual terragrunt.hcl files
