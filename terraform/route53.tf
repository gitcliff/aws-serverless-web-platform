
# ==========================================
#  ROUTE 53 (Domain & Hosted Zone)
# ==========================================
resource "aws_route53domains_domain" "demo_domain" {
  domain_name = local.domain_name
  auto_renew  = false

  admin_contact {
    address_line_1    = "101 Main Street"
    city              = "San Francisco"
    contact_type      = "COMPANY"
    country_code      = "US"
    email             = "terraform-acctest@example.com"
    fax               = "+1.4155551234"
    first_name        = "Terraform"
    last_name         = "Team"
    organization_name = "HashiCorp"
    phone_number      = "+1.4155551234"
    state             = "CA"
    zip_code          = "94105"
  }

  registrant_contact {
    address_line_1    = "101 Main Street"
    city              = "kampala"
    contact_type      = "COMPANY"
    country_code      = "UG"
    email             = "gitacliff48@gmail.com"
    fax               = "+1.4155551234"
    first_name        = "Gita"
    last_name         = "cliff"
    organization_name = "HashiCorp"
    phone_number      = "+256704567830"
    state             = "CA"
    zip_code          = "94105"
  }

  tech_contact {
    address_line_1    = "101 Main Street"
    city              = "San Francisco"
    contact_type      = "COMPANY"
    country_code      = "US"
    email             = "terraform-acctest@example.com"
    fax               = "+1.4155551234"
    first_name        = "Terraform"
    last_name         = "Team"
    organization_name = "HashiCorp"
    phone_number      = "+1.4155551234"
    state             = "CA"
    zip_code          = "94105"
  }

  tags = {
    Environment = "dev"
  }
}

resource "aws_route53_zone" "primary_zone" {
  name    = aws_route53domains_domain.demo_domain.domain_name
  comment = "Managed by cliff"
}

# Create Route53 records for the CloudFront distribution aliases
resource "aws_route53_record" "cloudfront" {
  for_each = aws_cloudfront_distribution.cdn.aliases
  zone_id  = aws_route53_zone.primary_zone.zone_id
  name     = each.value
  type     = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}