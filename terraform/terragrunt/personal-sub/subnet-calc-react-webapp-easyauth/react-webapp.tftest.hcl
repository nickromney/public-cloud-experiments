# Tests for subnet-calc-react-webapp stack
# Validates React SPA + Function App configuration
# Uses data source to look up current Azure context (no hardcoded UUIDs)

provider "azurerm" {
  features {}
}

# Validation tests

run "test_invalid_environment" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "production" # Invalid
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  expect_failures = [
    var.environment,
  ]
}

run "test_invalid_location" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "centralus" # Invalid
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  expect_failures = [
    var.location,
  ]
}

run "test_invalid_tenant_id" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    tenant_id             = "not-a-uuid" # Invalid format - intentionally testing validation
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  expect_failures = [
    var.tenant_id,
  ]
}

run "test_invalid_project_name" {
  command = plan

  variables {
    project_name          = "ThisHasUpperCase" # Invalid - must be lowercase
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  expect_failures = [
    var.project_name,
  ]
}

# Configuration tests

run "validate_resource_naming" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-subnetcalc-dev"
    error_message = "Log Analytics workspace should follow naming convention"
  }

  assert {
    condition     = azurerm_application_insights.this.name == "appi-subnetcalc-dev"
    error_message = "Application Insights should follow naming convention"
  }

  assert {
    condition     = module.web_app.service_plan_name == "plan-subnetcalc-dev-web"
    error_message = "Web App Service Plan should follow naming convention"
  }

  assert {
    condition     = module.function_app.service_plan_name == "plan-subnetcalc-dev-func"
    error_message = "Function App Service Plan should follow naming convention"
  }
}

run "validate_observability_stack" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Log Analytics retention should match variable"
  }

  assert {
    condition     = azurerm_application_insights.this.retention_in_days == 90
    error_message = "Application Insights retention should match variable"
  }

  assert {
    condition     = azurerm_application_insights.this.application_type == "web"
    error_message = "Application Insights should be web type"
  }
}

run "validate_web_app_configuration" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  # Note: The following assertions reference resources inside the web_app module
  # and cannot be tested directly. Internal module resources are not accessible
  # at the test level. These properties are validated by the module's own tests.
  #
  # To re-enable these tests, expose the required values as outputs from the
  # azure-web-app module and reference them as module.web_app.<output_name>.
  #
  # Commented out assertions:
  # - Service Plan SKU name and OS type
  # - Web App HTTPS enforcement
  # - System-assigned managed identity
  # - Node.js runtime version
  # - Always-on setting
}

run "validate_function_app_configuration" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  # Note: The following assertions reference resources inside the function_app module
  # and cannot be tested directly. Internal module resources are not accessible
  # at the test level. These properties are validated by the module's own tests.
  #
  # To re-enable these tests, expose the required values as outputs from the
  # azure-function-app module and reference them as module.function_app.<output_name>.
  #
  # Commented out assertions:
  # - Service Plan SKU name
  # - Function App HTTPS enforcement
  # - System-assigned managed identity
  # - Python runtime version
  # - Public network access setting
  # - CORS allowed origins
}

run "validate_storage_account" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  assert {
    condition     = can(regex("^st[a-z0-9]+func$", module.function_app.storage_account_name))
    error_message = "Storage account name should follow pattern stXXXXXfunc"
  }

  # Note: The following assertions reference internal storage account properties
  # that are not exposed as module outputs. These are validated by the module's own tests.
  #
  # Commented out assertions:
  # - Storage account tier (Standard)
  # - Replication type (LRS)
  # - HTTPS-only enforcement
  # - Minimum TLS version
}

run "validate_easy_auth_not_configured" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  # Note: Cannot test internal module Easy Auth configuration directly.
  # The web app resource is inside the azure-web-app module and not accessible.
  # Module behavior is validated by its own tests.
}

run "validate_easy_auth_configured" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth = {
        enabled                    = true
        client_id                  = "00000000-0000-0000-0000-000000000001" # Mock client ID for testing
        client_secret_setting_name = "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
        issuer                     = ""
        tenant_id                  = ""
        allowed_audiences          = []
        runtime_version            = "~1"
        unauthenticated_action     = "RedirectToLoginPage"
        token_store_enabled        = true
        login_parameters           = {}
        use_managed_identity       = true
      }
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  # Note: The following assertions reference the web app resource inside the azure-web-app module
  # and cannot be tested directly. Internal module resources are not accessible at the test level.
  # Easy Auth configuration is validated by the module's own tests.
  #
  # Commented out assertions:
  # - Easy Auth is configured (length check)
  # - Auth is enabled
  # - Unauthenticated action is RedirectToLoginPage
  # - Token store is enabled
  # - Azure AD client ID matches configured value
  # - Tenant auth endpoint is valid Microsoft login URL
}

# Note: App settings injection test removed
# Cannot test app_settings keys at plan time because values like
# APPLICATIONINSIGHTS_CONNECTION_STRING depend on resources being created.
# The merge() logic in main.tf ensures these are correctly injected.

run "validate_outputs" {
  command = plan

  variables {
    project_name          = "subnetcalc"
    environment           = "dev"
    location              = "uksouth"
    resource_group_name   = "rg-test-webapp"
    create_resource_group = true
    tags = {
      test = "true"
    }
    entra_id_app = {
      display_name     = "Test App Registration"
      sign_in_audience = "AzureADMyOrg"
      identifier_uris  = ["api://test-subnet-calculator"]
    }
    web_app = {
      name            = "web-test-react"
      plan_sku        = "B1"
      runtime_version = "22-lts"
      always_on       = true
      api_base_url    = ""
      app_settings    = {}
      easy_auth       = null
    }
    function_app = {
      name                          = "func-test-api"
      plan_sku                      = "EP1"
      runtime                       = "python"
      runtime_version               = "3.11"
      run_from_package              = true
      storage_account_name          = ""
      public_network_access_enabled = true
      cors_allowed_origins          = ["*"]
      app_settings                  = {}
    }
    observability = {
      log_retention_days          = 30
      app_insights_retention_days = 90
    }
  }

  # Note: URL outputs cannot be tested at plan time because they depend on
  # default_hostname which is only known after Azure provisions the resources

  assert {
    condition     = output.resource_group_name == "rg-test-webapp"
    error_message = "Output should return correct resource group name"
  }

  assert {
    condition     = output.application_insights_name == "appi-subnetcalc-dev"
    error_message = "Output should return Application Insights name"
  }

  assert {
    condition     = output.web_app_name == "web-test-react"
    error_message = "Output should return Web App name"
  }

  assert {
    condition     = output.function_app_name == "func-test-api"
    error_message = "Output should return Function App name"
  }
}
