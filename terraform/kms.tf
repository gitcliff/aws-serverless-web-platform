# Customer-managed KMS key used by S3 (website bucket), CloudWatch Logs,
# and Lambda environment variables. A single key keeps cost to ~$1/month.

data "aws_iam_policy_document" "kms_project" {
  # Account root retains full control so the key is never locked out
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  # CloudWatch Logs acts as a service principal — it must be explicitly granted
  # access in the key policy; IAM policies alone are insufficient for this case.
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }
}

resource "aws_kms_key" "project" {
  description             = "CMK for ${var.environment} project resources (S3, CloudWatch Logs, Lambda env vars)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_project.json
}

resource "aws_kms_alias" "project" {
  name          = "alias/${var.environment}-project-key"
  target_key_id = aws_kms_key.project.key_id
}
