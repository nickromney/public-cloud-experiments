# Tests for subnet-calc-shared-components stack
# Validates observability and secrets management infrastructure
# Uses data source to look up existing Azure resource groups for testing

provider "azurerm" {
  features {}
}

variables {
  location              = "uksouth"
  project_name          = "subnetcalc"
  component_name        = "shared"
  environment           = "dev"
  resource_group_name   = "rg-test-shared"
  create_resource_group = true

  key_vault_sku                        = "standard"
  key_vault_use_random_suffix          = true
  key_vault_purge_protection_enabled   = false
  key_vault_soft_delete_retention_days = 7
  log_retention_days                   = 30

  tags = {
    test = "true"
  }
}

# Validation tests - these test input constraints

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
    location = "westus" # Invalid
  }

  expect_failures = [
    var.location,
  ]
}

run "test_invalid_project_name" {
  command = plan

  variables {
    project_name = "this-project-name-is-way-too-long-for-azure-naming" # >24 chars
  }

  expect_failures = [
    var.project_name,
  ]
}

run "test_invalid_log_retention_too_low" {
  command = plan

  variables {
    log_retention_days = 29 # Below minimum
  }

  expect_failures = [
    var.log_retention_days,
  ]
}

run "test_invalid_log_retention_too_high" {
  command = plan

  variables {
    log_retention_days = 731 # Above maximum
  }

  expect_failures = [
    var.log_retention_days,
  ]
}

run "test_invalid_kv_soft_delete_too_low" {
  command = plan

  variables {
    key_vault_soft_delete_retention_days = 6 # Below minimum
  }

  expect_failures = [
    var.key_vault_soft_delete_retention_days,
  ]
}

run "test_invalid_kv_soft_delete_too_high" {
  command = plan

  variables {
    key_vault_soft_delete_retention_days = 91 # Above maximum
  }

  expect_failures = [
    var.key_vault_soft_delete_retention_days,
  ]
}

run "test_invalid_kv_sku" {
  command = plan

  variables {
    key_vault_sku = "basic" # Invalid
  }

  expect_failures = [
    var.key_vault_sku,
  ]
}

# Configuration tests - these test resource configuration

run "validate_resource_group_creation" {
  command = plan

  variables {
    create_resource_group = true
  }

  assert {
    condition     = length(local.resource_groups_to_create) == 1
    error_message = "Should create resource group when create_resource_group=true"
  }

  assert {
    condition     = length(local.resource_groups_existing) == 0
    error_message = "Should not use existing resource group when create_resource_group=true"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].name == "rg-test-shared"
    error_message = "Resource group name should match input"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].location == "uksouth"
    error_message = "Resource group location should match input"
  }
}

# Test existing resource group conditional logic
# Note: Uses created RG for testing since we can't guarantee discovery of backend RG
run "validate_resource_group_conditional" {
  command = plan

  variables {
    create_resource_group = true
    resource_group_name   = "rg-test-conditional"
  }

  # When create_resource_group=true
  assert {
    condition     = length(local.resource_groups_to_create) == 1
    error_message = "Should create one resource group when create_resource_group=true"
  }

  assert {
    condition     = length(local.resource_groups_existing) == 0
    error_message = "Should not reference existing RG when create_resource_group=true"
  }

  # Verify merge produces exactly one RG reference
  assert {
    condition     = length(local.resource_group_names) == 1
    error_message = "Merge logic should produce exactly one resource group name"
  }
}

run "validate_log_analytics_configuration" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.name == "log-subnetcalc-shared-dev"
    error_message = "Log Analytics workspace name should follow naming convention"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.location == "uksouth"
    error_message = "Log Analytics workspace should be in correct location"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "Log Analytics retention should match variable"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "Log Analytics should use PerGB2018 SKU"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["environment"] == "dev"
    error_message = "Tags should include environment"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.tags["managed_by"] == "terragrunt"
    error_message = "Tags should include managed_by"
  }
}

run "validate_key_vault_naming" {
  command = plan

  assert {
    condition     = length(local.kv_name) <= 20
    error_message = "Key Vault base name must be ≤20 chars to allow for 4-char suffix (24 char limit)"
  }

  assert {
    condition     = can(regex("^kv-sc-shared-dev$", local.kv_name))
    error_message = "Key Vault name should follow naming convention: kv-sc-{component}-{env}"
  }
}

run "validate_key_vault_configuration" {
  command = plan

  # Test module outputs (only check values known at plan time)
  # Note: name and vault_uri contain random suffix so aren't known until apply

  assert {
    condition     = module.key_vault.location == "uksouth"
    error_message = "Key Vault should be in correct location"
  }

  assert {
    condition     = module.key_vault.resource_group_name == "rg-test-shared"
    error_message = "Key Vault should be in correct resource group"
  }

  assert {
    condition     = can(module.key_vault.tenant_id)
    error_message = "Key Vault tenant_id output should be accessible"
  }
}

run "validate_diagnostics_configuration" {
  command = plan

  assert {
    condition     = azurerm_monitor_diagnostic_setting.kv.name == "keyvault-diagnostics"
    error_message = "Diagnostic setting should have correct name"
  }

  assert {
    condition     = length([for log in azurerm_monitor_diagnostic_setting.kv.enabled_log : log.category]) == 2
    error_message = "Should have exactly 2 enabled log categories"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.kv.enabled_log : log.category], "AuditEvent")
    error_message = "Should enable AuditEvent logging"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.kv.enabled_log : log.category], "AzurePolicyEvaluationDetails")
    error_message = "Should enable AzurePolicyEvaluationDetails logging"
  }
}

run "validate_rbac_assignment" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.kv_secrets_officer_current_user.role_definition_name == "Key Vault Secrets Officer"
    error_message = "Should assign Key Vault Secrets Officer role"
  }
}

run "validate_outputs" {
  command = plan

  assert {
    condition     = output.resource_group_name == "rg-test-shared"
    error_message = "Output resource_group_name should match input"
  }

  assert {
    condition     = output.resource_group_location == "uksouth"
    error_message = "Output resource_group_location should match location"
  }

  assert {
    condition     = output.log_analytics_workspace_name == "log-subnetcalc-shared-dev"
    error_message = "Output log_analytics_workspace_name should match created resource"
  }
}
