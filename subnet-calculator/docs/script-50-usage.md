# Script 50: Add HTTPS Listener - Usage Guide

## Overview

Script 50 (`50-add-https-listener.sh`) adds HTTPS/443 listener to an existing Application Gateway using a self-signed certificate stored in Azure Key Vault with managed identity access.

**Purpose:** Enable Cloudflare "Full" SSL/TLS mode for end-to-end encryption between Cloudflare and Azure.

## Prerequisites

- Application Gateway created (script 49)
- Custom domain configured on Static Web App
- Azure CLI authenticated (`az login`)
- OpenSSL installed (standard on Linux/macOS)

## Basic Usage

### Standalone Execution

```bash
RESOURCE_GROUP="rg-subnet-calc" \
./subnet-calculator/infrastructure/azure/50-add-https-listener.sh
```

Script will auto-detect:

- Application Gateway (if single in resource group)
- Custom domain (from HTTP settings)
- Key Vault (create new if none exist)

### With Explicit Configuration

```bash
RESOURCE_GROUP="rg-subnet-calc" \
APPGW_NAME="agw-swa-subnet-calc-private-endpoint" \
CUSTOM_DOMAIN="static-swa-private-endpoint.publiccloudexperiments.net" \
./subnet-calculator/infrastructure/azure/50-add-https-listener.sh
```

### Force Certificate Regeneration

```bash
RESOURCE_GROUP="rg-subnet-calc" \
FORCE_CERT_REGEN=true \
./subnet-calculator/infrastructure/azure/50-add-https-listener.sh
```

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RESOURCE_GROUP` | Yes | - | Azure resource group containing Application Gateway |
| `APPGW_NAME` | No | Auto-detect | Application Gateway name (required if multiple exist) |
| `CUSTOM_DOMAIN` | No | Auto-detect | Custom domain for certificate CN (detected from HTTP settings) |
| `KEY_VAULT_NAME` | No | Auto-detect/create | Key Vault name (required if multiple exist) |
| `FORCE_CERT_REGEN` | No | false | Skip prompt and regenerate certificate |

## What the Script Does

### Phase 1: Validation

1. Check Azure CLI authentication
2. Verify OpenSSL availability
3. Validate resource group exists
4. Detect Application Gateway
5. Detect custom domain

### Phase 2: Key Vault Setup (Idempotent)

1. Search for existing Key Vault in resource group
2. If none exist: Create new Key Vault with random suffix
3. If multiple exist: Require `KEY_VAULT_NAME` environment variable
4. Verify Key Vault is accessible

### Phase 3: Certificate Management (Idempotent)

1. Check if certificate secret exists in Key Vault
2. If exists: Show expiration date, prompt to update
3. If `FORCE_CERT_REGEN=true`: Skip prompt
4. Generate self-signed certificate (RSA 2048-bit, 365 days validity)
5. Export as PFX with random password
6. Upload to Key Vault as JSON secret

### Phase 4: Managed Identity (Idempotent)

1. Check if system-assigned identity enabled
2. If not: Enable system-assigned managed identity
3. Check if RBAC role assignment exists
4. If not: Assign "Key Vault Secrets User" role
5. Wait 30 seconds for RBAC propagation

### Phase 5: HTTPS Listener (Idempotent)

1. Check if HTTPS listener already exists
2. If exists: Skip configuration
3. Delete HTTP/80 listener and frontend port
4. Create HTTPS/443 frontend port
5. Add SSL certificate from Key Vault (versionless URI)
6. Create HTTPS listener
7. Update routing rule to use HTTPS listener

### Phase 6: Summary

1. Display configuration details
2. Show public IP address
3. Provide testing commands
4. Show Cloudflare configuration steps

## Idempotency

Script is safe to run multiple times:

- Existing Key Vault: Reused
- Existing certificate: Prompt to update or skip
- Existing managed identity: Reused
- Existing RBAC assignment: Skipped
- Existing HTTPS listener: Configuration verified

## Post-Deployment Steps

### 1. Test HTTPS Access

```bash
PUBLIC_IP=$(az network public-ip show \
  --name pip-agw-swa-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc \
  --query ipAddress -o tsv)

curl -k -v -H "Host: your-domain.com" https://${PUBLIC_IP}/
```

Expected: HTTP 302 redirect or 200 response (self-signed cert warning is normal)

### 2. Configure Cloudflare

1. Log into Cloudflare dashboard
2. Navigate to SSL/TLS settings
3. Change mode from "Flexible" to "Full"
4. Verify DNS record is proxied (orange cloud)
5. Wait ~30 seconds for propagation

### 3. Verify End-to-End HTTPS

```bash
curl -v https://your-domain.com/
```

Expected: No certificate warnings, HTTP 302 or 200

### 4. Check Backend Health

```bash
az network application-gateway show-backend-health \
  --name agw-swa-subnet-calc-private-endpoint \
  --resource-group rg-subnet-calc
```

Expected: Backend status "Healthy"

## Certificate Renewal

Certificate valid for 365 days. To renew before expiration:

```bash
RESOURCE_GROUP="rg-subnet-calc" \
FORCE_CERT_REGEN=true \
./subnet-calculator/infrastructure/azure/50-add-https-listener.sh
```

Script will:

1. Generate new certificate
2. Upload to Key Vault (new version)
3. Application Gateway automatically picks up new version (versionless URI)
4. No downtime required

## Cost Impact

- Key Vault: ~$0.03 per 10,000 operations (~$1/month total)
- Application Gateway: No change (~$215/month existing)
- Total increase: ~$1/month

## Troubleshooting

See: `docs/application-gateway-https-troubleshooting.md`

Common issues:

- RBAC propagation delays (wait 60 seconds)
- Cloudflare not proxied (orange cloud required)
- Certificate expiration (regenerate annually)

## Integration with Stack 16

Stack 16 automatically calls script 50 after creating Application Gateway:

```bash
./subnet-calculator/infrastructure/azure/azure-stack-16-swa-private-endpoint.sh
```

To skip HTTPS configuration:

```bash
SKIP_APP_GATEWAY=true ./azure-stack-16-swa-private-endpoint.sh
```

## References

- Design Document: `docs/plans/2025-10-30-application-gateway-https-keyvault-design.md`
- Implementation Plan: `docs/plans/2025-10-30-application-gateway-https-keyvault.md`
- Troubleshooting: `docs/application-gateway-https-troubleshooting.md`
- Azure Key Vault Managed Identity: <https://learn.microsoft.com/en-us/azure/key-vault/general/managed-identity>
