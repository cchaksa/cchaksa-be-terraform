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

resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # The backend workflow declares `environment: prod`, so GitHub emits the
    # environment subject instead of a branch subject for this OIDC token.
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:cchaksa/cchaksa-backend:environment:prod"]
    }
  }
}

resource "aws_iam_role" "github_database_backup" {
  name               = "${var.environment}-github-db-backup-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "github_database_backup_s3_access" {
  statement {
    sid    = "InspectBackupBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.database_backup.arn]
  }

  statement {
    sid    = "WriteAndVerifyBackupObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.database_backup.arn}/supabase-db/*"]
  }
}

resource "aws_iam_role_policy" "github_database_backup_s3_access" {
  name   = "${var.environment}-github-db-backup-s3-access"
  role   = aws_iam_role.github_database_backup.id
  policy = data.aws_iam_policy_document.github_database_backup_s3_access.json
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
