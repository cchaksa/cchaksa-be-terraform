# EC2 / ASG가 사용할 IAM Role
resource "aws_iam_role" "ec2" {
  count = var.enable_app_stack ? 1 : 0

  name = "${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_instance_profile" "ec2" {
  count = var.enable_app_stack ? 1 : 0

  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.ec2[0].name
}

# Lifecycle Hook 완료용 권한
resource "aws_iam_policy" "ec2_lifecycle_hook" {
  count = var.enable_app_stack ? 1 : 0

  name = "${var.environment}-ec2-lifecycle-hook"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CompleteLifecycleAction",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_lifecycle_hook" {
  count = var.enable_app_stack ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = aws_iam_policy.ec2_lifecycle_hook[0].arn
}

resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_agent" {
  count = var.enable_app_stack ? 1 : 0

  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
