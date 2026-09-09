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

