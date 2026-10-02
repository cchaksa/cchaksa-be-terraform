output "bucket_name" {
  description = "S3 bucket receiving admin-web/dist artifacts."
  value       = aws_s3_bucket.admin_web.id
}

output "certificate_arn" {
  description = "CloudFront certificate ARN in us-east-1."
  value       = local.certificate_arn
}

output "certificate_validation_records" {
  description = "Add these records to Cloudflare when Terraform requested the certificate."
  value = var.certificate_arn == null ? [
    for option in aws_acm_certificate.admin[0].domain_validation_options : {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  ] : []
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used by the deployment workflow."
  value       = try(aws_cloudfront_distribution.admin_web[0].id, null)
}

output "cloudfront_domain_name" {
  description = "Create a DNS-only Cloudflare CNAME from admin.cchaksa.com to this value."
  value       = try(aws_cloudfront_distribution.admin_web[0].domain_name, null)
}

output "deploy_policy_arn" {
  description = "Attach this policy to the AWS principal used by the admin deployment workflow."
  value       = aws_iam_policy.admin_web_deploy.arn
}
