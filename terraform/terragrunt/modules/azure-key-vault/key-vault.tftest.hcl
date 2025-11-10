# Tests for azure-key-vault module
# Validates configuration, naming, security, and diagnostics
# Uses data source to look up current Azure context (no hardcoded UUIDs)

provider "azurerm" {
  features {}
}

run "validate_naming_with_suffix" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = length(local.use_suffix) == 1
    error_message = "Should create random suffix when use_random_suffix=true"
  }

  # Note: Cannot test actual suffix value at plan time (random_string is unknown)
  # Suffix pattern and length are verified by variable validation
}

run "validate_naming_without_suffix" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = false
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = length(local.use_suffix) == 0
    error_message = "Should not create random suffix when use_random_suffix=false"
  }

  assert {
    condition     = local.name_with_suffix == "kv-test"
    error_message = "Name without suffix should equal input name"
  }
}

run "validate_key_vault_configuration" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.location == "uksouth"
    error_message = "Key Vault should be in correct location"
  }

  assert {
    condition     = azurerm_key_vault.this.resource_group_name == "rg-test"
    error_message = "Key Vault should be in correct resource group"
  }

  assert {
    condition     = azurerm_key_vault.this.sku_name == "standard"
    error_message = "Key Vault should use standard SKU"
  }

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "Key Vault should have RBAC authorization enabled"
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == false
    error_message = "Purge protection should match variable"
  }

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 7
    error_message = "Soft delete retention should match variable"
  }

  assert {
    condition     = azurerm_key_vault.this.tenant_id == data.azurerm_client_config.current.tenant_id
    error_message = "Key Vault should use tenant ID from current Azure context"
  }
}

run "validate_security_defaults" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == true
    error_message = "Public network access should be enabled by default"
  }

  assert {
    condition     = azurerm_key_vault.this.enabled_for_deployment == false
    error_message = "Deployment access should be disabled by default"
  }

  assert {
    condition     = azurerm_key_vault.this.enabled_for_disk_encryption == false
    error_message = "Disk encryption access should be disabled by default"
  }

  assert {
    condition     = azurerm_key_vault.this.enabled_for_template_deployment == false
    error_message = "Template deployment access should be disabled by default"
  }
}

run "validate_premium_sku" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "premium"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.sku_name == "premium"
    error_message = "Key Vault should use premium SKU when specified"
  }
}

run "validate_purge_protection_enabled" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = true
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "Purge protection should be enabled when specified"
  }
}

run "validate_tags" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = azurerm_key_vault.this.tags["test"] == "true"
    error_message = "Key Vault should have custom tags"
  }
}

run "validate_outputs" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = false # Set to false so output is known at plan time
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = output.name == "kv-test"
    error_message = "Output name should match Key Vault name"
  }

  # Note: output.id is unknown at plan time, cannot test
}

run "validate_diagnostics_not_created_without_workspace" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    log_analytics_workspace_id = null
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostics should not be created when workspace ID is null"
  }
}

run "validate_diagnostics_created_with_workspace" {
  command = plan

  variables {
    name                       = "kv-test"
    location                   = "uksouth"
    resource_group_name        = "rg-test"
    sku_name                   = "standard"
    use_random_suffix          = true
    enable_rbac_authorization  = true
    purge_protection_enabled   = false
    soft_delete_retention_days = 7
    # Using mock subscription ID for testing (not committed as actual secret)
    log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
    tags = {
      test = "true"
    }
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 1
    error_message = "Diagnostics should be created when workspace ID is provided"
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this["enabled"].name == "keyvault-diagnostics"
    error_message = "Diagnostic setting should have correct name"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.this["enabled"].enabled_log : log.category], "AuditEvent")
    error_message = "Should enable AuditEvent logging"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.this["enabled"].enabled_log : log.category], "AzurePolicyEvaluationDetails")
    error_message = "Should enable AzurePolicyEvaluationDetails logging"
  }
}
