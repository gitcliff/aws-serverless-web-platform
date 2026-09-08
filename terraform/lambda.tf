data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../backend/lambda_function.py"
  output_path = "${path.module}/../backend/lambda.zip"
}

resource "aws_lambda_function" "backend_logic" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Prevents this specific function from scaling beyond 20 concurrent executions,
  # saving the rest of the AWS account capacity and flattening billing spikes.
  reserved_concurrent_executions = 20

  # Kill execution quickly if code behaves unexpectedly
  timeout     = 5   # In seconds (Keep it under 10s for API endpoints)
  memory_size = 256 # Allocation limit in MB

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.visitor_counter.name
      ALLOWED_ORIGIN = "https://${local.domain_name}"
    }
  }
}
