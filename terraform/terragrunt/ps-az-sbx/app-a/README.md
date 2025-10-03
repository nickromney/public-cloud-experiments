# Pluralsight Sandbox - App A

Simple Terragrunt deployment for Pluralsight Azure Sandbox with toggleable resources using map patterns.

## Key Concepts

### Map Pattern (0 to n)

All resources use **maps** instead of booleans for maximum flexibility:

```hcl
# Disabled - empty map
function_apps = {}

# Enabled - add items to map
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "dotnet-isolated"
    runtime_version      = "8.0"
  }
}

# Multiple - add more items (0 to n)
function_apps = {
  "api" = { ... }
  "worker" = { ... }
  "processor" = { ... }
}
```

**Why maps over booleans?**

- `for_each` works naturally with maps
- Easy to add/remove resources without changing code
- Supports 0 to n instances, not just 0 or 1
- Clear intent: empty map = feature disabled

### Reference Keys

Resources reference each other using **keys** in the map:

```hcl
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"  # Links to app_service_plans["consumption"]
    storage_account_key  = "funcapp"      # Links to storage_accounts["funcapp"]
  }
}
```

## Structure

```text
pluralsight/app-a/
├── terragrunt.hcl              # Terragrunt config (points to module)
├── terraform.tfvars            # Your configuration (git-ignored)
├── terraform.tfvars.example    # Example configurations
└── README.md                   # This file
```

## Setup

1. **Copy example file:**

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Get Pluralsight sandbox:**
   - Go to Pluralsight Azure Sandbox
   - Note your **Resource Group name** (e.g., `1-12345678-playground-sandbox`)
   - Set environment variables:

     ```bash
     export ARM_SUBSCRIPTION_ID="your-sub-id"
     export ARM_TENANT_ID="your-tenant-id"
     export TF_BACKEND_RG="your-backend-rg"
     export TF_BACKEND_SA="your-backend-sa"
     export TF_BACKEND_CONTAINER="terraform-states"
     ```

3. **Update terraform.tfvars:**

   ```hcl
   existing_resource_group_name = "1-12345678-playground-sandbox"

   # Enable resources you want by adding to maps
   storage_accounts = { ... }
   function_apps = { ... }
   ```

## Usage

```bash
cd pluralsight/app-a

# Initialize
terragrunt init

# Plan
terragrunt plan

# Apply
terragrunt apply

# Destroy (when done with sandbox)
terragrunt destroy
```

## Toggle Examples

### Just Function App

```hcl
storage_accounts = {
  "funcapp" = {
    account_tier      = "Standard"
    replication_type  = "LRS"
    purpose           = "function-app-storage"
  }
}

app_service_plans = {
  "consumption" = {
    os_type  = "Linux"
    sku_name = "Y1"
  }
}

function_apps = {
  "api" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "dotnet-isolated"
    runtime_version      = "8.0"
    app_settings         = {}
  }
}

# Disabled
static_web_apps = {}
apim_instances = {}
apim_apis = {}
```

### Full Stack (Functions + SWA + APIM)

```hcl
storage_accounts = { ... }
app_service_plans = { ... }
function_apps = { ... }

static_web_apps = {
  "frontend" = {
    sku_tier = "Free"
    sku_size = "Free"
  }
}

apim_instances = {
  "shared" = {
    sku_name        = "Developer_1"
    publisher_name  = "Cloud Experiments"
    publisher_email = "your-email@example.com"
  }
}

apim_apis = {
  "api-v1" = {
    apim_key         = "shared"
    function_app_key = "api"
    path             = "api/v1"
    display_name     = "API V1"
    protocols        = ["https"]
  }
}
```

### Multiple Function Apps (0 to n)

```hcl
function_apps = {
  "api" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "dotnet-isolated"
    runtime_version      = "8.0"
    app_settings         = {}
  }
  "worker" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "python"
    runtime_version      = "3.11"
    app_settings         = {}
  }
  "processor" = {
    app_service_plan_key = "consumption"
    storage_account_key  = "funcapp"
    runtime              = "node"
    runtime_version      = "20"
    app_settings         = {}
  }
}
```

## Pluralsight Sandbox Limitations

- **4-hour expiration** - Everything is ephemeral
- **Vended resource group** - Cannot create new resource groups
- **No role assignments** - Cannot create custom RBAC roles
- **Limited regions** - eastus, westus2

## Module

The Terraform module uses `for_each` on all map variables:

```hcl
resource "azurerm_linux_function_app" "this" {
  for_each = var.function_apps  # 0 to n instances

  name = "func-${var.project_name}-${var.environment}-${each.key}"
  # ...
}
```

Empty map = no resources created. Add items to map = resources created.
