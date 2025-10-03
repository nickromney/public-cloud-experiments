# Pluralsight Azure Sandbox Template

This template is specifically designed for **Pluralsight Azure Sandbox** environments that expire after 4 hours.

## Key Features

- **Limited Region Support**: Only `eastus` and `westus2` are available
- **4-Hour Expiration**: All resources are tagged with sandbox expiration time
- **Azure Service Bus Support**: Full support for namespaces, topics, and subscriptions
- **Sandbox-Friendly Settings**: Purge protection disabled, minimal retention periods
- **Cost-Optimized Defaults**: LRS storage, consumption plans, minimal logging

## Supported Azure Regions

Pluralsight sandboxes only support:

- `eastus` - East US
- `westus2` - West US 2

## Azure Service Bus Components

### Service Bus Namespaces

- Basic, Standard, and Premium SKU support
- Zone redundancy for Premium tier
- Automatic connection string output for Function Apps

### Service Bus Topics

- Partitioning support
- Duplicate detection
- Message ordering
- Auto-delete on idle
- Configurable TTL

### Service Bus Subscriptions

- SQL filters for message filtering
- Correlation filters for property-based routing
- Session support for ordered processing
- Dead lettering configuration
- Forward to other topics/queues

## Quick Start

### 1. Bootstrap the Stack

```bash
# From the project root
tfwrapper -a ps-sandbox -e sbx -r eastus -s messaging bootstrap azure/ps-az-sbx

# Or use the Makefile
make messaging bootstrap sbx eastus
```

### 2. Configure Your Sandbox

1. Get your sandbox credentials from Pluralsight
2. Update the subscription ID in your configuration
3. Copy and customize the example tfvars:

```bash
cd ps-sandbox/sbx/eastus/messaging
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription ID
```

### 3. Deploy Resources

```bash
# Initialize
tfwrapper init

# Plan
tfwrapper plan

# Apply (remember: sandbox expires in 4 hours!)
tfwrapper apply
```

## Example: Service Bus Message Processing

The template includes a complete example with:

1. **Service Bus Namespace** with Standard SKU
2. **Topics**:
   - `orders` - Partitioned topic with duplicate detection
   - `events` - Non-partitioned with message ordering
3. **Subscriptions**:
   - `order-processing` - SQL filter for high-priority orders
   - `order-audit` - Receives all order messages
   - `event-handler` - Correlation filter for specific event types
4. **Function App** connected to Service Bus for processing

## Configuration Examples

### Minimal Service Bus Setup

```hcl
service_bus_namespaces = {
  "demo" = {
    resource_group_key = "main"
    sku                = "Basic"
  }
}

service_bus_topics = {
  "messages" = {
    namespace_key = "demo"
  }
}

service_bus_subscriptions = {
  "processor" = {
    topic_key = "messages"
  }
}
```

### Advanced Filtering Example

```hcl
service_bus_subscriptions = {
  "high-priority" = {
    topic_key = "orders"

    # SQL filter
    sql_filter = {
      sql_expression = "Priority = 'High' AND Amount > 1000"
      action         = "SET Category = 'Urgent'"
    }
  }

  "regional" = {
    topic_key = "orders"

    # Correlation filter
    correlation_filter = {
      properties = {
        Region = "US-East"
        Tier   = "Premium"
      }
    }
  }
}
```

### Function App with Service Bus Trigger

```hcl
function_apps = {
  "processor" = {
    resource_group_key        = "compute"
    storage_account_key       = "funcs"
    runtime_stack             = "python"
    runtime_version           = "3.11"

    # Automatic Service Bus connection
    service_bus_namespace_key = "main"
    service_bus_connection_name = "ServiceBusConnection"
  }
}
```

The connection string is automatically added to the Function App's application settings.

## Important Notes

### Sandbox Limitations

1. **4-Hour Expiration**: Plan your work accordingly
2. **Limited Regions**: Only eastus and westus2
3. **Resource Quotas**: Sandboxes have resource limits
4. **No Persistent State**: Use local state or temporary storage

### Best Practices for Sandboxes

1. **Use Minimal Resources**:
   - LRS for storage (not GRS)
   - Consumption plans for Functions
   - Basic/Standard SKUs where possible

2. **Disable Expensive Features**:
   - Set `purge_protection = false` for Key Vaults
   - Use minimum retention periods
   - Disable Application Insights for demos

3. **Quick Cleanup**:
   - Always run `terraform destroy` before sandbox expires
   - Use `prevent_deletion_if_contains_resources = false`

4. **State Management**:
   - Consider using local state for sandbox demos
   - Or create a temporary storage account for remote state

## Outputs

The template provides comprehensive outputs:

- Service Bus connection strings (sensitive)
- Service Bus endpoints and keys
- Topic and subscription IDs
- Function App details with Service Bus integration
- Sandbox expiration information

## Troubleshooting

### Common Issues

1. **Region Not Supported**: Ensure you're using `eastus` or `westus2`
2. **Subscription Not Found**: Update subscription_id in terraform.tfvars
3. **SKU Not Available**: Some Premium features may not be available in sandbox
4. **Quota Exceeded**: Reduce resource counts or sizes

### Service Bus Specific

1. **Namespace Already Exists**: Service Bus namespace names are globally unique
2. **SKU Limitations**: Basic tier doesn't support topics (only queues)
3. **Partitioning**: Can't be changed after topic creation
4. **Session Support**: Requires specific client configuration

## Clean Up

**IMPORTANT**: Always destroy resources before the 4-hour expiration:

```bash
# Destroy all resources
tfwrapper destroy

# Or force destroy if needed
terraform destroy -auto-approve
```

## Additional Resources

- [Pluralsight Sandbox Documentation](https://help.pluralsight.com/hc/en-us/articles/24392988447636-Azure-cloud-sandbox)
- [Azure Service Bus Documentation](https://docs.microsoft.com/en-us/azure/service-bus-messaging/)
- [Service Bus Pricing](https://azure.microsoft.com/en-us/pricing/details/service-bus/)
