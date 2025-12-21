resource "aws_lb" "app" {
  name               = "${var.environment}-alb"
  load_balancer_type = "application"
  internal           = false

  security_groups = [
    aws_security_group.alb.id
  ]

  subnets = [
    aws_subnet.public_a.id,
    aws_subnet.public_c.id
  ]

  tags = {
    Name        = "${var.environment}-alb"
    Environment = var.environment
  }
}