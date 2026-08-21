output "bucket_name" {
  value = aws_s3_bucket.database_backup.id
}

output "bucket_arn" {
  value = aws_s3_bucket.database_backup.arn
}
