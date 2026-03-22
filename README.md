# coder-infra

Self-hosted [Coder](https://coder.com) + [Claude Code](https://claude.ai/claude-code) on Hetzner with [Tailscale](https://tailscale.com) zero-trust networking.

Persistent remote Claude Code sessions with project isolation. No public ports. Fork and customize.

## Stack

| Layer | Tool |
|-------|------|
| Provisioning | Pulumi (TypeScript) |
| Configuration | Ansible (roles-based) |
| Networking | Tailscale (zero-trust, HTTPS via Serve) |
| Workspaces | Coder Community Edition |
| Container Runtime | Docker + Sysbox (Docker-in-Docker) |
| Server | Hetzner CX33 (4 vCPU, 8GB RAM, Ubuntu 24.04) |

## Quick Start

```bash
# 1. Install dependencies
cd pulumi && npm install
cd ../ansible && ansible-galaxy collection install -r requirements.yml

# 2. Configure
cd ../pulumi
pulumi stack init prod
pulumi config set --secret hcloud:token <hetzner-token>
pulumi config set --secret tailscaleAuthKey <tailscale-auth-key>
pulumi config set --secret claudeSetupToken <claude-setup-token>
pulumi config set --secret anthropicApiKey <anthropic-api-key>
pulumi config set coderAdminEmail your@email.com

# 3. Deploy
pulumi up

# 4. Verify
../scripts/verify.sh coder-dev
```

Then open the printed Coder URL, create your admin account, and push the workspace templates.

See [docs/setup.md](docs/setup.md) for detailed instructions.

## Architecture

```
Hetzner CX33 (no public inbound ports)
  ├── Tailscale (networking, HTTPS via Serve)
  ├── Docker + Sysbox (container runtimes)
  └── Coder (Docker Compose: coder + postgres + caddy)
        ├── base-dev   — Claude Code + tmux + dev tools
        └── docker-dev — base-dev + Docker-in-Docker via Sysbox
```

## Workspace Templates

- **base-dev**: Claude Code, tmux, Node.js, Python, common CLI tools, persistent home volume
- **docker-dev**: Everything above + full Docker daemon inside the workspace (Sysbox, no `--privileged`)

## License

MIT
