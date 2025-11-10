# Azure API Management Module

Reusable Terraform module for deploying Azure API Management (APIM) instances with optional Application Insights integration.

## Features

- **Multiple deployment modes**: Public (Developer/Standard), Internal VNet, External VNet
- **Application Insights integration**: Optional logger and diagnostics configuration
- **Firewall-friendly**: Outputs public IP addresses for NSG/firewall rules
- **Comprehensive diagnostics**: Configurable request/response logging
- **Validation**: Input validation for SKU, network type, email format
- **Flexible**: Supports both greenfield and brownfield scenarios

## Usage

### Public APIM (Developer Tier)

```hcl
module "apim_public" {
  source = "../../modules/azure-apim"

  name                = "apim-myapp-dev"
  location            = "uksouth"
  resource_group_name = "rg-myapp-dev"
  publisher_name      = "My Company"
  publisher_email     = "api@example.com"
  sku_name            = "Developer_1"

  # Public access
  virtual_network_type          = "None"
  public_network_access_enabled = true

  # Optional: Application Insights
  app_insights_id                 = azurerm_application_insights.this.id
  app_insights_instrumentation_key = azurerm_application_insights.this.instrumentation_key

  tags = {
    environment = "dev"
    project     = "myapp"
  }
}
```

### Internal APIM (VNet-integrated)

```hcl
module "apim_internal" {
  source = "../../modules/azure-apim"

  name                = "apim-myapp-prod"
  location            = "uksouth"
  resource_group_name = "rg-myapp-prod"
  publisher_name      = "My Company"
  publisher_email     = "api@example.com"
  sku_name            = "Premium_1"

  # Internal VNet integration
  virtual_network_type          = "Internal"
  subnet_id                     = azurerm_subnet.apim.id
  public_network_access_enabled = false

  # Application Insights
  app_insights_id                 = azurerm_application_insights.this.id
  app_insights_instrumentation_key = azurerm_application_insights.this.instrumentation_key

  tags = {
    environment = "prod"
    project     = "myapp"
  }
}
```

### Minimal Configuration (No Observability)

```hcl
module "apim_minimal" {
  source = "../../modules/azure-apim"

  name                = "apim-test"
  location            = "uksouth"
  resource_group_name = "rg-test"
  publisher_name      = "Test Publisher"
  publisher_email     = "test@example.com"

  # All other variables use defaults
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.8 |
| azurerm | >= 4.0 |

## Inputs

### Required Inputs

| Name | Description | Type | Default | Validation |
|------|-------------|------|---------|------------|
| name | API Management instance name | `string` | - | - |
| location | Azure region | `string` | - | - |
| resource_group_name | Resource group name | `string` | - | - |
| publisher_name | Publisher name | `string` | - | - |
| publisher_email | Publisher email | `string` | - | Valid email format |

### Optional Inputs

| Name | Description | Type | Default | Validation |
|------|-------------|------|---------|------------|
| sku_name | APIM SKU (e.g., Developer_1) | `string` | `"Developer_1"` | Format: `tier_capacity` |
| virtual_network_type | Network type (None/Internal/External) | `string` | `"None"` | Must be None, Internal, or External |
| subnet_id | VNet subnet ID | `string` | `null` | Required when `virtual_network_type != "None"` |
| public_network_access_enabled | Enable public access | `bool` | `true` | - |
| app_insights_id | Application Insights resource ID | `string` | `null` | - |
| app_insights_instrumentation_key | App Insights instrumentation key | `string` | `null` | Required if `app_insights_id` is set |
| diagnostics_sampling_percentage | Diagnostics sampling (0-100) | `number` | `100.0` | 0-100 |
| diagnostics_always_log_errors | Always log errors | `bool` | `true` | - |
| diagnostics_log_client_ip | Log client IPs | `bool` | `true` | - |
| diagnostics_verbosity | Verbosity level | `string` | `"information"` | error, information, verbose |
| diagnostics_http_correlation_protocol | Correlation protocol | `string` | `"W3C"` | None, Legacy, W3C |
| tags | Resource tags | `map(string)` | `{}` | - |

## Outputs

| Name | Description |
|------|-------------|
| id | APIM instance ID |
| name | APIM instance name |
| gateway_url | Gateway URL |
| management_api_url | Management API URL |
| developer_portal_url | Developer portal URL |
| public_ip_addresses | Outbound public IPs (for firewall rules) |
| private_ip_addresses | Private IPs (VNet mode) |
| identity_principal_id | Managed identity principal ID |
| logger_id | Application Insights logger ID |
| diagnostics_id | Diagnostics configuration ID |

## APIM SKU Tiers

| SKU | Use Case | Provisioning Time | Monthly Cost (approx) |
|-----|----------|-------------------|----------------------|
| Developer_1 | Development/testing, no SLA | ~37 minutes | ~$50 |
| Basic_1 | Small workloads, 99.95% SLA | ~25 minutes | ~$150 |
| Standard_1 | Production, 99.95% SLA | ~25 minutes | ~$700 |
| Premium_1 | Multi-region, VNet, 99.99% SLA | ~45 minutes | ~$2,850 |

**Important**: Developer tier is NOT for production use (no SLA, single deployment unit).

## Network Modes

### None (Public)

- APIM accessible from internet
- Suitable for Developer/Standard/Premium tiers
- No VNet integration required
- Use IP restrictions on backends for security

### Internal (Private)

- APIM accessible only from VNet
- Requires Premium SKU
- Need Azure Firewall or Application Gateway for public access
- Best for fully private architectures

### External (Hybrid)

- APIM gateway accessible from internet
- Management plane accessible only from VNet
- Requires Premium SKU
- Balance of security and accessibility

## Application Insights Integration

When `app_insights_id` is provided, the module creates:

1. **APIM Logger**: Connects APIM to Application Insights
2. **APIM Diagnostics**: Configures request/response logging

**Logged Information:**

- Request/response headers (configurable list)
- Request/response bodies (first N bytes, default 1024)
- Client IP addresses
- Errors and exceptions
- Performance metrics

**Cost Consideration**: Application Insights charges by data ingestion. Adjust sampling percentage and body bytes to manage costs.

## Firewall Integration

The module outputs `public_ip_addresses` for APIM outbound traffic. Use this for:

- **Azure Function IP restrictions**
- **NSG rules** (for VNet-integrated backends)
- **On-premises firewall rules**

Example:

```hcl
resource "azurerm_function_app_config" "restrictions" {
  for_each = toset(module.apim_public.public_ip_addresses)

  # Configure IP restrictions using APIM IPs
  # ...
}
```

## Diagnostics Configuration

Control diagnostics granularity:

```hcl
module "apim" {
  # ... other config ...

