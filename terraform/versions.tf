terraform {
  required_version = ">= 1.9"

  backend "s3" {
    bucket = "iac-state"
    key    = "coder-infra/terraform.tfstate"

    # Cloudflare R2 (S3-compatible)
    endpoints                    = { s3 = "https://720edb27683de16ac4382f8e75665aa7.r2.cloudflarestorage.com" }
    region                       = "us-east-1"  # dummy — R2 ignores region, but OpenTofu requires one
    skip_credentials_validation  = true
    skip_metadata_api_check      = true
    skip_requesting_account_id   = true
    skip_s3_checksum             = true
  }

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
