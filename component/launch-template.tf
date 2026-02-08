resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-app-"
  image_id      = coalesce(var.app_ami_id, data.aws_ami.app.id)
  instance_type = "t3.micro"

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