  # Reduce sampling for cost optimization
  diagnostics_sampling_percentage = 10.0

  # Log only errors
  diagnostics_verbosity = "error"

  # Reduce body logging
  diagnostics_frontend_request_body_bytes = 512
  diagnostics_backend_request_body_bytes  = 512

  # Custom headers to log
  diagnostics_frontend_request_headers = [
    "Authorization",
    "X-Correlation-ID"
  ]
}
```

## Examples

See the following stacks for usage examples:

- **Public APIM**: [subnet-calc-react-webapp-apim](../../personal-sub/subnet-calc-react-webapp-apim/main.tf)
- **Internal APIM**: [subnet-calc-internal-apim](../../personal-sub/subnet-calc-internal-apim/main.tf)

## Related Resources

After creating an APIM instance, you'll typically need:

1. **API Definition**: `azurerm_api_management_api`
2. **Backend Configuration**: `azurerm_api_management_backend`
3. **API Policies**: `azurerm_api_management_api_policy`
4. **Subscription** (if required): `azurerm_api_management_subscription`
5. **Private DNS** (for Internal mode): `azurerm_private_dns_zone`

These resources are NOT included in this module - they should be defined in the calling stack.

## Known Issues

1. **Provisioning Time**: APIM takes 30-45 minutes to provision. Plan accordingly.
2. **VNet Changes**: Changing VNet configuration requires APIM recreation.
3. **SKU Downgrade**: Cannot downgrade from Premium to lower SKUs.
4. **Public IP Changes**: Public IPs may change during APIM updates.

## Best Practices

1. **Use Premium for production** - Required for VNet, multi-region, SLA
2. **Enable diagnostics early** - Helps troubleshoot issues during development
3. **Use managed identity** - Avoid storing credentials in configuration
4. **Implement retry policies** - Handle transient failures gracefully
5. **Monitor usage** - Track API calls, errors, performance
6. **Version APIs** - Use revisions for breaking changes
7. **Secure backends** - Use IP restrictions or private endpoints
8. **Tag resources** - Include environment, project, owner tags

## References

- [Azure APIM Documentation](https://learn.microsoft.com/en-us/azure/api-management/)
- [APIM SKU Comparison](https://azure.microsoft.com/en-us/pricing/details/api-management/)
- [APIM VNet Integration](https://learn.microsoft.com/en-us/azure/api-management/api-management-using-with-vnet)
- [APIM Policies Reference](https://learn.microsoft.com/en-us/azure/api-management/api-management-policies)
