locals {
  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
    workload    = "subnet-calculator-react-webapp-apim"
  }, var.tags)

  web_app_name      = var.web_app.name != "" ? var.web_app.name : "web-${var.project_name}-${var.environment}-apim"
  function_app_name = var.function_app.name != "" ? var.function_app.name : "func-${var.project_name}-${var.environment}-apim"
  apim_name         = var.apim.name != "" ? var.apim.name : "apim-${var.project_name}-${var.environment}"

  # APIM gateway URL becomes the API base URL for the web app
  computed_api_base_url = var.web_app.api_base_url != "" ? var.web_app.api_base_url : "${module.apim.gateway_url}/${var.apim.api_path}"
}

# -----------------------------------------------------------------------------
# Resource Group
# -----------------------------------------------------------------------------

resource "azurerm_resource_group" "this" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

data "azurerm_resource_group" "this" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  rg_name = var.resource_group_name
  rg_loc  = var.create_resource_group ? azurerm_resource_group.this[0].location : data.azurerm_resource_group.this[0].location
}

# -----------------------------------------------------------------------------
# Shared Observability (Data Sources)
# -----------------------------------------------------------------------------

data "azurerm_log_analytics_workspace" "shared" {
  count               = var.observability.use_existing ? 1 : 0
  name                = var.observability.existing_log_analytics_name
  resource_group_name = var.observability.existing_resource_group_name
}

data "azurerm_application_insights" "shared" {
  count               = var.observability.use_existing ? 1 : 0
  name                = var.observability.existing_app_insights_name
  resource_group_name = var.observability.existing_resource_group_name
}

# Create new resources if not using existing
resource "azurerm_log_analytics_workspace" "this" {
  count               = var.observability.use_existing ? 0 : 1
  name                = "log-${var.project_name}-${var.environment}-apim"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = try(var.observability.log_retention_days, 30)
  tags                = local.common_tags
}

resource "azurerm_application_insights" "this" {
  count               = var.observability.use_existing ? 0 : 1
  name                = "appi-${var.project_name}-${var.environment}-apim"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  workspace_id        = azurerm_log_analytics_workspace.this[0].id
  application_type    = "web"
  retention_in_days   = try(var.observability.app_insights_retention_days, 90)
  tags                = local.common_tags
}

locals {
  log_analytics_workspace_id = var.observability.use_existing ? data.azurerm_log_analytics_workspace.shared[0].id : azurerm_log_analytics_workspace.this[0].id
  app_insights_key           = var.observability.use_existing ? data.azurerm_application_insights.shared[0].instrumentation_key : azurerm_application_insights.this[0].instrumentation_key
  app_insights_connection    = var.observability.use_existing ? data.azurerm_application_insights.shared[0].connection_string : azurerm_application_insights.this[0].connection_string
}

# -----------------------------------------------------------------------------
# API Management (Developer Tier)
# -----------------------------------------------------------------------------

module "apim" {
  source = "../../modules/azure-apim"

  name                = local.apim_name
  location            = local.rg_loc
  resource_group_name = local.rg_name
  publisher_name      = var.apim.publisher_name
  publisher_email     = var.apim.publisher_email
  sku_name            = var.apim.sku_name

  # Public access (Developer tier)
  virtual_network_type          = "None"
  public_network_access_enabled = true

