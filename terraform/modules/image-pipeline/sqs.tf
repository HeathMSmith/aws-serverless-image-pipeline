resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${local.name_prefix}-dlq"
  message_retention_seconds = var.dlq_message_retention_seconds

  tags = local.common_tags
}