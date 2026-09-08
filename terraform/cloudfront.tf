
# AWS WAFv2 Web ACL deployed at the CloudFront Edge
resource "aws_wafv2_web_acl" "waf" {
  name        = "cliff-cloudfront-waf"
  description = "Edge firewall protecting CloudFront origins"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "IPRateLimitRule"
    priority = 0 # Priority 0 ensures this evaluates BEFORE standard core rule sets

    action {
      block {} # Drop traffic immediately if the threshold is crossed
    }

    statement {
      rate_based_statement {
        limit              = 300 # Maximum requests allowed per IP address in a rolling 5-minute window
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "IPRateLimitRuleMetric"
      sampled_requests_enabled   = true
    }
  }


  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CliffCloudFrontWAFMetric"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "cdn" {

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [local.domain_name]

  web_acl_id = aws_wafv2_web_acl.waf.arn

  #Origin 1: S3 Bucket 
  origin {
    domain_name              = aws_s3_bucket.first_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.first_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # Origin 2: API Gateway Backend
  origin {
    domain_name = replace(aws_apigatewayv2_stage.prod.invoke_url, "https://", "")
    origin_id   = "APIGateway-Backend"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "S3-${aws_s3_bucket.first_bucket.id}"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_policy.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    # Force HTTP → HTTPS
    viewer_protocol_policy = "redirect-to-https"

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Ordered Cache Behavior (Routes /api/* to API Gateway; Cache Disabled for dynamic data)
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "APIGateway-Backend"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    viewer_protocol_policy     = "https-only"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_policy.id

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Origin"]
      cookies { forward = "all" }
    }

    # Bypassing cache completely (TTL = 0) so changes reflect dynamically
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # HTTPS certificate
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.website_cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Custom Response Headers Policy for strict browser security enforcement
resource "aws_cloudfront_response_headers_policy" "security_policy" {
  name    = "cliff-advanced-security-headers-policy"
  comment = "Enforces strict CSP, HSTS, and CORS for the Serverless application"

  # 1. HSTS Configuration: Forces browsers to interact ONLY via HTTPS
  security_headers_config {
    strict_transport_security {
      override                   = true
      access_control_max_age_sec = 31536000 # 1 Year in seconds
      include_subdomains         = true
      preload                    = true
    }

    # Anti-Clickjacking
    frame_options {
      override     = true
      frame_option = "DENY"
    }

    # Anti-MIME Sniffing
    content_type_options {
      override = true
    }

    # XSS Protection for legacy browsers
    xss_protection {
      override   = true
      protection = true
      mode_block = true
    }

    # 2. CSP Configuration: Restricts assets to self-loading and your explicit backend API domain
    content_security_policy {
      override = true
      # Allow code/styles from self; allow scripts/connections strictly to your apex domain and subdomains
      content_security_policy = "default-src 'self'; script-src 'self' 'identity'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' https://${local.domain_name} https://*.${local.domain_name}; frame-ancestors 'none'; object-src 'none';"
    }
  }

  # 3. CORS Configuration: Validates and locks cross-domain scripts
  cors_config {
    access_control_allow_credentials = true
    origin_override                  = true

    access_control_allow_origins {
      items = ["https://${local.domain_name}"] # Restricts script actions tightly to your official domain
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    }

    access_control_allow_headers {
      items = ["Authorization", "Content-Type", "Origin", "X-Requested-With"]
    }

    access_control_expose_headers {
      items = ["Content-Length"]
    }

    access_control_max_age_sec = 600
  }

  # Implementing Permissions Policy
  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      override = true

      # Strict production-grade baseline string: disabling hardware feature tracking completely
      value = "camera=(), microphone=(), geolocation=(), payment=(), usb=(), accelerometer=(), gyroscope=(), magnetometer=()"
    }
  }
}
