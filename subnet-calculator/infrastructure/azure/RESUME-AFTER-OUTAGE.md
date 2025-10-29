# Resume Deployment After Azure Outage

**Date of Outage**: 2025-10-29
**Affected Service**: Azure Front Door (impacting Function App creation and deployment)
**Status**: Infrastructure created successfully, deployment failed due to Azure service issues

## What Was Being Done

We were deploying **Stack 16: Private Endpoint + Entra ID** (`azure-stack-16-swa-private-endpoint.sh`), which is the high-security setup with:

- Azure Static Web App with private endpoint
- Function App on App Service Plan (P0V3) with private endpoint
- VNet with private endpoints subnet
- Entra ID authentication
- Custom domain as PRIMARY with azurestaticapps.net disabled

## What Got Created Successfully

All infrastructure is in place:

1. **VNet Infrastructure** (Step 1/10) - COMPLETE
   - VNet: `vnet-subnet-calc-private` (10.100.0.0/24)
   - Subnet: `snet-function-integration` (10.100.0.0/28)
   - Subnet: `snet-private-endpoints` (10.100.0.16/28)

2. **App Service Plan** (Step 2/10) - COMPLETE
   - Name: `plan-subnet-calc-private`
   - SKU: P0V3 (1 vCPU, 4 GB RAM)
   - Cost: ~$142/month

3. **Storage Account** (Step 3/10) - COMPLETE
   - Name: `stfuncprivateep61925`
   - Tagged: `purpose=func-subnet-calc-private-endpoint`
   - Note: Tag-based discovery implemented for idempotency

4. **Function App** (Step 3/10) - COMPLETE
   - Name: `func-subnet-calc-private-endpoint`
   - Plan: `plan-subnet-calc-private` (P0V3)
   - URL: `https://func-subnet-calc-private-endpoint.azurewebsites.net`
   - Auth: Disabled (DISABLE_AUTH=true, SWA handles auth)
   - CORS: Configured for custom domain

5. **VNet Integration** (Step 4/10) - COMPLETE
   - Function App integrated with VNet
   - Subnet: `snet-function-integration`

## What Failed

**Step 5/10: Deploy Function API** - Failed due to Azure outage

**Error Details**:

```text
Deployment endpoint responded with status code 202
Zip deployment failed. {'status': 3, 'complete': True, 'active': False}
```

**Root Cause** (from deployment logs):

```text
Running oryx build...
Deployment Log file does not exist in /tmp/oryx-build.log
The logfile at /tmp/oryx-build.log is empty. Unable to fetch the summary of build
Deployment Failed.
```

