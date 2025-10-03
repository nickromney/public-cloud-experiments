# Charity Azure Service Bus Template

Template for charity organizations (like RNLI) to manage Azure Service Bus infrastructure using a cost-optimized shared namespace pattern.

## Architecture Pattern

### Environment Structure

- **nonprod subscription**: `shared`, `dev`, `test` environments
- **prod subscription**: `shared`, `prod` environments

The "shared" environment contains the Service Bus namespace, while other environments deploy topics/queues/subscriptions into that shared namespace with environment prefixes.

## Template Features

This template uses the [Claranet Service Bus module](https://github.com/claranet/terraform-azurerm-service-bus) and implements:

- **Environment-aware deployment** - Automatically detects whether to deploy namespace (shared) or topics/queues (dev/test/prod)
- **Automatic prefixing** - Topics/queues in non-shared environments get automatic prefixes (dev-, test-, prod-)
- **Cost optimization** - Share expensive Service Bus namespaces between environments in the same subscription
- **Full feature support** - Topics, subscriptions, queues, SQL/correlation filters, session support
- **Claranet module integration** - Uses official Claranet Service Bus module for shared environment deployments

## Deployment Flow

### Step 1: Deploy Shared Namespace (Once per subscription)

```bash
# Bootstrap the shared namespace stack
tfwrapper -a charity -e shared -r uksouth -s charity-asb bootstrap azure/charity-asb

# Configure (edit terraform.tfvars)
cd charity/shared/uksouth/charity-asb
cp terraform.tfvars.shared.example terraform.tfvars
# Edit terraform.tfvars with your values

# Deploy
tfwrapper init
tfwrapper plan
tfwrapper apply

# Capture namespace details for next steps
tfwrapper output -json > namespace-outputs.json
```

### Step 2: Deploy Dev Topics

```bash
# Bootstrap dev topics stack
tfwrapper -a charity -e dev -r uksouth -s charity-asb bootstrap azure/charity-asb

# Configure
cd charity/dev/uksouth/charity-asb
cp terraform.tfvars.dev.example terraform.tfvars
# Edit terraform.tfvars - set existing_namespace_name and existing_namespace_resource_group

# Deploy dev topics/queues
tfwrapper init
tfwrapper plan
tfwrapper apply
```

### Step 3: Deploy Test Topics

```bash
# Bootstrap test topics stack
tfwrapper -a charity -e test -r uksouth -s charity-asb bootstrap azure/charity-asb

# Configure
cd charity/test/uksouth/charity-asb
cp terraform.tfvars.test.example terraform.tfvars
# Edit terraform.tfvars - use THE SAME namespace as dev

# Deploy test topics/queues
tfwrapper init
tfwrapper plan
tfwrapper apply
```

## Using the Makefile

The Makefile supports the standard tfwrapper pattern:

```bash
# Deploy shared namespace
make charity-asb bootstrap shared uks
make charity-asb plan shared uks
make charity-asb apply shared uks

# Deploy dev environment
make charity-asb bootstrap dev uks
make charity-asb plan dev uks
make charity-asb apply dev uks

# Deploy test environment
make charity-asb bootstrap test uks
make charity-asb plan test uks
make charity-asb apply test uks
```

## Configuration Examples

### Shared Environment (terraform.tfvars.shared.example)

- Creates the Service Bus namespace
- Sets up resource group
- Configures namespace SKU, capacity, network rules
- Does NOT create topics/queues

### Dev Environment (terraform.tfvars.dev.example)

- References existing shared namespace
- Creates dev-prefixed topics and queues
- Includes subscriptions with filters
- Development-friendly settings (shorter TTLs, auto-delete)

### Test Environment (terraform.tfvars.test.example)

- References THE SAME shared namespace as dev
- Creates test-prefixed topics and queues
- Includes test-specific topics (integration-testing)
- Higher limits for load testing

## Key Variables

### For Shared Environment

- `environment = "shared"` - MUST be "shared" to trigger namespace creation
- `shared_environment_suffix` - "nonprod" or "prod" for naming
- `servicebus_namespace_sku` - Basic, Standard, or Premium
- `create_resource_group` - Whether to create the resource group

### For Dev/Test/Prod Environments

- `environment` - "dev", "test", or "prod" (triggers topic/queue creation)
- `existing_namespace_name` - Name of the shared namespace
- `existing_namespace_resource_group` - Resource group of shared namespace
- `servicebus_topics` - List of topics with subscriptions and rules
- `servicebus_queues` - List of queues

## Naming Conventions

### Generated Names (Default)

- Resource Group: `{org}-rg-{workload}-servicebus-{env}-{location_short}`
- Namespace: Uses Claranet module naming convention
- Topics/Queues: `{env}-{name}` (e.g., dev-contact-updates, test-donation-events)

## Cost Optimization

1. **Shared namespaces** between dev/test in nonprod subscription
2. **Standard SKU** for non-prod (Premium only for prod if needed)
3. **Auto-delete** on test topics/queues
4. **Appropriate TTLs** on messages
5. **Partitioning** only where needed (increases cost)

## Production Considerations

For production deployments:

1. Deploy a separate `shared` environment in the prod subscription
2. Use **Premium SKU** for better performance
3. Enable **zone redundancy**
4. Configure **private endpoints**
5. Set `public_network_access_enabled = false`
6. Enable **diagnostic settings** with Log Analytics
7. Consider **geo-disaster recovery**

## Troubleshooting

### Common Issues

1. **"Namespace not found"** - Ensure shared environment is deployed first
2. **"Access denied"** - Check subscription and permissions
3. **"Topic already exists"** - Check if another environment already created it
4. **"Cannot create topic"** - Basic tier only supports queues, not topics

### Useful Commands

```bash
# List all topics in a namespace
az servicebus topic list --namespace-name charity-sbns-dataservices-nonprod-uks --resource-group charity-rg-dataservices-servicebus-shared-uks

# Check namespace connection string
az servicebus namespace authorization-rule keys list --name RootManageSharedAccessKey --namespace-name charity-sbns-dataservices-nonprod-uks --resource-group charity-rg-dataservices-servicebus-shared-uks
```

## Module Reference

This template uses the official [Claranet Service Bus module](https://github.com/claranet/terraform-azurerm-service-bus) for shared environment deployments. The module provides:

- Standardized naming conventions
- Built-in diagnostic settings support
- Authorization rules management
- Network rules configuration
- Tags management

For non-shared environments, raw Azure resources are used to allow deploying into an existing namespace not managed by the current stack.
