# ==============================================================================
# SERVICE LEVEL OBJECTIVES (SLOs)
#
# Composite alarms combine existing per-tier alarms into SLO breach signals.
# Two SLOs are defined:
#
#   Availability SLO — 99.9 % uptime (≤ 43.8 min downtime / month)
#     Breached when the API tier or compute tier are both in ALARM
#
#   Latency SLO — p95 API response < 500 ms
#     Breached when p95 latency exceeds 500 ms for 3 consecutive minutes
#
# Composite alarms do not add cost per alarm-state evaluation; they simply
# aggregate the state of child alarms already paid for above.
# ==============================================================================

# ------------------------------------------------------------------------------
# LATENCY SLO: p95 API Gateway latency < 500 ms
# (The existing api_latency alarm measures average; this measures the tail.)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "api_latency_p95" {
  alarm_name          = "${var.environment}-api-p95-latency-slo"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = 60
  extended_statistic  = "p95"
  threshold           = 500 # 500 ms — SLO target for tail latency
  alarm_description   = "SLO: p95 API Gateway latency exceeded 500ms for 3 consecutive minutes."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    ApiId = aws_apigatewayv2_api.http_api.id
  }
}

# ------------------------------------------------------------------------------
# AVAILABILITY SLO: 99.9 % — composite of API + Lambda error alarms
# Both child alarms must fire together before the SLO breach is signalled,
# reducing false positives from transient single-tier flaps.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_composite_alarm" "availability_slo" {
  alarm_name        = "${var.environment}-slo-availability-breach"
  alarm_description = "SLO breach: 99.9% availability is at risk. Both API Gateway and Lambda error alarms are firing simultaneously."

  alarm_rule = join(" AND ", [
    "ALARM(\"${aws_cloudwatch_metric_alarm.api_gateway_errors.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.lambda_errors.alarm_name}\")",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ------------------------------------------------------------------------------
# LATENCY SLO COMPOSITE: tail latency or high average — either signals risk
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_composite_alarm" "latency_slo" {
  alarm_name        = "${var.environment}-slo-latency-breach"
  alarm_description = "SLO breach: Latency SLO at risk. p95 or average API latency thresholds are both exceeded."

  alarm_rule = join(" AND ", [
    "ALARM(\"${aws_cloudwatch_metric_alarm.api_latency_p95.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.api_latency.alarm_name}\")",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
