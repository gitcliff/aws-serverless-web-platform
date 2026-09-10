# ==============================================================================
# 1. NOTIFICATION CHANNEL (SNS)
# ==============================================================================

resource "aws_sns_topic" "alerts" {
  name              = "${var.environment}-system-alerts-topic"
  kms_master_key_id = "alias/aws/sns"
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowAccountOwner"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "sns:Publish",
      "sns:Subscribe",
      "sns:Receive",
      "sns:GetTopicAttributes",
      "sns:ListSubscriptionsByTopic",
    ]
    resources = [aws_sns_topic.alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_sns_topic_subscription" "email_sub" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ==============================================================================
# 2. PERIMETER PROTECTION LAYER: AWS WAF ALARMS
# ==============================================================================

# Alarms if a high volume of requests are being blocked (Potential DDoS or Web Scraping)
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  alarm_name          = "${var.environment}-waf-high-blocked-requests"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100 # Adjust based on normal traffic volume
  alarm_description   = "Triggered if WAF edge drops 100+ malicious or rate-limited requests within 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    WebACL = aws_wafv2_web_acl.waf.name
    Region = "us-east-1"
  }
}

# ==============================================================================
# 3. INTERFACE LAYER: AMAZON API GATEWAY ALARMS
# ==============================================================================

# Alarms if API experience high system failure rates (HTTP 5xx Server Errors)
resource "aws_cloudwatch_metric_alarm" "api_gateway_errors" {
  alarm_name          = "${var.environment}-api-high-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = 300 # 5 minutes
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggered if API Gateway yields 5+ HTTP 5xx responses over 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.http_api.id
  }
}

# Alarms if end-to-end response time breaches acceptable latency envelopes
resource "aws_cloudwatch_metric_alarm" "api_latency" {
  alarm_name          = "${var.environment}-api-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 60
  statistic           = "Average"
  threshold           = 1000 # 1000 milliseconds (1 Second)
  alarm_description   = "Triggered if API Gateway end-to-end response averages over 1s for 2 consecutive minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.http_api.id
  }
}

# ==============================================================================
# 4. COMPUTE LAYER: AWS LAMBDA ALARMS
# ==============================================================================

# Digital Tripwire: Monitors runtime execution failures
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.environment}-lambda-high-error-rate"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Triggered if backend Lambda experiences 5+ execution crashes or exceptions within 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.backend_logic.function_name
  }
}

# Warns when p95 execution time is creeping toward the 5-second timeout,
# giving time to investigate slow DynamoDB calls or cold-start regressions
resource "aws_cloudwatch_metric_alarm" "lambda_duration_p95" {
  alarm_name          = "${var.environment}-lambda-p95-duration-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 60
  extended_statistic  = "p95"
  threshold           = 3000 # 3 000 ms — 60 % of the 5 s timeout ceiling
  alarm_description   = "Triggered if p95 Lambda execution duration exceeds 3s for 3 consecutive minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.backend_logic.function_name
  }
}

# ==============================================================================
# 5. DATA LAYER: AMAZON DYNAMODB ALARMS
# ==============================================================================

# Catches DynamoDB service-side failures that are not client errors
resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  alarm_name          = "${var.environment}-dynamodb-system-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Triggered if DynamoDB returns any system-level (5xx) errors within 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = aws_dynamodb_table.visitor_counter.name
    Operation = "UpdateItem"
  }
}

# Detects DynamoDB latency degradation before it breaches the Lambda timeout
resource "aws_cloudwatch_metric_alarm" "dynamodb_latency" {
  alarm_name          = "${var.environment}-dynamodb-high-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SuccessfulRequestLatency"
  namespace           = "AWS/DynamoDB"
  period              = 60
  statistic           = "Average"
  threshold           = 50 # 50 ms — DynamoDB on-demand should stay well under this
  alarm_description   = "Triggered if DynamoDB UpdateItem average latency exceeds 50ms for 2 consecutive minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TableName = aws_dynamodb_table.visitor_counter.name
    Operation = "UpdateItem"
  }
}

# ==============================================================================
# 6. CDN LAYER: AMAZON CLOUDFRONT ALARMS
# ==============================================================================
# CloudFront metrics are always published to us-east-1 (Global region).
# Since var.aws_region defaults to us-east-1, the default provider applies.

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx_errors" {
  alarm_name          = "${var.environment}-cloudfront-high-5xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 1 # 1 % of requests returning 5xx
  alarm_description   = "Triggered if CloudFront 5xx error rate exceeds 1% over 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx_errors" {
  alarm_name          = "${var.environment}-cloudfront-high-4xx-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 5 # 5 % — elevated client errors may indicate broken links or auth issues
  alarm_description   = "Triggered if CloudFront 4xx error rate exceeds 5% over 5 minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_origin_latency" {
  alarm_name          = "${var.environment}-cloudfront-high-origin-latency"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 60
  statistic           = "Average"
  threshold           = 800 # 800 ms — CloudFront origin latency covers API GW + Lambda round trip
  alarm_description   = "Triggered if CloudFront-to-origin average latency exceeds 800ms for 2 consecutive minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DistributionId = aws_cloudfront_distribution.cdn.id
    Region         = "Global"
  }
}
