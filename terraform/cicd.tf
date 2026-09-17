# ─────────────────────────────────────────────────────────────────────────────
# GitHub Actions OIDC — allows GitHub to assume an AWS role via short-lived
# tokens with no static credentials stored anywhere.
#
# Bootstrap: run `terraform apply` locally once (with admin credentials) to
# create the OIDC provider and IAM role. Then copy the output ARN into
# GitHub → Settings → Secrets → Actions → AWS_ROLE_ARN.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  # GitHub's OIDC CA thumbprints — both are valid and should be kept
  # See: https://github.blog/changelog/2023-06-27-github-actions-update-on-oidc-integration-with-aws/
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# ─── Trust policy ─────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Scope to this specific repo — no other GitHub repo can assume this role.
    # GitHub's OIDC sub claim now includes numeric IDs (e.g. owner@ID/repo@ID),
    # so both the legacy and current formats must be accepted.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:gitcliff/aws-serverless-web-platform:*",
        "repo:gitcliff@*/aws-serverless-web-platform@*:*",
      ]
    }
  }
}

# ─── Permissions boundary ─────────────────────────────────────────────────────
# Hard ceiling on what any Lambda execution role can ever do.
# Even if a CI-managed policy grants broader access, the boundary blocks it.
# Must be attached to the Lambda execution role (see iam.tf).

resource "aws_iam_policy" "lambda_permissions_boundary" {
  name        = "lambda-permissions-boundary"
  description = "Maximum permissions a Lambda execution role may ever have — enforced by AWS at eval time"

  policy = data.aws_iam_policy_document.lambda_boundary.json
}

data "aws_iam_policy_document" "lambda_boundary" {
  # Scoped to the specific resources this Lambda interacts with
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.environment}-${var.lambda_function_name}:*",
    ]
  }

  statement {
    sid    = "DynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [aws_dynamodb_table.visitor_counter.arn]
  }

  statement {
    sid    = "XRay"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
    ]
    resources = ["*"] # X-Ray does not support resource-level permissions
  }

  statement {
    sid       = "SQSDLQSend"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }

  statement {
    sid       = "KMSDecrypt"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.project.arn]
  }
}

# ─── CI/CD permissions ────────────────────────────────────────────────────────

# ─── Policy 1 of 3: storage + compute (S3, Lambda, DynamoDB, SQS) ─────────────
data "aws_iam_policy_document" "github_actions_permissions" {
  # Terraform remote state — scoped to the state bucket only
  statement {
    sid    = "TerraformState"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::cliff-terraform-state-storage-bucket",
      "arn:aws:s3:::cliff-terraform-state-storage-bucket/*",
    ]
  }

  # S3 — manage only the project's website and access-logs buckets
  statement {
    sid    = "S3ProjectBuckets"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketAcl",
      "s3:GetAccelerateConfiguration",
      "s3:PutBucketAcl",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketLogging",
      "s3:PutBucketLogging",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls",
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:GetObjectTagging",
      "s3:PutObjectTagging",
      "s3:ListBucketVersions",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:GetBucketWebsite",
      "s3:PutBucketWebsite",
      "s3:HeadObject",
      "s3:GetBucketNotification",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetReplicationConfiguration",
    ]
    resources = [
      aws_s3_bucket.first_bucket.arn,
      "${aws_s3_bucket.first_bucket.arn}/*",
      aws_s3_bucket.access_logs.arn,
      "${aws_s3_bucket.access_logs.arn}/*",
      aws_s3_bucket.canary_artifacts.arn,
      "${aws_s3_bucket.canary_artifacts.arn}/*",
    ]
  }

  # Lambda — scoped to this project's function
  statement {
    sid    = "Lambda"
    effect = "Allow"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:ListVersionsByFunction",
      "lambda:PublishVersion",
      "lambda:CreateAlias",
      "lambda:UpdateAlias",
      "lambda:DeleteAlias",
      "lambda:GetAlias",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:GetPolicy",
      "lambda:TagResource",
      "lambda:UntagResource",
      "lambda:ListTags",
      "lambda:PutFunctionConcurrency",
      "lambda:DeleteFunctionConcurrency",
      "lambda:GetFunctionConcurrency",
    ]
    resources = [
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-${var.lambda_function_name}",
      "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.environment}-${var.lambda_function_name}:*",
    ]
  }

  # DynamoDB — scoped to the visitor counter table
  statement {
    sid    = "DynamoDB"
    effect = "Allow"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateTable",
    ]
    resources = [
      aws_dynamodb_table.visitor_counter.arn,
    ]
  }

  # SQS — scoped to the Lambda dead-letter queue
  statement {
    sid    = "SQSLambdaDLQ"
    effect = "Allow"
    actions = [
      "sqs:CreateQueue",
      "sqs:DeleteQueue",
      "sqs:GetQueueAttributes",
      "sqs:SetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:TagQueue",
      "sqs:UntagQueue",
      "sqs:ListQueueTags",
    ]
    resources = [aws_sqs_queue.lambda_dlq.arn]
  }

  # ListQueues does not support resource-level restrictions
  statement {
    sid       = "SQSList"
    effect    = "Allow"
    actions   = ["sqs:ListQueues"]
    resources = ["*"]
  }
}

