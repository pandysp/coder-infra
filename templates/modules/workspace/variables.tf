variable "enable_docker_in_docker" {
  type        = bool
  description = "Enable Docker-in-Docker via Sysbox runtime"
  default     = false
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
