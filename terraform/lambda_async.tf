resource "aws_lambda_function_event_invoke_config" "processor_async" {
  function_name                = aws_lambda_function.processor.function_name
  maximum_retry_attempts       = 0
  maximum_event_age_in_seconds = 60
}