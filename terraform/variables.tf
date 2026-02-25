variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Base name used for tagging and resource names"
  type        = string
  default     = "aws-serverless-image-pipeline"
}

variable "dest_prefix_256" {
  description = "Prefix for 256px thumbnails"
  type        = string
  default     = "processed/thumb_256/"
}

variable "dest_prefix_1024" {
  description = "Prefix for 1024px thumbnails"
  type        = string
  default     = "processed/thumb_1024/"
}

variable "size_256" {
  description = "Max dimension for 256 thumbnails"
  type        = number
  default     = 256
}

variable "size_1024" {
  description = "Max dimension for 1024 thumbnails"
  type        = number
  default     = 1024
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project = "aws-serverless-image-pipeline"
    Owner   = "HeathMSmith"
  }
}