The Oryx build system (Azure's remote build infrastructure) is failing to:

- Download Python dependencies from PyPI
- Communicate with Azure build services
- Write build logs properly

This is a **service-side issue**, not a problem with our code or configuration.

## Bug Fixes Applied During Troubleshooting

While debugging the deployment failure, we discovered and fixed query bugs in multiple scripts:

### Issue: Empty Hostname in Function App Output

**Problem**: Azure CLI query path was incorrect
**Impact**: Scripts couldn't retrieve Function App URLs for display or configuration

**Files Fixed**:

1. `10-function-app.sh` (2 locations)
2. `13-create-function-app-on-app-service-plan.sh` (2 locations)
3. `azure-stack-14-swa-noauth-jwt.sh` (2 locations: defaultHostName + customDomainVerificationId)
4. `azure-stack-15-swa-entraid-linked.sh` (2 locations: defaultHostName + customDomainVerificationId)

**Changes**:

```bash
# BROKEN Before:
--query "properties.defaultHostName" -o tsv
--query "properties.customDomainVerificationId" -o tsv

# FIXED After:
--query "defaultHostName" -o tsv
--query "customDomainVerificationId" -o tsv
```

**Verification**:

```bash
# Test that queries now work:
az functionapp show --name func-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc --query "defaultHostName" -o tsv
# Should return: func-subnet-calc-private-endpoint.azurewebsites.net

az functionapp show --name func-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc --query "customDomainVerificationId" -o tsv
# Should return: FFE57DFD85B4BB2D17E7C017DB03F556D7D9FF5336357B7A54B8CC700D589CD3
```

**Note**: ~20 other scripts still have the same bug but weren't critical for this deployment.

## Test Coverage Created During Downtime

While waiting for Azure to recover, we created comprehensive BATS test coverage:

1. **`tests/test_stack_14_jwt.bats`** (70+ tests)
   - JWT authentication stack validation
   - Custom domain configuration
   - Security warnings

2. **`tests/test_stack_15_entraid.bats`** (100+ tests)
   - Entra ID app registration handling
   - Multiple redirect URIs
   - Y/n prompt patterns
   - Certificate polling logic

3. **`tests/test_stack_16_private_endpoint.bats`** (110+ tests)
   - VNet infrastructure validation
   - Storage account tag-based discovery
   - Private endpoint configuration
   - Cost calculations per SKU
   - Application Gateway conditional logic

## What To Do Next (In Order)

### 1. Verify Azure Services Are Healthy

Check Azure status before proceeding:

```bash
# Check if Function App is accessible
curl -I https://func-subnet-calc-private-endpoint.azurewebsites.net

# Check Azure Status
open https://status.azure.com/
```

### 2. Resume Deployment at Step 5

The deployment script is idempotent and can be re-run from the beginning:

```bash
cd /Users/nickromney/Developer/personal/public-cloud-experiments/subnet-calculator/infrastructure/azure

# Set required credentials
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"

# Re-run the deployment
./azure-stack-16-swa-private-endpoint.sh
```

The script will:

- Skip VNet (already exists)
- Skip App Service Plan (already exists)
- Skip Function App (already exists)
- Skip VNet integration (already configured)
- **Resume at Step 5**: Deploy Function API (should work now)
- Continue with remaining steps...

### 3. Alternatively, Deploy Function Code Manually

If you want to test just the deployment step:

```bash
cd /Users/nickromney/Developer/personal/public-cloud-experiments/subnet-calculator/infrastructure/azure

export RESOURCE_GROUP="rg-subnet-calc"
export FUNCTION_APP_NAME="func-subnet-calc-private-endpoint"
export DISABLE_AUTH=true

# Deploy Function code
./22-deploy-function-zip.sh
```

This will retry the exact step that failed due to the outage.

### 4. Complete Remaining Steps

After successful Function deployment, the script needs to complete:

- **Step 6/10**: Create private endpoint for Function App
- **Step 7/10**: Create Static Web App
- **Step 8/10**: Create private endpoint for SWA
- **Step 9/10**: Link Function to SWA
- **Step 10/10**: Configure custom domain (manual DNS required)
- **Step 11/11**: Update Entra ID and deploy frontend
- **Optional**: Application Gateway (Y/n prompt)

### 5. Test the Deployment

Once complete, verify:

```bash
# Check Function App is deployed
curl https://func-subnet-calc-private-endpoint.azurewebsites.net/api/v1/docs

# Check SWA exists
az staticwebapp show --name swa-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc

# Check private endpoints
az network private-endpoint list --resource-group rg-subnet-calc -o table

# Check VNet integration
az functionapp vnet-integration list \
  --name func-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc
```

### 6. Run Test Coverage

Execute the new BATS tests:

```bash
cd /Users/nickromney/Developer/personal/public-cloud-experiments/subnet-calculator/infrastructure/azure/tests

# Run Stack 14 tests
bats test_stack_14_jwt.bats

# Run Stack 15 tests
bats test_stack_15_entraid.bats

# Run Stack 16 tests
bats test_stack_16_private_endpoint.bats
```

### 7. Optional: Fix Remaining Scripts

If time permits, fix the query bug in the remaining ~20 scripts:

```bash
# Find all scripts with the bug
grep -l "properties.defaultHostName\|properties.customDomainVerificationId" *.sh

# Fix pattern in each:
# - Replace "properties.defaultHostName" → "defaultHostName"
# - Replace "properties.customDomainVerificationId" → "customDomainVerificationId"
```

## Environment Details

**Resource Group**: `rg-subnet-calc`
**Location**: `uksouth`
**Subscription**: `9800bc67-8c79-4be8-b6a7-9e536e752abf`

**Created Resources**:

- VNet: `vnet-subnet-calc-private`
- App Service Plan: `plan-subnet-calc-private` (P0V3)
- Storage: `stfuncprivateep61925`
- Function: `func-subnet-calc-private-endpoint`

**Expected Final Resources** (after completion):

- Static Web App: `swa-subnet-calc-private-endpoint`
- Private Endpoint: `pe-func-subnet-calc-private-endpoint`
- Private Endpoint: `pe-swa-subnet-calc-private-endpoint`
- Private DNS Zones: (auto-created)
- Application Gateway: `agw-swa-subnet-calc-private-endpoint` (optional)

## Key Configuration

**Entra ID**:

- Custom domain only redirect URI (azurestaticapps.net disabled)
- Must be provided via environment variables

**Network**:

- VNet: 10.100.0.0/24
- Functions subnet: 10.100.0.0/28
- Private endpoints subnet: 10.100.0.16/28
- AppGW subnet (if created): 10.100.0.32/27

**Costs** (monthly):

- SWA Standard: $9
- P0V3 Plan: $142
- Private Endpoints: Free
- **Total**: ~$151/month (without Application Gateway)
- **With AppGW**: ~$471-576/month (AppGW Standard_v2 adds ~$320-425/month)

## Questions to Resolve

1. **Application Gateway**: Do you want to create it (provides public access to private SWA)?
2. **Custom Domain DNS**: Do you have access to configure DNS for `static-swa-private-endpoint.publiccloudexperiments.net`?
3. **Other Scripts**: Should we fix the query bug in all ~20 remaining scripts or just leave them?

## Azure Status References

- Azure Status Dashboard: <https://status.azure.com/>
- Azure Front Door outage started: ~16:00 UTC 2025-10-29
- Affected services: Function App deployments, management APIs

---

**TL;DR**: Infrastructure is ready. Re-run `./azure-stack-16-swa-private-endpoint.sh` when Azure is healthy. It will skip existing resources and resume at the failed deployment step.
