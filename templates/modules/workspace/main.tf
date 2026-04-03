terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --- Workspace parameters (shown in Coder UI at workspace creation) ----------

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the workspace container"
  type         = "number"
  default      = "2"
  mutable      = true
  icon         = "/icon/memory.svg"

  validation {
    min = 1
    max = 4
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Memory limit for the workspace container"
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "/icon/memory.svg"

  validation {
    min = 1
    max = 8
  }
}

data "coder_parameter" "web_preview_port" {
  name         = "web_preview_port"
  display_name = "Web Preview Port"
  description  = "Port for the web preview app"
  type         = "number"
  default      = "3000"
  mutable      = true
  icon         = "/icon/globe.svg"

  validation {
    min = 1024
    max = 65535
  }
}

# --- Agent -------------------------------------------------------------------

locals {
  base_startup = <<-EOT
    #!/bin/bash
    set -e

    if ! command -v rg &> /dev/null; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq ripgrep fd-find tree
    fi

    if ! command -v node &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
  EOT

  dind_startup = <<-EOT
    # Sysbox provides the runtime; only the CLI is needed inside the container
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com | sh
    fi
  EOT

  claude_startup = <<-EOT
    if [ -n "$${CLAUDE_SETUP_TOKEN:-}" ]; then
      npx --yes @anthropic-ai/claude-code@latest setup-token "$CLAUDE_SETUP_TOKEN" 2>/dev/null || true
      unset CLAUDE_SETUP_TOKEN
    fi
  EOT

  startup_script = join("\n", compact([
    local.base_startup,
    var.enable_docker_in_docker ? local.dind_startup : "",
    local.claude_startup,
  ]))
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"
  dir  = "/home/coder"

  display_apps {
    vscode                 = true
    web_terminal           = true
    ssh_helper             = true
    port_forwarding_helper = true
  }

  startup_script = local.startup_script

  metadata {
    display_name = "CPU Usage"
    key          = "cpu"
    script       = "top -bn1 | grep 'Cpu(s)' | awk '{print $2\"%\"}'"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "mem"
    script       = "free -m | awk 'NR==2{printf \"%s/%sMB (%.0f%%)\", $3,$2,$3*100/$2}'"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk"
    script       = "df -h /home/coder | awk 'NR==2{print $5}'"
    interval     = 600
    timeout      = 1
  }
}

module "claude_code" {
  source   = "registry.coder.com/coder/claude-code/coder"
  version  = "4.8.1"
  agent_id = coder_agent.main.id
  workdir  = "/home/coder"
}

resource "coder_app" "web_preview" {
  agent_id     = coder_agent.main.id
  slug         = "web-preview"
  display_name = "Web Preview"
  url          = "http://localhost:${data.coder_parameter.web_preview_port.value}"
  icon         = "/icon/globe.svg"
  subdomain    = true
  share        = "owner"
}

# --- Container ---------------------------------------------------------------

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = "codercom/enterprise-base:ubuntu"
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  dns      = ["100.100.100.100", "1.1.1.1"]
  runtime  = var.enable_docker_in_docker ? "sysbox-runc" : null

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "ANTHROPIC_API_KEY=${var.anthropic_api_key}",
    "CLAUDE_SETUP_TOKEN=${var.claude_setup_token}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder/"
    volume_name    = docker_volume.home.name
    read_only      = false
  }

  # Workspace containers can't reach the Tailscale FQDN directly (they're not
  # on the tailnet). Replace the access URL with the Caddy proxy reachable via
  # the Docker bridge, and fall back to replacing localhost/127.0.0.1 as well.
  entrypoint = ["sh", "-c", replace(
    replace(coder_agent.main.init_script, data.coder_workspace.me.access_url, "http://host.docker.internal:80"),
    "/localhost|127\\.0\\.0\\.1/",
    "host.docker.internal"
  )]
}
