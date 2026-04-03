terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13.0, < 3.0.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_task" "me" {}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "CPU scheduling weight (relative to other containers, not dedicated cores)"
  type         = "number"
  default      = "2"
  mutable      = true
  form_type    = "slider"
  order        = 1
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
  form_type    = "slider"
  order        = 2
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
  order        = 6
  icon         = "/icon/globe.svg"

  validation {
    min = 1024
    max = 65535
  }
}

data "coder_parameter" "repo_url" {
  name         = "repo_url"
  display_name = "Repository URL"
  description  = "Git repository to clone into the workspace (leave empty to skip)"
  type         = "string"
  default      = ""
  mutable      = false
  order        = 3
  icon         = "/icon/git.svg"

  validation {
    regex = "^(|https://.+|git@.+)$"
    error = "Repository URL must be empty or start with https:// or git@"
  }
}

data "coder_parameter" "repo_branch" {
  name         = "repo_branch"
  display_name = "Repository Branch"
  description  = "Git branch to clone when a repository URL is provided"
  type         = "string"
  default      = ""
  mutable      = true
  order        = 4
  icon         = "/icon/git.svg"
}

data "coder_parameter" "claude_permission" {
  name         = "claude_permission"
  display_name = "Claude Permission Mode"
  description  = "Permission level for Claude Code"
  type         = "string"
  default      = "bypassPermissions"
  mutable      = true
  form_type    = "radio"
  order        = 5
  icon         = "/icon/coder.svg"

  option {
    name  = "Bypass Permissions (full autonomy)"
    value = "bypassPermissions"
  }
  option {
    name  = "Accept Edits (auto-approve file changes)"
    value = "acceptEdits"
  }
  option {
    name  = "Default (ask for approval)"
    value = "default"
  }
}

data "coder_workspace_preset" "quick_task" {
  name        = "Quick Task"
  description = "Low-resource default for fast one-off work."
  default     = true
  parameters = {
    (data.coder_parameter.cpu.name)               = "1"
    (data.coder_parameter.memory.name)            = "2"
    (data.coder_parameter.web_preview_port.name)  = "3000"
    (data.coder_parameter.repo_url.name)          = ""
    (data.coder_parameter.repo_branch.name)       = ""
    (data.coder_parameter.claude_permission.name) = "bypassPermissions"
  }
}

data "coder_workspace_preset" "full_development" {
  name        = "Full Development"
  description = "Higher-resource preset for active coding sessions."
  parameters = {
    (data.coder_parameter.cpu.name)               = "3"
    (data.coder_parameter.memory.name)            = "6"
    (data.coder_parameter.web_preview_port.name)  = "3000"
    (data.coder_parameter.repo_url.name)          = ""
    (data.coder_parameter.repo_branch.name)       = ""
    (data.coder_parameter.claude_permission.name) = "acceptEdits"
  }
}

data "coder_workspace_preset" "autonomous_agent" {
  name        = "Autonomous Agent"
  description = "Balanced preset for longer autonomous Claude runs."
  parameters = {
    (data.coder_parameter.cpu.name)               = "2"
    (data.coder_parameter.memory.name)            = "4"
    (data.coder_parameter.web_preview_port.name)  = "3000"
    (data.coder_parameter.repo_url.name)          = ""
    (data.coder_parameter.repo_branch.name)       = ""
    (data.coder_parameter.claude_permission.name) = "bypassPermissions"
  }
}

