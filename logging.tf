# Cloud Logging sink that captures every VPC firewall rule create/update
# operation from Cloud Audit Logs (Admin Activity, always-on) and routes
# it to the Pub/Sub topic in real time.
resource "google_logging_project_sink" "firewall_changes" {
  name        = "firewall-rule-change-sink"
  project     = var.project_id
  destination = "pubsub.googleapis.com/${google_pubsub_topic.firewall_changes.id}"

  filter = <<-EOT
    resource.type="gce_firewall_rule"
    AND protoPayload.methodName=("v1.compute.firewalls.insert" OR "v1.compute.firewalls.patch")
  EOT

  # Cloud Logging creates a dedicated service account for this sink — grant
  # it just enough access to publish to the destination topic.
  unique_writer_identity = true
}

# Allow the log sink's dedicated service account to publish to the Pub/Sub topic.
resource "google_pubsub_topic_iam_member" "sink_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.firewall_changes.name
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.firewall_changes.writer_identity
}
