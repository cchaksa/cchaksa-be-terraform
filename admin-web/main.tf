data "aws_caller_identity" "current" {}

locals {
  bucket_name = var.bucket_name != null ? var.bucket_name : "cck-admin-web-${var.environment}-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Application = "admin-web"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "cchaksa-be-terraform"
  }

  certificate_arn = var.certificate_arn != null ? var.certificate_arn : aws_acm_certificate.admin[0].arn

  # Stable IDs published by AWS for managed CloudFront policies.
  caching_optimized_policy_id             = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  caching_disabled_policy_id              = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  all_viewer_except_host_origin_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  security_headers_response_policy_id     = "67f7725c-6f97-4210-82d7-5512b31e9d03"
}

resource "aws_s3_bucket" "admin_web" {
  bucket        = local.bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "admin_web" {
  bucket = aws_s3_bucket.admin_web.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "admin_web" {
  bucket = aws_s3_bucket.admin_web.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "admin_web" {
  bucket = aws_s3_bucket.admin_web.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "admin_web" {
  bucket = aws_s3_bucket.admin_web.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_acm_certificate" "admin" {
  count    = var.certificate_arn == null ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudfront_origin_access_control" "admin_web" {
  name                              = "${var.environment}-admin-web-s3"
  description                       = "Private S3 origin for ${var.domain_name}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${var.environment}-admin-web-spa-rewrite"
  runtime = "cloudfront-js-1.0"
  comment = "Rewrite extensionless admin SPA routes to index.html"
  publish = true
  code    = file("${path.module}/spa-rewrite.js")
}

resource "aws_cloudfront_distribution" "admin_web" {
  count = var.enable_distribution ? 1 : 0

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.environment} admin web"
  default_root_object = "index.html"
  aliases             = [var.domain_name]
  price_class         = "PriceClass_200"
  retain_on_delete    = true
  wait_for_deployment = true

  origin {
    domain_name              = aws_s3_bucket.admin_web.bucket_regional_domain_name
    origin_id                = "admin-web-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.admin_web.id
  }

  origin {
    domain_name = var.api_origin_domain_name
    origin_id   = "admin-api"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = "admin-web-s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = local.security_headers_response_policy_id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/api/admin/*"
    target_origin_id       = "admin-api"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    compress               = true

    cache_policy_id            = local.caching_disabled_policy_id
    origin_request_policy_id   = local.all_viewer_except_host_origin_policy_id
    response_headers_policy_id = local.security_headers_response_policy_id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.certificate_arn
    minimum_protocol_version = "TLSv1.2_2021"
    ssl_support_method       = "sni-only"
  }

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = var.certificate_arn != null || length(aws_acm_certificate.admin) == 1
      error_message = "A us-east-1 ACM certificate is required before enabling CloudFront."
    }
  }
}

data "aws_iam_policy_document" "admin_web_bucket" {
  count = var.enable_distribution ? 1 : 0

  statement {
    sid     = "AllowCloudFrontReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.admin_web.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.admin_web[0].arn]
    }
  }
}

resource "aws_s3_bucket_policy" "admin_web" {
  count = var.enable_distribution ? 1 : 0

  bucket = aws_s3_bucket.admin_web.id
  policy = data.aws_iam_policy_document.admin_web_bucket[0].json
}

data "aws_iam_policy_document" "admin_web_deploy" {
  statement {
    sid       = "ListAdminWebBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.admin_web.arn]
  }

  statement {
    sid    = "DeployAdminWebObjects"
    effect = "Allow"
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["${aws_s3_bucket.admin_web.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.enable_distribution ? [1] : []

    content {
      sid       = "InvalidateAdminWebDistribution"
      effect    = "Allow"
      actions   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
      resources = [aws_cloudfront_distribution.admin_web[0].arn]
    }
  }
}

resource "aws_iam_policy" "admin_web_deploy" {
  name        = "${var.environment}-admin-web-deploy"
  description = "Least-privilege deployment policy for the admin SPA"
  policy      = data.aws_iam_policy_document.admin_web_deploy.json
}

resource "aws_iam_user_policy_attachment" "admin_web_deploy" {
  count = var.deploy_iam_user_name == null ? 0 : 1

  user       = var.deploy_iam_user_name
  policy_arn = aws_iam_policy.admin_web_deploy.arn
}
