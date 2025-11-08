# Azure Static Web App Module - Stack-Based Implementation
# Generates resources from logical stack definitions

locals {
  # Compute which stacks have function apps
  stacks_with_functions = {
    for k, v in var.stacks : k => v
    if v.function_app != null
  }

  # Generate resource names from stack keys
  swa_names = {
    for k, v in var.stacks : k => "swa-${var.project_name}-${k}"
  }

  function_names = {
    for k, v in local.stacks_with_functions : k => "func-${var.project_name}-${k}"
  }

  plan_names = {
    for k, v in local.stacks_with_functions : k => "asp-${var.project_name}-${k}"
  }

  storage_names = {
    for k, v in local.stacks_with_functions : k => "st${var.project_name}${k}${random_string.storage_suffix[k].result}"
  }

  # Determine always_on based on plan SKU if not explicitly set
  function_always_on = {
    for k, v in local.stacks_with_functions : k => (
      v.function_app.always_on != null ? v.function_app.always_on :
      (v.function_app.plan_sku == "FC1" || v.function_app.plan_sku == "Y1") ? false : true
    )
  }

  # Default app settings per auth method
  default_app_settings = {
    jwt = {
      FUNCTIONS_WORKER_RUNTIME       = "python"
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      ENABLE_ORYX_BUILD              = "true"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    }
    swa = {
      FUNCTIONS_WORKER_RUNTIME       = "python"
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      ENABLE_ORYX_BUILD              = "true"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    }
    none = {
      FUNCTIONS_WORKER_RUNTIME       = "python"
      AzureWebJobsFeatureFlags       = "EnableWorkerIndexing"
      ENABLE_ORYX_BUILD              = "true"
      SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    }
  }

  # Merge default and custom app settings
  function_app_settings = {
    for k, v in local.stacks_with_functions : k => merge(
      local.default_app_settings[v.function_app.auth_method],
      {
        AUTH_METHOD  = v.function_app.auth_method
        CORS_ORIGINS = v.swa.custom_domain != null ? "https://${v.swa.custom_domain}" : ""
      },
      v.function_app.app_settings
    )
  }
}

# Random suffix for storage account names (globally unique)
resource "random_string" "storage_suffix" {
  for_each = local.stacks_with_functions

  length  = 5
  special = false
  upper   = false
}

# Static Web Apps
resource "azurerm_static_web_app" "this" {
  for_each = var.stacks

  name                = local.swa_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.location

  sku_tier = each.value.swa.sku
  sku_size = each.value.swa.sku

  public_network_access_enabled = each.value.swa.network_access == "Enabled"

  tags = var.tags
}

# Custom domains for Static Web Apps
resource "azurerm_static_web_app_custom_domain" "this" {
  for_each = {
    for k, v in var.stacks : k => v
    if v.swa.custom_domain != null
  }

  static_web_app_id = azurerm_static_web_app.this[each.key].id
  domain_name       = each.value.swa.custom_domain
  validation_type   = "cname-delegation"
}

# App Service Plans (only for stacks with function apps)
resource "azurerm_service_plan" "this" {
  for_each = local.stacks_with_functions

  name                = local.plan_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type  = "Linux"
  sku_name = each.value.function_app.plan_sku

  tags = var.tags
}

# Storage Accounts (only for stacks with function apps)
resource "azurerm_storage_account" "this" {
  for_each = local.stacks_with_functions

  name                = local.storage_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = var.tags
}

# Function Apps
resource "azurerm_linux_function_app" "this" {
  for_each = local.stacks_with_functions

  name                = local.function_names[each.key]
  resource_group_name = var.resource_group_name
  location            = var.location

  service_plan_id            = azurerm_service_plan.this[each.key].id
  storage_account_name       = azurerm_storage_account.this[each.key].name
  storage_account_access_key = azurerm_storage_account.this[each.key].primary_access_key

  site_config {
    always_on = local.function_always_on[each.key]

    application_stack {
      python_version = each.value.function_app.python_version
    }

    dynamic "cors" {
      for_each = each.value.swa.custom_domain != null ? [1] : []
      content {
        allowed_origins = ["https://${each.value.swa.custom_domain}"]
      }
    }
  }

  app_settings = local.function_app_settings[each.key]

  tags = var.tags
}

# Custom hostname bindings for Function Apps
resource "azurerm_app_service_custom_hostname_binding" "this" {
  for_each = {
    for k, v in local.stacks_with_functions : k => v
    if v.function_app.custom_domain != null
  }

  hostname            = each.value.function_app.custom_domain
  app_service_name    = azurerm_linux_function_app.this[each.key].name
  resource_group_name = var.resource_group_name
}
