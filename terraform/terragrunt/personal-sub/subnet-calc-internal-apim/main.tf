locals {
  common_tags = merge({
    environment = var.environment
    project     = var.project_name
    managed_by  = "terragrunt"
  }, var.tags)

  cloudflare_restrictions = var.web_app.cloudflare_only ? [
    for idx, ip in var.cloudflare_ips : {
      name       = "Cloudflare-${idx}"
      ip_address = ip
      priority   = 100 + idx
    }
  ] : []
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
# Networking
# -----------------------------------------------------------------------------

resource "azurerm_virtual_network" "this" {
  name                = "${var.project_name}-${var.environment}-vnet"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  address_space       = [var.vnet_cidr]
  tags                = local.common_tags
}

resource "azurerm_subnet" "web_integration" {
  name                 = "snet-web-integration"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnets.web_integration_cidr]

  delegation {
    name = "delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action"
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnets.private_endpoints_cidr]
}

resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnets.apim_cidr]
}

# -----------------------------------------------------------------------------
# App Service Plan & Web App
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "web" {
  name                = "plan-${var.project_name}-${var.environment}-web"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.web_app.plan_sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "web" {
  name                = var.web_app.name != "" ? var.web_app.name : "web-${var.project_name}-${var.environment}"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  service_plan_id     = azurerm_service_plan.web.id
  identity {
    type = "SystemAssigned"
  }

  https_only = true

  site_config {
    minimum_tls_version    = "1.2"
    ftps_state             = "Disabled"
    http2_enabled          = true
    always_on              = var.web_app.always_on
    vnet_route_all_enabled = true
    linux_fx_version       = "NODE|${var.web_app.runtime_version}"

    dynamic "ip_restriction" {
      for_each = local.cloudflare_restrictions
      content {
        name       = ip_restriction.value.name
        action     = "Allow"
        ip_address = ip_restriction.value.ip_address
        priority   = ip_restriction.value.priority
      }
    }

    dynamic "ip_restriction" {
      for_each = var.web_app.cloudflare_only ? [] : [1]
      content {
        name       = "AllowAll"
        priority   = 100
        action     = "Allow"
        ip_address = "Any"
      }
    }

    ip_restriction {
      name                      = "AllowPrivateEndpoints"
      priority                  = 400
      action                    = "Allow"
      virtual_network_subnet_id = azurerm_subnet.private_endpoints.id
    }

    default_documents = ["index.html"]
  }

  app_settings = merge({
    "WEBSITE_RUN_FROM_PACKAGE"       = "0"
    "WEBSITE_NODE_DEFAULT_VERSION"   = "~${var.web_app.runtime_version}"
    "SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
    "API_BASE_URL"                   = var.web_app.api_base_url
  }, try(var.web_app.app_settings, {}))

  tags = local.common_tags
}

resource "azurerm_app_service_virtual_network_swift_connection" "web" {
  app_service_id = azurerm_linux_web_app.web.id
  subnet_id      = azurerm_subnet.web_integration.id
}

resource "azurerm_private_endpoint" "web" {
  count               = var.web_app.enable_private_endpoint ? 1 : 0
  name                = "pe-${azurerm_linux_web_app.web.name}"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-${azurerm_linux_web_app.web.name}-connection"
    private_connection_resource_id = azurerm_linux_web_app.web.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }
}

resource "azurerm_private_dns_zone" "webapps" {
  count               = var.web_app.enable_private_endpoint || var.function_app.enable_private_endpoint ? 1 : 0
  name                = "privatelink.azurewebsites.net"
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "webapps" {
  count                 = var.web_app.enable_private_endpoint || var.function_app.enable_private_endpoint ? 1 : 0
  name                  = "link-${var.project_name}-webapps"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.webapps[0].name
  virtual_network_id    = azurerm_virtual_network.this.id
}

# -----------------------------------------------------------------------------
# Function App
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "function" {
  name                = "plan-${var.project_name}-${var.environment}-func"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  os_type             = "Linux"
  sku_name            = var.function_app.plan_sku
  tags                = local.common_tags
}

resource "azurerm_storage_account" "function" {
  name                     = var.function_app.storage_account_name != "" ? var.function_app.storage_account_name : lower(replace("st${var.project_name}${var.environment}func", "-", ""))
  resource_group_name      = local.rg_name
  location                 = local.rg_loc
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  tags                     = local.common_tags
}

resource "azurerm_linux_function_app" "this" {
  name                          = var.function_app.name != "" ? var.function_app.name : "func-${var.project_name}-${var.environment}"
  resource_group_name           = local.rg_name
  location                      = local.rg_loc
  service_plan_id               = azurerm_service_plan.function.id
  storage_account_name          = azurerm_storage_account.function.name
  storage_account_access_key    = azurerm_storage_account.function.primary_access_key
  https_only                    = true
  public_network_access_enabled = false

  site_config {
    ftps_state             = "Disabled"
    minimum_tls_version    = "1.2"
    http2_enabled          = true
    vnet_route_all_enabled = true
    ip_restriction {
      name                      = "AllowPrivateEndpoints"
      priority                  = 100
      action                    = "Allow"
      virtual_network_subnet_id = azurerm_subnet.private_endpoints.id
    }

    application_stack {
      python_version = var.function_app.runtime == "python" ? var.function_app.runtime_version : null
      node_version   = var.function_app.runtime == "node" ? var.function_app.runtime_version : null
      dotnet_version = var.function_app.runtime == "dotnet-isolated" ? var.function_app.runtime_version : null
    }
  }

  app_settings = merge({
    "FUNCTIONS_WORKER_RUNTIME" = var.function_app.runtime == "dotnet-isolated" ? "dotnet-isolated" : var.function_app.runtime
    "WEBSITE_RUN_FROM_PACKAGE" = var.function_app.run_from_package ? "1" : "0"
  }, try(var.function_app.app_settings, {}))

  tags = local.common_tags
}

resource "azurerm_private_endpoint" "function" {
  count               = var.function_app.enable_private_endpoint ? 1 : 0
  name                = "pe-${azurerm_linux_function_app.this.name}"
  resource_group_name = local.rg_name
  location            = local.rg_loc
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "pe-${azurerm_linux_function_app.this.name}-connection"
    private_connection_resource_id = azurerm_linux_function_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }
}

