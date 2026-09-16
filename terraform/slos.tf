# ==============================================================================
# SERVICE LEVEL OBJECTIVES (SLOs)
#
# Two SLOs are defined. Each directly measures the service's behavior against
# its published target — not just whether downstream alarms are firing.
#
#   Availability SLO — 99.9 % uptime (≤ 0.1 % error rate)
#     Measured as: (5XXError / Count) × 100 over a 5-minute window.
#     Breaches when observed error rate exceeds 0.1 % (i.e., < 99.9 % success).
#     This is a true SLO signal: it reflects whether the service is actually
#     meeting its availability target, not just whether error alarms are active.
#
#   Latency SLO — p95 API response < 500 ms
#     Breached when p95 latency exceeds 500 ms for 3 consecutive minutes.
#     The composite below also captures average-latency degradation as an
#     early-warning signal: EITHER condition alone is sufficient to indicate risk.
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
# AVAILABILITY SLO: 99.9 % — measured as actual API error rate
#
# Uses metric math to calculate (5XXError / Count) * 100 directly from
# API Gateway metrics. This measures whether the service is meeting its 99.9 %
# availability target, rather than inferring it from alarm states.
#
# The IF() guard prevents a false alarm when Count is zero (no traffic),
# treating a quiet period as non-breaching.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "availability_slo" {
  alarm_name          = "${var.environment}-slo-availability-breach"
  alarm_description   = "SLO breach: API error rate exceeded 0.1% (99.9% availability target). Calculated from 5XXError/Count over 5-minute window."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 0.1 # 0.1 % error rate corresponds to 99.9 % availability
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "error_rate"
    expression  = "IF(m_count > 0, (m_errors / m_count) * 100, 0)"
    label       = "Error Rate %"
    return_data = true
  }

  metric_query {
    id    = "m_errors"
    label = "5XX Errors"
    metric {
      metric_name = "5XXError"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.http_api.id
      }
    }
  }

  metric_query {
    id    = "m_count"
    label = "Total Requests"
    metric {
      metric_name = "Count"
      namespace   = "AWS/ApiGateway"
      period      = 300
      stat        = "Sum"
      dimensions = {
        ApiId = aws_apigatewayv2_api.http_api.id
      }
    }
  }
}

# ------------------------------------------------------------------------------
# LATENCY SLO COMPOSITE: tail latency OR high average — either signals risk
# OR is correct here: a single threshold breach is enough to indicate the SLO
# is at risk; requiring both to fire simultaneously would mask partial failures.
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_composite_alarm" "latency_slo" {
  alarm_name        = "${var.environment}-slo-latency-breach"
  alarm_description = "SLO breach: Latency SLO at risk. p95 or average API latency threshold exceeded."

  alarm_rule = join(" OR ", [
    "ALARM(\"${aws_cloudwatch_metric_alarm.api_latency_p95.alarm_name}\")",
    "ALARM(\"${aws_cloudwatch_metric_alarm.api_latency.alarm_name}\")",
  ])

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
