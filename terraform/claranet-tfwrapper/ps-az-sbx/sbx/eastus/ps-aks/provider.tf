provider "azurerm" {
  features {
    # Sandbox-friendly settings - allow deletion without issues
    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = false
    }

    application_insights {
      disable_generated_rule = false
    }

    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }

  subscription_id = var.subscription_id

  # Disable automatic resource provider registration for Pluralsight sandbox
  # The sandbox has limited permissions and cannot register providers
  resource_provider_registrations = "none"
}
