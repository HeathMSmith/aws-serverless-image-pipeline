output "uploads_bucket" {
  description = "Name of the S3 bucket used for incoming images."
  value       = module.image_pipeline.uploads_bucket
}

output "processed_bucket" {
  description = "Name of the S3 bucket used for processed images."
  value       = module.image_pipeline.processed_bucket
}

output "lambda_name" {
  description = "Name of the image-processing Lambda function."
  value       = module.image_pipeline.lambda_name
}

output "lambda_log_group_name" {
  description = "CloudWatch log group for the Lambda function."
  value       = module.image_pipeline.lambda_log_group_name
}

output "lambda_error_alarm_name" {
  description = "CloudWatch alarm for Lambda errors."
  value       = module.image_pipeline.lambda_error_alarm_name
}

output "lambda_duration_alarm_name" {
  description = "CloudWatch alarm for Lambda duration."
  value       = module.image_pipeline.lambda_duration_alarm_name
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for the image pipeline."
  value       = module.image_pipeline.cloudwatch_dashboard_name
}

output "lambda_dlq_name" {
  description = "Name of the Lambda dead-letter queue."
  value       = module.image_pipeline.lambda_dlq_name
}

output "lambda_dlq_url" {
  description = "URL of the Lambda dead-letter queue."
  value       = module.image_pipeline.lambda_dlq_url
}

output "lambda_dlq_arn" {
  description = "ARN of the Lambda dead-letter queue."
  value       = module.image_pipeline.lambda_dlq_arn
}
