resource "aws_route53_zone" "main" {
  name = "cchaksa.com"

  tags = {
    Environment = var.environment
  }
}