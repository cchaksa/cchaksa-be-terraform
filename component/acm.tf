resource "aws_acm_certificate" "app" {
  domain_name       = "*.cchaksa.com"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.environment}-api-cert"
    Environment = var.environment
  }
}