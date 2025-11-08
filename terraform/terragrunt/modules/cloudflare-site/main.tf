resource "cloudflare_dns_record" "records" {
  for_each = var.records

  zone_id = var.zone_id
  name    = each.key
  type    = each.value.type
  content = each.value.value

  # TTL: 1 = automatic, or use provided value (must be 60-86400, or 30-86400 for Enterprise zones)
  # Default to 1 (automatic) if not specified
  ttl      = coalesce(each.value.ttl, 1)
  proxied  = try(each.value.proxied, null)
  priority = try(each.value.priority, null)
  comment  = try(each.value.comment, null)
}
