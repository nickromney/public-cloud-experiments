# Subnet Calculator - React Web App with Azure API Management

Complete APIM-fronted application stack with authentication termination at the API gateway layer.

## Architecture Overview

```text
┌─────────────────┐
│  Client Browser │
│  (React SPA)    │
└────────┬────────┘
         │ HTTP Request
         │ Header: Ocp-Apim-Subscription-Key: <key>
         ↓
┌──────────────────────────────────────────────┐
│  Azure Web App (App Service)                 │
│  - Runtime: Node.js 22                       │
│  - Serves: React SPA (server-side rendered)  │
│  - Configured with APIM gateway URL          │
└────────┬─────────────────────────────────────┘
         │
         │ HTTP Request
         │ Header: Ocp-Apim-Subscription-Key: <key>
         ↓
┌──────────────────────────────────────────────┐
│  Azure API Management (APIM)                 │
│  - SKU: Developer (single unit, no SLA)     │
│  - **AUTH TERMINATION POINT**                │
│  - Validates subscription key                │
│  - Applies rate limiting (100 req/min)       │
│  - Injects X-User-ID, X-User-Name headers    │
│  - Policy: inbound-subscription.xml          │
└────────┬─────────────────────────────────────┘
         │
         │ HTTP Request (NO AUTH HEADER)
         │ Headers: X-User-ID, X-User-Name
         ↓
┌──────────────────────────────────────────────┐
│  Azure Function App (Backend API)            │
│  - Runtime: Python 3.11 (FastAPI)           │
│  - **AUTH_METHOD=none**                      │
│  - Trusts APIM (reads X-User-ID header)     │
│  - Optional: IP restrictions to APIM only   │
└──────────────────────────────────────────────┘
```

## Key Design Decisions

### 1. Authentication Termination at APIM

**APIM handles ALL authentication** - the Function App has `AUTH_METHOD=none`.

**Benefits:**

- Single point of authentication (APIM)
- Simplified backend code (no JWT validation)
- Centralized policy management
- Rate limiting per subscription
- Request/response transformation
- Monitoring and analytics
- Easy to add/modify auth methods without changing backend

**Trade-offs:**

- Backend must trust APIM completely
- Need IP restrictions to prevent bypass
- APIM becomes critical path (if APIM is down, backend is unreachable)

### 2. IP Restrictions for Backend Protection

The `security.enforce_apim_only_access` variable controls whether the Function App accepts direct traffic or only traffic from APIM.

**When disabled (testing):**

- Function App accepts traffic from any IP
- Can test direct access: `curl https://func-app/api/v1/health`
- Can test APIM access: `curl -H "Ocp-Apim-Subscription-Key: <key>" https://apim-gateway/subnet-calc/api/v1/health`

**When enabled (production):**

- Function App only accepts traffic from APIM outbound IPs
- Direct access returns 403 Forbidden
- All traffic MUST go through APIM

**Implementation:**

