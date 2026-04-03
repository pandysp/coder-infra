terraform {
  required_version = ">= 1.9"

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

module "workspace" {
  source                  = "./modules/workspace"
  enable_docker_in_docker = false
  anthropic_api_key       = var.anthropic_api_key
  claude_setup_token      = var.claude_setup_token
}
