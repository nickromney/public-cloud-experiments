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

  extra_tags = merge(
    {
      sandbox_expires_hours = var.sandbox_expires_in_hours
      sandbox_type          = "pluralsight"
    },
    each.value.tags
  )
}

# Data sources for existing resource groups
# Support both full resource ID and just the name
data "azurerm_resource_group" "existing" {
  for_each = var.existing_resource_groups

  name = can(regex("^/subscriptions/", each.value)) ? split("/", each.value)[4] : each.value
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

  # Map all container registries (created and existing) by key
  container_registry_ids = merge(
    { for k, v in azurerm_container_registry.main : k => v.id },
    var.existing_container_registries
  )

  # Map all vnets (created and existing) by key
  vnet_ids = merge(
    { for k, v in module.vnet : k => v.id },
    var.existing_vnets
  )

  # Map all subnets (created and existing) by key
  subnet_ids = merge(
    { for k, v in module.subnet : k => v.id },
    var.existing_subnets
  )

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

  # Disable Azure Defender for sandbox (no permissions to read security pricing)
  advanced_threat_protection_enabled = false

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = merge(
    {
      purpose               = each.value.purpose
      sandbox_expires_hours = var.sandbox_expires_in_hours
    },
    each.value.tags
  )
}

# Azure Container Registries - direct resource to avoid count issues
resource "azurerm_container_registry" "main" {
  for_each = var.container_registries

  name                = lower(replace("acr${each.key}${var.client_name}${var.environment}", "-", ""))
  resource_group_name = local.resource_group_names[each.value.resource_group_key]
  location            = module.azure_region.location
  sku                 = each.value.sku
  admin_enabled       = each.value.admin_enabled

  # Public network access for Pluralsight sandbox (no private endpoints)
  public_network_access_enabled = true

  # Data endpoint only for Premium SKU
  data_endpoint_enabled = each.value.sku == "Premium" ? each.value.data_endpoint_enabled : false

  # Zone redundancy only for Premium SKU
  zone_redundancy_enabled = each.value.sku == "Premium" ? each.value.zone_redundancy_enabled : false

  # Anonymous pull settings
  anonymous_pull_enabled = each.value.anonymous_pull_enabled

  tags = merge(
    {
      environment           = var.environment
      sandbox_expires_hours = var.sandbox_expires_in_hours
      managed_by            = "terraform"
    },
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

  extra_tags = merge(
    { sandbox_expires_hours = var.sandbox_expires_in_hours },
    each.value.tags
  )
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
  purge_protection_enabled   = each.value.purge_protection # Usually false for sandbox

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = merge(
    { sandbox_expires_hours = var.sandbox_expires_in_hours },
    each.value.tags
  )
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

  extra_tags = merge(
    { sandbox_expires_hours = var.sandbox_expires_in_hours },
    each.value.tags
  )
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

  application_settings = merge(
    {
      "FUNCTIONS_WORKER_RUNTIME" = each.value.runtime_stack
    },
    # Add Container Registry connection if registry is specified
    each.value.container_registry_key != null ? {
      "ACR_LOGIN_SERVER" = azurerm_container_registry.main[each.value.container_registry_key].login_server
      "ACR_NAME"         = azurerm_container_registry.main[each.value.container_registry_key].name
    } : {}
  )

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

  extra_tags = merge(
    { sandbox_expires_hours = var.sandbox_expires_in_hours },
    each.value.tags
  )
}

# Virtual Networks - presence in map means create
module "vnet" {
  for_each = var.vnets

  source  = "claranet/vnet/azurerm"
  version = "~> 8.0"

  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  cidrs = each.value.cidrs

  extra_tags = merge(
    { sandbox_expires_hours = var.sandbox_expires_in_hours },
    each.value.tags
  )
}

# Subnets - presence in map means create
module "subnet" {
  for_each = var.subnets

  source  = "claranet/subnet/azurerm"
  version = "~> 8.0"

  location_short = module.azure_region.location_short
  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  name_suffix = each.value.name_suffix

  # Support both created and existing vnets
  virtual_network_name = coalesce(
    try(module.vnet[each.value.vnet_key].name, null),
    each.value.existing_vnet_name
  )

  cidrs             = each.value.cidrs
  service_endpoints = each.value.service_endpoints

  # Note: Azure subnets don't support tags directly
}

# Direct storage account creation (avoiding Claranet module security pricing issues)
resource "azurerm_storage_account" "main" {
  for_each = var.simple_storage_accounts

  name                     = lower(replace("st${each.key}${var.environment}", "-", ""))
  resource_group_name      = local.resource_group_names[each.value.resource_group_key]
  location                 = module.azure_region.location
  account_tier             = each.value.account_tier
  account_replication_type = each.value.replication_type

  tags = merge(
    {
      environment           = var.environment
      sandbox_expires_hours = var.sandbox_expires_in_hours
      managed_by            = "terraform"
    },
    each.value.tags
  )
}

# SSH key for AKS nodes
resource "tls_private_key" "aks_ssh" {
  for_each = var.aks_clusters

  algorithm = "RSA"
  rsa_bits  = 2048
}

# AKS Clusters - presence in map means create
module "aks" {
  for_each = var.aks_clusters

  source  = "claranet/aks-light/azurerm"
  version = "~> 8.6"

  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  environment    = var.environment
  stack          = each.key

  # Support both created and existing resource groups
  resource_group_name = coalesce(
    try(local.resource_group_names[each.value.resource_group_key], null),
    each.value.existing_resource_group_id != null ? split("/", each.value.existing_resource_group_id)[4] : null
  )

  kubernetes_version = each.value.kubernetes_version
  service_cidr       = each.value.service_cidr

  # Subnet configuration
  nodes_subnet = {
    name = coalesce(
      try(module.subnet[each.value.subnet_key].name, null),
      each.value.existing_subnet_name
    )
    virtual_network_name = coalesce(
      try(module.vnet[each.value.vnet_key].name, null),
      each.value.existing_vnet_name
    )
  }

  # Public cluster for Pluralsight sandboxes (no private endpoint support)
  private_cluster_enabled = false

  # Default node pool configuration
  default_node_pool = {
    vm_size             = each.value.default_node_pool.vm_size
    os_disk_size_gb     = each.value.default_node_pool.os_disk_size_gb
    enable_auto_scaling = each.value.default_node_pool.enable_auto_scaling
    min_count           = each.value.default_node_pool.min_count
    max_count           = each.value.default_node_pool.max_count
    node_count          = each.value.default_node_pool.node_count
  }

  # Additional node pools
  node_pools = each.value.node_pools

  # Linux profile with SSH key
  linux_profile = {
    username = each.value.linux_username
    ssh_key  = tls_private_key.aks_ssh[each.key].public_key_openssh
  }

  # Don't attach container registry through the module to avoid count issues
  # We handle this with a separate azurerm_role_assignment resource below
  container_registry_id = null

  # OMS agent configuration (disabled for sandbox - no log analytics)
  oms_agent = null

  # Disable data collection rule by setting enabled to false
  data_collection_rule = {
    enabled = false
  }

  # Conditionally enable diagnostics based on local flag
  logs_destinations_ids = local.enable_diagnostics ? compact([
    try(module.storage["logs"].id, ""),
    try(module.run["shared"].log_analytics_workspace_id, ""),
  ]) : []

  extra_tags = merge(
    {
      sandbox_expires_hours = var.sandbox_expires_in_hours
      purpose               = "kubernetes-sandbox"
    },
    each.value.tags
  )
}

# NOTE: Pluralsight sandbox limitations:
# - No role assignments allowed (cannot grant AKS pull access to ACR)
# - No container operations allowed (cannot push/pull images)
# The ACR is created for demonstration purposes only
