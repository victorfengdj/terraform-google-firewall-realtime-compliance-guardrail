# Zip the Cloud Function source code for upload to GCS.
data "archive_file" "guardrail" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
  excludes    = ["__pycache__"]
}
