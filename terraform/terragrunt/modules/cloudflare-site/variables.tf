variable "zone_name" {
  description = "Cloudflare zone to manage (e.g., publiccloudexperiments.net)."
  type        = string
}

variable "records" {
  description = "Map of DNS records to create, keyed by logical name."
  type = map(object({
    type     = string
    value    = string
    ttl      = optional(number)
    proxied  = optional(bool)
    priority = optional(number)
    comment  = optional(string)
  }))
  default = {}
}
