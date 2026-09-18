
resource "aws_apigatewayv2_api" "http_api" {
  name          = var.api_gateway_name
  protocol_type = local.api_gateway_protocol_type
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = var.api_gateway_stage_name
  auto_deploy = local.api_gateway_stage_auto_deploy

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw_logs.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }

  default_route_settings {
    throttling_burst_limit = 50 # Allows a brief, sudden spike of up to 50 concurrent requests
    throttling_rate_limit  = 20 # Mandates a steady speed ceiling of 20 requests per second maximum
  }
}

# Integration targets the `live` alias, not $LATEST, so blue/green traffic
# shifts (aws_lambda_alias.live.function_version update) take effect without
# touching API Gateway configuration.
resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = local.api_gateway_integration_type
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = local.api_gateway_payload_format_version
}

# Dynamic fallback route routing /api/{proxy+} to the Lambda function
resource "aws_apigatewayv2_route" "api_route" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = local.api_gateway_route_key
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

# JWT authorizer validates Cognito-issued tokens before the request reaches Lambda.
# The token is expected as: Authorization: Bearer <access_token>
resource "aws_apigatewayv2_authorizer" "cognito_jwt" {
  api_id           = aws_apigatewayv2_api.http_api.id
  authorizer_type  = "JWT"
  name             = "cognito-jwt-authorizer"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.spa_client.id]
    issuer   = "https://cognito-idp.${var.aws_region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# Explicit protected route — matched before the ANY /api/{proxy+} catch-all.
# API Gateway returns 401 if the JWT is absent or invalid; Lambda is never invoked.
resource "aws_apigatewayv2_route" "protected_api_route" {
  api_id             = aws_apigatewayv2_api.http_api.id
  route_key          = "GET /api/dashboard"
  target             = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_jwt.id
}

# Grant API Gateway invoke rights on the alias specifically (not on $LATEST)
resource "aws_lambda_permission" "api_gw_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = local.api_gateway_lambda_permission_action
  function_name = aws_lambda_function.backend_logic.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = local.api_gateway_lambda_permission_principal
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}