  # Application Insights integration
  app_insights_id                  = var.observability.use_existing ? data.azurerm_application_insights.shared[0].id : azurerm_application_insights.this[0].id
  app_insights_instrumentation_key = local.app_insights_key

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Function App (FastAPI backend with AUTH_METHOD=none)
# -----------------------------------------------------------------------------

# Storage Account for Function App
resource "azurerm_storage_account" "function" {
  name                     = var.function_app.storage_account_name != "" ? var.function_app.storage_account_name : "st${var.project_name}${var.environment}apim"
  resource_group_name      = local.rg_name
  location                 = local.rg_loc
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags                     = local.common_tags
}

# App Service Plan for Function App
resource "azurerm_service_plan" "function" {
  name                = "plan-${var.project_name}-${var.environment}-func-apim"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.function_app.plan_sku
  tags                = local.common_tags
}

# Function App
resource "azurerm_linux_function_app" "api" {
  name                       = local.function_app_name
  resource_group_name        = local.rg_name
  location                   = local.rg_loc
  service_plan_id            = azurerm_service_plan.function.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key

  # Network configuration - optional enforcement via NSG
  public_network_access_enabled = var.function_app.public_network_access_enabled

  site_config {
    application_stack {
      python_version = var.function_app.runtime == "python" ? var.function_app.runtime_version : null
    }

    # CORS configuration - allow APIM and local development
    cors {
      allowed_origins = concat(
        [module.apim.gateway_url],
        try(var.function_app.cors_allowed_origins, [])
      )
      support_credentials = false
    }
  }

  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME"              = var.function_app.runtime == "dotnet-isolated" ? "dotnet-isolated" : var.function_app.runtime
    "FUNCTIONS_EXTENSION_VERSION"           = "~4"
    "SCM_DO_BUILD_DURING_DEPLOYMENT"        = "true"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = local.app_insights_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = local.app_insights_connection
    # AUTH_METHOD=none - APIM handles all authentication
    "AUTH_METHOD" = "none"
  }, try(var.function_app.app_settings, {}))

  identity {
    type = "SystemAssigned"
  }

  tags = local.common_tags
}

# -----------------------------------------------------------------------------
# Network Security (Optional NSG Enforcement)
# -----------------------------------------------------------------------------

# APIM outbound IPs are available from the module output
# No need for additional data source

# NSG for Function App (when enforcement is enabled)
resource "azurerm_network_security_group" "function_app" {
  count               = var.security.enforce_apim_only_access ? 1 : 0
  name                = "nsg-${local.function_app_name}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  tags                = local.common_tags
}

# Allow APIM to access Function App (HTTPS)
resource "azurerm_network_security_rule" "allow_apim_https" {
  count                       = var.security.enforce_apim_only_access ? 1 : 0
  name                        = "AllowAPIMHttps"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefixes     = module.apim.public_ip_addresses
  destination_address_prefix  = "*"
  resource_group_name         = local.rg_name
  network_security_group_name = azurerm_network_security_group.function_app[0].name
}

# Deny all other inbound traffic
resource "azurerm_network_security_rule" "deny_all_inbound" {
  count                       = var.security.enforce_apim_only_access ? 1 : 0
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.rg_name
  network_security_group_name = azurerm_network_security_group.function_app[0].name
}

# Note: NSG association to Function App requires VNet integration
# For App Service on shared infra, use IP restrictions instead
resource "null_resource" "function_app_ip_restrictions" {
  count = var.security.enforce_apim_only_access ? 1 : 0

  # Use Azure CLI to configure IP restrictions
  provisioner "local-exec" {
    command = <<-EOT
      # Remove default allow rule
      az functionapp config access-restriction remove \
        --name ${azurerm_linux_function_app.api.name} \
        --resource-group ${local.rg_name} \
        --rule-name "Allow all" || true

      # Add APIM IP addresses
      ${join("\n      ", [for ip in module.apim.public_ip_addresses :
    "az functionapp config access-restriction add --name ${azurerm_linux_function_app.api.name} --resource-group ${local.rg_name} --rule-name 'AllowAPIM-${replace(ip, ".", "-")}' --action Allow --ip-address ${ip}/32 --priority ${100 + index(module.apim.public_ip_addresses, ip)}"
])}

      # Deny all other traffic (default)
      az functionapp config access-restriction set \
        --name ${azurerm_linux_function_app.api.name} \
        --resource-group ${local.rg_name} \
        --use-same-restrictions-for-scm-site false
    EOT
}

triggers = {
  apim_ips          = join(",", module.apim.public_ip_addresses)
  function_app_name = azurerm_linux_function_app.api.name
  enforcement       = var.security.enforce_apim_only_access
}

depends_on = [azurerm_linux_function_app.api, module.apim]
}

