# Pub/Sub topic that receives firewall rule change events from the
# Cloud Logging sink and triggers the guardrail Cloud Function.
resource "google_pubsub_topic" "firewall_changes" {
  name    = "firewall-rule-change-events"
  project = var.project_id

  depends_on = [google_project_service.required]
}
