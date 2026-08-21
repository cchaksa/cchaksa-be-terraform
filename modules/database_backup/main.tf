data "aws_caller_identity" "current" {}

locals {
  bucket_name = "cck-${var.environment}-db-backup-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  common_tags = {
    Name        = "${var.environment}-db-backup"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "database-backup"
  }
}

resource "aws_s3_bucket" "database_backup" {
  bucket = local.bucket_name

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "database_backup" {
  bucket = aws_s3_bucket.database_backup.id

  rule {
    id     = "expire-daily-backups"
    status = "Enabled"

    filter {
      prefix = "supabase-db/daily/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "expire-monthly-backups"
    status = "Enabled"

    filter {
      prefix = "supabase-db/monthly/"
    }

    expiration {
      days = 365
    }
  }

  rule {
    id     = "expire-noncurrent-latest-backups"
    status = "Enabled"

    filter {
      prefix = "supabase-db/latest/"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "abort-incomplete-backup-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = "supabase-db/"
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
