output "server_ipv4" {
  value = hcloud_server.coder.ipv4_address
}

output "hostname" {
  value = var.server_name
}

output "deploy_public_key" {
  value     = tls_private_key.deploy.public_key_openssh
  sensitive = true
}
