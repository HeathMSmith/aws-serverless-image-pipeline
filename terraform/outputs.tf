output "uploads_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "lambda_name" {
  value = aws_lambda_function.processor.function_name
}
output "lambda_log_group_name" {
  description = "CloudWatch log group for the Lambda function"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "lambda_error_alarm_name" {
  description = "CloudWatch alarm name for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "lambda_duration_alarm_name" {
  description = "CloudWatch alarm name for Lambda duration"
  value       = aws_cloudwatch_metric_alarm.lambda_duration.alarm_name
}

output "cloudwatch_dashboard_name" {
  description = "CloudWatch dashboard for the image pipeline"
  value       = aws_cloudwatch_dashboard.pipeline.dashboard_name
}
output "lambda_dlq_name" {
  description = "Name of the Lambda dead-letter queue"
  value       = aws_sqs_queue.lambda_dlq.name
}

output "lambda_dlq_url" {
  description = "URL of the Lambda dead-letter queue"
  value       = aws_sqs_queue.lambda_dlq.url
}

output "lambda_dlq_arn" {
  description = "ARN of the Lambda dead-letter queue"
  value       = aws_sqs_queue.lambda_dlq.arn
}
