terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Claude Code"
  sensitive   = true
  default     = ""
}

variable "claude_setup_token" {
  type        = string
  description = "Claude Code setup token from `claude setup-token`"
  sensitive   = true
  default     = ""
}

provider "coder" {}
provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

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

  startup_script = <<-EOT
    #!/bin/bash
    set -e

    if ! command -v tmux &> /dev/null; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq \
        build-essential git curl wget vim tmux jq unzip \
        ripgrep fd-find htop tree python3 python3-pip
    fi

    if ! command -v node &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi

    # Sysbox provides the runtime; only the CLI is needed inside the container
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com | sh
    fi

    if [ -n "$${CLAUDE_SETUP_TOKEN:-}" ]; then
      npx --yes @anthropic-ai/claude-code@latest setup-token "$CLAUDE_SETUP_TOKEN" 2>/dev/null || true
      unset CLAUDE_SETUP_TOKEN
    fi
  EOT

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
  url          = "http://localhost:3000"
  icon         = "/icon/globe.svg"
  subdomain    = true
  share        = "owner"
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

# Sysbox runtime enables Docker-in-Docker without --privileged.
# The container runs its own Docker daemon natively — no socket mount needed.
resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = "codercom/enterprise-base:ubuntu"
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  dns      = ["1.1.1.1"]
  runtime  = "sysbox-runc"

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

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
}
