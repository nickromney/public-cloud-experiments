# Tests for subnet-calc-react-webapp stack
# Validates React SPA + Function App configuration

# Generate test data using random provider
run "setup" {
  command = plan

  module {
    source = "./tests/fixtures"
  }
}

variables {
  project_name        = "subnetcalc"
  environment         = "dev"
  location            = "uksouth"
  resource_group_name = "rg-test-webapp"
  tenant_id           = run.setup.tenant_id
  create_resource_group = true

  tags = {
    test = "true"
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

# Validation tests

run "test_invalid_environment" {
  command = plan

  variables {
    environment = "production" # Invalid
  }

  expect_failures = [
    var.environment,
  ]
}

run "test_invalid_location" {
  command = plan

  variables {
    location = "centralus" # Invalid
  }

  expect_failures = [
    var.location,
  ]
}

run "test_invalid_tenant_id" {
  command = plan

  variables {
    tenant_id = "not-a-uuid" # Invalid format
  }

  expect_failures = [
    var.tenant_id,
  ]
}

run "test_invalid_project_name" {
  command = plan

  variables {
    project_name = "ThisHasUpperCase" # Invalid - must be lowercase
  }

  expect_failures = [
    var.project_name,
  ]
}

# Configuration tests

run "validate_resource_naming" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-subnetcalc-dev"
    error_message = "Log Analytics workspace should follow naming convention"
  }

  assert {
    condition     = azurerm_application_insights.this.name == "appi-subnetcalc-dev"
    error_message = "Application Insights should follow naming convention"
  }

  assert {
    condition     = azurerm_service_plan.web.name == "asp-subnetcalc-web-dev"
    error_message = "Web App Service Plan should follow naming convention"
  }

  assert {
    condition     = azurerm_service_plan.function.name == "asp-subnetcalc-func-dev"
    error_message = "Function App Service Plan should follow naming convention"
  }
}

run "validate_observability_stack" {
  command = plan

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

  assert {
    condition     = azurerm_service_plan.web.sku_name == "B1"
    error_message = "Web App Service Plan should use B1 SKU"
  }

  assert {
    condition     = azurerm_service_plan.web.os_type == "Linux"
    error_message = "Web App Service Plan should use Linux"
  }

  assert {
    condition     = azurerm_linux_web_app.this.https_only == true
    error_message = "Web App should enforce HTTPS"
  }

  assert {
    condition     = azurerm_linux_web_app.this.identity[0].type == "SystemAssigned"
    error_message = "Web App should have system-assigned managed identity"
  }

  assert {
    condition     = azurerm_linux_web_app.this.site_config[0].application_stack[0].node_version == "22-lts"
    error_message = "Web App should use Node.js 22 LTS"
  }

  assert {
    condition     = azurerm_linux_web_app.this.site_config[0].always_on == true
    error_message = "Web App should have always_on enabled"
  }
}

run "validate_function_app_configuration" {
  command = plan

  assert {
    condition     = azurerm_service_plan.function.sku_name == "EP1"
    error_message = "Function App Service Plan should use EP1 (Elastic Premium)"
  }

  assert {
    condition     = azurerm_linux_function_app.this.https_only == true
    error_message = "Function App should enforce HTTPS"
  }

  assert {
    condition     = azurerm_linux_function_app.this.identity[0].type == "SystemAssigned"
    error_message = "Function App should have system-assigned managed identity"
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].application_stack[0].python_version == "3.11"
    error_message = "Function App should use Python 3.11"
  }

  assert {
    condition     = azurerm_linux_function_app.this.public_network_access_enabled == true
    error_message = "Function App should have public network access enabled"
  }

  assert {
    condition     = contains(azurerm_linux_function_app.this.site_config[0].cors[0].allowed_origins, "*")
    error_message = "Function App CORS should include configured origins"
  }
}

