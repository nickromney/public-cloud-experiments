# Outputs for shared environment
output "namespace_id" {
  description = "The ID of the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_id : null
}

output "namespace_name" {
  description = "The name of the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_name : null
}

output "namespace_endpoint" {
  description = "The endpoint of the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_endpoint : null
}

output "namespace_primary_connection_string" {
  description = "The primary connection string for the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_primary_connection_string : null
  sensitive   = true
}

output "namespace_secondary_connection_string" {
  description = "The secondary connection string for the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_secondary_connection_string : null
  sensitive   = true
}

output "namespace_primary_key" {
  description = "The primary access key for the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_primary_key : null
  sensitive   = true
}

output "namespace_secondary_key" {
  description = "The secondary access key for the Service Bus namespace"
  value       = local.is_shared_environment ? module.service_bus_shared[0].namespace_secondary_key : null
  sensitive   = true
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = local.is_shared_environment ? azurerm_resource_group.main[0].name : data.azurerm_resource_group.existing[0].name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = local.is_shared_environment ? azurerm_resource_group.main[0].id : data.azurerm_resource_group.existing[0].id
}

# Outputs for non-shared environments
output "topics" {
  description = "Map of created topics and their IDs"
  value = !local.is_shared_environment ? {
    for k, v in azurerm_servicebus_topic.main : k => {
      id                    = v.id
      name                  = v.name
      enable_partitioning   = v.enable_partitioning
      max_size_in_megabytes = v.max_size_in_megabytes
    }
  } : {}
}

output "subscriptions" {
  description = "Map of created subscriptions and their IDs"
  value = !local.is_shared_environment ? {
    for k, v in azurerm_servicebus_subscription.main : k => {
      id                 = v.id
      name               = v.name
      max_delivery_count = v.max_delivery_count
      requires_session   = v.requires_session
    }
  } : {}
}

output "queues" {
  description = "Map of created queues and their IDs"
  value = !local.is_shared_environment ? {
    for k, v in azurerm_servicebus_queue.main : k => {
      id                    = v.id
      name                  = v.name
      max_size_in_megabytes = v.max_size_in_megabytes
      requires_session      = v.requires_session
    }
  } : {}
}

# General outputs
output "environment" {
  description = "The environment name"
  value       = var.environment
}

output "is_shared_environment" {
  description = "Whether this is a shared environment deployment"
  value       = local.is_shared_environment
}

output "topic_prefix" {
  description = "The prefix applied to topics/queues/subscriptions"
  value       = local.topic_prefix
}
