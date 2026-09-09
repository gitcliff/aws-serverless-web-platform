locals {
  domain_name = "cliffworld.link"

  # API Gateway implementation constants (not user-configurable)
  api_gateway_protocol_type               = "HTTP"
  api_gateway_stage_auto_deploy           = true
  api_gateway_integration_type            = "AWS_PROXY"
  api_gateway_payload_format_version      = "2.0"
  api_gateway_route_key                   = "ANY /api/{proxy+}"
  api_gateway_lambda_permission_action    = "lambda:InvokeFunction"
  api_gateway_lambda_permission_principal = "apigateway.amazonaws.com"
}
