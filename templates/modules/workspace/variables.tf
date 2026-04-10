variable "workspace_image" {
  type        = string
  description = "Docker image for the workspace container"
  default     = "codercom/enterprise-base@sha256:5abfb835c2421f89d5a30fe42bfa369de91222f3e13145172448d9fd173676de"
}

variable "enable_docker_in_docker" {
  type        = bool
  description = "Enable Docker-in-Docker via Sysbox runtime"
  default     = true
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

variable "enable_tailscale" {
  type        = bool
  description = "Install Tailscale and join tailnet on startup"
  default     = false
}

variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale ephemeral auth key for workspace to join tailnet"
  sensitive   = true
  default     = ""
}

variable "enable_infra_tools" {
  type        = bool
  description = "Install infrastructure tools (OpenTofu, Ansible, hcloud CLI)"
  default     = false
}
