data "cloudflare_zone" "selected" {
  zone_id = var.zone_id
}

resource "cloudflare_dns_record" "records" {
  for_each = var.records

  zone_id = data.cloudflare_zone.selected.id
  name    = each.key
  type    = each.value.type
  content = each.value.value

  # TTL must be 1 (automatic) for proxied records, otherwise use provided value or null
  ttl      = try(each.value.proxied, false) == true ? 1 : try(each.value.ttl, null)
  proxied  = try(each.value.proxied, null)
  priority = try(each.value.priority, null)
  comment  = try(each.value.comment, null)
}