# ─── Policy 2 of 3: IAM + KMS ─────────────────────────────────────────────────
data "aws_iam_policy_document" "github_actions_permissions_iam_kms" {
  # IAM — scoped to project service roles and their policies only
  # Does NOT include github-actions-* to prevent self-escalation
  statement {
    sid    = "IAMServiceRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:DeleteRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:GetRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:PassRole",
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:GetPolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.environment}-${var.lambda_execution_role}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.environment}-dynamodb-backup-role",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.environment}-synthetics-canary-role",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/${var.environment}-${var.lambda_cloudwatch_dynamoDB_policy_name}",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/lambda-permissions-boundary",
    ]
  }

  # IAM — read-only on CI role itself (Terraform needs to read, not modify)
  statement {
    sid    = "IAMCIRoleReadOnly"
    effect = "Allow"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListPolicyVersions",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-*",
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/github-actions-*",
    ]
  }

  # IAM — manage the GitHub OIDC provider
  statement {
    sid    = "IAMOIDCProvider"
    effect = "Allow"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com",
    ]
  }

  # Explicit deny: prevent CI from creating IAM users, access keys, or escalating
  statement {
    sid    = "DenyDangerousIAM"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:CreateServiceLinkedRole",
      "iam:DeactivateMFADevice",
    ]
    resources = ["*"]
  }

  # KMS — create/list operations require wildcard (no resource-level support)
  statement {
    sid    = "KMSGlobalOps"
    effect = "Allow"
    actions = [
      "kms:CreateKey",
      "kms:ListAliases",
      "kms:ListKeys",
    ]
    resources = ["*"]
  }

  # KMS — full lifecycle management of the project CMK
  statement {
    sid    = "KMSProjectKeyOps"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:PutKeyPolicy",
      "kms:EnableKeyRotation",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
      "kms:UpdateKeyDescription",
      "kms:ListResourceTags",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:Decrypt",
      "kms:Encrypt",
      "kms:ReEncrypt*",
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    resources = [
      aws_kms_key.project.arn,
      "arn:aws:kms:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alias/${var.environment}-project-key",
    ]
  }
}

