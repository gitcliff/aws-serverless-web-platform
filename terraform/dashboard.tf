resource "aws_cloudwatch_dashboard" "main_dashboard" {
  dashboard_name = "Serverless-App-Operations"

  # Dashboard layout defined using standard JSON grid coordinate structure (x, y, w, h)
  dashboard_body = jsonencode({
    widgets = [
      # ==============================================================================
      # WIDGET 1: PERIMETER SECURITY (WAF BLOCKS)
      # ==============================================================================
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", aws_wafv2_web_acl.waf.name, "Region", "us-east-1", { "stat" : "Sum", "label" : "Blocked Bad Requests / DDoS Fits" }],
            [".", "AllowedRequests", ".", ".", ".", ".", { "stat" : "Sum", "label" : "Allowed Good Requests" }]
          ]
          period  = 300
          view    = "timeSeries"
          stacked = false
          title   = "🛡️ AWS WAF Edge Firewall Protection"
          region  = "us-east-1"
        }
      },

      # ==============================================================================
      # WIDGET 2: BACKEND ROUTER FAULTS (API GATEWAY 5XX)
      # ==============================================================================
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12 # Left half of screen split
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "5XXError", "ApiId", aws_apigatewayv2_api.http_api.id, { "stat" : "Sum", "color" : "#d62728", "label" : "System Errors (5xx)" }],
            [".", "4XXError", ".", ".", { "stat" : "Sum", "color" : "#ff7f0e", "label" : "Client Errors (4xx)" }]
          ]
          period = 300
          view   = "timeSeries"
          title  = "⚡ API Gateway Network Error Trends"
          region = var.aws_region
        }
      },

      # ==============================================================================
      # WIDGET 3: PERFORMANCE METRIC (API LATENCY ENVELOPE)
      # ==============================================================================
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12 # Right half of screen split
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", aws_apigatewayv2_api.http_api.id, { "stat" : "Average", "label" : "Avg Latency (ms)" }],
            [".", "IntegrationLatency", ".", ".", { "stat" : "Average", "label" : "Lambda Execution Latency (ms)" }]
          ]
          period = 60
          view   = "timeSeries"
          title  = "⏱️ End-to-End Latency vs. Internal Compute Execution Time"
          region = var.aws_region
          yAxis = {
            left = {
              min = 0
            }
          }
          annotations = {
            horizontal = [
              {
                color = "#d62728"
                label = "Alert Threshold (1s)"
                value = 1000
              }
            ]
          }
        }
      },

      # ==============================================================================
      # WIDGET 4: COMPUTE HEALTH (LAMBDA RUNTIME ERRORS & INVOCATIONS)
      # ==============================================================================
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24 # Spans full screen width
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.backend_logic.function_name, { "stat" : "Sum", "color" : "#1f77b4", "label" : "Successful Worker Runs" }],
            [".", "Errors", ".", ".", { "stat" : "Sum", "color" : "#d62728", "label" : "Code Crashes" }],
            [".", "Throttles", ".", ".", { "stat" : "Sum", "color" : "#9467bd", "label" : "Concurrency Throttles" }]
          ]
          period = 300
          view   = "timeSeries"
          title  = "⚙️ AWS Lambda Serverless Compute Worker Performance"
          region = var.aws_region
        }
      }
    ]
  })
}
