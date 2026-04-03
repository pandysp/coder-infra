variable "hcloud_token" {
  type        = string
  description = "Hetzner Cloud API token"
  sensitive   = true
}

variable "server_name" {
  type        = string
  description = "Server hostname and Tailscale device name"
  default     = "coder-dev"
}

variable "server_type" {
  type        = string
  description = "Hetzner server type"
  default     = "cx33"
}

variable "server_location" {
  type        = string
  description = "Hetzner datacenter location"
  default     = "fsn1"
}

variable "tailscale_auth_key" {
  type        = string
  description = "Tailscale auth key (reusable, ephemeral recommended)"
  sensitive   = true
}

variable "coder_admin_email" {
  type        = string
  description = "Email for the initial Coder admin account"
}

variable "claude_setup_token" {
  type        = string
  description = "Claude Code setup token from `claude setup-token`"
  sensitive   = true
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key for Claude Code in workspaces"
  sensitive   = true
}

variable "github_oauth_client_id" {
  type        = string
  description = "GitHub OAuth App client ID for Coder external auth (optional)"
  default     = ""
}

variable "github_oauth_client_secret" {
  type        = string
  description = "GitHub OAuth App client secret for Coder external auth (optional)"
  sensitive   = true
  default     = ""
}

variable "force_reprovision" {
  type        = string
  description = "Change this value to re-run Ansible without replacing the server. Useful after rotating secrets."
  default     = ""
}
