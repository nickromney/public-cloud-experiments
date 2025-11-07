# Subnet Calculator - Internal APIM Stack

Secure Azure deployment with TypeScript web app, Python Function App, and Internal API Management.

## Architecture

```text
TypeScript Web App (Node.js)
    ↓
Internal API Management (VNet)
    ↓
Python Function App (Private Endpoint)
```

**Key Features:**

- **Web App**: TypeScript Vite SPA on App Service with VNet integration
- **Function App**: Python FastAPI backend with private endpoint (no public access)
- **APIM**: Internal mode (only accessible within VNet)
- **Authentication**: Azure AD with validate-jwt APIM policy
- **Networking**: Dedicated VNet with subnets for web integration, private endpoints, and APIM
- **Optional**: Cloudflare IP restrictions on web app

## Prerequisites

1. **Azure CLI**: Logged in with appropriate permissions
2. **Terragrunt**: Installed (`brew install terragrunt`)
3. **OpenTofu**: Installed (`brew install opentofu`)
4. **Environment Variables**: Set via `terraform/terragrunt/setup-env.sh`

## Setup

### 1. Configure Environment

From the terragrunt root directory:

```bash
cd terraform/terragrunt
./setup-env.sh
```

This will:

- Detect or prompt for Azure subscription/tenant
- Find or create state storage account
- Check/assign Storage Blob Data Contributor role
- Output environment variables to export

**Export the variables shown:**

```bash
export ARM_SUBSCRIPTION_ID='...'
export ARM_TENANT_ID='...'
export TF_BACKEND_RG='...'
export TF_BACKEND_SA='...'
export TF_BACKEND_CONTAINER='...'
```

### 2. Configure Deployment

Edit `terraform.tfvars` to customize your deployment:

```bash
cd personal-sub/subnet-calc-internal-apim
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**Key settings:**

- **Network CIDRs**: Adjust if conflicts with existing VNets
- **SKUs**: Change to P0v3 for cheaper dev/test (Developer_1 is cheapest APIM)
- **Email**: Update `publisher_email` to your email
- **Cloudflare**: Set `cloudflare_only = true` if behind Cloudflare

### 3. Deploy Infrastructure

```bash
terragrunt init
terragrunt plan
terragrunt apply
```

**Deployment time**: ~20-30 minutes (APIM provisioning is slow)

### 4. Deploy Applications

After infrastructure is deployed, deploy the applications:

**Function App (Backend API):**

```bash
cd ../../../subnet-calculator/api-fastapi-azure-function
uv sync --extra dev
func azure functionapp publish <function-app-name>
```

**Web App (Frontend):**

```bash
cd ../infrastructure/azure
RESOURCE_GROUP=subnetcalc-dev-rg \
  APP_SERVICE_NAME=<web-app-name> \
  API_BASE_URL=https://apim-subnetcalc-dev.azure-api.net/api/subnet-calc \
  ./59-deploy-typescript-app-service.sh
```

## Configuration

### Network Layout

| Subnet | CIDR | Purpose |
|--------|------|---------|
| web-integration | 10.120.0.0/24 | Web App VNet integration (outbound) |
| private-endpoints | 10.120.1.0/24 | Private endpoints for Function + Web |
| apim | 10.120.2.0/24 | Internal APIM subnet |

### Resource Naming

Resources are auto-named based on `project_name` and `environment` from root.hcl:

- Resource Group: `{project}-{env}-rg`
- Web App: `web-{project}-{env}`
- Function App: `func-{project}-{env}`
- APIM: `apim-{project}-{env}`
- VNet: `{project}-{env}-vnet`

### SKU Options

**Web/Function App Service Plans:**

- `P0v3`: 1 core, 4GB RAM (~$80/month) - Cheapest Premium
- `P1v3`: 2 cores, 8GB RAM (~$160/month)
- `S1`: 1 core, 1.75GB RAM (~$70/month) - Standard tier
- `S2`: 2 cores, 3.5GB RAM (~$140/month)

**APIM:**

- `Developer_1`: Single unit, no SLA (~$50/month) - Dev/test only
- `Basic_1`: Production, 99.95% SLA (~$150/month)
- `Standard_1`: Multi-region, 99.95% SLA (~$700/month)
- `Premium_1`: VPN/ExpressRoute, 99.99% SLA (~$2,900/month)

**Note**: APIM is expensive. Developer tier has no SLA and is for non-production only.

## Outputs

After deployment, Terragrunt outputs useful information:

```bash
terragrunt output
```

**Key outputs:**

- `web_app_hostname`: Web app URL
- `function_app_hostname`: Function app URL (private only)
- `apim_name`: APIM instance name
- `apim_private_ip`: APIM internal IP
- `apim_audience`: Azure AD audience for API authentication
- `web_app_identity_principal_id`: Managed identity for role assignments

## Accessing Resources

**Web App**: Publicly accessible (or Cloudflare-only if configured)

```bash
curl https://<web-app-hostname>
```

**Function App**: Only accessible via APIM from within VNet

**APIM**: Internal only, requires VNet access or VPN

## Testing

### Test from Web App (has VNet integration)

```bash
az webapp ssh --name <web-app-name> --resource-group subnetcalc-dev-rg

# Inside the web app container:
curl https://apim-subnetcalc-dev.azure-api.net/api/subnet-calc/health
```

### Test API Directly (requires VPN/bastion)

If you have VPN or Azure Bastion access to the VNet:

```bash
curl https://apim-subnetcalc-dev.azure-api.net/api/subnet-calc/health \
  -H "Authorization: Bearer <token>"
```

## Troubleshooting

### APIM Provisioning Timeout

APIM can take 30-45 minutes to provision. If terragrunt times out:

```bash
# Check status in portal, then refresh state
terragrunt refresh
terragrunt apply
```

### Function App Not Accessible

Verify private endpoint DNS resolution:

```bash
az network private-endpoint dns-zone-group list \
  --endpoint-name pe-func-subnetcalc-dev \
  --resource-group subnetcalc-dev-rg
```

### Web App Can't Reach APIM

Check VNet integration:

```bash
az webapp vnet-integration list \
  --name web-subnetcalc-dev \
  --resource-group subnetcalc-dev-rg
```

### Authentication Failures

Verify Azure AD app registration and role assignments:

```bash
# Check web app identity
az webapp identity show --name web-subnetcalc-dev -g subnetcalc-dev-rg

# Check role assignment
az role assignment list \
  --assignee <principal-id> \
  --scope /subscriptions/<sub-id>
```

## Cleanup

```bash
terragrunt destroy
```

**Note**: APIM deletion can take 10-15 minutes.

## Cost Estimation

**Monthly costs** (approximate, UK South region):

| Resource | SKU | Cost |
|----------|-----|------|
| Web App Plan | P1v3 | ~$160 |
| Function Plan | P1v3 | ~$160 |
| APIM | Developer_1 | ~$50 |
| Storage | Standard LRS | ~$2 |
| VNet/Private Endpoints | - | ~$10 |
| **Total** | | **~$382/month** |

**Cheaper options:**

- Use S1 plans instead of P1v3: ~$222/month (~$160 savings)
- Use Consumption Function plan: Not compatible with private endpoints
- Remove APIM: ~$332/month savings, but loses internal routing

## Security Notes

- Function App has `public_network_access_enabled = false` (private endpoint only)
- APIM is in Internal mode (not publicly accessible)
- Azure AD authentication via validate-jwt policy
- TLS 1.2 minimum on all resources
- Managed identity for inter-service authentication
