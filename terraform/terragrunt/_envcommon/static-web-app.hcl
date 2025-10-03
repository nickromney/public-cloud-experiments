# Common configuration for Azure Static Web Apps

locals {
  # Static Web App Configuration
  swa_config = {
    sku_tier = "Free" # Free or Standard
    sku_size = "Free"
  }

  # Common app settings
  app_settings = {
    # API backend configuration (will point to APIM)
    # Set in actual terragrunt.hcl based on dependencies
  }

  # Common tags
  common_tags = {
    managed_by = "terragrunt"
    component  = "frontend"
  }
}

# This is a pattern file - include it in actual terragrunt.hcl files
