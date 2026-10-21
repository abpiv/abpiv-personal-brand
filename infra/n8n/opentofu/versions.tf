terraform {
  required_version = ">= 1.8.0"

  backend "gcs" {
    bucket = "abpiv-personal-brand-opentofu-state"
    prefix = "infra/n8n"
  }

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.8.2, < 6.0.0"
    }

    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0, < 7.0.0"
    }

  }
}
