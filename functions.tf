# Cloud Function (2nd gen) — evaluates and remediates non-compliant
# VPC firewall rules, triggered in real time by the Pub/Sub topic.
resource "google_cloudfunctions2_function" "guardrail" {
  project  = var.project_id
  name     = "fw-realtime-compliance-guardrail"
  location = var.region

  build_config {
    runtime     = "python312"
    entry_point = "fw_guardrail"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.guardrail_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 5
    available_memory      = var.function_memory
    timeout_seconds       = var.function_timeout
    service_account_email = google_service_account.guardrail.email

    environment_variables = {
      BLOCKED_PORTS = join(",", var.blocked_ports)
      GCP_PROJECT   = var.project_id
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.firewall_changes.id
    service_account_email = google_service_account.guardrail.email
    retry_policy          = "RETRY_POLICY_RETRY"
  }

  depends_on = [google_project_service.required]
}
