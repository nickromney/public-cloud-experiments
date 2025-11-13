# Function App Deployment Comparison

## Issue Summary

`func-subnet-calc-react-api` returns 404 errors on all API endpoints.

**Root Cause:** Dependencies not installed during deployment.

## Application Insights Evidence

Query:

```kql
exceptions
| where timestamp > ago(24h)
| where cloud_RoleName == "func-subnet-calc-react-api"
| project timestamp, type, outerMessage
| order by timestamp desc
```

Error:

```text
ModuleNotFoundError: No module named 'fastapi'
Cannot find module. Please check the requirements.txt file for the missing module.
```

## Configuration Comparison

### Working: `func-subnet-calc-jwt`

```json
{
  "AzureWebJobsStorage": "...",
  "DEPLOYMENT_STORAGE_CONNECTION_STRING": "...",
  "AUTH_METHOD": "jwt",
  "JWT_SECRET_KEY": "...",
  "JWT_ALGORITHM": "HS256",
  "JWT_ACCESS_TOKEN_EXPIRE_MINUTES": "30",
  "JWT_TEST_USERS": "{\"demo\": \"$argon2id$v=19$m=65536,t=3,p=4$R6e4JFJ6OlyjZSKBPj9+tw$L2mlnO5TCYDzKI4tLpu6Vr6A4f0IJCn2oTaUcKBD/0w\"}",
  "CORS_ORIGINS": "https://static-swa-no-auth.publiccloudexperiments.net"
}
```

**Key Observations:**

- NO `WEBSITE_RUN_FROM_PACKAGE` setting
- NO `ENABLE_ORYX_BUILD` setting
- NO `SCM_DO_BUILD_DURING_DEPLOYMENT` setting
- NO `AzureWebJobsFeatureFlags`

### Broken: `func-subnet-calc-react-api`

```json
{
  "AzureWebJobsStorage": "...",
  "AzureWebJobsFeatureFlags": "EnableWorkerIndexing",
  "APPLICATIONINSIGHTS_CONNECTION_STRING": "...",
  "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING": "...",
  "JWT_ACCESS_TOKEN_EXPIRE_MINUTES": "30",
  "AUTH_METHOD": "jwt",
  "FUNCTIONS_WORKER_RUNTIME": "python",
  "JWT_SECRET_KEY": "dev-secret-key-minimum-32-characters-long-for-security",
  "JWT_ALGORITHM": "HS256",
  "ENABLE_ORYX_BUILD": "true",
  "FUNCTIONS_EXTENSION_VERSION": "~4",
  "WEBSITE_CONTENTSHARE": "func-subnet-calc-react-api-9750",
  "JWT_TEST_USERS": "{\"demo\":\"$argon2id$v=19$m=65536,t=3,p=4$TklhcmEkyMzqJaH3KHQQDA$rgp8AmtaR6PzBgjyZGNsivb2yJRqULRt5B+BmzUnzbo\",\"admin\":\"$argon2id$v=19$m=65536,t=3,p=4$JiTJZlTwD/1jJLlMQMOwCA$HbubnE11kzEfcszqKtMOmjvxj14vjooqbdZtgc1NYCs\"}",
  "WEBSITE_RUN_FROM_PACKAGE": "1",
  "APPINSIGHTS_INSTRUMENTATIONKEY": "...",
  "AzureWebJobsDashboard": "...",
  "SCM_DO_BUILD_DURING_DEPLOYMENT": "false"
}
```

**Problem Settings:**

- `WEBSITE_RUN_FROM_PACKAGE=1` - Tells Azure to run directly from zip
- `SCM_DO_BUILD_DURING_DEPLOYMENT=false` - Prevents Oryx from building dependencies
- `ENABLE_ORYX_BUILD=true` - Contradicts the setting above

## The Issue

When deploying a zip with `requirements.txt`:

1. **Wrong approach** (current):
   - Set `WEBSITE_RUN_FROM_PACKAGE=1`
   - Set `SCM_DO_BUILD_DURING_DEPLOYMENT=false`
   - Deploy zip with only source files
   - Result: Azure doesn't install dependencies (BROKEN)

