# CLAUDE.md — coder-infra

## What This Is
Self-hosted Coder + Claude Code on Hetzner VPS with Tailscale zero-trust networking.
OSS reference setup for solo developers who want persistent remote CC sessions with project isolation.

The key insight: Coder is an enterprise CDE platform whose isolated, persistent, Terraform-managed environments turned out to be exactly what AI coding agents need. This repo wires up the full stack -- fire-and-forget Tasks, workspace presets, MCP delegation, GitHub Issue-to-Task automation -- on a single EUR 15/month VPS.

## Stack
- **Terraform/OpenTofu** (HCL) — infrastructure provisioning (Hetzner Cloud)
- **Ansible** — server configuration (roles-based)
- **Tailscale** — zero-trust networking (no public ports)
- **Coder** (Community Edition) — workspace management
- **Sysbox** — Docker-in-Docker runtime for nested containers
- **Docker** — container runtime

## Architecture
```
Hetzner CX33 (4 vCPU, 8GB RAM, 100GB NVMe, Ubuntu 24.04)
  ├── Tailscale (networking, zero-trust access)
  ├── Docker + Sysbox (container runtimes)
  └── Coder (Docker Compose: coder + postgres + Caddy (TLS via Cloudflare or Tailscale Serve))
        ├── Workspace template: base-dev (Tasks + CC + code-server + dotfiles + git-clone + Node.js)
        └── Workspace template: docker-dev (base-dev + DinD via Sysbox)
```

## Reference: Coder docker-claude template
The official Coder template for Claude Code uses:
- `module "claude-code"` from `registry.coder.com/coder/claude-code/coder` (v4.9.1)
- Docker volumes for persistent /home/coder/
- `coder_agent` resource with metadata and display apps, plus `coder_script` resources instead of a monolithic `startup_script`
- `coder_app` for web preview ports
- `coder_ai_task` wired to the Claude Code module's task app output for the Tasks UI

## Repo Structure
```
coder-infra/
├── CLAUDE.md                         # This file
├── README.md                         # Setup guide
├── .github/workflows/coder-task.yml  # Create Coder tasks from labeled GitHub issues
├── .gitignore
├── terraform/
│   ├── versions.tf                   # Provider requirements (>= 1.9)
│   ├── variables.tf                  # All input variables with defaults
│   ├── main.tf                       # Ansible provisioner (terraform_data + local-exec)
│   ├── server.tf                     # Hetzner server + TLS deploy key + SSH key
│   ├── firewall.tf                   # No inbound, all outbound
│   ├── outputs.tf                    # server_ipv4, hostname, deploy_public_key
│   ├── user-data.sh.tftpl            # Cloud-init: Tailscale bootstrap
│   └── terraform.tfvars.example      # Config template (copy + customize)
├── ansible/
│   ├── ansible.cfg
│   ├── playbook.yml
│   ├── inventory/hosts.ini.example
│   ├── group_vars/all.yml
│   ├── requirements.yml
│   └── roles/
│       ├── system/tasks/main.yml     # Base packages, locale, swap
│       ├── ufw/tasks/main.yml        # Tailscale-only firewall
│       ├── docker/tasks/main.yml     # Docker engine + compose plugin
│       ├── sysbox/tasks/main.yml     # Sysbox runtime for DinD
│       ├── coder/                    # Coder via Docker Compose
│       │   ├── tasks/main.yml
│       │   ├── templates/docker-compose.yml.j2
│       │   ├── templates/Caddyfile.j2
│       │   └── templates/Dockerfile.caddy
│       └── mosh/tasks/main.yml       # Mosh server (optional)
├── Makefile                          # validate, lint, push-templates, verify
├── templates/                        # Coder workspace templates (Terraform)
│   ├── modules/workspace/            # Shared module (agent, params, container)
│   ├── base-dev/main.tf              # Thin wrapper (enable_docker_in_docker=false)
│   └── docker-dev/main.tf            # Thin wrapper (enable_docker_in_docker=true)
├── scripts/
│   ├── provision.sh                  # Ansible wrapper (called by Terraform)
│   └── verify.sh                     # Post-deploy health check
└── docs/
    └── setup.md                      # Detailed setup instructions
```

