resource "aws_lb" "app" {
  count = var.enable_app_stack ? 1 : 0

  name               = "${var.environment}-alb"
  load_balancer_type = "application"
  internal           = false
  depends_on         = [aws_s3_bucket_policy.alb_access_logs]

  security_groups = [
    aws_security_group.alb[0].id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_access_logs[0].bucket
    prefix  = "${var.environment}/alb"
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-alb"
    Environment = var.environment
  }
}
