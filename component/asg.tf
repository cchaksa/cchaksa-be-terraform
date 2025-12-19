resource "aws_autoscaling_group" "app" {
  name                = "${var.environment}-app-asg"
  min_size            = 1
  desired_capacity    = 1
  max_size            = 3

  vpc_zone_identifier = [
    aws_subnet.public_a.id
  ]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  health_check_type         = "EC2"
  health_check_grace_period = 60

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