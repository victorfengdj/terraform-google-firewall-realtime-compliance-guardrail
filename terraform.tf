terraform {
  required_version = ">= 1.2"

  cloud {
    organization = "wgf"

    workspaces {
      name = "terraform-google-firewall-realtime-compliance-guardrail"
    }
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
