resource "aws_lb" "app" {
  name               = "${var.environment}-alb"
  load_balancer_type = "application"
  internal           = false
  depends_on         = [aws_s3_bucket_policy.alb_access_logs]

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id
  ]

  access_logs {
    bucket  = aws_s3_bucket.alb_access_logs.bucket
    prefix  = "${var.environment}/alb"
    enabled = true
  }

  tags = {
    Name        = "${var.environment}-alb"
    Environment = var.environment
  }
}
