# coder-infra

[![Coder Version](https://img.shields.io/badge/coder-v2.31.7-blue)](https://github.com/coder/coder/releases/tag/v2.31.7)

Self-hosted AI coding agents on a EUR 15/month VPS. Fire tasks, close the lid, review PRs.

An open-source reference setup for running [Coder](https://coder.com) + [Claude Code](https://claude.ai/claude-code) on Hetzner with [Tailscale](https://tailscale.com) zero-trust networking.

## Why This Exists

AI coding agents are tethered to your laptop. Close the lid, lose WiFi, run out of battery -- session dies. You can't run multiple agents in parallel. You can't fire-and-forget.

[Coder](https://coder.com) started as an enterprise Cloud Development Environment platform: Terraform-managed, self-hosted, cloud-agnostic dev containers. Then people realized the same isolated, persistent environments that developers need are exactly what AI agents need. Coder leaned in -- Tasks API, Claude Code module, MCP server, workspace presets.

This repo is a reference implementation proving the full stack works on a single EUR 15/month Hetzner VPS. Fork it, customize it, run your own.

## What You Can Do

**AI Agent Features**
- **Fire-and-forget Tasks** -- delegate work to Claude Code, close the laptop, it keeps running
- **Workspace presets** -- Quick Task / Full Development / Autonomous Agent (one-click resource profiles)
- **MCP Server** -- Claude Code or Claude Desktop on your local machine can manage remote workspaces
- **GitHub Issue to Task** -- label an issue `coder`, a GitHub Action creates a task, Claude Code works autonomously and opens a PR
- **Parallel agents** -- run multiple tasks simultaneously, each in its own isolated workspace

**Development Environment Features**
- **code-server** -- full VS Code in the browser via subdomain
- **Web Preview** -- live preview of web apps via wildcard subdomain routing
- **Docker-in-Docker** -- nested containers via Sysbox (docker-dev template)
- **Git integration** -- GitHub OAuth for seamless auth, or SSH keys
- **Dotfiles** -- personal environment customization via Coder module
- **Persistent storage** -- Docker volumes survive workspace restarts
- **Resource monitoring** -- memory/disk threshold alerts in the dashboard
- **Live metadata** -- CPU, memory, disk usage visible in workspace dashboard

**Infrastructure Features**
- **Zero public ports** -- Tailscale-only access, no inbound firewall rules
- **Wildcard TLS** -- custom domain with certs via Cloudflare DNS-01 (optional)
- **Infrastructure as code** -- Terraform provisioning + Ansible configuration, fully reproducible
- **One-command deploy** -- `tofu apply` provisions everything
- **Health checks** -- `scripts/verify.sh` validates the full stack

## Three Concepts

**Template** (Terraform blueprint) defines what a workspace looks like. **Workspace** is a running instance of a template -- a container with tools, storage, and an agent. **Task** is a workspace + AI agent + prompt: fire-and-forget autonomous work.

## Setup Variants

| Decision | Default | Alternative | When to switch |
|----------|---------|-------------|----------------|
| **TLS/Routing** | Tailscale Serve | Custom domain + Cloudflare | You want wildcard subdomain routing for web previews and code-server |
| **Docker-in-Docker** | Disabled (base-dev) | Enabled (docker-dev) | Workspaces need to build/run containers |
| **GitHub OAuth** | Disabled | Enabled | You want seamless git auth in workspaces |
| **Claude Auth** | Setup token | + API key | You want direct API access alongside subscription auth |

See [docs/setup.md](docs/setup.md) for detailed instructions on each variant.

## Quick Start

```bash
# 1. Configure
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Hetzner token, Tailscale key, etc.

# 2. Deploy
tofu init && tofu apply

# 3. Verify
cd .. && bash scripts/verify.sh

# 4. Log in and push templates
coder login https://<your-server>.ts.net  # or https://coder.yourdomain.com
make push-templates
```

Then create a workspace:

```bash
coder create my-workspace --template base-dev
```

## Architecture

```
Tailnet Client (your laptop / Claude Desktop / MCP)
    |
    v (HTTPS via Tailscale Serve or Caddy + Cloudflare)
Hetzner Cloud (no public inbound ports)
    ├── Tailscale (zero-trust networking)
    ├── Caddy (reverse proxy, optional wildcard TLS with Cloudflare DNS-01)
    ├── Coder (workspace manager, port 7080)
    ├── PostgreSQL (Coder state)
    ├── UFW (Tailscale-only firewall)
    └── Workspace containers
          ├── base-dev   (Claude Code + code-server + Node.js + tools)
          └── docker-dev (base-dev + Docker daemon via Sysbox)
```

## Stack

| Layer | Tool |
|-------|------|
| Provisioning | Terraform/OpenTofu (HCL) |
| Configuration | Ansible (roles-based) |
| Networking | Tailscale (zero-trust, HTTPS via Serve or Caddy) |
| Workspaces | Coder Community Edition |
| Container Runtime | Docker + Sysbox (Docker-in-Docker) |
| Server | Hetzner Cloud (Ubuntu 24.04) |

## Development

```bash
make help           # Show all targets
make validate       # Lint Terraform + Ansible
make push-templates # Push templates to Coder
make verify         # Post-deploy health checks
```

## License

MIT
