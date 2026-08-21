resource "aws_lb_target_group" "app" {
  count = var.enable_app_stack ? 1 : 0

  name     = "${var.environment}-app-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path              = "/health"
    protocol          = "HTTP"
    matcher           = "200"
    interval          = 30
    timeout           = 5
    healthy_threshold = 2
    # 첫 실패에 즉시 판단되지 않도록 민감도 완화
    unhealthy_threshold = 5
  }

  tags = {
    Name        = "${var.environment}-app-tg"
    Environment = var.environment
  }
}
