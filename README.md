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
| Server | Hetzner CX33 (4 vCPU, 8GB RAM, Ubuntu 24.04) |

## Quick Start

```bash
# 1. Install Ansible dependencies
cd ansible && ansible-galaxy collection install -r requirements.yml && cd ..

# 2. Configure
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your secrets and email

# 3. Deploy
terraform init
terraform apply

# 4. Verify
cd .. && scripts/verify.sh coder-dev
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

## State Security

Terraform stores all resource attributes — including secrets — in `terraform.tfstate` as plain text. This file contains your SSH private key, Tailscale auth key, and API tokens.

**Recommendations:**
- `chmod 600 terraform.tfstate terraform.tfstate.backup`
- Never commit state files to version control (already in `.gitignore`)
- For encrypted state at rest, use a remote backend:
  - **Hetzner Object Storage** (S3-compatible — you already have the account)
  - **Terraform Cloud** free tier (encrypted, access-controlled)

See `terraform/terraform.tfvars.example` for backend configuration examples.

## Re-provisioning

To re-run Ansible without replacing the server (e.g., after rotating API keys):

```bash
cd terraform
# Edit terraform.tfvars:
#   force_reprovision = "2026-03-23-rotated-keys"
terraform apply
```

## Migration from Pulumi

If you previously deployed with Pulumi:

```bash
cd pulumi && pulumi destroy && cd ..
cd terraform && terraform init && terraform apply
```

This is a clean cutover — Terraform creates fresh resources. The Tailscale device persists if using the same hostname and auth key.

## License

MIT
