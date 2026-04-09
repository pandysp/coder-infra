# Setup Guide

This guide walks through deploying a self-hosted Coder instance with Claude Code on a Hetzner VPS behind Tailscale. The result is a persistent, zero-trust platform for running AI coding agents and remote development environments -- accessible only from your tailnet.

## Setup Variants

Choose your tier based on what you need. Each builds on the previous one.

### Minimal (fastest path)

Tailscale Serve for HTTPS, no custom domain, no GitHub OAuth. You get fire-and-forget Tasks, Claude Code in workspaces, and code-server -- all behind Tailscale. This is sufficient for solo use where you access everything via Tailscale URLs.

**You need:** Hetzner account, Tailscale account, Claude setup token.

### Recommended (full feature set)

Adds a custom domain with wildcard TLS (via Cloudflare DNS-01) and GitHub OAuth. Wildcard subdomains enable code-server and Web Preview on their own URLs instead of port-forwarded proxies. GitHub OAuth gives seamless git auth inside workspaces.

**You additionally need:** A domain with DNS on Cloudflare, a GitHub OAuth App.

See [Custom Domain](#custom-domain-optional) and [GitHub External Auth](#github-external-auth-optional) below.

### Team (small teams, automation)

Adds the GitHub Action for Issue-to-Task automation and workspace presets for different use cases. Multiple team members can fire tasks from GitHub issues without touching the Coder UI.

**You additionally need:** Tailscale OAuth client (for GitHub Actions to join tailnet), Coder session token.

See [Automated Issue-to-Task](#automated-issue-to-task) below.

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.9 (or [Terraform](https://developer.hashicorp.com/terraform/install))
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.15
- [Tailscale](https://tailscale.com/download) installed and connected on your local machine
- [Coder CLI](https://coder.com/docs/install) (for template push and workspace management)
- GNU Make
- A [Hetzner Cloud](https://www.hetzner.com/cloud) account with API token
- A Tailscale auth key (reusable, ephemeral) from the [admin console](https://login.tailscale.com/admin/settings/keys)
- A Claude Code setup token (run `claude setup-token` locally)
- A Cloudflare account with DNS control for your zone (optional, only if you want a custom domain)

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
github_oauth_client_id     = "" # GitHub OAuth App for external auth (optional)
github_oauth_client_secret = "" # (create at github.com/settings/developers)
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
6. Either configure Tailscale Serve for HTTPS or, when `coder_domain` is set, build Caddy with Cloudflare DNS-01 and wildcard subdomain routing
7. Shred cloud-init artifacts containing secrets

## 3. Verify

```bash
cd ..
bash scripts/verify.sh
```

This checks Tailscale connectivity, SSH access, Docker, Sysbox, Coder API, and whichever routing mode is active (`tailscale serve` or custom-domain TLS on `443`).

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

The Coder UI will prompt for workspace parameters (CPU cores, memory, repo, branch, Claude mode, web preview port).

## Workspace Parameters

Both templates expose these parameters, configurable per-workspace:

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| CPU Cores | 2 | 1-4 | CPU scheduling weight (relative, via `cpu_shares`) |
| Memory (GB) | 4 | 1-8 | Container memory limit |
| Repository URL | (empty) | empty, `https://...`, or `git@...` | Git repo to clone into workspace |
| Repository Branch | (empty) | any string | Branch passed to the git clone module when a repository URL is set |
| Claude Permission | bypassPermissions | default/acceptEdits/bypassPermissions | Permission level for Claude Code |
| Web Preview Port | 3000 | 1024-65535 | Port for the web preview app |

## Workspace Presets

The shared workspace module defines three presets so users can pick a sane resource/profile bundle without filling every field manually:

| Preset | CPU | Memory | Claude Mode | Notes |
|--------|-----|--------|-------------|-------|
| Quick Task | 1 | 2 GB | `bypassPermissions` | Default preset for fast, low-overhead tasks |
| Full Development | 3 | 6 GB | `acceptEdits` | Higher-resource preset for active coding sessions |
| Autonomous Agent | 2 | 4 GB | `bypassPermissions` | Balanced preset for longer autonomous runs |

## GitHub External Auth (Optional)

To enable GitHub OAuth for seamless git operations in workspaces:

1. Create a GitHub OAuth App at [github.com/settings/developers](https://github.com/settings/developers)
2. Set the callback URL to: `https://<your-coder-url>/external-auth/github/callback`
3. Add to `terraform.tfvars`:

```hcl
github_oauth_client_id     = "<your-client-id>"
github_oauth_client_secret = "<your-client-secret>"
```

4. Re-provision: `cd terraform && tofu apply`

After re-provisioning, users can connect their GitHub account via the Coder dashboard under Settings > External Auth.

## Custom Domain (Optional)

To enable wildcard subdomain routing for apps like code-server and Web Preview, point a custom domain at the server's Tailscale IP and let Caddy terminate TLS with Cloudflare DNS-01.

> **Note:** The DNS records point at a Tailscale IP (100.x.y.z), which is only reachable from devices on your tailnet. This gives you wildcard subdomain routing and nicer URLs for tailnet members — it does not make Coder publicly accessible.

1. In [Cloudflare DNS](https://dash.cloudflare.com/), create two `A` records (DNS-only mode, not proxied):
   - `coder.yourdomain.com` -> `<tailscale-ip>`
   - `*.coder.yourdomain.com` -> `<tailscale-ip>`

   Get your server's Tailscale IP with: `tailscale ip -4 <server-name>`

2. Create a Cloudflare API token with `Zone > DNS > Edit` permission for your zone.

3. Add these variables to `terraform.tfvars`:

```hcl
coder_domain         = "coder.yourdomain.com"
cloudflare_api_token = "<cloudflare-token-with-zone-dns-edit>"
```

4. Re-provision so Ansible rebuilds Caddy with the Cloudflare DNS plugin:

```hcl
# terraform.tfvars
force_reprovision = "2026-04-04-custom-domain"
```

```bash
cd terraform
tofu apply
```

When `coder_domain` is set, Coder uses `https://coder.yourdomain.com`, Caddy binds port `443` directly with a wildcard TLS cert, and Tailscale Serve is disabled. Port 80 remains open on the Docker bridge for workspace container agent bootstrapping — tailnet peers can also reach it, but all traffic is already encrypted at the WireGuard layer.

## MCP Server (Optional)

Coder can expose an MCP server so local Claude Code or Claude Desktop sessions can inspect and manage your remote workspaces without SSHing into the server manually.

Configure it from a logged-in machine with:

```bash
coder exp mcp configure claude-code
```

This feature is currently beta. Expect roughly 5,900 tokens of tool overhead per turn, so it is useful when local orchestration matters and unnecessary when you are already working inside the Coder workspace itself.

## Tasks UI

The workspace templates include `coder_ai_task` which enables the Coder Tasks UI for fire-and-forget background agents:

1. Open the Coder dashboard
2. Navigate to Tasks
3. Create a new task with a prompt (e.g., "Fix the auth timeout bug")
4. Claude Code runs autonomously in an isolated workspace
5. Review the results when notified

Tasks auto-pause at workspace idle timeout and can be resumed later.

## Automated Issue-to-Task

A GitHub Action (`.github/workflows/coder-task.yml`) automates creating Coder Tasks from GitHub issues:

1. Add repository secrets: `CODER_URL` and `CODER_SESSION_TOKEN`
2. Label any GitHub issue with `coder`
3. The action runs `coder task create --template base-dev` with the issue body and repository URL in the prompt
4. Claude Code works autonomously and creates a PR

Generate a session token with:

```bash
coder tokens create
```

## Workspace Networking

Workspace containers run on the Docker bridge network and cannot reach the Tailscale FQDN directly. The template handles this with three mechanisms:

1. **Caddy binds to `0.0.0.0:80`** so workspace containers can reach it via the Docker bridge gateway (`host.docker.internal`). When `coder_domain` is set, Caddy also binds `0.0.0.0:443` and handles TLS itself; otherwise Tailscale Serve terminates HTTPS on `443`. External access is blocked by the Hetzner cloud firewall (no inbound rules). Note: Docker port publishing bypasses UFW via iptables NAT rules, so the Hetzner firewall is the sole perimeter control for port 80/443.

   When `coder_domain` is set, Caddy also gets a Docker network alias matching the domain name. This lets the Coder container resolve the access URL to Caddy's container IP directly (with valid TLS via SNI), which is required for the deployment health check — without it, DNS resolves to the Tailscale IP, which is unreachable from the Docker bridge network (EACS03). In Tailscale Serve mode (no custom domain), Caddy gets a Docker network alias matching the Tailscale FQDN and serves it with `tls internal`; the Coder container trusts that internal CA via `SSL_CERT_DIR`, so the same deployment health check works without routing back to the Tailscale interface.

2. **Init script URL rewriting**: The Coder agent init script references `CODER_ACCESS_URL` (Tailscale FQDN by default, custom domain when enabled). The template's `replace()` rewrites this to `http://host.docker.internal:80` so the agent can download and connect through Caddy.

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
