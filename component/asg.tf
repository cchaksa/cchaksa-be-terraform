resource "aws_autoscaling_group" "app" {
  name                = var.app_asg_name
  min_size            = 1
  desired_capacity    = 1
  max_size            = 2

  vpc_zone_identifier = [
    aws_subnet.public_a.id
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns = [
    aws_lb_target_group.app.arn
  ]

  health_check_type         = "ELB"
  health_check_grace_period = 180

  # 기대 효과: ELB system health transient failure로 인한 SetInstanceHealth(Unhealthy) 이벤트 차단

  tag {
    key                 = "Name"
    value               = "${var.environment}-app"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}
