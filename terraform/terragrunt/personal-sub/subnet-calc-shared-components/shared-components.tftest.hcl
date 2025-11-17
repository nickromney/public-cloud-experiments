# Tests for subnet-calc-shared-components stack
# Validates observability and secrets management infrastructure with map-based (0-to-n) patterns

provider "azurerm" {
  features {}
}

variables {
  environment = "dev"
  tags = {
    test = "true"
  }
}

# -----------------------------------------------------------------------------
# Variable Validation Tests
# -----------------------------------------------------------------------------

run "test_invalid_environment" {
  command = plan

  variables {
    environment = "production" # Invalid
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
  }

  expect_failures = [
    var.environment,
  ]
}

run "test_invalid_resource_group_location" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "westus" # Invalid - must be uksouth or ukwest
      }
    }
  }

  expect_failures = [
    var.resource_groups,
  ]
}

run "test_invalid_log_retention_too_low" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    log_analytics_workspaces = {
      main = {
        name              = "log-test"
        retention_in_days = 29 # Below minimum of 30
      }
    }
  }

  expect_failures = [
    var.log_analytics_workspaces,
  ]
}

run "test_invalid_log_retention_too_high" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    log_analytics_workspaces = {
      main = {
        name              = "log-test"
        retention_in_days = 731 # Above maximum of 730
      }
    }
  }

  expect_failures = [
    var.log_analytics_workspaces,
  ]
}

run "test_invalid_kv_soft_delete_too_low" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    key_vaults = {
      main = {
        name                       = "kv-test"
        soft_delete_retention_days = 6 # Below minimum of 7
      }
    }
  }

  expect_failures = [
    var.key_vaults,
  ]
}

run "test_invalid_kv_soft_delete_too_high" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    key_vaults = {
      main = {
        name                       = "kv-test"
        soft_delete_retention_days = 91 # Above maximum of 90
      }
    }
  }

  expect_failures = [
    var.key_vaults,
  ]
}

run "test_invalid_kv_sku" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    key_vaults = {
      main = {
        name = "kv-test"
        sku  = "basic" # Invalid - must be standard or premium
      }
    }
  }

  expect_failures = [
    var.key_vaults,
  ]
}

# -----------------------------------------------------------------------------
# Configuration Tests
# -----------------------------------------------------------------------------

run "validate_resource_group_creation" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
        tags = {
          purpose = "testing"
        }
      }
    }
  }

  assert {
    condition     = azurerm_resource_group.this["main"].name == "rg-test-shared"
    error_message = "Resource group name should match input"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].location == "uksouth"
    error_message = "Resource group location should match input"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].tags["environment"] == "dev"
    error_message = "Resource group should have environment tag from common_tags"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].tags["managed_by"] == "terragrunt"
    error_message = "Resource group should have managed_by tag"
  }

  assert {
    condition     = azurerm_resource_group.this["main"].tags["purpose"] == "testing"
    error_message = "Resource group should have custom tags merged"
  }
}

run "validate_log_analytics_workspace" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    log_analytics_workspaces = {
      main = {
        name              = "log-test-workspace"
        sku               = "PerGB2018"
        retention_in_days = 90
      }
    }
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this["main"].name == "log-test-workspace"
    error_message = "Log Analytics workspace name should match input"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this["main"].sku == "PerGB2018"
    error_message = "Log Analytics workspace should use correct SKU"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this["main"].retention_in_days == 90
    error_message = "Log Analytics retention should match input"
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this["main"].tags["environment"] == "dev"
    error_message = "Log Analytics workspace should have environment tag"
  }
}

run "validate_key_vault_module" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    key_vaults = {
      main = {
        name                       = "kv-test"
        sku                        = "standard"
        use_random_suffix          = true
        purge_protection_enabled   = false
        soft_delete_retention_days = 7
        enable_rbac_authorization  = true
      }
    }
  }

  assert {
    condition     = module.key_vaults["main"].location == "uksouth"
    error_message = "Key Vault should be in correct location"
  }

  assert {
    condition     = module.key_vaults["main"].resource_group_name == "rg-test-shared"
    error_message = "Key Vault should be in correct resource group"
  }
}

run "validate_key_vault_diagnostics" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    log_analytics_workspaces = {
      main = {
        name              = "log-test"
        retention_in_days = 30
      }
    }
    key_vaults = {
      main = {
        name                        = "kv-test"
        log_analytics_workspace_key = "main"
      }
    }
  }

  assert {
    condition     = azurerm_monitor_diagnostic_setting.kv["main"].name == "keyvault-diagnostics"
    error_message = "Diagnostic setting should have correct name"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.kv["main"].enabled_log : log.category], "AuditEvent")
    error_message = "Should enable AuditEvent logging"
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.kv["main"].enabled_log : log.category], "AzurePolicyEvaluationDetails")
    error_message = "Should enable AzurePolicyEvaluationDetails logging"
  }
}

run "validate_rbac_assignment" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-shared"
        location = "uksouth"
      }
    }
    key_vaults = {
      main = {
        name = "kv-test"
      }
    }
    grant_current_user_key_vault_access = true
  }

  assert {
    condition     = azurerm_role_assignment.kv_secrets_officer_current_user["main"].role_definition_name == "Key Vault Secrets Officer"
    error_message = "Should assign Key Vault Secrets Officer role"
  }
}

run "validate_multiple_resources" {
  command = plan

  variables {
    resource_groups = {
      main = {
        name     = "rg-test-1"
        location = "uksouth"
      }
      secondary = {
        name     = "rg-test-2"
        location = "ukwest"
      }
    }
    log_analytics_workspaces = {
      primary = {
        name              = "log-primary"
        retention_in_days = 30
      }
      secondary = {
        name              = "log-secondary"
        retention_in_days = 90
      }
    }
    key_vaults = {
      dev = {
        name = "kv-dev"
        sku  = "standard"
      }
      prod = {
        name = "kv-prod"
        sku  = "premium"
      }
    }
  }

  assert {
    condition     = length(azurerm_resource_group.this) == 2
    error_message = "Should create 2 resource groups"
  }

  assert {
    condition     = length(azurerm_log_analytics_workspace.this) == 2
    error_message = "Should create 2 Log Analytics workspaces"
  }

  assert {
    condition     = length(module.key_vaults) == 2
    error_message = "Should create 2 Key Vaults"
  }
}

# Note: validate_existing_resource_group test removed because it requires an actual
# existing resource group in Azure. The data source lookup will fail if RG doesn't exist.
# To test this feature:
# 1. Create a resource group in your Azure subscription (e.g., "rg-test-existing")
# 2. Set existing_resource_group_name = "rg-test-existing"
# 3. Set resource_groups = {}
# 4. Verify that no new RGs are created and the existing RG is referenced
