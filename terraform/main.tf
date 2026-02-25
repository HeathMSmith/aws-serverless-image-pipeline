resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix = lower(random_id.suffix.hex)
  name   = "${var.project_name}-${local.suffix}"

  uploads_bucket   = "${local.name}-uploads"
  processed_bucket = "${local.name}-processed"
}
