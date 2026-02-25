data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/lambda.zip"
}

resource "aws_lambda_layer_version" "pillow" {
  layer_name          = "${local.name}-pillow"
  filename            = "${path.module}/../layer/pillow-layer.zip"
  source_code_hash    = filebase64sha256("${path.module}/../layer/pillow-layer.zip")
  compatible_runtimes = ["python3.12"]
  description         = "Pillow dependency for image resizing"
}

resource "aws_lambda_function" "processor" {
  function_name = "${local.name}-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = 30
  memory_size = 512

  layers = [aws_lambda_layer_version.pillow.arn]

  environment {
    variables = {
      DEST_BUCKET      = aws_s3_bucket.processed.bucket
      DEST_PREFIX_256  = var.dest_prefix_256
      DEST_PREFIX_1024 = var.dest_prefix_1024
      SIZE_256         = tostring(var.size_256)
      SIZE_1024        = tostring(var.size_1024)
    }
  }

  tags = var.tags
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "uploads_notify" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}
