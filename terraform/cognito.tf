# ==============================================================================
# COGNITO AUTHENTICATION
# User pool with email-based login, a public SPA client (PKCE / auth-code flow),
# and a Cognito-hosted UI on the prefix domain.
# ==============================================================================

resource "aws_cognito_user_pool" "main" {
  name = "${var.environment}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 8
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }
}

resource "aws_cognito_user_pool_client" "spa_client" {
  name         = "${var.environment}-spa-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client — no secret; PKCE handles the security for SPAs
  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30
}

# Prefix domain: https://${var.environment}-cliffworld.auth.${var.aws_region}.amazoncognito.com
# No extra ACM certificate required — uses the Cognito-managed certificate.
resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${var.environment}-cliffworld"
  user_pool_id = aws_cognito_user_pool.main.id
}