2. **Correct approach #1** (like func-subnet-calc-jwt):
   - DON'T set `WEBSITE_RUN_FROM_PACKAGE`
   - DON'T set `SCM_DO_BUILD_DURING_DEPLOYMENT`
   - Deploy zip with source files
   - Result: Azure automatically builds dependencies (WORKS)

3. **Correct approach #2** (package everything):
   - Set `WEBSITE_RUN_FROM_PACKAGE=1`
   - Include ALL dependencies in zip (`.python_packages/`)
   - Deploy complete zip
   - Result: Azure runs from complete package (WORKS)

## Local Validation

Tested deployment zip locally with podman:

```bash
cd /tmp/function-test
podman-compose up -d

# Wait for startup
curl http://localhost:8080/api/v1/health
# SUCCESS: {"status":"healthy","service":"Subnet Calculator API (Azure Function)","version":"1.0.0"}

# Test JWT login
curl -X POST "http://localhost:8080/api/v1/auth/login" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=demo&password=password123"
# SUCCESS: {"access_token":"eyJ...","token_type":"bearer"}
```

**Conclusion:** The deployment zip code is correct. The issue is Azure deployment configuration.

## Solution

### Option A: Remove conflicting settings (Recommended)

Remove from Terraform `app_settings`:

```hcl
# Remove these:
"WEBSITE_RUN_FROM_PACKAGE"       = "1"
"ENABLE_ORYX_BUILD"              = "true"
"SCM_DO_BUILD_DURING_DEPLOYMENT" = "false"
```

Let Azure handle the build automatically like `func-subnet-calc-jwt` does.

### Option B: Deploy with dependencies included

Change deployment script to include `.python_packages/`:

```bash
# Install dependencies locally
cd /path/to/function-app
pip install -r requirements.txt --target .python_packages/lib/site-packages

# Include in zip
zip -r function-app.zip \
  auth.py \
  config.py \
  function_app.py \
  host.json \
  requirements.txt \
  .python_packages/
```

## Recommendation

**Use Option A** - Let Azure build dependencies automatically:

1. It's simpler and matches the working `func-subnet-calc-jwt`
2. Smaller deployment zip (16K vs potentially 50MB+)
3. Faster deployments
4. Azure optimizes the build for its runtime environment

## Fix Applied

Updated Terraform configuration and deployment script to enable remote builds:

**Changes in `main.tf:110-115`:**

- Removed `WEBSITE_RUN_FROM_PACKAGE` setting
- Kept only essential Azure Functions settings
- Let Azure automatically handle dependency builds

**Changes in `terraform.tfvars:40-51`:**

- Removed `ENABLE_ORYX_BUILD = "true"`
- Added comment documenting why these settings should NOT be set

**Changes in `Makefile:121-128`:**

- Added `--build-remote true` flag to deployment command
- Added `--timeout 600` for long builds
- Matches the `22-deploy-function-zip.sh` script approach

**Key Insight - Hosting Plan Differences:**

| Plan Type | func-subnet-calc-jwt | func-subnet-calc-react-api |
|-----------|---------------------|----------------------------|
| Hosting | **Flex Consumption** | **Elastic Premium (EP1)** |
| App Settings | 8 settings | 15 settings |
| Content Share | Not needed | Required (`WEBSITE_CONTENTSHARE`) |
| Deployment | Simplified | Traditional App Service model |

**The Critical Flag:**

```bash
az functionapp deployment source config-zip \
  --build-remote true    # Sets SCM_DO_BUILD_DURING_DEPLOYMENT=true
```

**Without `--build-remote true`**: Azure sets `SCM_DO_BUILD_DURING_DEPLOYMENT=false` (No dependency installation)

**With `--build-remote true`**: Azure sets `SCM_DO_BUILD_DURING_DEPLOYMENT=true` (Dependencies installed via Oryx)

**Result:** Function App now works correctly with all endpoints responding

## Related Files

- Terraform configuration: `terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-proxied/main.tf:110-115`
- Terraform variables: `terraform/terragrunt/personal-sub/subnet-calc-react-easyauth-proxied/terraform.tfvars:40-51`
- Deployment script: `terraform/terragrunt/deployment-scripts/build-function-zip.sh`
- Reference working script: `subnet-calculator/infrastructure/azure/22-deploy-function-zip.sh:138` (`--build-remote true`)
