# Dedicated, least-privilege service account for the guardrail Cloud Function.
resource "google_service_account" "guardrail" {
  project      = var.project_id
  account_id   = "fw-compliance-guardrail"
  display_name = "Real-Time Firewall Compliance Guardrail"
}

# Custom role: read and remediate VPC firewall rules — nothing else.
resource "google_project_iam_custom_role" "firewall_remediator" {
  project     = var.project_id
  role_id     = "firewallComplianceRemediator"
  title       = "Firewall Compliance Remediator"
  description = "Least-privilege role for the real-time firewall guardrail: read and remediate VPC firewall rules"

  permissions = [
    "compute.firewalls.get",
    "compute.firewalls.list",
    "compute.firewalls.update",
    "compute.firewalls.delete",
  ]
}

resource "google_project_iam_member" "guardrail_remediator" {
  project = var.project_id
  role    = google_project_iam_custom_role.firewall_remediator.id
  member  = "serviceAccount:${google_service_account.guardrail.email}"
}

# Allow the function to write its own structured logs.
resource "google_project_iam_member" "guardrail_logwriter" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.guardrail.email}"
}

# Allow the service account to receive Eventarc/Pub/Sub-triggered invocations.
resource "google_project_iam_member" "guardrail_eventarc" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.guardrail.email}"
}

resource "google_project_iam_member" "guardrail_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.guardrail.email}"
}
