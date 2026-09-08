# ==============================================================================
# 1. NOTIFICATION CHANNEL (SNS)
# ==============================================================================

resource "aws_sns_topic" "alerts" {
  name = "cliff-system-alerts-topic"
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
  alarm_name          = "cliff-waf-high-blocked-requests"
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
  alarm_name          = "cliff-api-high-error-rate"
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
  alarm_name          = "api-high-latency"
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
  alarm_name          = "lambda-high-error-rate"
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
