variable "azure_region" {
  description = "Azure region to use (Pluralsight Sandbox supported regions)"
  type        = string

  validation {
    condition = contains([
      "eastus",
      "westus2"
    ], var.azure_region)
    error_message = "Azure region must be one of the Pluralsight Sandbox supported regions: eastus, westus2"
  }
}

variable "client_name" {
  description = "Client name/account used in naming"
  type        = string
  default     = "ps-sandbox" # Default for sandbox environments
}

variable "environment" {
  description = "Project environment"
  type        = string
  default     = "sbx" # Sandbox environment

  validation {
    condition     = contains(["sbx", "dev", "test"], var.environment)
    error_message = "Environment must be one of: sbx, dev, test (sandbox environments)"
  }
}

variable "subscription_id" {
  description = "Azure subscription ID (required for azurerm provider 4.x)"
  type        = string
}

variable "sandbox_expires_in_hours" {
  description = "Hours until sandbox expires (Pluralsight sandboxes last 4 hours)"
  type        = number
  default     = 4
}

# Resource Groups - always use map even if you think there's only one
# Presence in map means create. To use existing, add to existing_resource_groups instead.
variable "resource_groups" {
  description = "Map of resource groups to create"
  type = map(object({
    location = optional(string) # Override default location if needed
    tags     = optional(map(string), {})
  }))
  default = {}
}

variable "existing_resource_groups" {
  description = "Map of existing resource groups to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "platform" = "/subscriptions/xxx/resourceGroups/rg-platform-prod" }
}

# Storage Accounts - multiple with different purposes
# Presence in map means create. To use existing, add to existing_storage_accounts instead.
variable "storage_accounts" {
  description = "Map of storage accounts to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    account_tier               = optional(string, "Standard")
    replication_type           = optional(string, "LRS")
    purpose                    = optional(string, "general") # logs, state, function, general
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.storage_accounts :
      contains(["Standard", "Premium"], v.account_tier)
    ])
    error_message = "Storage account tier must be either 'Standard' or 'Premium'"
  }

  validation {
    condition = alltrue([
      for k, v in var.storage_accounts :
      contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], v.replication_type)
    ])
    error_message = "Storage account replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS"
  }

  validation {
    condition = alltrue([
      for k, v in var.storage_accounts :
      (v.resource_group_key != null && v.existing_resource_group_id == null) ||
      (v.resource_group_key == null && v.existing_resource_group_id != null)
    ])
    error_message = "Each storage account must specify either resource_group_key OR existing_resource_group_id, not both"
  }
}

variable "existing_storage_accounts" {
  description = "Map of existing storage accounts to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "logs" = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stlogs001" }
}

# Azure Container Registries
variable "container_registries" {
  description = "Map of Azure Container Registries to create for AKS testing"
  type = map(object({
    resource_group_key         = optional(string)          # Reference to key in resource_groups
    existing_resource_group_id = optional(string)          # Use existing resource group by ID
    sku                        = optional(string, "Basic") # Basic, Standard, Premium
    admin_enabled              = optional(bool, true)      # Enable admin user (useful for sandbox)
    # Note: anonymous_pull_enabled and data_endpoint_enabled removed - not supported by Claranet ACR module v8.2
    zone_redundancy_enabled = optional(bool, false) # Zone redundancy (Premium only)
    tags                    = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.container_registries :
      contains(["Basic", "Standard", "Premium"], v.sku)
    ])
    error_message = "Container Registry SKU must be one of: Basic, Standard, Premium"
  }

  validation {
    condition = alltrue([
      for k, v in var.container_registries :
      (v.resource_group_key != null && v.existing_resource_group_id == null) ||
      (v.resource_group_key == null && v.existing_resource_group_id != null)
    ])
    error_message = "Each Container Registry must specify either resource_group_key OR existing_resource_group_id, not both"
  }
}

variable "existing_container_registries" {
  description = "Map of existing Container Registries to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "main" = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/acr001" }
}


# App Service Plans - support multiple
# Presence in map means create. To use existing, add to existing_app_service_plans instead.
variable "app_service_plans" {
  description = "Map of App Service Plans to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    os_type                    = optional(string, "Linux")
    sku_name                   = string
    worker_count               = optional(number, 1)
    tags                       = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.app_service_plans :
      contains(["Linux", "Windows"], v.os_type)
    ])
    error_message = "App Service Plan os_type must be either 'Linux' or 'Windows'"
  }

  validation {
    condition = alltrue([
      for k, v in var.app_service_plans :
      v.worker_count >= 1 && v.worker_count <= 10
    ])
    error_message = "App Service Plan worker_count must be between 1 and 10"
  }
}

variable "existing_app_service_plans" {
  description = "Map of existing App Service Plans to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "main" = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.Web/serverFarms/plan-main" }
}

