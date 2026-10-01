variable "environment" {
  description = "Admin web deployment environment."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be either dev or prod."
  }
}

variable "aws_profile" {
  description = "AWS CLI profile used for local Terraform execution."
  type        = string
  default     = "default"
}

variable "aws_region" {
  description = "Region for the S3 origin and regional resources."
  type        = string
  default     = "ap-northeast-2"
}

variable "domain_name" {
  description = "Public admin SPA domain."
  type        = string
  default     = "admin.cchaksa.com"
}

variable "api_origin_domain_name" {
  description = "Existing API Gateway custom domain used only by /api/admin/*."
  type        = string
  default     = "api.cchaksa.com"
}

variable "bucket_name" {
  description = "Optional globally unique S3 bucket name override."
  type        = string
  default     = null
  nullable    = true
}

variable "certificate_arn" {
  description = "Optional issued us-east-1 ACM certificate ARN. When null, Terraform requests a DNS-validated certificate."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.certificate_arn == null || startswith(var.certificate_arn, "arn:aws:acm:us-east-1:")
    error_message = "certificate_arn must reference an ACM certificate in us-east-1."
  }
}

variable "enable_distribution" {
  description = "Creates CloudFront after the ACM certificate is issued. Keep false for the certificate bootstrap apply."
  type        = bool
  default     = false
}
