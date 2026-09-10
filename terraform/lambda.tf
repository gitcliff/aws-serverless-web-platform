# Installs runtime dependencies (aws-xray-sdk) into backend/package/ so the zip
# includes everything Lambda needs. Triggers only when requirements.txt or
# lambda_function.py change to avoid unnecessary rebuilds.
resource "null_resource" "pip_install" {
  triggers = {
    requirements = filemd5("${path.module}/../backend/requirements.txt")
    lambda_code  = filemd5("${path.module}/../backend/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      pip install -r ${path.module}/../backend/requirements.txt \
        -t ${path.module}/../backend/package \
        --quiet \
        --upgrade && \
      cp ${path.module}/../backend/lambda_function.py \
        ${path.module}/../backend/package/
    EOT
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/package"
  output_path = "${path.module}/../backend/lambda.zip"
  depends_on  = [null_resource.pip_install]
}

resource "aws_lambda_function" "backend_logic" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.environment}-${var.lambda_function_name}"
  role             = aws_iam_role.lambda_role.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # publish = true creates a numbered version on every deploy; the `live`
  # alias below pins to the latest published version, enabling blue/green
  # traffic shifting and safe rollbacks without changing the API Gateway config.
  publish = true

  # Prevents this specific function from scaling beyond 20 concurrent executions,
  # saving the rest of the AWS account capacity and flattening billing spikes.
  reserved_concurrent_executions = 20

  # Kill execution quickly if code behaves unexpectedly
  timeout     = 5   # In seconds (Keep it under 10s for API endpoints)
  memory_size = 256 # Allocation limit in MB

  # Emit traces to AWS X-Ray for end-to-end latency visibility
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.visitor_counter.name
      ALLOWED_ORIGIN = "https://${local.domain_name}"
      ENVIRONMENT    = var.environment
    }
  }
}

# Stable pointer to the latest published version. API Gateway targets this
# alias so that all traffic shifts atomically when the alias is updated.
resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.backend_logic.function_name
  function_version = aws_lambda_function.backend_logic.version
}
