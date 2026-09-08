data "aws_caller_identity" "current" {}

# Trust policy allowing Lambda to assume the execution role
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name               = var.lambda_execution_role
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

# Custom policy for CloudWatch Logging and DynamoDB write privileges
data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.lambda_function_name}:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.visitor_counter.arn]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = var.lambda_cloudwatch_dynameDB_policy_name
  description = "Allows Lambda to write to CloudWatch Logs and query/update DynamoDB."
  policy      = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}
