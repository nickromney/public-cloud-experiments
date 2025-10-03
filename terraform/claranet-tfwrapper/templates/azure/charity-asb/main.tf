locals {
  # Determine deployment mode based on environment
  is_shared_environment = var.environment == "shared"

  # Naming conventions
  location_short = module.azure_region.location_short

  # Resource group naming
  rg_name = coalesce(
    var.resource_group_name,
    "${var.organisation}-rg-${var.workload}-servicebus-${var.environment}-${local.location_short}"
  )

  # Managed identity naming
  identity_name = coalesce(
    var.managed_identity_name,
    "${var.organisation}-id-${var.workload}-servicebus-${var.environment}-${local.location_short}"
  )

  # Topic prefix for non-shared environments
  topic_prefix = local.is_shared_environment ? "" : "${var.environment}-"

  # Build topics list with environment prefix for non-shared environments
  prefixed_topics = [
    for topic in var.servicebus_topics : merge(
      topic,
      {
        name = local.is_shared_environment ? topic.name : "${local.topic_prefix}${topic.name}"
        custom_name = local.is_shared_environment ? topic.custom_name : (
          topic.custom_name != null ? "${local.topic_prefix}${topic.custom_name}" : null
        )
        subscriptions = [
          for sub in coalesce(topic.subscriptions, []) : merge(
            sub,
            {
              name = local.is_shared_environment ? sub.name : "${local.topic_prefix}${sub.name}"
              custom_name = local.is_shared_environment ? sub.custom_name : (
                sub.custom_name != null ? "${local.topic_prefix}${sub.custom_name}" : null
              )
            }
          )
        ]
      }
    )
  ]

  # Build queues list with environment prefix for non-shared environments
  prefixed_queues = [
    for queue in var.servicebus_queues : merge(
      queue,
      {
        name = local.is_shared_environment ? queue.name : "${local.topic_prefix}${queue.name}"
        custom_name = local.is_shared_environment ? queue.custom_name : (
          queue.custom_name != null ? "${local.topic_prefix}${queue.custom_name}" : null
        )
      }
    )
  ]
}

module "azure_region" {
  source  = "claranet/regions/azurerm"
  version = "~> 8.0"

  azure_region = var.azure_region
}

# Resource Group - only for shared environment
resource "azurerm_resource_group" "main" {
  count = local.is_shared_environment && var.create_resource_group ? 1 : 0

  name     = local.rg_name
  location = module.azure_region.location

  tags = merge(
    {
      environment  = var.environment
      workload     = var.workload
      managed_by   = "terraform"
      organisation = var.organisation
    },
    var.tags,
    var.additional_tags
  )
}

# Data source for existing resource group (non-shared environments)
data "azurerm_resource_group" "existing" {
  count = !local.is_shared_environment ? 1 : 0

  name = coalesce(
    var.existing_resource_group_name,
    local.rg_name
  )
}

# Managed Identity for Service Bus - only for shared environment
resource "azurerm_user_assigned_identity" "main" {
  count = local.is_shared_environment && var.create_managed_identity ? 1 : 0

  name                = local.identity_name
  resource_group_name = azurerm_resource_group.main[0].name
  location            = module.azure_region.location

  tags = merge(
    {
      environment  = var.environment
      workload     = var.workload
      managed_by   = "terraform"
      organisation = var.organisation
    },
    var.tags,
    var.additional_tags
  )
}

# Service Bus using Claranet module - for shared environment
module "service_bus_shared" {
  count = local.is_shared_environment ? 1 : 0

  source  = "claranet/service-bus/azurerm"
  version = "~> 8.0"

  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  client_name    = var.organisation
  environment    = var.shared_environment_suffix
  stack          = var.workload

  resource_group_name = local.is_shared_environment ? azurerm_resource_group.main[0].name : null

  # Namespace configuration
  namespace_sku       = var.servicebus_namespace_sku
  capacity            = var.servicebus_namespace_capacity
  zone_redundant      = var.zone_redundant
  local_auth_enabled  = var.local_auth_enabled
  minimum_tls_version = var.minimum_tls_version

  # Custom naming
  custom_namespace_name = var.namespace_custom_name

  # Network configuration
  public_network_access_enabled = var.public_network_access_enabled
  trusted_services_allowed      = var.trusted_services_allowed

  # Identity configuration - assign managed identity to namespace
  identity_type = var.create_managed_identity ? "UserAssigned" : null
  identity_ids  = var.create_managed_identity ? [azurerm_user_assigned_identity.main[0].id] : null

  # Topics, Queues, Subscriptions (empty for shared - just create namespace)
  servicebus_topics = []
  servicebus_queues = []

  # Diagnostic settings
  logs_destinations_ids = var.logs_destinations_ids

  # Tags
  extra_tags = merge(
    {
      shared_resource   = "true"
      subscription_type = local.is_shared_environment ? "nonprod" : "prod"
    },
    var.tags,
    var.additional_tags
  )
}

# Get existing Service Bus namespace for non-shared environments
data "azurerm_servicebus_namespace" "existing" {
  count = !local.is_shared_environment ? 1 : 0

  name                = var.existing_namespace_name
  resource_group_name = var.existing_namespace_resource_group
}

