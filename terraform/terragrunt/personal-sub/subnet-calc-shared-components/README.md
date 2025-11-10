# Subnet Calculator - Shared Components Stack

This stack provides shared infrastructure components used by all Subnet Calculator stacks:

- **Log Analytics Workspace**: Centralized logging and monitoring for all applications
- **Key Vault**: Secure secret storage with RBAC authorization

## Architecture

```text
Shared Components
├── Log Analytics Workspace
│   └── Used by: App Insights, diagnostics, logs
└── Key Vault
    └── Used by: Entra ID app secrets, app settings
```

## Resources Created

Following CAF naming convention: `{resource-type}-{workload}-{component}-{environment}`

- `log-subnetcalc-shared-dev` - Log Analytics Workspace (30-day retention)
- `kv-sc-shared-dev-<random>` - Key Vault with RBAC authorization (sc = subnet-calc abbreviated due to 24-char limit)

## Usage

### Deploy

```bash
cd terraform/terragrunt

# Using Makefile
make subnet-calc shared-components init
make subnet-calc shared-components apply

# Direct terragrunt
cd personal-sub/subnet-calc-shared-components
terragrunt init
terragrunt apply
```

### Reference in Other Stacks

```hcl
# In subnet-calc-react-webapp-easyauth/terragrunt.hcl
dependency "shared" {
  config_path = "../subnet-calc-shared-components"
}

inputs = {
  key_vault_id                = dependency.shared.outputs.key_vault_id
  log_analytics_workspace_id  = dependency.shared.outputs.log_analytics_workspace_id
  # ...
}
```

## Outputs

- `key_vault_id` - Key Vault resource ID
- `key_vault_name` - Key Vault name (with random suffix)
- `key_vault_uri` - Key Vault URI for secret operations
- `log_analytics_workspace_id` - Log Analytics resource ID
- `log_analytics_workspace_name` - Log Analytics name

## Key Vault RBAC

The Key Vault uses Azure RBAC for authorization. Common roles:

- **Key Vault Secrets Officer**: Full secret management (granted to deploying user)
- **Key Vault Secrets User**: Read secrets (granted to apps/services)

### Grant App Access to Secrets

```bash
# Get Key Vault ID
KV_ID=$(cd personal-sub/subnet-calc-shared-components && terragrunt output -raw key_vault_id)

# Grant web app access
WEB_APP_PRINCIPAL=$(az webapp show --name web-subnet-calc-react --resource-group rg-subnet-calc --query identity.principalId -o tsv)
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $WEB_APP_PRINCIPAL \
  --scope $KV_ID
```

## Dependencies

This stack should be deployed first, before other stacks that depend on it.

## Notes

- **Purge Protection**: Disabled by default for dev environments
- **Soft Delete**: 90-day retention (Azure default)
- **RBAC Model**: Enabled for better security and auditability
- **Random Suffix**: Ensures globally unique Key Vault name

## Related Stacks

- `subnet-calc-react-webapp-easyauth` - Uses shared Key Vault and Log Analytics
- `subnet-calc-react-apim` - Uses shared Log Analytics

## Cost Estimate

- Log Analytics: ~$2.76/GB ingested + $0.12/GB retention
- Key Vault: $0.03 per 10,000 operations
- Typical monthly cost: $5-20 depending on usage
