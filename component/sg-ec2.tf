resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "EC2 application security group"
  vpc_id      = aws_vpc.main.id

  # 임시: 내부 통신용 (나중에 ALB SG로 제한)
  ingress {
    description = "HTTP from VPC"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment}-app-sg"
    Environment = var.environment
  }
}