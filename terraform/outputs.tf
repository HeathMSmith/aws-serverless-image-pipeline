output "uploads_bucket" {
  value = aws_s3_bucket.uploads.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "lambda_name" {
  value = aws_lambda_function.processor.function_name
}
