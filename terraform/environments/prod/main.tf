module "image_pipeline" {
  source = "../../modules/image-pipeline"

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}