run "validate_storage_account" {
  command = plan

  assert {
    condition     = can(regex("^st[a-z0-9]+func$", azurerm_storage_account.function.name))
    error_message = "Storage account name should follow pattern stXXXXXfunc"
  }

  assert {
    condition     = azurerm_storage_account.function.account_tier == "Standard"
    error_message = "Storage account should use Standard tier"
  }

  assert {
    condition     = azurerm_storage_account.function.account_replication_type == "LRS"
    error_message = "Storage account should use LRS replication"
  }

  assert {
    condition     = azurerm_storage_account.function.https_traffic_only_enabled == true
    error_message = "Storage account should enforce HTTPS only"
  }

  assert {
    condition     = azurerm_storage_account.function.min_tls_version == "TLS1_2"
    error_message = "Storage account should require TLS 1.2 minimum"
  }
}

run "validate_easy_auth_not_configured" {
  command = plan

  variables {
    web_app = {
      plan_sku  = "B1"
      easy_auth = null
    }
  }

  assert {
    condition     = length(azurerm_linux_web_app.this.auth_settings_v2) == 0
    error_message = "Web App should not have EasyAuth when easy_auth is null"
  }
}

run "validate_easy_auth_configured" {
  command = plan

  variables {
    web_app = {
      plan_sku = "B1"
      easy_auth = {
        enabled                    = true
        client_id                  = run.setup.client_id
        client_secret              = ""
        client_secret_setting_name = "MICROSOFT_PROVIDER_AUTHENTICATION_SECRET"
        issuer                     = ""
        tenant_id                  = ""
        allowed_audiences          = []
        runtime_version            = "~1"
        unauthenticated_action     = "RedirectToLoginPage"
        token_store_enabled        = true
        login_parameters           = {}
      }
    }
  }

  assert {
    condition     = length(azurerm_linux_web_app.this.auth_settings_v2) > 0
    error_message = "Web App should have EasyAuth configured when easy_auth is provided"
  }

  assert {
    condition     = azurerm_linux_web_app.this.auth_settings_v2[0].auth_enabled == true
    error_message = "EasyAuth should be enabled"
  }

  assert {
    condition     = azurerm_linux_web_app.this.auth_settings_v2[0].unauthenticated_action == "RedirectToLoginPage"
    error_message = "Unauthenticated users should be redirected to login"
  }

  assert {
    condition     = azurerm_linux_web_app.this.auth_settings_v2[0].login[0].token_store_enabled == true
    error_message = "Token store should be enabled"
  }

  assert {
    condition     = azurerm_linux_web_app.this.auth_settings_v2[0].active_directory_v2[0].client_id == run.setup.client_id
    error_message = "Azure AD client ID should match variable"
  }

  assert {
    condition     = can(regex("^https://login.microsoftonline.com/.*", azurerm_linux_web_app.this.auth_settings_v2[0].active_directory_v2[0].tenant_auth_endpoint))
    error_message = "Tenant auth endpoint should be valid Microsoft login URL"
  }
}

run "validate_app_settings_injection" {
  command = plan

  assert {
    condition     = can(azurerm_linux_web_app.this.app_settings["APPLICATIONINSIGHTS_CONNECTION_STRING"])
    error_message = "Web App should have Application Insights connection string"
  }

  assert {
    condition     = can(azurerm_linux_web_app.this.app_settings["API_BASE_URL"])
    error_message = "Web App should have API_BASE_URL set"
  }

  assert {
    condition     = can(azurerm_linux_function_app.this.app_settings["APPLICATIONINSIGHTS_CONNECTION_STRING"])
    error_message = "Function App should have Application Insights connection string"
  }

  assert {
    condition     = can(azurerm_linux_function_app.this.app_settings["AzureWebJobsStorage"])
    error_message = "Function App should have AzureWebJobsStorage connection string"
  }
}

run "validate_outputs" {
  command = plan

  assert {
    condition     = can(regex("^https://.*\\.azurewebsites\\.net$", output.web_app_url))
    error_message = "Web App URL should be valid Azure Web Sites URL"
  }

  assert {
    condition     = can(regex("^https://.*\\.azurewebsites\\.net$", output.function_app_url))
    error_message = "Function App URL should be valid Azure Web Sites URL"
  }

  assert {
    condition     = output.resource_group_name == "rg-test-webapp"
    error_message = "Output should return correct resource group name"
  }

  assert {
    condition     = output.application_insights_name == "appi-subnetcalc-dev"
    error_message = "Output should return Application Insights name"
  }
}