# Function Apps - support multiple
# Presence in map means create. To use existing, add to existing_function_apps instead.
variable "function_apps" {
  description = "Map of Function Apps to create"
  type = map(object({
    resource_group_key           = optional(string) # Reference to key in resource_groups
    existing_resource_group_id   = optional(string) # Use existing resource group by ID
    app_service_plan_key         = optional(string) # Reference to app_service_plans key
    existing_app_service_plan_id = optional(string) # Use existing app service plan by ID
    storage_account_key          = optional(string) # Reference to storage_accounts key
    existing_storage_account_id  = optional(string) # Use existing storage account by ID
    runtime_stack                = optional(string, "python")
    runtime_version              = optional(string, "3.11")
    app_insights_enabled         = optional(bool, true)
    log_analytics_workspace_key  = optional(string) # Reference to log_analytics_workspaces key
    existing_log_analytics_id    = optional(string) # Use existing Log Analytics workspace by ID

    # Container Registry connection (optional)
    container_registry_key = optional(string) # Reference to container_registries key

    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.function_apps :
      contains(["dotnet", "java", "node", "python", "powershell"], v.runtime_stack)
    ])
    error_message = "Function App runtime_stack must be one of: dotnet, java, node, python, powershell"
  }

  validation {
    condition = alltrue([
      for k, v in var.function_apps :
      (v.storage_account_key != null && v.existing_storage_account_id == null) ||
      (v.storage_account_key == null && v.existing_storage_account_id != null) ||
      (v.storage_account_key == null && v.existing_storage_account_id == null)
    ])
    error_message = "Each function app must specify either storage_account_key OR existing_storage_account_id, not both"
  }
}

# Log Analytics Workspaces
# Presence in map means create. To use existing, add to existing_log_analytics_workspaces instead.
variable "log_analytics_workspaces" {
  description = "Map of Log Analytics workspaces to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    retention_days             = optional(number, 30)
    tags                       = optional(map(string), {})
  }))
  default = {}
}

variable "existing_log_analytics_workspaces" {
  description = "Map of existing Log Analytics workspaces to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "shared" = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.OperationalInsights/workspaces/log-shared-001" }
}

# Key Vaults
# Presence in map means create. To use existing, add to existing_key_vaults instead.
variable "key_vaults" {
  description = "Map of Key Vaults to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    soft_delete_days           = optional(number, 7)
    purge_protection           = optional(bool, false) # Set to false for sandbox environments
    tags                       = optional(map(string), {})
  }))
  default = {}
}

variable "existing_key_vaults" {
  description = "Map of existing Key Vaults to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "platform" = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.KeyVault/vaults/kv-platform-001" }
}

# Virtual Networks
# Presence in map means create. To use existing, add to existing_vnets instead.
variable "vnets" {
  description = "Map of Virtual Networks to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    cidrs                      = list(string)
    tags                       = optional(map(string), {})
  }))
  default = {}
}

variable "existing_vnets" {
  description = "Map of existing Virtual Networks to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "main" = "/subscriptions/.../resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-main-001" }
}

# Subnets
# Presence in map means create. To use existing, add to existing_subnets instead.
variable "subnets" {
  description = "Map of Subnets to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID
    vnet_key                   = optional(string) # Reference to key in vnets
    existing_vnet_name         = optional(string) # Name of existing vnet
    name_suffix                = string
    cidrs                      = list(string)
    service_endpoints          = optional(list(string), [])
    tags                       = optional(map(string), {})
  }))
  default = {}
}

variable "existing_subnets" {
  description = "Map of existing Subnets to reference by ID"
  type        = map(string)
  default     = {}
  # Example: { "aks" = "/subscriptions/.../resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-main/subnets/snet-aks" }
}

# AKS Clusters
# Presence in map means create
variable "aks_clusters" {
  description = "Map of AKS clusters to create"
  type = map(object({
    resource_group_key         = optional(string) # Reference to key in resource_groups
    existing_resource_group_id = optional(string) # Use existing resource group by ID

    # Kubernetes configuration
    kubernetes_version = optional(string, "1.30")
    service_cidr       = optional(string, "10.0.16.0/22")

    # Network configuration
    subnet_key           = optional(string) # Reference to key in subnets
    existing_subnet_name = optional(string) # Name of existing subnet
    vnet_key             = optional(string) # Reference to key in vnets
    existing_vnet_name   = optional(string) # Name of existing vnet

    # Default node pool
    default_node_pool = optional(object({
      vm_size             = optional(string, "Standard_B2ms")
      os_disk_size_gb     = optional(number, 64)
      enable_auto_scaling = optional(bool, true)
      min_count           = optional(number, 1)
      max_count           = optional(number, 3)
      node_count          = optional(number, 1)
    }), {})

    # Additional node pools
    node_pools = optional(list(object({
      name                = string
      vm_size             = optional(string, "Standard_B2ms")
      os_disk_type        = optional(string, "Managed")
      os_disk_size_gb     = optional(number, 64)
      vnet_subnet_id      = optional(string) # For explicit subnet reference
      enable_auto_scaling = optional(bool, true)
      min_count           = optional(number, 1)
      max_count           = optional(number, 3)
      node_count          = optional(number, 1)
    })), [])

    # Linux configuration
    linux_username = optional(string, "azureuser")

    # Container Registry attachment
    container_registry_key = optional(string) # Reference to container_registries key

    # Monitoring
    enable_oms_agent            = optional(bool, false)
    log_analytics_workspace_key = optional(string) # Reference to log_analytics_workspaces key

    tags = optional(map(string), {})
  }))
  default = {}
}
