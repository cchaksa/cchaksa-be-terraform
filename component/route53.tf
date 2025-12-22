resource "aws_route53_zone" "dev_api" {
  name    = "dev.api.cchaksa.com"
  comment = "dev api zone (delegated from Cloudflare)"
}