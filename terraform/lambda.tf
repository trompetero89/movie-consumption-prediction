# Validates the newly-arrived consumption file before the SageMaker
# Processing Job runs. Deployment package is zipped from lambda/validation/.

data "archive_file" "validation_lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/validation"
  output_path = "${path.module}/build/validation_lambda.zip"
}

resource "aws_lambda_function" "validation" {
  function_name    = "${var.project_name}-validate-input"
  role             = aws_iam_role.validation_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.validation_lambda.output_path
  source_code_hash = data.archive_file.validation_lambda.output_base64sha256

  environment {
    variables = {
      DATA_BUCKET = aws_s3_bucket.data.bucket
    }
  }
}

resource "aws_cloudwatch_log_group" "validation_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.validation.function_name}"
  retention_in_days = 90
}
