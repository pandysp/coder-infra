# Setup Guide

## Prerequisites

- [Pulumi CLI](https://www.pulumi.com/docs/install/) with a Pulumi Cloud account
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) >= 2.15
- [Tailscale](https://tailscale.com/download) installed and connected on your local machine
- A [Hetzner Cloud](https://www.hetzner.com/cloud) account with API token
- A Tailscale auth key (reusable, ephemeral) from the [admin console](https://login.tailscale.com/admin/settings/keys)
- An [Anthropic API key](https://console.anthropic.com/)
- A Claude Code setup token (run `claude setup-token` locally)

## 1. Clone and Configure

```bash
git clone <repo-url> && cd coder-infra
cd pulumi && npm install
```

Initialize the Pulumi stack:

```bash
pulumi stack init prod
```

Set required config values:

```bash
pulumi config set --secret hcloud:token <your-hetzner-api-token>
pulumi config set --secret tailscaleAuthKey <your-tailscale-auth-key>
pulumi config set --secret claudeSetupToken <your-claude-setup-token>
pulumi config set --secret anthropicApiKey <your-anthropic-api-key>
pulumi config set coderAdminEmail your@email.com
```

Optional config (these have defaults):

```bash
pulumi config set serverName coder-dev          # default: coder-dev
pulumi config set serverType cx33               # default: cx33
pulumi config set serverLocation fsn1           # default: fsn1
pulumi config set --secret githubToken <token>  # for workspace repo access
```

## 2. Install Ansible Dependencies

```bash
cd ../ansible
ansible-galaxy collection install -r requirements.yml
```

## 3. Deploy

```bash
cd ../pulumi
pulumi up
```

This will:
1. Create a Hetzner CX33 server with no public inbound ports
2. Bootstrap Tailscale via cloud-init (the only thing cloud-init does)
3. Wait for the server to appear on your tailnet
4. Run Ansible to configure Docker, Sysbox, and Coder
5. Start Coder via Docker Compose with Caddy reverse proxy
6. Configure Tailscale Serve for HTTPS access
7. Shred the cloud-init log (contains the Tailscale auth key)

## 4. Complete Coder Setup

After deployment, the Coder URL is printed (e.g., `https://coder-dev.tailnet-name.ts.net`).

1. Open the Coder URL in your browser (must be on the same tailnet)
2. Create your admin account
3. Push workspace templates:

```bash
cd ../templates/base-dev
coder templates push base-dev \
  --variable anthropic_api_key=<your-key> \
  --variable claude_setup_token=<your-token>

cd ../docker-dev
coder templates push docker-dev \
  --variable anthropic_api_key=<your-key> \
  --variable claude_setup_token=<your-token>
```

## 5. Verify

```bash
../scripts/verify.sh coder-dev
```

## Workspace Templates

### base-dev

General-purpose development workspace with:
- Claude Code with Coder Tasks integration
- tmux, vim, git, jq, ripgrep, fd, htop
- Node.js 22 LTS
- Python 3
- Persistent `/home/coder` volume
- Web preview on port 3000

### docker-dev

Everything in base-dev, plus:
- Docker-in-Docker via Sysbox (no `--privileged` needed)
- Full Docker daemon inside the workspace
- Suitable for container-based development and CI workflows

## Architecture

```
Tailnet Client (your laptop)
    │
    ▼ (HTTPS via Tailscale Serve)
Hetzner CX33 (no public inbound ports)
    │
    ├── Tailscale (networking + HTTPS cert)
    │       │
    │       ▼ (proxy to localhost:80)
    │   Caddy (Docker container)
    │       │
    │       ▼ (reverse proxy to coder:7080)
    │   Coder (Docker container)
    │       │
    │       ├── PostgreSQL (Docker container)
    │       │
    │       └── Workspace containers
    │           ├── base-dev (standard runtime)
    │           └── docker-dev (Sysbox runtime, DinD)
    │
    ├── Docker + Sysbox (container runtimes)
    └── UFW (Tailscale-only firewall)
```

## Maintenance

### Update Coder

```bash
ssh root@coder-dev "cd /opt/coder && docker compose pull && docker compose up -d"
```

### SSH to Server

```bash
ssh root@coder-dev   # via Tailscale MagicDNS
mosh root@coder-dev  # for unreliable connections
```

### Destroy

```bash
cd pulumi && pulumi destroy
```

## Troubleshooting

**Server not appearing on tailnet**: Check that your Tailscale auth key is valid and reusable. Verify cloud-init completed: `ssh root@<server-public-ip> "cloud-init status"` (temporarily add SSH to Hetzner firewall if needed).

**Coder not responding**: SSH to the server and check Docker: `docker compose -f /opt/coder/docker-compose.yml logs`.

**Sysbox containers failing**: Ensure the kernel supports user namespaces: `ssh root@coder-dev "sysctl kernel.unprivileged_userns_clone"`. Ubuntu 24.04 enables this by default.
