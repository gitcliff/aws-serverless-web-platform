# ==============================================================================
# AWS COST ANOMALY DETECTION
# Detects unexpected total account spend spikes and alerts via SNS.
# OVERALL type has no per-account creation limit (DIMENSIONAL is capped at 2).
# ==============================================================================

resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "${var.environment}-service-cost-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "LINKED_ACCOUNT"
  # LINKED_ACCOUNT has a separate quota from SERVICE monitors (capped at 2).
  # Monitors total spend anomalies across this account.
}

resource "aws_ce_anomaly_subscription" "alerts" {
  name      = "${var.environment}-cost-anomaly-alerts"
  frequency = "IMMEDIATE"

  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn,
  ]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.alerts.arn
  }

  # Alert only when the anomaly is both meaningfully large in percentage terms
  # AND crosses an absolute dollar threshold — avoids noise from tiny-dollar spikes.
  threshold_expression {
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(var.cost_anomaly_threshold_percentage)]
      }
    }
    and {
      dimension {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(var.cost_anomaly_threshold_absolute)]
      }
    }
  }
}
