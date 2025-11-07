# DNS Core Stack

Manages the primary DNS records for `publiccloudexperiments.net` using the `cloudflare-site` module.

## Usage

```bash
export TF_BACKEND_RG=rg-apim-experiment
export TF_BACKEND_SA=sttfstate202511061704
export TF_BACKEND_CONTAINER=terraform-states
export CLOUDFLARE_API_TOKEN=<token>
export CLOUDFLARE_ACCOUNT_ID=<account>

cd terraform/terragrunt/cloudflare-publiccloudexperiments/dns-core
cp terraform.tfvars.example terraform.tfvars   # customize records
terragrunt init
terragrunt plan
terragrunt apply
```

Records are defined as a map where each key is the DNS name (relative to the zone) and includes the Cloudflare record attributes (`type`, `value`, optional `ttl`, `proxied`, etc.). The module automatically looks up the zone ID and creates the necessary `cloudflare_dns_record` resources.
