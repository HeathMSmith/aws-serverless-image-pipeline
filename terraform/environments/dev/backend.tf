terraform {
  backend "s3" {
    bucket         = "hms-terraform-state-portfolio"
    key            = "serverless-image-pipeline/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "hms-terraform-locks"
    encrypt        = true
  }
}
