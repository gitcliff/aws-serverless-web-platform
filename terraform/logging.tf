# ==============================================================================
# ACCESS LOGGING INFRASTRUCTURE
# ==============================================================================

# Central S3 bucket that receives all access logs (CloudFront, S3)
resource "aws_s3_bucket" "access_logs" {
  bucket = "cliff-access-logs-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  # block_public_acls is false to allow the log-delivery-write ACL required
  # by CloudFront and S3 log delivery — log-delivery-write is not a public ACL
  block_public_acls       = false
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable ACLs so CloudFront log delivery can write using log-delivery-write
resource "aws_s3_bucket_ownership_controls" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "access_logs" {
  depends_on = [
    aws_s3_bucket_ownership_controls.access_logs,
    aws_s3_bucket_public_access_block.access_logs,
  ]
  bucket = aws_s3_bucket.access_logs.id
  acl    = "log-delivery-write"
}

# Allow the S3 server access logging service to deliver logs from the website bucket
resource "aws_s3_bucket_policy" "access_logs" {
  bucket     = aws_s3_bucket.access_logs.id
  depends_on = [aws_s3_bucket_public_access_block.access_logs]

  policy = data.aws_iam_policy_document.access_logs_bucket_policy.json
}

data "aws_iam_policy_document" "access_logs_bucket_policy" {
  statement {
    sid    = "AllowS3LogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/s3/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.first_bucket.arn]
    }
  }
}

# Move logs to cheaper storage after 30 days, delete after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

# S3 server access logging for the website bucket
resource "aws_s3_bucket_logging" "website" {
  bucket        = aws_s3_bucket.first_bucket.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "s3/"
}

# CloudWatch log group for API Gateway HTTP access logs
resource "aws_cloudwatch_log_group" "api_gw_logs" {
  name              = "/aws/apigateway/${var.api_gateway_name}"
  retention_in_days = 14
}

# CloudWatch log group for Lambda — explicit retention prevents unbounded log growth
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 14
}