# ─── Policy 3 of 3: networking + observability ─────────────────────────────────
data "aws_iam_policy_document" "github_actions_permissions_infra" {
  # CloudFront — scoped to this distribution
  statement {
    sid    = "CloudFront"
    effect = "Allow"
    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource",
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListDistributions",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:ListOriginAccessControls",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
      "cloudfront:ListResponseHeadersPolicies",
      "cloudfront:GetCachePolicy",
      "cloudfront:ListCachePolicies",
    ]
    resources = ["*"] # CloudFront ARNs are global and use distribution ID not known at plan time
  }

  # WAF — CLOUDFRONT scope, must be us-east-1
  statement {
    sid    = "WAF"
    effect = "Allow"
    actions = [
      "wafv2:GetWebACL",
      "wafv2:CreateWebACL",
      "wafv2:UpdateWebACL",
      "wafv2:DeleteWebACL",
      "wafv2:ListWebACLs",
      "wafv2:AssociateWebACL",
      "wafv2:DisassociateWebACL",
      "wafv2:GetWebACLForResource",
      "wafv2:ListTagsForResource",
      "wafv2:TagResource",
      "wafv2:UntagResource",
      "wafv2:CheckCapacity",
    ]
    resources = ["*"]
  }

  # API Gateway
  statement {
    sid    = "APIGateway"
    effect = "Allow"
    actions = [
      "apigateway:GET",
      "apigateway:POST",
      "apigateway:PUT",
      "apigateway:PATCH",
      "apigateway:DELETE",
      "apigateway:TagResource",
      "apigateway:UntagResource",
    ]
    resources = [
      "arn:aws:apigateway:${var.aws_region}::/apis",
      "arn:aws:apigateway:${var.aws_region}::/apis/*",
    ]
  }

  # ACM — certificates for CloudFront must live in us-east-1
  statement {
    sid    = "ACM"
    effect = "Allow"
    actions = [
      "acm:RequestCertificate",
      "acm:DescribeCertificate",
      "acm:DeleteCertificate",
      "acm:ListCertificates",
      "acm:ListTagsForCertificate",
      "acm:AddTagsToCertificate",
      "acm:RemoveTagsFromCertificate",
      "acm:GetCertificate",
    ]
    resources = ["*"] # ACM cert ARNs use random IDs
  }

  # Route 53 — zone management scoped to the project hosted zone
  statement {
    sid    = "Route53ZoneManagement"
    effect = "Allow"
    actions = [
      "route53:GetHostedZone",
      "route53:ListResourceRecordSets",
      "route53:ChangeResourceRecordSets",
      "route53:ListTagsForResource",
      "route53:ChangeTagsForResource",
    ]
    resources = [aws_route53_zone.primary_zone.arn]
  }

  # ListHostedZones and GetChange do not support resource-level restrictions
  statement {
    sid    = "Route53Global"
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:GetChange",
    ]
    resources = ["*"]
  }

  # CloudWatch Logs — scoped to project log groups
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:ListTagsLogGroup",
      "logs:TagLogGroup",
      "logs:AssociateKmsKey",
      "logs:DisassociateKmsKey",
    ]
    resources = [
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.environment}-${var.lambda_function_name}:*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/apigateway/${var.api_gateway_name}:*",
      "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/synthetics/*",
    ]
  }

  # CloudWatch Alarms — scoped to project alarms by environment prefix
  statement {
    sid    = "CloudWatchAlarmsManage"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:PutCompositeAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [
      "arn:aws:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:${var.environment}-*",
    ]
  }

  # DescribeAlarms does not support resource-level restrictions
  statement {
    sid       = "CloudWatchAlarmsRead"
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }

  # CloudWatch Dashboards — scoped to project dashboards by environment prefix
  statement {
    sid    = "CloudWatchDashboardsManage"
    effect = "Allow"
    actions = [
      "cloudwatch:PutDashboard",
      "cloudwatch:GetDashboard",
      "cloudwatch:DeleteDashboards",
    ]
    resources = [
      "arn:aws:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/${var.environment}-*",
      "arn:aws:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/Serverless-App-Operations",
    ]
  }

  # ListDashboards does not support resource-level restrictions
  statement {
    sid       = "CloudWatchDashboardsRead"
    effect    = "Allow"
    actions   = ["cloudwatch:ListDashboards"]
    resources = ["*"]
  }

  # SNS — scoped to the alerts topic
  statement {
    sid    = "SNS"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:SetTopicAttributes",
      "sns:ListTopics",
      "sns:Subscribe",
      "sns:Unsubscribe",
      "sns:GetSubscriptionAttributes",
      "sns:ListSubscriptionsByTopic",
      "sns:TagResource",
      "sns:UntagResource",
      "sns:ListTagsForResource",
    ]
    resources = [
      aws_sns_topic.alerts.arn,
    ]
  }

  # Route 53 Domains — manage the registered domain
  statement {
    sid    = "Route53Domains"
    effect = "Allow"
    actions = [
      "route53domains:GetDomainDetail",
      "route53domains:GetOperationDetail",
      "route53domains:UpdateDomainNameservers",
      "route53domains:ListTagsForDomain",
      "route53domains:UpdateTagsForDomain",
      "route53domains:DeleteTagsForDomain",
      "route53domains:ListOperations",
    ]
    resources = ["*"] # Route 53 Domains does not support resource-level restrictions
  }

  # AWS Backup — vault, plan, and selection for DynamoDB
  statement {
    sid    = "Backup"
    effect = "Allow"
    actions = [
      "backup:DescribeBackupVault",
      "backup:CreateBackupVault",
      "backup:DeleteBackupVault",
      "backup:GetBackupPlan",
      "backup:CreateBackupPlan",
      "backup:UpdateBackupPlan",
      "backup:DeleteBackupPlan",
      "backup:GetBackupSelection",
      "backup:CreateBackupSelection",
      "backup:DeleteBackupSelection",
      "backup:ListTags",
      "backup:TagResource",
      "backup:UntagResource",
    ]
    resources = [
      "arn:aws:backup:${var.aws_region}:${data.aws_caller_identity.current.account_id}:backup-vault:${var.environment}-*",
      "arn:aws:backup:${var.aws_region}:${data.aws_caller_identity.current.account_id}:backup-plan:*",
    ]
  }

  # Synthetics — canary health checks
  statement {
    sid    = "Synthetics"
    effect = "Allow"
    actions = [
      "synthetics:GetCanary",
      "synthetics:CreateCanary",
      "synthetics:UpdateCanary",
      "synthetics:DeleteCanary",
      "synthetics:StartCanary",
      "synthetics:StopCanary",
      "synthetics:DescribeCanaries",
      "synthetics:ListTagsForResource",
      "synthetics:TagResource",
      "synthetics:UntagResource",
    ]
    resources = ["*"] # Synthetics does not support resource-level restrictions for most actions
  }
}

