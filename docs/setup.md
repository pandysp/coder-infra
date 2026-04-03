# Setup Guide

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.9 (or [Terraform](https://developer.hashicorp.com/terraform/install))
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.15
- [Tailscale](https://tailscale.com/download) installed and connected on your local machine
- [Coder CLI](https://coder.com/docs/install) (for template push and workspace management)
- GNU Make
- A [Hetzner Cloud](https://www.hetzner.com/cloud) account with API token
- A Tailscale auth key (reusable, ephemeral) from the [admin console](https://login.tailscale.com/admin/settings/keys)
- A Claude Code setup token (run `claude setup-token` locally)

## 1. Clone and Configure

```bash
git clone https://github.com/pandysp/coder-infra.git && cd coder-infra
```

Copy and edit the Terraform variables file:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
hcloud_token       = "<your-hetzner-api-token>"
tailscale_auth_key = "<your-tailscale-auth-key>"
claude_setup_token = "<output-of-claude-setup-token>"
anthropic_api_key  = ""  # optional if using setup-token for subscription auth
coder_admin_email  = "your@email.com"
```

Optional variables (these have defaults):

```hcl
server_name     = "coder-dev"   # Hostname and Tailscale device name
server_type     = "cx33"        # Hetzner server type (cx33 = 4 vCPU, 8GB)
server_location = "fsn1"        # Hetzner datacenter (fsn1, nbg1, hel1)
github_token    = ""            # For workspace repo access
```

## 2. Deploy

```bash
cd terraform
tofu init
tofu apply
```

This will:
1. Create a Hetzner server with no public inbound ports
2. Bootstrap Tailscale via cloud-init
3. Wait for the server to appear on your tailnet
4. Run Ansible to configure Docker, Sysbox, and Coder
5. Start Coder via Docker Compose behind Caddy
6. Configure Tailscale Serve for HTTPS
7. Shred cloud-init artifacts containing secrets

## 3. Verify

```bash
cd ..
bash scripts/verify.sh
```

This checks Tailscale connectivity, SSH access, Docker, Sysbox, Coder API, and Tailscale Serve.

## 4. Complete Coder Setup

After deployment, the Coder URL is printed (e.g., `https://coder-dev.tailnet-name.ts.net`).

1. Log in with the Coder CLI:

```bash
coder login https://coder-dev.tailnet-name.ts.net
# Creates your admin account on first login
```

2. Push workspace templates:

```bash
make push-templates
```

This uses `tar -cvh` to dereference the shared module symlinks before pushing to Coder.

3. Create a workspace:

```bash
coder create my-workspace --template base-dev
```

The Coder UI will prompt for workspace parameters (CPU cores, memory, web preview port).

## Workspace Parameters

Both templates expose these parameters, configurable per-workspace:

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| CPU Cores | 2 | 1-4 | CPU scheduling weight (relative, via `cpu_shares`) |
| Memory (GB) | 4 | 1-8 | Container memory limit |
| Web Preview Port | 3000 | 1024-65535 | Port for the web preview app |

## Workspace Networking

Workspace containers run on the Docker bridge network and cannot reach the Tailscale FQDN directly. The template handles this with three mechanisms:

1. **Caddy binds to `0.0.0.0:80`** so workspace containers can reach it via the Docker bridge gateway (`host.docker.internal`). External access is blocked by the Hetzner cloud firewall (no inbound rules). Note: Docker port publishing bypasses UFW via iptables NAT rules, so the Hetzner firewall is the sole perimeter control for port 80.

2. **Init script URL rewriting**: The Coder agent init script references `CODER_ACCESS_URL` (a Tailscale FQDN). The template's `replace()` rewrites this to `http://host.docker.internal:80` so the agent can download and connect through Caddy.

3. **Dual DNS**: Containers use `100.100.100.100` (Tailscale MagicDNS) for Tailscale name resolution and `1.1.1.1` (Cloudflare) for internet DNS.

## Template Architecture

The workspace templates use a shared Terraform module to eliminate duplication:

```
templates/
  modules/workspace/     # Shared: agent, parameters, container, claude_code
  base-dev/
    main.tf              # enable_docker_in_docker = false
    modules -> ../modules  # Symlink (dereferenced during push)
  docker-dev/
    main.tf              # enable_docker_in_docker = true
    modules -> ../modules
```

## State Security

Terraform stores all resource attributes in `terraform.tfstate` as plain JSON, including sensitive values like your SSH private key and API tokens.

**Protect your state file:**
- `chmod 600 terraform.tfstate terraform.tfstate.backup`
- Never commit state files (already in `.gitignore`)

**For encrypted state**, configure a remote backend in `versions.tf`:

- **Hetzner Object Storage** (S3-compatible, see example in `terraform.tfvars.example`)
- **Terraform Cloud** free tier (encrypted at rest, access-controlled)

## Maintenance

### Update Coder

```bash
ssh root@coder-dev "cd /opt/coder && docker compose pull && docker compose up -d"
```

### Re-provision (e.g., after rotating secrets)

```bash
cd terraform
# Edit terraform.tfvars: force_reprovision = "2026-04-03-rotated-keys"
tofu apply
```

### Update templates

After editing files in `templates/modules/workspace/`:

```bash
make validate        # Check syntax
make push-templates  # Push to Coder
```

### SSH to Server

```bash
ssh root@coder-dev   # via Tailscale MagicDNS
mosh root@coder-dev  # for unreliable connections
```

### Destroy

```bash
cd terraform && tofu destroy
```

This removes the Hetzner server and attempts to log the device out of Tailscale.

## Troubleshooting

**Server not appearing on tailnet**: Check that your Tailscale auth key is valid and reusable. Verify cloud-init completed: `ssh root@<server-public-ip> "cloud-init status"` (temporarily add SSH to Hetzner firewall if needed).

**Coder not responding**: SSH to the server and check Docker: `docker compose -f /opt/coder/docker-compose.yml logs`.

**Workspace agent not connecting**: The most common cause is DNS — workspace containers need to resolve the Coder access URL. Check `docker logs <workspace-container>` for "Could not resolve host" errors. See the Workspace Networking section above.

**Sysbox containers failing**: Ensure the kernel supports user namespaces: `ssh root@coder-dev "sysctl kernel.unprivileged_userns_clone"`. Ubuntu 24.04 enables this by default.

**Re-provisioning fails**: If Ansible fails mid-run, `tofu apply` will re-run the full playbook. The playbook is idempotent — safe to re-run.
