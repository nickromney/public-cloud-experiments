output "zone_id" {
  description = "Cloudflare zone ID managed by this module."
  value       = var.zone_id
}

output "record_ids" {
  description = "Map of DNS record IDs created."
  value = {
    for name, record in cloudflare_dns_record.records : name => record.id
  }
}