data "aws_iam_policy_document" "github_actions_terraform_read" {
  # DescribeLogGroups is a list API with no resource-level support — must use "*".
  # ListTagsForResource is also here because the Terraform AWS provider passes
  # log group ARNs in a format (with or without trailing ":*") that may not
  # match the scoped ARNs in CloudWatchLogs, so "*" is the safe scope.
  statement {
    sid    = "ReadCloudWatchLogGroups"
    effect = "Allow"

    actions = [
      "logs:DescribeLogGroups",
      "logs:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "github_actions_terraform_read" {
  role   = aws_iam_role.github_actions.name
  policy = data.aws_iam_policy_document.github_actions_terraform_read.json
}

# ─── Role + policy attachment ─────────────────────────────────────────────────

resource "aws_iam_role" "github_actions" {
  name                 = "github-actions-deploy"
  description          = "Assumed by GitHub Actions via OIDC, no static credentials required"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  max_session_duration = 3600 # 1-hour cap per workflow run
}

resource "aws_iam_policy" "github_actions_deploy" {
  name        = "github-actions-deploy-policy"
  description = "Permissions for GitHub Actions CI/CD deployments: storage and compute"
  policy      = data.aws_iam_policy_document.github_actions_permissions.json
}

resource "aws_iam_policy" "github_actions_iam_kms" {
  name        = "github-actions-iam-kms-policy"
  description = "Permissions for GitHub Actions CI/CD deployments: IAM and KMS"
  policy      = data.aws_iam_policy_document.github_actions_permissions_iam_kms.json
}

resource "aws_iam_policy" "github_actions_infra" {
  name        = "github-actions-infra-policy"
  description = "Permissions for GitHub Actions CI/CD deployments: networking and observability"
  policy      = data.aws_iam_policy_document.github_actions_permissions_infra.json
}

resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_deploy.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_iam_kms" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_iam_kms.arn
}

resource "aws_iam_role_policy_attachment" "github_actions_infra" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_infra.arn
}

output "github_actions_role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "Set this as the AWS_ROLE_ARN repository secret"
}