Uses Azure Function App IP restrictions (not NSG, as Function Apps don't support NSG without VNet integration). The `null_resource.function_app_ip_restrictions` provisions via Azure CLI.

### 3. Shared Observability Resources

Application Insights and Log Analytics Workspace can be shared across stacks using data sources.

**Benefits:**

- Single pane of glass for monitoring
- Cost savings (one workspace instead of multiple)
- Easier correlation across stacks
- No state migration needed (uses data sources)

**Configuration:**

```hcl
observability = {
  use_existing                   = true
  existing_resource_group_name   = "rg-subnet-calc"
  existing_log_analytics_name    = "log-subnetcalc-dev"
  existing_app_insights_name     = "appi-subnetcalc-dev"
}
```

### 4. Bring Your Own Platform Resources

Function Apps almost always sit on shared platform components. This stack now exposes
`existing_service_plan_id` and `existing_storage_account_id` so you can opt into
landing-zone provided infrastructure instead of creating new instances.

```hcl
function_app = {
  name                        = "func-subnet-calc-apim"
  existing_service_plan_id    = "/subscriptions/<sub>/resourceGroups/rg-platform/providers/Microsoft.Web/serverFarms/plan-platform-ep1"
  existing_storage_account_id = "/subscriptions/<sub>/resourceGroups/rg-shared/providers/Microsoft.Storage/storageAccounts/stplatformshared"
}
```

**Minimum Requirements**: Terraform 1.8+ and azurerm 4.0+ are required for provider-defined functions used in the BYO pattern. The `provider::azurerm::normalise_resource_id` and `provider::azurerm::parse_resource_id` functions provide robust resource ID parsing, removing brittle `split("/")` approaches and ensuring IDs are casing-correct before they are passed to Azure APIs.

## Resource Details

### Azure API Management

- **SKU:** Developer_1 (least expensive, dev/test only)
- **Cost:** ~$50/month
- **Provisioning Time:** ~37 minutes on first deployment
- **Limitations:**
  - Single deployment unit
  - No SLA
  - Not for production use
  - Maximum 100 API calls/minute (configurable)

**For production**, use Basic, Standard, or Premium SKU.

### Function App

- **SKU:** Elastic Premium EP1
- **Cost:** ~$146/month (744 hours)
- **Auth Method:** none
- **Runtime:** Python 3.11
- **Backend:** FastAPI
- **Deployment:** Zip deployment with `--build-remote true`
- **Protected by:** APIM (optional IP restrictions)

### Web App

- **SKU:** App Service B1
- **Cost:** ~$13/month
- **Runtime:** Node.js 22 LTS
- **Frontend:** React SPA with Express server
- **API URL:** Configured to use APIM gateway

### Total Monthly Cost

- APIM Developer: ~$50
- Function App EP1: ~$146
- Web App B1: ~$13
- Storage Account: <$1
- Application Insights: Pay-per-use (first 5GB free)

### Total Monthly Cost: ~$210/month

## Deployment Guide

### Prerequisites

1. **Azure CLI** logged in
2. **Terraform/Terragrunt** installed
3. **Environment variables** set:

   ```bash
   export ARM_SUBSCRIPTION_ID="your-subscription-id"
   export ARM_TENANT_ID="your-tenant-id"
   export PERSONAL_SUB_REGION="uksouth"  # or preferred region
   ```

4. **Publisher email** for APIM (required)

### Step 1: Configure Variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and update:

- `apim.publisher_email` - **REQUIRED**
- `apim.enable_app_insights` - Toggle APIM ↔ Application Insights diagnostics
- `observability.use_existing` - Set to `true` to use shared resources
- `security.enforce_apim_only_access` - Start with `false`, enable after testing

### Step 2: Deploy Infrastructure

```bash
make init      # Initialize Terragrunt
make plan      # Review planned changes
make apply     # Deploy (takes ~37 minutes due to APIM)
```

**IMPORTANT:** APIM provisioning takes approximately 37 minutes. Plan accordingly.

### Step 3: Deploy Function App

```bash
make deploy-function
```

This builds an optimized deployment zip (16K) with only essential files and deploys with remote build.

### Step 4: Deploy Web App

```bash
make deploy-frontend
```

This builds the React frontend with the APIM gateway URL configured.

### Stage Overlays & Toggle Workflow

The `stages/` directory mirrors the staged toggle experience from the aks-course
baseline. Each `.tfvars` overlay captures a milestone:

- `stages/100-minimal.tfvars` – minimal inputs to unblock non-interactive plans with
  required APIM settings.
- `stages/200-create-observability.tfvars` – flips `create_resource_group` and
  `observability.use_existing` so this stack can stand alone.
- `stages/300-byo-platform.tfvars` – demonstrates reusing App Service Plans and
  Storage Accounts via the new `existing_*` inputs.

Apply an overlay with standard Terragrunt syntax:

```bash
terragrunt plan -- -var-file=stages/300-byo-platform.tfvars
```

Copy or extend these overlays to document every environment’s toggle set without
editing `terraform.tfvars` directly.

### Step 5: Test Deployment

```bash
# Test via APIM (should work)
make test-apim

# Test direct access (should work initially)
make test-direct

# Test web app
curl https://$(terragrunt output -raw web_app_hostname)
```

### Step 6: Enable IP Restrictions (Optional)

After verifying APIM connectivity:

1. Update `terraform.tfvars`:

   ```hcl
   security = {
     enforce_apim_only_access = true
   }
   ```

2. Re-apply:

   ```bash
   make apply
   ```

3. Verify direct access is now blocked:

   ```bash
   make test-direct
   # Should return 403 Forbidden
   ```

## Testing & Validation

### Get APIM Subscription Key

```bash
make get-subscription-key
```

### Test API via APIM

```bash
# Using make target
make test-apim

# Or manually
curl -H "Ocp-Apim-Subscription-Key: $(terragrunt output -raw apim_subscription_key)" \
  $(terragrunt output -raw apim_api_url)/api/v1/health
```

### Test Direct Function App Access

```bash
# Using make target
make test-direct

# Or manually
curl https://$(terragrunt output -raw function_app_hostname)/api/v1/health

# If IP restrictions enabled: returns 403
# If IP restrictions disabled: returns 200
```

### Test All Endpoints

```bash
make test-endpoints
```

## APIM Policies

Policies are defined in `policies/` directory and applied via Terraform.

### inbound-subscription.xml (Default)

- Validates `Ocp-Apim-Subscription-Key` header
- Rate limits to 100 requests/minute per subscription
- Enables CORS for frontend access
- Injects `X-User-ID` and `X-User-Name` headers for backend
- Removes internal headers from response

### inbound-none.xml (Optional)

- No authentication required (open access)
- Rate limits by IP address instead of subscription
- Enables CORS for frontend access

To switch policies, set `apim.subscription_required = false` in `terraform.tfvars`.

## Monitoring & Debugging

### Application Insights Queries

All resources send telemetry to Application Insights. Use the Azure Portal or these sample KQL queries:

```kql
# APIM Request Overview
requests
| where cloud_RoleName contains "apim"
| summarize
    TotalRequests = count(),
    AvgDuration = avg(duration)
  by bin(timestamp, 5m)
| render timechart

# Function App Errors
exceptions
| where cloud_RoleName contains "func"
| project timestamp, type, outerMessage, innermostMessage
| order by timestamp desc

# Rate Limit Violations
traces
| where message contains "rate-limit"
| project timestamp, message, severityLevel
| order by timestamp desc
```

### APIM Diagnostics

APIM sends detailed diagnostics to Application Insights:

- Request/response headers
- Request/response bodies (first 1024 bytes)
- Backend communication
- Policy execution details

See `main.tf:azurerm_api_management_diagnostic` for configuration.

### Function App Access Restrictions

View current IP restrictions:

```bash
az functionapp config access-restriction show \
  --name $(terragrunt output -raw function_app_name) \
  --resource-group rg-subnet-calc
```

## Troubleshooting

### APIM Provisioning Timeout

**Symptom:** APIM creation takes longer than expected

**Solution:**

- APIM Developer tier takes ~37 minutes
- Check status: `az apim show --name <name> --resource-group <rg> --query provisioningState`
- If stuck, check Azure Service Health for regional issues

### Function App Returns 404

**Symptom:** All API endpoints return 404

**Cause:** Dependencies not installed

**Solution:**

- Verify `SCM_DO_BUILD_DURING_DEPLOYMENT=true` is set (check Terraform)
- Redeploy with `make deploy-function` (uses `--build-remote true`)
- Check deployment logs in Azure Portal

### Direct Access Works When It Shouldn't

**Symptom:** Can access Function App directly despite IP restrictions enabled

**Cause:** IP restrictions not applied or APIM IPs changed

**Solution:**

- Verify setting: `terragrunt output security_configuration`
- Re-apply Terraform: `make apply`
- Check IP restrictions: See "Function App Access Restrictions" above

### APIM Returns 401 Unauthorized

**Symptom:** API calls via APIM return 401

**Cause:** Missing or invalid subscription key

**Solution:**

- Get valid key: `make get-subscription-key`
- Verify header: `Ocp-Apim-Subscription-Key: <key>`
- Check subscription status in Azure Portal

## Security Considerations

### Authentication Flow

1. **Client → APIM:** Subscription key in header
2. **APIM Validates:** Checks key against subscriptions
3. **APIM → Backend:** No auth header, injects X-User-ID
4. **Backend:** Trusts APIM, reads X-User-ID if needed

### Trust Boundary

**APIM is the security boundary.** The Function App trusts that:

- All requests come through APIM
- APIM has validated authentication
- X-User-ID header is legitimate

**Enforce this trust** with IP restrictions (see Step 6).

### Subscription Key Management

- Primary and secondary keys supported
- Rotate keys without downtime (update to secondary, regenerate primary, update back)
- Keys are sensitive - store in Key Vault or use Azure Managed Identity in production

### Production Recommendations

1. **Use Premium SKU** for production (SLA, VNet, multi-region)
2. **Enable IP restrictions** to prevent bypass
3. **Use OAuth2/OIDC** instead of subscription keys for production
4. **Configure VNet integration** for private communication
5. **Use Managed Identity** for Azure service authentication
6. **Enable APIM policies** for request validation, transformation
7. **Set up alerts** in Application Insights for errors, rate limits
8. **Regular key rotation** via Azure Key Vault
9. **Enable diagnostic logs** for audit trail
10. **Use custom domains** with SSL certificates

## Comparison with Direct Access Stack

| Aspect | Direct Access (subnet-calc-react-webapp) | APIM Stack (this) |
|--------|------------------------------------------|-------------------|
| Auth Location | Function App (JWT) | APIM (Subscription Key) |
| Backend Auth | JWT validation | None (trusts APIM) |
| Rate Limiting | None | 100 req/min per subscription |
| API Gateway | None | APIM Developer |
| Cost | ~$160/month | ~$210/month (+$50 for APIM) |
| Complexity | Low | Medium |
| Production Ready | No | Partial (need Premium APIM) |
| Observability | Basic | Advanced (APIM + App Insights) |
| Policy Management | Code changes | APIM policies (XML) |

## References

- [Azure API Management Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
- [APIM Policy Reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
- [Function App IP Restrictions](https://learn.microsoft.com/en-us/azure/azure-functions/functions-networking-options#inbound-access-restrictions)
- [Application Insights Integration](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-app-insights)
