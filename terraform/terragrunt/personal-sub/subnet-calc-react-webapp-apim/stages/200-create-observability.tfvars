# Stage 200 - standalone stack with new observability resources
#
# Usage:
#   terragrunt plan -- -var-file=stages/200-create-observability.tfvars

create_resource_group = true
resource_group_name   = "rg-subnet-calc-apim-dev"

observability = {
  use_existing                = false
  log_retention_days          = 30
  app_insights_retention_days = 90
}
