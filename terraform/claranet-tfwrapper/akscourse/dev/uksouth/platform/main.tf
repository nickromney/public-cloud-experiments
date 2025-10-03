module "azure_region" {
  source  = "claranet/regions/azurerm"
  version = "~> 8.0"

  azure_region = var.azure_region
}

# Resource Groups - presence in map means create
module "rg" {
  for_each = var.resource_groups

  source  = "claranet/rg/azurerm"
  version = "~> 8.0"

  location       = coalesce(each.value.location, module.azure_region.location)
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key

  extra_tags = each.value.tags
}

# Data sources for existing resource groups
# We need to fetch them to get the name from the ID
data "azurerm_resource_group" "existing" {
  for_each = var.existing_resource_groups

  name = split("/", each.value)[4] # Extract name from ID: /subscriptions/xxx/resourceGroups/NAME
}

# Locals for resource lookups and configuration
locals {
  # Map all resource groups (created and existing) by key
  # For existing RGs, we extract the name from the data source
  resource_group_names = merge(
    { for k, v in module.rg : k => v.name },
    { for k, v in data.azurerm_resource_group.existing : k => v.name }
  )

  # Map all storage accounts (created and existing) by key
  storage_account_ids = merge(
    { for k, v in module.storage : k => v.id },
    var.existing_storage_accounts
  )

  # Map all log analytics workspaces (created and existing) by key
  log_analytics_workspace_ids = merge(
    { for k, v in module.run : k => v.log_analytics_workspace_id },
    var.existing_log_analytics_workspaces
  )

  # Note: Add similar locals for other resource types as needed
  # e.g., key_vault_ids, aks_cluster_ids when you start using them

  # Disable diagnostics for initial deployment to avoid circular dependencies
  # Set to true after infrastructure exists
  enable_diagnostics = false
}

# Storage Accounts - presence in map means create
module "storage" {
  for_each = var.storage_accounts

  source  = "claranet/storage-account/azurerm"
  version = "~> 8.6"

  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key
  location       = module.azure_region.location
  location_short = module.azure_region.location_short

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  account_tier             = each.value.account_tier
  account_replication_type = each.value.replication_type

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = merge(
    { purpose = each.value.purpose },
    each.value.tags
  )
}

# Log Analytics Workspaces using run module - presence in map means create
module "run" {
  for_each = var.log_analytics_workspaces

  source  = "claranet/run/azurerm"
  version = "~> 8.8"

  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key
  location       = module.azure_region.location
  location_short = module.azure_region.location_short

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  monitoring_function_enabled = false
  backup_vm_enabled           = false
  automation_account_enabled  = false

  log_analytics_workspace_retention_in_days = each.value.retention_days

  extra_tags = each.value.tags
}

# Key Vaults - presence in map means create
module "key_vault" {
  for_each = var.key_vaults

  source  = "claranet/keyvault/azurerm"
  version = "~> 8.1"

  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key
  location       = module.azure_region.location
  location_short = module.azure_region.location_short

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  soft_delete_retention_days = each.value.soft_delete_days
  purge_protection_enabled   = each.value.purge_protection

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = each.value.tags
}

# App Service Plans - presence in map means create
module "app_service_plan" {
  for_each = var.app_service_plans

  source  = "claranet/app-service-plan/azurerm"
  version = "~> 8.2"

  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key
  location       = module.azure_region.location
  location_short = module.azure_region.location_short

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  os_type      = each.value.os_type
  sku_name     = each.value.sku_name
  worker_count = each.value.worker_count

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = each.value.tags
}

# Function Apps - presence in map means create
module "function_app" {
  for_each = var.function_apps

  source  = "claranet/function-app/azurerm"
  version = "~> 8.5"

  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key
  location       = module.azure_region.location
  location_short = module.azure_region.location_short

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  os_type              = "Linux"
  function_app_version = 4

  # Use existing storage if specified
  use_existing_storage_account = each.value.existing_storage_account_id != null
  storage_account_id = coalesce(
    each.value.existing_storage_account_id,
    try(local.storage_account_ids[each.value.storage_account_key], null)
  )

  # Map runtime stacks to their correct Azure version key names
  site_config = {
    application_stack = {
      "${each.value.runtime_stack == "dotnet" ? "dotnet_core" : each.value.runtime_stack}_version" = each.value.runtime_version
    }
  }

  application_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = each.value.runtime_stack
  }

  storage_account_identity_type         = "SystemAssigned"
  storage_account_network_rules_enabled = false

  # Support both created and existing log analytics workspaces for app insights
  application_insights_enabled = each.value.app_insights_enabled
  application_insights_log_analytics_workspace_id = each.value.app_insights_enabled ? coalesce(
    each.value.existing_log_analytics_id,
    try(local.log_analytics_workspace_ids[each.value.log_analytics_workspace_key], null),
    try(local.log_analytics_workspace_ids["shared"], null)
  ) : null

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = each.value.tags
}

# AKS Clusters - presence in map means create
resource "azurerm_kubernetes_cluster" "aks" {
  for_each = var.aks_clusters

  name       = "${var.client_name}-${var.environment}-aks-${each.key}"
  location   = module.azure_region.location
  dns_prefix = "${var.client_name}-${var.environment}-${each.key}"

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  kubernetes_version = each.value.kubernetes_version

  default_node_pool {
    name           = "default"
    node_count     = each.value.default_node_pool.node_count
    vm_size        = each.value.default_node_pool.vm_size
    vnet_subnet_id = each.value.default_node_pool.vnet_subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  tags = merge(
    {
      environment = var.environment
      cluster     = each.key
      managed_by  = "terraform"
    },
    each.value.tags
  )
}
