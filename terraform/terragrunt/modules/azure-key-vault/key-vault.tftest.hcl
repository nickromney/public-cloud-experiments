# Tests for azure-key-vault module
# Validates configuration, naming, security, and diagnostics

# Generate test data using random provider
run "setup" {
  command = plan

  module {
    source = "./tests/fixtures"
  }
}

variables {
  name                = "kv-test"
  location            = "uksouth"
  resource_group_name = "rg-test"
  tenant_id           = run.setup.tenant_id
  sku_name            = "standard"
  use_random_suffix   = true

  enable_rbac_authorization = true
  purge_protection_enabled  = false
  soft_delete_retention_days = 7

  log_analytics_workspace_id = null

  tags = {
    test = "true"
  }
}

run "validate_naming_with_suffix" {
  command = plan

  assert {
    condition     = length(local.random_suffix_map) == 1
    error_message = "Should create random suffix when use_random_suffix=true"
  }

  assert {
    condition     = can(regex("^kv-test-[a-z0-9]{4}$", local.name_with_suffix))
    error_message = "Name with suffix should follow pattern: {name}-{4chars}"
  }

  assert {
    condition     = length(local.name_with_suffix) <= 24
    error_message = "Key Vault name must not exceed 24 characters"
  }
}

run "validate_naming_without_suffix" {
  command = plan

  variables {
    use_random_suffix = false
  }

  assert {
    condition     = length(local.random_suffix_map) == 0
    error_message = "Should not create random suffix when use_random_suffix=false"
  }

  assert {
    condition     = local.name_with_suffix == "kv-test"
    error_message = "Name without suffix should equal input name"
  }
}

run "validate_key_vault_configuration" {
  command = plan

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
    condition     = azurerm_key_vault.this.tenant_id == run.setup.tenant_id
    error_message = "Key Vault should use correct tenant ID"
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
}

run "validate_security_defaults" {
  command = plan

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
    sku_name = "premium"
  }

  assert {
    condition     = azurerm_key_vault.this.sku_name == "premium"
    error_message = "Key Vault should use premium SKU when specified"
  }
}

run "validate_purge_protection_enabled" {
  command = plan

  variables {
    purge_protection_enabled = true
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "Purge protection should be enabled when specified"
  }
}

run "validate_tags" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.tags["test"] == "true"
    error_message = "Key Vault should have custom tags"
  }
}

run "validate_outputs" {
  command = plan

  assert {
    condition     = can(regex("^kv-test-[a-z0-9]{4}$", output.name))
    error_message = "Output name should include random suffix"
  }
}

run "validate_diagnostics_not_created_without_workspace" {
  command = plan

  variables {
    log_analytics_workspace_id = null
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this) == 0
    error_message = "Diagnostics should not be created when workspace ID is null"
  }
}

run "validate_diagnostics_created_with_workspace" {
  command = plan

  variables {
    log_analytics_workspace_id = "/subscriptions/${run.setup.subscription_id}/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
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