# Enables "Connect GitHub" button in the Coder UI for OAuth-based git operations.
# Git auth is handled automatically by the Coder agent via GIT_ASKPASS.
# The access_token is passed as GITHUB_TOKEN for non-git tools (gh CLI).
# Requires CODER_EXTERNAL_AUTH_0_ID="github" on the Coder server.
data "coder_external_auth" "github" {
  id       = "github"
  optional = true
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

  resources_monitoring {
    memory {
      enabled   = true
      threshold = 80
    }
    volume {
      enabled   = true
      threshold = 90
      path      = "/home/coder"
    }
  }

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

resource "coder_script" "system_setup" {
  agent_id           = coder_agent.main.id
  display_name       = "System Setup"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 300
  script             = <<-EOT
    #!/bin/bash
    set -eo pipefail
    if ! command -v rg &> /dev/null; then
      sudo apt-get update -qq
      sudo apt-get install -y -qq ripgrep fd-find tree
    fi
    if ! command -v gh &> /dev/null; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      ARCH="$(dpkg --print-architecture)"
      echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update -qq
      sudo apt-get install -y -qq gh
    fi
    if ! command -v node &> /dev/null; then
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
  EOT
}

resource "coder_script" "docker_cli" {
  count              = var.enable_docker_in_docker ? 1 : 0
  agent_id           = coder_agent.main.id
  display_name       = "Docker CLI"
  icon               = "/icon/docker.svg"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 120
  script             = <<-EOT
    #!/bin/bash
    set -eo pipefail
    # Sysbox provides the runtime; install CLI + daemon inside the container
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com | sh
    fi
    # Start dockerd if not already running (no systemd in Sysbox containers)
    if ! docker info &>/dev/null; then
      sudo dockerd &>/tmp/dockerd.log &
      for i in $(seq 1 30); do
        docker info &>/dev/null && break
        sleep 1
      done
    fi
  EOT
}

module "claude_code" {
  source                       = "registry.coder.com/coder/claude-code/coder"
  version                      = "4.9.1"
  agent_id                     = coder_agent.main.id
  workdir                      = "/home/coder"
  claude_code_oauth_token      = var.claude_setup_token
  claude_api_key               = var.anthropic_api_key
  ai_prompt                    = data.coder_task.me.prompt
  permission_mode              = data.coder_parameter.claude_permission.value
  dangerously_skip_permissions = data.coder_parameter.claude_permission.value == "bypassPermissions"
  cli_app                      = true
  disable_autoupdater          = true
  system_prompt                = "You are running in a Coder workspace. Tools available: rg, fd, tree, node, npm, git. If a repo was cloned, it is in /home/coder/."
  # Pre-seed ~/.claude.json so the bypass-permissions consent TUI is skipped.
  # The module's install.sh only writes this in standalone mode, not tasks mode.
  pre_install_script = <<-EOT
    if [ -f ~/.claude.json ]; then
      jq '.bypassPermissionsModeAccepted = true | .hasCompletedOnboarding = true | .hasAcknowledgedCostThreshold = true' ~/.claude.json > ~/.claude.json.tmp && mv ~/.claude.json.tmp ~/.claude.json
    else
      echo '{"bypassPermissionsModeAccepted":true,"hasCompletedOnboarding":true,"hasAcknowledgedCostThreshold":true}' > ~/.claude.json
    fi
  EOT
}

module "dotfiles" {
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
}

module "code_server" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/code-server/coder"
  version        = "1.4.4"
  agent_id       = coder_agent.main.id
  folder         = "/home/coder"
  install_prefix = "/home/coder/.code-server"
  use_cached     = true
  subdomain      = true
  order          = 1
}

module "git_clone" {
  count       = data.coder_parameter.repo_url.value != "" ? 1 : 0
  source      = "registry.coder.com/coder/git-clone/coder"
  version     = "1.2.3"
  agent_id    = coder_agent.main.id
  url         = data.coder_parameter.repo_url.value
  branch_name = data.coder_parameter.repo_branch.value
}

resource "coder_ai_task" "claude" {
  count  = data.coder_workspace.me.start_count
  app_id = module.claude_code.task_app_id
}

resource "coder_app" "preview" {
  agent_id     = coder_agent.main.id
  slug         = "preview"
  display_name = "Web Preview"
  url          = "http://localhost:${data.coder_parameter.web_preview_port.value}"
  icon         = "/icon/globe.svg"
  subdomain    = true
  share        = "owner"

  healthcheck {
    url       = "http://localhost:${data.coder_parameter.web_preview_port.value}"
    interval  = 15
    threshold = 3
  }
}

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = "codercom/enterprise-base@sha256:5abfb835c2421f89d5a30fe42bfa369de91222f3e13145172448d9fd173676de"
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  dns      = ["100.100.100.100", "1.1.1.1"]
  runtime  = var.enable_docker_in_docker ? "sysbox-runc" : null

  stop_timeout          = 300
  destroy_grace_seconds = 300

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "GITHUB_TOKEN=${data.coder_external_auth.github.access_token}",
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
