# Outputs for test fixtures

output "tenant_id" {
  description = "Random UUID for tenant ID in tests"
  value       = random_uuid.tenant_id.result
}

output "subscription_id" {
  description = "Random UUID for subscription ID in tests"
  value       = random_uuid.subscription_id.result
}

output "client_id" {
  description = "Random UUID for client ID in tests"
  value       = random_uuid.client_id.result
}

output "object_id" {
  description = "Random UUID for object ID in tests"
  value       = random_uuid.object_id.result
}
