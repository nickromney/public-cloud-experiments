# Exporting DNS Records from Cloudflare to Terraform

The `export-to-terraform.sh` script exports existing DNS records from Cloudflare into formats suitable for Terraform/Terragrunt.

## Prerequisites

1. Cloudflare credentials loaded:

   ```bash
   eval "$(./setup-cloudflare-env.sh)"
   ```

2. Required tools:
   - `jq` (JSON processing): `brew install jq`
   - `yq` (YAML processing, only for YAML output): `brew install yq`

## Usage

### Basic Usage

```bash
# Export to JSON (default)
./export-to-terraform.sh publiccloudexperiments.net

# Export to YAML
./export-to-terraform.sh publiccloudexperiments.net yaml

# Export to Terraform tfvars format
./export-to-terraform.sh publiccloudexperiments.net tfvars

# Save to file
./export-to-terraform.sh publiccloudexperiments.net tfvars > dns-core/terraform.tfvars
```

### Using the Makefile

From the `dns-core/` directory:

```bash
# Load credentials
eval "$(../setup-cloudflare-env.sh)"

# Export DNS records to stdout
make export-to-terraform

# Save to terraform.tfvars
make export-to-terraform > terraform.tfvars
```

## Output Formats

### JSON

Complete JSON export including zone metadata:

```json
{
  "zone_name": "publiccloudexperiments.net",
  "zone_id": "d338fed554857c1081ad974209c5ef23",
  "ssl_mode": "full",
  "records": [...]
}
```

### YAML

Human-readable YAML format:

```yaml
zone_name: publiccloudexperiments.net
zone_id: d338fed554857c1081ad974209c5ef23
ssl_mode: full
records:
  - name: example.publiccloudexperiments.net
    type: A
    content: 203.0.113.10
```

### Terraform tfvars

Ready-to-use Terraform variable format:

```hcl
zone_name = "publiccloudexperiments.net"

records = {
  "example" = {
    type    = "A"
    value   = "203.0.113.10"
    proxied = true
    ttl     = 300
  }
}
```

## Record Types Supported

The script exports all DNS record types:

- **A** - IPv4 address
- **AAAA** - IPv6 address
- **CNAME** - Canonical name
- **TXT** - Text records
- **MX** - Mail exchange (includes priority)
- **SRV** - Service records (includes priority)
- **NS** - Name server
- **CAA** - Certification Authority Authorization

## Features

### Smart Key Generation

- Apex records use `@` as the key
- Subdomain records use the subdomain name (e.g., `www`, `api`)
- Full domain names are preserved for uniqueness

### Cloudflare-Specific Fields

- **proxied**: Whether the record is proxied through Cloudflare (orange cloud)
- **ttl**: Time to live (1 = Auto)
- **priority**: For MX and SRV records
- **comment**: Record comments (if set)

### SSL Settings

The script also fetches the current SSL mode:

- `off` - No SSL
- `flexible` - SSL between browser and Cloudflare only
- `full` - SSL between browser and Cloudflare, and Cloudflare and origin
- `strict` - Full SSL with certificate verification

## Example Workflow

### Initial Import from Existing Zone

1. **Export existing records to terraform.tfvars:**

   ```bash
   cd dns-core
   eval "$(../setup-cloudflare-env.sh)"
   make export-to-terraform > terraform.tfvars
   ```

2. **Review and edit if needed:**

   ```bash
   # terraform.tfvars now contains all your existing DNS records
   # Edit if you want to manage only a subset
   ```

3. **Initialize Terragrunt:**

   ```bash
   # Make sure Azure backend variables are set
   export TF_BACKEND_RG='rg-apim-experiment'
   export TF_BACKEND_SA='sttfstate202511061704'
   export TF_BACKEND_CONTAINER='terraform-states'

   make init
   ```

4. **Import existing records into state:**

   ```bash
   make import-to-terraform
   # This will prompt for confirmation, then import all records
   ```

5. **Verify state matches configuration:**

   ```bash
   make plan
   # Should show "No changes" if import was successful
   ```

### Import Process

The `import-to-terraform` target uses the `import-to-terraform.sh` script which:

1. Fetches all DNS records from Cloudflare
2. Generates the correct Terraform resource addresses
3. Runs `terragrunt import` for each record
4. Uses the format: `zone_id/record_id` for Cloudflare imports

**Import Resource Addressing:**

- Terraform resource: `module.cloudflare_dns_record.records["<key>"]`
- Cloudflare import ID: `<zone_id>/<record_id>`
- Example: `terragrunt import 'module.cloudflare_dns_record.records["www"]' 'd338fed554857c1081ad974209c5ef23/abc123def456'`

### Using with Other Zones

The script is designed to be reusable:

```bash
# Export from a different zone
./export-to-terraform.sh example.com tfvars > example-dns.tfvars

# Export from multiple zones
for zone in zone1.com zone2.net zone3.org; do
  ./export-to-terraform.sh "$zone" tfvars > "${zone%.com}.tfvars"
done
```

## Limitations

- **Read-only**: Current API token has `DNS:Read` permission only
- **SSL settings**: Can read SSL mode but cannot modify (would need `SSL and Certificates:Edit`)
- **Pagination**: Handles up to 10,000 records (100 records × 100 pages)

## Troubleshooting

### Error: "CLOUDFLARE_API_TOKEN is not set"

Load credentials first:

```bash
eval "$(./setup-cloudflare-env.sh)"
```

### Error: "jq is not installed"

Install required tools:

```bash
brew install jq
# For YAML output:
brew install yq
```

### Error: "Zone not found"

Check the zone name is correct:

```bash
# List zones in your account
curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r '.result[].name'
```

## API Token Permissions

Current token permissions for `publiccloudexperiments.net`:

- Zone Settings:Read
- DNS:Read
- SSL and Certificates:Read

To enable SSL mode management, add:

- SSL and Certificates:Edit
