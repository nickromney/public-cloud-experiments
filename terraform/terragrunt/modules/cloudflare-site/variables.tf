variable "zone_name" {
  description = "Cloudflare zone to manage (e.g., publiccloudexperiments.net). Used for documentation and output purposes only."
  type        = string
}

variable "zone_id" {
  description = "Cloudflare zone ID. Required for zone data source lookup."
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
