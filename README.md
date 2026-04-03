# coder-infra

Self-hosted [Coder](https://coder.com) + [Claude Code](https://claude.ai/claude-code) on Hetzner with [Tailscale](https://tailscale.com) zero-trust networking.

Persistent remote Claude Code sessions with project isolation. No public ports. Fork and customize.

## Stack

| Layer | Tool |
|-------|------|
| Provisioning | Terraform/OpenTofu (HCL) |
| Configuration | Ansible (roles-based) |
| Networking | Tailscale (zero-trust, HTTPS via Serve) |
| Workspaces | Coder Community Edition |
| Container Runtime | Docker + Sysbox (Docker-in-Docker) |
| Server | Hetzner Cloud (Ubuntu 24.04) |

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

# 4. Log in to Coder and push templates
coder login https://<your-server>.ts.net
make push-templates
```

Then create a workspace from the Coder UI or CLI:

```bash
coder create my-workspace --template base-dev
```

See [docs/setup.md](docs/setup.md) for detailed instructions.

## Architecture

```
Tailnet Client (your laptop)
    |
    v (HTTPS via Tailscale Serve, port 443)
Hetzner Cloud (no public inbound ports)
    |
    +-- Tailscale (networking + HTTPS cert)
    +-- Caddy (reverse proxy, port 80)
    +-- Coder (workspace manager, port 7080)
    +-- PostgreSQL (Coder state)
    +-- Workspace containers
    |     +-- base-dev   (Claude Code + dev tools)
    |     +-- docker-dev (base-dev + DinD via Sysbox)
    +-- UFW (Tailscale-only firewall)
```

## Workspace Templates

Both templates share a common Terraform module (`templates/modules/workspace/`). Each template is a thin wrapper that toggles `enable_docker_in_docker`.

- **base-dev**: Claude Code, Node.js, ripgrep, fd, tree. Persistent home volume. Configurable CPU, memory, and web preview port via Coder UI.
- **docker-dev**: Everything above + full Docker daemon via Sysbox (no `--privileged`).

Templates are pushed with `make push-templates`, which dereferences the module symlinks for Coder's template archive format.

## Development

```bash
make help           # Show all targets
make validate       # Lint Terraform + Ansible (installs Galaxy deps)
make push-templates # Push templates to Coder
make verify         # Post-deploy health checks
```

Dry-run provisioning (validates env vars + Ansible syntax without SSH):

```bash
DRY_RUN=true SERVER_NAME=x SSH_PRIVATE_KEY=x \
  CODER_ADMIN_EMAIL=x CLAUDE_SETUP_TOKEN=x \
  bash scripts/provision.sh
```

## State Security

Terraform state contains secrets in plain text (SSH key, auth tokens). Protect it:

- `chmod 600 terraform.tfstate terraform.tfstate.backup` (done automatically)
- Never commit state files (already in `.gitignore`)
- For encrypted state, use a remote backend (see `terraform.tfvars.example` for examples)

## Re-provisioning

To re-run Ansible without replacing the server (e.g., after rotating API keys):

```bash
cd terraform
# Edit terraform.tfvars:
#   force_reprovision = "2026-04-03-rotated-keys"
tofu apply
```

## License

MIT
