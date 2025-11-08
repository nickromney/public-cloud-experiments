# Stack-Based Infrastructure Design Pattern

## Philosophy

Instead of defining individual Azure resources with explicit names, we define **logical application stacks**. Each stack represents a complete deployment topology with related resources.

## Data Structure

```hcl
stacks = {
  "stack-key" = {
    # Logical identifier used in Terraform - NOT the Azure resource name
    # Azure names are computed from: naming conventions + stack key + random suffix

    swa = {
      # Static Web App configuration
      sku            = "Standard"
      custom_domain  = "example.com"
      network_access = "Enabled"  # or "Disabled" for private endpoint
      # Note: auth_enabled, auth_provider, allowed_roles are planned features
    }

    function_app = {
      # Function App configuration (optional - some SWAs don't have backends)
      plan_sku       = "FC1"        # FC1 (Flex Consumption) or B1, S1, etc.
      python_version = "3.11"
      auth_method    = "jwt"        # jwt, swa, none
      custom_domain  = "api.example.com"

      # CORS origins computed from SWA custom domain
      app_settings = {
        # Additional app settings beyond defaults
      }
    }
  }
}
```

## Naming Convention

Resources are named using a predictable pattern:

- **Static Web Apps**: `swa-{project}-{stack-key}`
- **Function Apps**: `func-{project}-{stack-key}`
- **App Service Plans**: `asp-{project}-{stack-key}`
- **Storage Accounts**: `st{project}{stack-key}{random}`

Where:

- `{project}` = project identifier (e.g., "subnetcalc")
- `{stack-key}` = the stack map key (e.g., "noauth", "entraid")
- `{random}` = random suffix for globally unique names (storage accounts)

## Benefits

1. **Logical organization**: Think in terms of application stacks, not individual resources
2. **DRY**: Common patterns defined once, applied to all stacks
3. **Relationships**: Stack defines topology, Terraform manages dependencies
4. **Scalability**: Add new stack = one new map entry
5. **Import-friendly**: Can import existing resources by mapping Azure names to stack keys

## Import Strategy

When importing existing infrastructure:

1. Map existing Azure resources to logical stack keys
2. Use Terraform's `import` with the logical resource address
3. Adjust terraform.tfvars to match actual deployed configuration

Example import:

```bash
# Existing Azure resource: swa-subnet-calc-noauth
# Maps to logical stack: "noauth"
terragrunt import 'azurerm_static_web_app.this["noauth"]' "/subscriptions/.../swa-subnet-calc-noauth"
```

## Resource Generation

The module uses `for_each` over the stacks map to generate:

- One Static Web App per stack
- One Function App per stack (if function_app is defined)
- One App Service Plan per stack with function_app
- One Storage Account per stack with function_app

All resources within a stack automatically reference each other via local computations.
