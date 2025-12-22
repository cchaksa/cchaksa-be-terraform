resource "aws_acm_certificate" "app" {
  domain_name       = "dev.api.cchaksa.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "dev-api-cert"
    Environment = develop
  }
}