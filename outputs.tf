output "function_name" {
  description = "Name of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.guardrail.name
}

output "function_uri" {
  description = "URI of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.guardrail.url
}

output "service_account_email" {
  description = "Email of the guardrail's dedicated service account"
  value       = google_service_account.guardrail.email
}

output "pubsub_topic" {
  description = "Pub/Sub topic that receives firewall rule change events"
  value       = google_pubsub_topic.firewall_changes.id
}

output "log_sink_writer_identity" {
  description = "Service account used by the Cloud Logging sink to publish events"
  value       = google_logging_project_sink.firewall_changes.writer_identity
}
