resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-app-"
  image_id      = coalesce(var.app_ami_id, data.aws_ami.app.id)
  instance_type = "t3.micro"
  user_data = base64encode(templatefile("${path.module}/user-data/app-user-data.sh.tmpl", {
    asg_name            = var.app_asg_name
    lifecycle_hook_name = var.app_lifecycle_hook_name
    aws_region          = var.aws_region
    environment         = var.environment
  }))

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.app.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${var.environment}-app"
      Environment = var.environment
    }
  }
}
