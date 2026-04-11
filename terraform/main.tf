check "custom_domain_requires_cloudflare" {
  assert {
    condition     = var.coder_domain == "" || (var.cloudflare_api_token != "" && var.cloudflare_zone_id != "" && var.tailnet_dns_name != "")
    error_message = "When coder_domain is set, cloudflare_api_token, cloudflare_zone_id, and tailnet_dns_name are all required. Caddy needs the token for ACME DNS-01; Terraform manages DNS CNAMEs via the zone ID pointing to the MagicDNS name."
  }
}

# Requires: the machine running Terraform must be on the same tailnet
resource "terraform_data" "provision" {
  # Store server_name so the destroy provisioner can reference it via self.output
  input = var.server_name

  triggers_replace = [
    hcloud_server.coder.id,
    var.force_reprovision,
  ]

  provisioner "local-exec" {
    command = "bash ${path.module}/../scripts/provision.sh"
    environment = {
      SERVER_NAME                = var.server_name
      SSH_PRIVATE_KEY            = tls_private_key.deploy.private_key_openssh
      CODER_ADMIN_EMAIL          = var.coder_admin_email
      CLAUDE_SETUP_TOKEN         = var.claude_setup_token
      ANTHROPIC_API_KEY          = var.anthropic_api_key
      GITHUB_OAUTH_CLIENT_ID     = var.github_oauth_client_id
      GITHUB_OAUTH_CLIENT_SECRET = var.github_oauth_client_secret
      CODER_DOMAIN               = var.coder_domain
      CLOUDFLARE_API_TOKEN       = var.cloudflare_api_token
      PROVISION_GRAFANA_ADMIN_USER     = var.grafana_admin_user
      PROVISION_GRAFANA_ADMIN_PASSWORD = var.grafana_admin_password
      PROVISION_ALERTMANAGER_WEBHOOK_URL = var.alertmanager_webhook_url
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@${self.output} 'tailscale logout' 2>/dev/null || true"
  }
}