## Terraform Variables
```
hcloud_token (sensitive) — Hetzner API token
tailscale_auth_key (sensitive) — Tailscale auth key (reusable, ephemeral)
claude_setup_token (sensitive) — From `claude setup-token`
anthropic_api_key (sensitive, optional) — For CC API access (not needed with setup-token subscription auth)
server_name — hostname (default: "coder-dev")
server_type — Hetzner type (default: "cx33")
server_location — DC location (default: "fsn1")
coder_admin_email — admin user email
github_oauth_client_id (optional) — GitHub OAuth App client ID for external auth
github_oauth_client_secret (sensitive, optional) — GitHub OAuth App client secret
coder_domain (optional) — Custom Coder domain that enables wildcard subdomain routing
cloudflare_api_token (sensitive, optional) — Cloudflare DNS token for ACME DNS-01 when coder_domain is set
force_reprovision — change to re-run Ansible without server replacement
```

## Key Patterns
1. Cloud-init only does Tailscale bootstrap (with --force-reauth); Ansible does everything else
2. `scripts/provision.sh` wraps Ansible, receives secrets via env vars from Terraform. Supports `DRY_RUN=true`
3. `terraform_data` with `local-exec` provisioner triggers Ansible on server creation/replacement
4. Secrets passed via temp file to Ansible (not CLI args), cleaned up in trap
5. Cloud-init artifacts containing auth key are shredded (both self-cleanup in user-data and belt-and-suspenders in provision.sh)
6. Deploy keys generated by Terraform (`tls_private_key`, ED25519)
7. Local state (`terraform.tfstate`) by default — optional remote backend for encryption
8. `force_reprovision` variable for secret rotation without server replacement
9. Destroy-time provisioner runs `tailscale logout` (graceful fallback if SSH fails)
10. Workspace templates use shared module via symlinks; push with `make push-templates` (tar -cvh dereferences)
11. Workspace containers use chained `replace()`: first rewrites the external Coder access URL → `http://host.docker.internal:80`, then replaces remaining `localhost/127.0.0.1` references
12. DNS: `["100.100.100.100", "1.1.1.1"]` — MagicDNS for Tailscale names, Cloudflare for internet
13. Template uses `coder_script` resources instead of monolithic `startup_script` for per-step dashboard progress
14. Claude-code module v4.9.1 handles auth via `coder_env` (not Docker container env vars); uses `claude_code_oauth_token`
15. `coder_task` + `coder_ai_task` wire Claude Code into the Tasks UI for fire-and-forget background agents
16. Web preview app slug `"preview"` (magic slug) enables Tasks UI preview navbar
17. GitHub external auth is server-side config (`CODER_EXTERNAL_AUTH_0_*` env vars) + template-side `data.coder_external_auth`
18. `resources_monitoring` on `coder_agent` provides memory/disk threshold alerts without custom scripts
19. Caddy TLS is conditional: default installs use Tailscale Serve on `443`; setting `coder_domain` switches to Caddy on `443` with Cloudflare DNS-01 and `CODER_WILDCARD_ACCESS_URL`
20. Workspace templates use dynamic parameters (`form_type`, `order`, regex validation) instead of splitting simple UX differences into separate templates
21. `data "coder_workspace_preset"` defines Quick Task, Full Development, and Autonomous Agent with all parameter values explicit
22. `module "code_server"` adds a browser IDE app on a subdomain alongside Claude Code and Web Preview

## Coding Style
- Terraform: HCL with consistent formatting, one resource per logical file
- Ansible: YAML with comments, one task per logical action
- Terraform: official Coder provider patterns for workspace templates
- All config values should have sensible defaults where possible
- Template files (.j2, .tftpl) for anything that needs variable substitution
