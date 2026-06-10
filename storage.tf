# GCS bucket that stores the Cloud Function source archive.
resource "google_storage_bucket" "function_source" {
  name                        = var.source_bucket_name
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  public_access_prevention = "enforced"

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket_object" "guardrail_source" {
  name   = "function-source/guardrail-${data.archive_file.guardrail.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.guardrail.output_path
}
