# ==============================================================================
# SYNTHETIC MONITORING — CloudWatch Synthetics Canary
#
# Runs a lightweight NodeJS health check against the public API endpoint every
# 5 minutes. A SuccessPercent < 100 triggers the canary-failure alarm which
# pages the same SNS topic as all other operational alarms.
# ==============================================================================

# S3 bucket for canary run artifacts (logs, screenshots)
resource "aws_s3_bucket" "canary_artifacts" {
  bucket = "${var.environment}-synthetics-artifacts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "canary_artifacts" {
  bucket = aws_s3_bucket.canary_artifacts.id

  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"

    expiration {
      days = 30
    }

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

# IAM execution role — Synthetics runs the canary as a Lambda function
resource "aws_iam_role" "canary" {
  name = "${var.environment}-synthetics-canary-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "canary" {
  name = "${var.environment}-synthetics-canary-policy"
  role = aws_iam_role.canary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactsBucket"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.canary_artifacts.arn,
          "${aws_s3_bucket.canary_artifacts.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/synthetics/*"
      },
      {
        Sid      = "SyntheticsMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudWatchSynthetics"
          }
        }
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets",
          "xray:GetSamplingStatisticSummaries"
        ]
        Resource = "*"
      }
    ]
  })
}

# Package the canary script: zip must contain nodejs/node_modules/index.js
# to match the handler "index.handler" expected by the NodeJS puppeteer runtime.
data "archive_file" "canary_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../backend/canary"
  output_path = "${path.module}/../backend/canary.zip"
}

resource "aws_synthetics_canary" "api_health" {
  name                 = "${var.environment}-api-health"
  artifact_s3_location = "s3://${aws_s3_bucket.canary_artifacts.id}/artifacts/"
  execution_role_arn   = aws_iam_role.canary.arn
  handler              = "index.handler"
  zip_file             = data.archive_file.canary_zip.output_path
  runtime_version      = "syn-nodejs-puppeteer-9.1"
  start_canary         = true

  schedule {
    expression = "rate(5 minutes)"
  }

  run_config {
    timeout_in_seconds = 30
    environment_variables = {
      API_URL = "https://${local.domain_name}/api/"
    }
  }

  success_retention_period = 2  # Keep passing run artifacts for 2 days
  failure_retention_period = 14 # Keep failing run artifacts for 14 days for diagnosis
}

# ==============================================================================
# CANARY ALARM
# ==============================================================================

resource "aws_cloudwatch_metric_alarm" "canary_failure" {
  alarm_name          = "${var.environment}-api-canary-failure"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SuccessPercent"
  namespace           = "CloudWatchSynthetics"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "breaching" # No data means the canary itself may be broken
  alarm_description   = "Triggered if the API health canary fails any run within 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    CanaryName = aws_synthetics_canary.api_health.name
  }
}
