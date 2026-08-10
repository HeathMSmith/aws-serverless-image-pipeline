resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  suffix      = lower(random_id.suffix.hex)
  name_prefix = "${var.project_name}-${var.environment}"

  uploads_bucket   = "${local.name_prefix}-${local.suffix}-uploads"
  processed_bucket = "${local.name_prefix}-${local.suffix}-processed"
}
