output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "The raw CloudFront distribution URL endpoint."
}

output "application_url" {
  value       = "https://${local.domain_name}"
  description = "The main target application URL."
}

output "base_url" {
  description = "Base URL for API Gateway stage."
  value       = aws_apigatewayv2_stage.prod.invoke_url
}

output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.cdn.id
  description = "CloudFront distribution ID — used by CI/CD to issue cache invalidations after deploy."
}

output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.main.id
  description = "Cognito User Pool ID — needed to construct the JWT issuer URL."
}

output "cognito_app_client_id" {
  value       = aws_cognito_user_pool_client.spa_client.id
  description = "Cognito App Client ID — used as the OAuth2 client_id in the frontend auth flow."
}

output "cognito_hosted_ui_domain" {
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
  description = "Base URL of the Cognito Hosted UI (login, token, logout endpoints)."
}

