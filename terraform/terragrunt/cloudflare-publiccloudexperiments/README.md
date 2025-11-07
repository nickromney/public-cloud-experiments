# Cloudflare Terragrunt Stacks

This hierarchy manages Cloudflare resources (DNS records, Access apps, etc.) for `publiccloudexperiments.net`. It mirrors the layout of `terragrunt/personal-sub`, but uses the Cloudflare provider (v5) and keeps state in the same Azure Storage Account.

## Prerequisites

1. Export Azure backend variables (same ones used everywhere else):

   ```bash
   export TF_BACKEND_RG=rg-apim-experiment
   export TF_BACKEND_SA=sttfstate202511061704
   export TF_BACKEND_CONTAINER=terraform-states
   ```

2. Export Cloudflare credentials:

   ```bash
   export CLOUDFLARE_API_TOKEN=<token with DNS/Edit scope>
   export CLOUDFLARE_ACCOUNT_ID=<account uuid>
   ```

3. Install Terragrunt/OpenTofu.

### Cloudflare API Token Scopes

Create an account-owned token per [the Cloudflare docs](https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/) with at least:

- **Zone → DNS → Edit** (manage DNS records)
- **Zone → Zone Settings → Read** (provider needs to inspect the zone)
- **Account → Account Settings → Read** (allows listing zones under the account)

If you later add Access, Workers, or Tunnels resources, extend the token with the relevant scopes (for example, *Account → Cloudflare Tunnel → Edit*). Store the token securely (1Password/Azure Key Vault) and only export it in the shell where you run Terragrunt.

## Usage

Each stack lives under this directory (e.g., `dns-core`). From a stack folder:

```bash
terragrunt init
terragrunt plan
terragrunt apply
```

The generated `provider.tf` pulls credentials from `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`. No secrets live in tfvars or source control.

## Modules

- `terraform/terragrunt/modules/cloudflare-site` – simple module that looks up a zone and manages a map of DNS records (`cloudflare_dns_record`). Additional resources (access applications, Workers, tunnels) can be layered in future modules.

## Recommended Stack Layout

- `dns-core` – authoritative DNS records for the primary zone.
- `access-apps` – Cloudflare Access apps/service tokens.
- `tunnels` – Cloudflare Tunnels + routing records.

Add new stacks as needed, each pointing at the relevant module(s). Ensure the Terragrunt `inputs` reference `zone_name` and record maps instead of embedding tokens in Terraform files.
