resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "dev.api.cchaksa.com"
  type    = "A"

  alias {
    name                   = aws_lb.app.dns_name
    zone_id                = aws_lb.app.zone_id
    evaluate_target_health = true
  }
}