terraform {
  required_version = ">= 1.12"

  cloud {
    # Replace with your own HCP Terraform organization before `terraform init`.
    organization = "change-to-your-org"

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
      version = "~> 2.7"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