# Topics and Queues for non-shared environments using raw resources
# (Since we need to target an existing namespace not managed by this stack)
resource "azurerm_servicebus_topic" "main" {
  for_each = local.is_shared_environment ? {} : { for t in var.servicebus_topics : t.name => t }

  name         = "${local.topic_prefix}${each.value.name}"
  namespace_id = data.azurerm_servicebus_namespace.existing[0].id

  status                                  = try(each.value.status, "Active")
  auto_delete_on_idle                     = try(each.value.auto_delete_on_idle, null)
  default_message_ttl                     = try(each.value.default_message_ttl, null)
  duplicate_detection_history_time_window = try(each.value.duplicate_detection_history_time_window, null)
  max_message_size_in_kilobytes           = try(each.value.max_message_size_in_kilobytes, null)
  max_size_in_megabytes                   = try(each.value.max_size_in_megabytes, null)

  enable_batched_operations    = try(each.value.batched_operations_enabled, true)
  enable_partitioning          = try(each.value.partitioning_enabled, false)
  enable_express               = try(each.value.express_enabled, false)
  requires_duplicate_detection = try(each.value.requires_duplicate_detection, false)
  support_ordering             = try(each.value.support_ordering, false)
}

# Subscriptions for non-shared environments
resource "azurerm_servicebus_subscription" "main" {
  for_each = local.is_shared_environment ? {} : {
    for item in flatten([
      for topic in var.servicebus_topics : [
        for sub in coalesce(topic.subscriptions, []) : {
          key          = "${topic.name}-${sub.name}"
          topic_name   = topic.name
          subscription = sub
        }
      ]
    ]) : item.key => item
  }

  name     = "${local.topic_prefix}${each.value.subscription.name}"
  topic_id = azurerm_servicebus_topic.main[each.value.topic_name].id

  status              = try(each.value.subscription.status, "Active")
  auto_delete_on_idle = try(each.value.subscription.auto_delete_on_idle, null)
  default_message_ttl = try(each.value.subscription.default_message_ttl, null)
  lock_duration       = try(each.value.subscription.lock_duration, null)
  max_delivery_count  = each.value.subscription.max_delivery_count

  enable_batched_operations                 = try(each.value.subscription.batched_operations_enabled, true)
  dead_lettering_on_message_expiration      = try(each.value.subscription.dead_lettering_on_message_expiration, false)
  dead_lettering_on_filter_evaluation_error = try(each.value.subscription.dead_lettering_on_filter_evaluation_error, false)
  requires_session                          = try(each.value.subscription.requires_session, false)

  forward_to                        = try(each.value.subscription.forward_to, null)
  forward_dead_lettered_messages_to = try(each.value.subscription.forward_dead_lettered_messages_to, null)
}

# Subscription Rules for non-shared environments
resource "azurerm_servicebus_subscription_rule" "main" {
  for_each = local.is_shared_environment ? {} : {
    for item in flatten([
      for topic in var.servicebus_topics : [
        for sub in coalesce(topic.subscriptions, []) : [
          for rule in coalesce(sub.rules, []) : {
            key        = "${topic.name}-${sub.name}-${rule.name}"
            topic_name = topic.name
            sub_name   = sub.name
            rule       = rule
          }
        ]
      ]
    ]) : item.key => item
  }

  name            = each.value.rule.name
  subscription_id = azurerm_servicebus_subscription.main["${each.value.topic_name}-${each.value.sub_name}"].id
  filter_type     = each.value.rule.filter_type

  sql_filter = each.value.rule.filter_type == "SqlFilter" ? each.value.rule.sql_expression : null
  action     = each.value.rule.filter_type == "SqlFilter" ? try(each.value.rule.sql_action, null) : null

  dynamic "correlation_filter" {
    for_each = each.value.rule.filter_type == "CorrelationFilter" ? [each.value.rule.correlation_filter] : []
    content {
      correlation_id      = try(correlation_filter.value.correlation_id, null)
      message_id          = try(correlation_filter.value.message_id, null)
      to                  = try(correlation_filter.value.to, null)
      reply_to            = try(correlation_filter.value.reply_to, null)
      label               = try(correlation_filter.value.label, null)
      session_id          = try(correlation_filter.value.session_id, null)
      reply_to_session_id = try(correlation_filter.value.reply_to_session_id, null)
      content_type        = try(correlation_filter.value.content_type, null)
      properties          = try(correlation_filter.value.properties, {})
    }
  }
}

# Queues for non-shared environments
resource "azurerm_servicebus_queue" "main" {
  for_each = local.is_shared_environment ? {} : { for q in var.servicebus_queues : q.name => q }

  name         = "${local.topic_prefix}${each.value.name}"
  namespace_id = data.azurerm_servicebus_namespace.existing[0].id

  status                                  = try(each.value.status, "Active")
  auto_delete_on_idle                     = try(each.value.auto_delete_on_idle, null)
  default_message_ttl                     = try(each.value.default_message_ttl, null)
  duplicate_detection_history_time_window = try(each.value.duplicate_detection_history_time_window, null)
  max_message_size_in_kilobytes           = try(each.value.max_message_size_in_kilobytes, null)
  max_size_in_megabytes                   = try(each.value.max_size_in_megabytes, null)
  max_delivery_count                      = each.value.max_delivery_count
  lock_duration                           = try(each.value.lock_duration, null)

  enable_batched_operations    = try(each.value.batched_operations_enabled, true)
  enable_partitioning          = try(each.value.partitioning_enabled, false)
  enable_express               = try(each.value.express_enabled, false)
  requires_duplicate_detection = try(each.value.requires_duplicate_detection, false)
  requires_session             = try(each.value.requires_session, false)

  dead_lettering_on_message_expiration = try(each.value.dead_lettering_on_message_expiration, false)

  forward_to                        = try(each.value.forward_to, null)
  forward_dead_lettered_messages_to = try(each.value.forward_dead_lettered_messages_to, null)
}
