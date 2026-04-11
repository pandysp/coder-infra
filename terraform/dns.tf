# DNS records for custom domain → Tailscale MagicDNS
#
# Uses CNAME to the MagicDNS FQDN so records auto-follow Tailscale IP changes.
# Only created when coder_domain, cloudflare_zone_id, and tailnet_dns_name are all set.

locals {
  manage_dns = var.coder_domain != "" && var.cloudflare_zone_id != "" && var.tailnet_dns_name != ""
}

resource "cloudflare_dns_record" "coder" {
  count   = local.manage_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.coder_domain
  type    = "CNAME"
  content = var.tailnet_dns_name
  ttl     = 300
  proxied = false
}

resource "cloudflare_dns_record" "coder_wildcard" {
  count   = local.manage_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "*.${var.coder_domain}"
  type    = "CNAME"
  content = var.tailnet_dns_name
  ttl     = 300
  proxied = false
}
