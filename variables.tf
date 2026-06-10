variable "project_id" {
  description = "GCP project ID where the guardrail will be deployed"
  type        = string
}

variable "region" {
  description = "GCP region for the Cloud Function, Pub/Sub topic, and source bucket"
  type        = string
  default     = "us-central1"
}

variable "source_bucket_name" {
  description = "Globally unique name for the GCS bucket that stores the Cloud Function source archive"
  type        = string
}

variable "blocked_ports" {
  description = "TCP/UDP ports that must not be exposed to the public internet (0.0.0.0/0 or ::/0) by any VPC firewall rule"
  type        = list(number)
  default     = [21, 22, 23, 3389]
}

variable "function_timeout" {
  description = "Cloud Function timeout in seconds"
  type        = number
  default     = 60
}

variable "function_memory" {
  description = "Cloud Function memory allocation"
  type        = string
  default     = "256M"
}
