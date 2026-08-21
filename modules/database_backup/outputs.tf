output "bucket_name" {
  value = aws_s3_bucket.database_backup.id
}

output "bucket_arn" {
  value = aws_s3_bucket.database_backup.arn
}

output "github_oidc_role_arn" {
  value = aws_iam_role.github_database_backup.arn
}