# Note: VNet link for privatelink.azurewebsites.net is created once at line 179
# A single VNet link provides DNS resolution for all private endpoints in that VNet
# -----------------------------------------------------------------------------
# API Management
# -----------------------------------------------------------------------------

module "apim" {
  source = "../../modules/azure-apim"

  name                = var.apim.name != "" ? var.apim.name : "apim-${var.project_name}-${var.environment}"
  location            = local.rg_loc
  resource_group_name = local.rg_name
  publisher_name      = var.apim.publisher_name
  publisher_email     = var.apim.publisher_email
  sku_name            = var.apim.sku_name

  # Internal VNet integration
  virtual_network_type          = "Internal"
  subnet_id                     = azurerm_subnet.apim.id
  public_network_access_enabled = false

  tags = local.common_tags
}

resource "azurerm_private_dns_zone" "apim" {
  name                = "azure-api.net"
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "apim" {
  name                  = "link-${var.project_name}-apim"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_private_dns_a_record" "apim" {
  depends_on          = [module.apim]
  name                = module.apim.name
  resource_group_name = local.rg_name
  zone_name           = azurerm_private_dns_zone.apim.name
  ttl                 = 300
  records             = [module.apim.private_ip_addresses[0]]
}

resource "azurerm_api_management_api" "function_api" {
  name                = "api-${var.project_name}"
  resource_group_name = local.rg_name
  api_management_name = module.apim.name
  revision            = "1"
  display_name        = "Function API"
  path                = var.apim.api_path
  protocols           = ["https"]
}

resource "azurerm_api_management_backend" "function" {
  name                = "backend-${var.project_name}"
  resource_group_name = local.rg_name
  api_management_name = module.apim.name
  protocol            = "http"
  url                 = "https://${azurerm_linux_function_app.this.default_hostname}"
  resource_id         = azurerm_linux_function_app.this.id
  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

resource "azurerm_api_management_api_policy" "function_api" {
  api_name            = azurerm_api_management_api.function_api.name
  resource_group_name = local.rg_name
  api_management_name = module.apim.name
  xml_content = coalesce(var.apim.policy_xml, templatefile("${path.module}/templates/api-policy.xml.tftpl", {
    tenant_id     = var.tenant_id
    audience      = local.apim_audience
    required_role = one([for role in azuread_application.apim_api.app_role : role.value if role.value == "invoke"])
  }))
}

# -----------------------------------------------------------------------------
# Azure AD (Managed identity + validate-jwt setup)
# -----------------------------------------------------------------------------

locals {
  apim_identifier_uri = var.apim.identifier_uri != "" ? var.apim.identifier_uri : "api://${module.apim.name}"
  apim_audience       = local.apim_identifier_uri
}

resource "azuread_application" "apim_api" {
  display_name     = "${var.project_name}-${var.environment}-apim-api"
  identifier_uris  = [local.apim_identifier_uri]
  sign_in_audience = "AzureADMyOrg"

  api {
    requested_access_token_version = 2
  }

  app_role {
    allowed_member_types = ["Application"]
    description          = "Invoke the APIM-protected API"
    display_name         = "Invoke"
    enabled              = true
    # Generate deterministic UUID using DNS namespace (RFC 4122 Appendix C)
    # Ensures consistent role ID across terraform apply runs for same project/environment
    id    = uuidv5("6ba7b811-9dad-11d1-80b4-00c04fd430c8", "${var.project_name}-${var.environment}-invoke-role")
    value = "invoke"
  }
}

resource "azuread_service_principal" "apim_api" {
  client_id = azuread_application.apim_api.client_id
}

resource "azuread_app_role_assignment" "web_to_apim" {
  depends_on          = [azuread_service_principal.apim_api, azurerm_linux_web_app.web]
  principal_object_id = azurerm_linux_web_app.web.identity[0].principal_id
  resource_object_id  = azuread_service_principal.apim_api.object_id
  app_role_id         = one([for role in azuread_application.apim_api.app_role : role.id if role.value == "invoke"])
}