# -----------------------------------------------------------------------------
# APIM API Backend Configuration
# -----------------------------------------------------------------------------

# Backend pointing to Function App
resource "azurerm_api_management_backend" "function_app" {
  name                = "backend-${local.function_app_name}"
  resource_group_name = local.rg_name
  api_management_name = module.apim.name
  protocol            = "http"
  url                 = "https://${azurerm_linux_function_app.api.default_hostname}"
  description         = "Subnet Calculator Function App (AUTH_METHOD=none)"

  # Optional: Proxy settings for debugging
  # proxy {
  #   url      = "http://localhost:8888"
  #   username = "proxy-user"
  #   password = "proxy-pass"
  # }
}

# API definition
resource "azurerm_api_management_api" "subnet_calc" {
  name                = var.apim.api_path
  resource_group_name = local.rg_name
  api_management_name = module.apim.name
  revision            = "1"
  display_name        = var.apim.api_display_name
  path                = var.apim.api_path
  protocols           = ["https"]
  service_url         = "https://${azurerm_linux_function_app.api.default_hostname}"

  subscription_required = var.apim.subscription_required

  import {
    content_format = "openapi+json-link"
    content_value  = "https://${azurerm_linux_function_app.api.default_hostname}/api/v1/openapi.json"
  }

  depends_on = [
    azurerm_linux_function_app.api,
    azurerm_api_management_backend.function_app
  ]
}

# APIM Policy (subscription-based authentication)
resource "azurerm_api_management_api_policy" "subnet_calc" {
  api_name            = azurerm_api_management_api.subnet_calc.name
  api_management_name = module.apim.name
  resource_group_name = local.rg_name

  xml_content = var.apim.subscription_required ? templatefile("${path.module}/policies/inbound-subscription.xml", {
    rate_limit = var.apim.rate_limit_per_minute
    }) : templatefile("${path.module}/policies/inbound-none.xml", {
    rate_limit = var.apim.rate_limit_per_minute
  })
}

# APIM Subscription (for subscription-based auth)
resource "azurerm_api_management_subscription" "subnet_calc" {
  count               = var.apim.subscription_required ? 1 : 0
  api_management_name = module.apim.name
  resource_group_name = local.rg_name
  display_name        = "Subnet Calculator Web App Subscription"
  api_id              = azurerm_api_management_api.subnet_calc.id
  state               = "active"
  allow_tracing       = true
}

# -----------------------------------------------------------------------------
# Web App (React SPA pointing to APIM)
# -----------------------------------------------------------------------------

# App Service Plan for Web App
resource "azurerm_service_plan" "web" {
  name                = "plan-${var.project_name}-${var.environment}-web-apim"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.web_app.plan_sku
  tags                = local.common_tags
}

# Web App
resource "azurerm_linux_web_app" "react" {
  name                = local.web_app_name
  resource_group_name = local.rg_name
  location            = local.rg_loc
  service_plan_id     = azurerm_service_plan.web.id
  https_only          = true
  tags                = local.common_tags

  site_config {
    always_on        = var.web_app.always_on
    app_command_line = "node server.js"

    application_stack {
      node_version = var.web_app.runtime_version
    }
  }

  app_settings = merge({
    "API_BASE_URL" = local.computed_api_base_url
    # APIM subscription key (if required)
    "APIM_SUBSCRIPTION_KEY" = var.apim.subscription_required ? azurerm_api_management_subscription.subnet_calc[0].primary_key : ""
    "STACK_NAME"            = "Subnet Calculator React (via APIM)"
    # Runtime configuration for Express server
    "AUTH_METHOD" = "none" # Web app doesn't authenticate - APIM does
  }, try(var.web_app.app_settings, {}))

  identity {
    type = "SystemAssigned"
  }
}
