resource "tls_private_key" "deploy" {
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "deploy" {
  name       = "${var.server_name}-deploy"
  public_key = tls_private_key.deploy.public_key_openssh
}

resource "hcloud_server" "coder" {
  name         = var.server_name
  server_type  = var.server_type
  location     = var.server_location
  image        = "ubuntu-24.04"
  ssh_keys     = [hcloud_ssh_key.deploy.name]
  firewall_ids = [hcloud_firewall.default.id]

  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    tailscale_auth_key = var.tailscale_auth_key
    hostname           = var.server_name
  })
}
