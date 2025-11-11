# Stage 100 - minimal inputs to unblock non-interactive plans
# Provides required APIM settings plus optional tags.
#
# Usage:
#   terragrunt plan -- -var-file=stages/100-minimal.tfvars
#
# Update publisher_email to your real address before applying.

apim = {
  name                  = "apim-subnetcalc-dev"
  publisher_name        = "Subnet Calculator"
  publisher_email       = "you@example.com"
  sku_name              = "Developer_1"
  api_path              = "subnet-calc"
  api_display_name      = "Subnet Calculator API"
  subscription_required = true
  rate_limit_per_minute = 100
}

tags = {
  environment = "dev"
  workload    = "subnetcalc-apim"
}
