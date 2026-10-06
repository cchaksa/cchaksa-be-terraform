data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "alb_access_logs" {
  count = var.enable_app_stack ? 1 : 0

  bucket        = "${var.environment}-alb-access-logs-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  force_destroy = true

  tags = {
    Name        = "${var.environment}-alb-access-logs"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "alb_access_logs" {
  count = var.enable_app_stack ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_access_logs" {
  count = var.enable_app_stack ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "alb_access_logs" {
  count = var.enable_app_stack ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "alb_access_logs" {
  count = var.enable_app_stack ? 1 : 0

  bucket = aws_s3_bucket.alb_access_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowALBLogDelivery"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.alb_access_logs[0].arn}/${var.environment}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "ec2_user_data" {
  count = var.enable_app_stack ? 1 : 0

  name              = "/${var.environment}/ec2/user-data"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_cloudwatch_log_group" "ec2_system" {
  count = var.enable_app_stack ? 1 : 0

  name              = "/${var.environment}/ec2/system"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}
