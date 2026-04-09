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
        └── Workspace template: dev (Tasks + CC + code-server + dotfiles + git-clone + Node.js + DinD via Sysbox)
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
│       ├── mosh/tasks/main.yml       # Mosh server (optional)
│       └── monitoring/               # Observability stack via Docker Compose
│           ├── tasks/main.yml
│           ├── templates/            # Jinja2 config templates
│           ├── alerts/               # Prometheus alert rule templates
│           └── files/dashboards/     # Grafana dashboard JSON files
├── Makefile                          # validate, lint, push-templates, verify
├── templates/                        # Coder workspace templates (Terraform)
│   ├── modules/workspace/            # Shared module (agent, params, container)
│   │   ├── main.tf
│   │   └── variables.tf
│   └── examples/                     # Reference templates (copy to get started)
│       └── base-dev/
│           ├── main.tf               # Thin wrapper: module "workspace" { ... }
│           └── modules -> ../../modules
# Active templates live at templates/<name>/ — gitignored, copy from examples/
# Run: make new-template NAME=dev
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
grafana_admin_password (sensitive, optional) — Grafana admin password (defaults to empty → set post-deploy)
alertmanager_webhook_url (optional) — Webhook URL for Alertmanager critical alert notifications
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
10. Workspace templates: reference templates live in `templates/examples/`; active templates in `templates/<name>/` are gitignored. Use `make new-template NAME=dev` to copy an example, then `make push-dev` to push. Push copies modules into a temp dir (no symlink needed for push; symlink is for local `tofu validate/plan`)
11. Workspace containers use chained `replace()`: first rewrites the external Coder access URL → `http://host.docker.internal:80`, then replaces remaining `localhost/127.0.0.1` references
12. DNS: `["100.100.100.100", "1.1.1.1"]` — MagicDNS for Tailscale names, Cloudflare for internet
13. Template uses `coder_script` resources instead of monolithic `startup_script` for per-step dashboard progress
14. Claude-code module v4.9.1 handles auth via `coder_env` (not Docker container env vars); uses `claude_code_oauth_token`
15. `coder_task` + `coder_ai_task` wire Claude Code into the Tasks UI for fire-and-forget background agents. Workspace names are limited to 32 characters
16. Web preview app slug `"preview"` (magic slug) enables Tasks UI preview navbar
17. GitHub external auth is server-side config (`CODER_EXTERNAL_AUTH_0_*` env vars) + template-side `data.coder_external_auth`
18. `resources_monitoring` on `coder_agent` provides memory/disk threshold alerts without custom scripts
19. Caddy TLS is conditional: default installs use Tailscale Serve on `443`; setting `coder_domain` switches to Caddy on `443` with Cloudflare DNS-01 and `CODER_WILDCARD_ACCESS_URL`. When `coder_domain` is set, Caddy gets a Docker network alias matching the domain so the Coder container can resolve the access URL to Caddy directly (required for the deployment health check; without it, DNS resolves to the Tailscale IP which is unreachable from Docker). Tailscale Serve mode now applies the same pattern with a network alias for the Tailscale FQDN plus `tls internal`, and Coder trusts Caddy's internal CA via `SSL_CERT_DIR`
20. Workspace templates use dynamic parameters (`form_type`, `order`, regex validation) instead of splitting simple UX differences into separate templates
21. `data "coder_workspace_preset"` defines Quick Task, Full Development, and Autonomous Agent with all parameter values explicit
22. `module "code_server"` adds a browser IDE app on a subdomain alongside Claude Code and Web Preview

## Monitoring

### Architecture
The observability stack is a second independent Docker Compose project at `/opt/monitoring/`. It does **not** share a Docker network with the Coder stack. Instead, monitoring services reach Coder and Postgres via `host.docker.internal` (host-gateway), and node_exporter uses `network_mode: host`. This avoids cross-stack ordering dependencies.

Services and memory limits (864MB total, 1.4GB with Loki):
- **Prometheus** (384M) — scrapes Coder (`:2112`), node (`:9100`), Postgres exporter (`:9187`), cAdvisor (`:8080`)
- **Grafana** (192M) — dashboards and alerting UI, port `127.0.0.1:3000`
- **Alertmanager** (64M) — alert routing, port `127.0.0.1:9093`
- **node_exporter** (64M) — host CPU, memory, disk, network metrics
- **postgres_exporter** (64M) — PostgreSQL metrics via `host.docker.internal:5432`
- **cAdvisor** (96M) — Docker container resource metrics
- **Loki** (384M, optional) — log aggregation, disabled by default
- **promtail** (128M, optional) — log shipping to Loki

All ports bound to `127.0.0.1` — access via Tailscale SSH tunnel or Tailscale Serve.

### Accessing Grafana
Grafana is exposed via Tailscale Serve on port 8443:
`https://<server-name>.<tailnet>.ts.net:8443`
(admin / password set in `grafana_admin_password`)

Monitoring access is independent of Coder's Caddy proxy — if Coder is down, Grafana still works as long as Tailscale is up.

### Key Dashboards
- **Coder Overview** (`coder-overview`) — API health, workspace builds, provisioner queue, agent connectivity
- **Node Exporter Full** — Host CPU, memory, disk I/O, network, filesystem
- **PostgreSQL** — Connections, query duration, cache hit ratio, replication lag

### Alert Rules
- `CoderWorkspaceBuildFailures` — >5 failed builds in 10 minutes (warning)
- `CoderAPIErrorRate` — 5xx rate >5% for 5 minutes (warning)
- `CoderProvisionerQueueBacklog` — jobs waiting >60s (warning)
- `CoderAgentDisconnected` — agent offline >5 minutes (critical)
- `HostHighMemory` — memory >85% for 5 minutes (critical — tight on 8GB box)
- `HostHighCPU` — CPU >85% for 5 minutes (warning)
- `HostDiskSpaceLow` — disk >80% on / (warning)
- `HostSwapHigh` — swap >50% (warning — early memory pressure indicator)
- `PostgresDown` — pg_up == 0 for 1 minute (critical)
- `PostgresConnectionsHigh` — connections >80% of max_connections (warning)
- `PostgresNotificationQueueFilling` — LISTEN/NOTIFY queue >50% (warning — Coder uses this heavily)

### Enabling Loki
Set `monitoring_loki_enabled: true` in `ansible/group_vars/all.yml`, then re-run Ansible.
Loki adds 512MB memory usage (Loki 384M + promtail 128M). Retention defaults to 7 days (`168h`).

### Day-2 Operations
```bash
# Check monitoring stack status
cd /opt/monitoring && docker compose ps

# View logs for a specific service
docker compose -f /opt/monitoring/docker-compose.yml logs -f prometheus

# Check disk usage (Prometheus TSDB + Grafana data)
du -sh /opt/monitoring/
docker system df

# Reload Prometheus config without restart (requires --web.enable-lifecycle)
curl -X POST http://localhost:9090/-/reload

# Restart entire monitoring stack
cd /opt/monitoring && docker compose restart

# Disable monitoring (tears down stack, keeps data volumes)
# Set monitoring_enabled: false in group_vars/all.yml, then re-run Ansible
```

## Coding Style
- Terraform: HCL with consistent formatting, one resource per logical file
- Ansible: YAML with comments, one task per logical action
- Terraform: official Coder provider patterns for workspace templates
- All config values should have sensible defaults where possible
- Template files (.j2, .tftpl) for anything that needs variable substitution
