# Azure API Management Module
# Supports both public (Developer/Standard) and internal (VNet-integrated) modes

resource "azurerm_api_management" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name

  sku_name        = var.sku_name
  publisher_name  = var.publisher_name
  publisher_email = var.publisher_email

  # Network configuration
  virtual_network_type          = var.virtual_network_type
  public_network_access_enabled = var.public_network_access_enabled

  # VNet integration (only when virtual_network_type = "Internal" or "External")
  dynamic "virtual_network_configuration" {
    for_each = var.virtual_network_type != "None" && var.subnet_id != null ? [1] : []
    content {
      subnet_id = var.subnet_id
    }
  }

  tags = var.tags
}

# Application Insights integration (optional)
locals {
  enable_app_insights = var.app_insights_id != null ? { enabled = true } : {}
}

# APIM Logger for Application Insights (optional)
resource "azurerm_api_management_logger" "appinsights" {
  for_each = local.enable_app_insights

  name                = "apim-logger-appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  resource_id         = var.app_insights_id

  application_insights {
    instrumentation_key = var.app_insights_instrumentation_key
  }
}

# APIM Diagnostics Settings (optional)
resource "azurerm_api_management_diagnostic" "this" {
  for_each = local.enable_app_insights

  identifier               = "applicationinsights"
  api_management_name      = azurerm_api_management.this.name
  resource_group_name      = var.resource_group_name
  api_management_logger_id = azurerm_api_management_logger.appinsights["enabled"].id

  sampling_percentage       = var.diagnostics_sampling_percentage
  always_log_errors         = var.diagnostics_always_log_errors
  log_client_ip             = var.diagnostics_log_client_ip
  verbosity                 = var.diagnostics_verbosity
  http_correlation_protocol = var.diagnostics_http_correlation_protocol

  frontend_request {
    body_bytes     = var.diagnostics_frontend_request_body_bytes
    headers_to_log = var.diagnostics_frontend_request_headers
  }

  frontend_response {
    body_bytes     = var.diagnostics_frontend_response_body_bytes
    headers_to_log = var.diagnostics_frontend_response_headers
  }

  backend_request {
    body_bytes     = var.diagnostics_backend_request_body_bytes
    headers_to_log = var.diagnostics_backend_request_headers
  }

  backend_response {
    body_bytes     = var.diagnostics_backend_response_body_bytes
    headers_to_log = var.diagnostics_backend_response_headers
  }
}

# Data source to retrieve outbound IPs (useful for firewall rules)
data "azurerm_api_management" "outbound_ips" {
  name                = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  depends_on          = [azurerm_api_management.this]
}
