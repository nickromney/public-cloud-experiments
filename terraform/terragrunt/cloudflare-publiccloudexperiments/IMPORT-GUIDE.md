# Importing Cloudflare DNS Records into Terraform State

This guide shows how to import existing DNS records from Cloudflare into Terraform/Terragrunt state, allowing you to manage them as Infrastructure as Code.

**Direction:** Cloudflare → Terraform (reads from Cloudflare API, writes to Terraform state)

## Prerequisites

1. **Cloudflare credentials loaded:**

   ```bash
   eval "$(./setup-cloudflare-env.sh)"
   ```

2. **Azure backend variables set:**

   ```bash
   export TF_BACKEND_RG='rg-apim-experiment'
   export TF_BACKEND_SA='sttfstate202511061704'
   export TF_BACKEND_CONTAINER='terraform-states'
   ```

3. **Terragrunt initialized:**

   ```bash
   cd dns-core
   make init
   ```

## Quick Start

```bash
cd dns-core

# 1. Load credentials
eval "$(../setup-cloudflare-env.sh)"
export TF_BACKEND_RG='rg-apim-experiment'
export TF_BACKEND_SA='sttfstate202511061704'
export TF_BACKEND_CONTAINER='terraform-states'

# 2. Export existing DNS records from Cloudflare
make export-to-terraform > terraform.tfvars

# 3. Initialize Terragrunt
make init

# 4. Import records into Terraform state
make import-to-terraform

# 5. Verify no changes needed
make plan
```

## Step-by-Step Process

### Step 1: Export Current DNS Records

Export all existing DNS records from Cloudflare to `terraform.tfvars`:

```bash
make export-to-terraform > terraform.tfvars
```

This creates a file like:

```hcl
zone_name = "publiccloudexperiments.net"

records = {
  "static-swa-private-endpoint" = {
    type    = "A"
    value   = "20.254.110.219"
    proxied = true
  }
  "www" = {
    type    = "CNAME"
    value   = "example.com"
  }
  # ... more records
}
```

### Step 2: Review Configuration

Review `terraform.tfvars` and remove any records you don't want Terraform to manage. You can manage a subset of records if desired.

### Step 3: Initialize Terragrunt

```bash
make init
```

This sets up:

- Azure backend for state storage
- Cloudflare provider
- Terraform modules

### Step 4: Import Existing Records

```bash
make import-to-terraform
```

This will:

1. Prompt for confirmation
2. Fetch all records from Cloudflare API
3. Import each record into Terraform state
4. Show a summary of imported records

**What happens during import:**

For each DNS record, Terragrunt runs:

```bash
terragrunt import 'cloudflare_dns_record.records["<key>"]' '<zone_id>/<record_id>'
```

Example:

```bash
terragrunt import 'cloudflare_dns_record.records["www"]' 'd338fed554857c1081ad974209c5ef23/abc123def456'
```

### Step 5: Verify State

After importing, verify that Terraform's state matches your configuration:

```bash
make plan
```

**Expected output:**

```text
No changes. Your infrastructure matches the configuration.
```

If you see changes, it means:

- The exported tfvars don't match what's in Cloudflare
- Some records failed to import
- Record attributes differ (proxied, TTL, etc.)

## Import Script Details

The `import-to-terraform.sh` script:

1. **Fetches zone information:**

   ```bash
   curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/zones?name=example.com"
   ```

2. **Retrieves all DNS records:**

   ```bash
   curl -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records"
   ```

3. **Generates resource addresses:**
   - Apex records: `records["@"]`
   - Subdomains: `records["www"]`, `records["api"]`
   - Full names preserved for uniqueness

4. **Executes imports:**

   ```bash
   terragrunt import '<resource_address>' '<zone_id>/<record_id>'
   ```

## Cloudflare Import Format

Cloudflare DNS records use the format: `<zone_id>/<record_id>`

**Example:**

- Zone ID: `d338fed554857c1081ad974209c5ef23`
- Record ID: `abc123def456789`
- Import ID: `d338fed554857c1081ad974209c5ef23/abc123def456789`

**Resource Address:**

- Module: `module.cloudflare_dns_record`
- Resource type: `records`
- Key: Record name (e.g., "www", "@", "api")
- Full address: `cloudflare_dns_record.records["www"]`

## Troubleshooting

### Import Fails: "Resource already exists"

The record is already in state. This is normal if you run import multiple times.

**Solution:** No action needed, or run:

```bash
make clean
make init
make import-to-terraform
```

### Import Fails: "Module not found"

Terragrunt hasn't been initialized.

**Solution:**

```bash
make init
make import-to-terraform
```

### Plan Shows Changes After Import

The configuration doesn't match the actual state in Cloudflare.

**Solutions:**

1. **Re-export the records:**

   ```bash
   make export-to-terraform > terraform.tfvars
   make plan
   ```

2. **Check for formatting differences:**
   - TTL values (1 = Auto)
   - Proxied status
   - TXT record quotes

3. **Manually adjust terraform.tfvars to match Cloudflare**

### Import Script Hangs

The Cloudflare API might be rate-limited.

**Solution:** Wait a minute and try again.

## Manual Import

If you need to import a single record manually:

```bash
# Get the zone ID and record ID from Cloudflare API or dashboard
ZONE_ID="d338fed554857c1081ad974209c5ef23"
RECORD_ID="abc123def456789"

# Import the record
terragrunt import \
  'cloudflare_dns_record.records["www"]' \
  "$ZONE_ID/$RECORD_ID"
```

## Using with Other Zones

The import script works with any zone:

```bash
# Import from a different zone
../import-to-terraform.sh example.com

# Or create a custom Makefile for the new zone
cd ../example-com
make import-to-terraform
```

## State Management

After successful import, your Terraform state contains:

- All DNS record IDs
- Current configuration values
- Resource dependencies

**To view state:**

```bash
terragrunt state list
terragrunt state show 'cloudflare_dns_record.records["www"]'
```

**To remove a record from state (without deleting):**

```bash
terragrunt state rm 'cloudflare_dns_record.records["www"]'
```

## Best Practices

1. **Always export before import** - Ensures configuration matches reality
2. **Review before applying** - Check `terraform.tfvars` for correctness
3. **Use version control** - Commit `terraform.tfvars` to git
4. **Test with plan** - Always run `make plan` after import
5. **Document exceptions** - Comment why certain records aren't managed
6. **Regular exports** - Re-export periodically to catch manual changes

## Next Steps

After importing:

1. **Make changes:**

   ```bash
   # Edit terraform.tfvars
   make plan
   make apply
   ```

2. **Add new records:**

   ```bash
   # Add to terraform.tfvars
   make plan
   make apply
   ```

3. **Remove records:**

   ```bash
   # Remove from terraform.tfvars
   make plan
   # Records will be deleted from Cloudflare!
   make apply
   ```

## Reference

- [Cloudflare Provider - DNS Records](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/dns_record)
- [Terraform Import](https://opentofu.org/docs/cli/import/)
- [Terragrunt Documentation](https://terragrunt.gruntwork.io/)
