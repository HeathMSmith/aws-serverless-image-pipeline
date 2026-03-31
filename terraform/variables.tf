#############################
# Core Project Settings
#############################

variable "project_name" {
  type        = string
  description = "Name of the project"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev or prod)"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment must be 'dev' or 'prod'."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy into"
  default     = "us-east-1"
}

#############################
# S3 / Pipeline Configuration
#############################

variable "source_prefix" {
  type        = string
  description = "Prefix for incoming images"
  default     = "incoming/"

  validation {
    condition     = can(regex(".*/$", var.source_prefix))
    error_message = "source_prefix must end with a trailing slash (/)."
  }
}

variable "dest_prefix_256" {
  type        = string
  description = "Destination prefix for 256px images"
  default     = "processed/thumb_256/"

  validation {
    condition     = can(regex(".*/$", var.dest_prefix_256))
    error_message = "dest_prefix_256 must end with a trailing slash (/)."
  }
}

variable "dest_prefix_1024" {
  type        = string
  description = "Destination prefix for 1024px images"
  default     = "processed/thumb_1024/"

  validation {
    condition     = can(regex(".*/$", var.dest_prefix_1024))
    error_message = "dest_prefix_1024 must end with a trailing slash (/)."
  }
}

#############################
# Image Processing Settings
#############################

variable "size_256" {
  type        = number
  description = "Max dimension for small thumbnail"
  default     = 256
}

variable "size_1024" {
  type        = number
  description = "Max dimension for large image"
  default     = 1024
}

variable "max_file_size_mb" {
  type        = number
  description = "Maximum allowed file size in MB"
  default     = 10

  validation {
    condition     = var.max_file_size_mb > 0 && var.max_file_size_mb <= 50
    error_message = "max_file_size_mb must be between 1 and 50."
  }
}

variable "allowed_extensions" {
  type        = string
  description = "Comma-separated list of allowed file extensions"
  default     = ".jpg,.jpeg,.png,.gif,.webp"
}

#############################
# Lambda Configuration
#############################

variable "lambda_timeout" {
  type        = number
  description = "Lambda execution timeout in seconds"
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 5 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 5 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  type        = number
  description = "Lambda memory size in MB"
  default     = 512

  validation {
    condition     = contains([128, 256, 512, 1024, 2048, 3008], var.lambda_memory_size)
    error_message = "Lambda memory must be a valid AWS value (128–3008 MB)."
  }
}

variable "log_level" {
  type        = string
  description = "Logging level for Lambda"
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARNING", "ERROR"], var.log_level)
    error_message = "log_level must be one of DEBUG, INFO, WARNING, ERROR."
  }
}
variable "log_retention_in_days" {
  type        = number
  description = "CloudWatch log retention for Lambda"
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch retention value."
  }
}

variable "lambda_duration_alarm_threshold_ms" {
  type        = number
  description = "Average Lambda duration threshold in milliseconds for alarm"
  default     = 20000
}

variable "alarm_topic_arn" {
  type        = string
  description = "Optional SNS topic ARN for CloudWatch alarm notifications"
  default     = ""
}
variable "dlq_message_retention_seconds" {
  type        = number
  description = "How long failed events stay in the DLQ"
  default     = 1209600 # 14 days

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600."
  }
}