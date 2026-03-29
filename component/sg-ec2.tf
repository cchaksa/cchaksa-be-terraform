resource "aws_security_group" "app" {
  name        = "${var.environment}-app-sg"
  description = "EC2 / ASG application security group)"
  vpc_id      = aws_vpc.main.id

  ############################
  # Inbound
  ############################

  # SSH
  ingress {
    description = "SSH (temporary)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP - 내부 통신만
  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Redis - 로컬 캐시로 변경하면서 제거 예정
  ingress {
    description = "Redis from anywhere"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ############################
  # Outbound
  ############################

  # 외부 크롤링/통신 전체 허용
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