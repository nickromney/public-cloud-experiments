# Stage 300 - reuse shared platform resources (App Service Plan + Storage)
#
# Update the placeholder IDs with the resources that should host the Function App.
# Usage:
#   terragrunt apply -- -var-file=stages/300-byo-platform.tfvars

observability = {
  use_existing                 = true
  existing_resource_group_name = "rg-shared-observability"
  existing_log_analytics_name  = "log-shared-dev"
  existing_app_insights_name   = "appi-shared-dev"
}

function_app = {
  existing_service_plan_id    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-platform/providers/Microsoft.Web/serverFarms/plan-platform-ep1"
  existing_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stplatformshared"
  runtime                     = "python"
  runtime_version             = "3.11"
  cors_allowed_origins        = []
  app_settings                = {}
}
