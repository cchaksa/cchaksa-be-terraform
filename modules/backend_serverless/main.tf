locals {
  lambda_handler       = "com.chukchuk.haksa.global.lambda.StreamLambdaHandler::handleRequest"
  lambda_runtime       = "java17"
  lambda_architectures = ["arm64"]
  lambda_timeout       = 30
  lambda_memory_size   = 1024
  create_custom_domain = trimspace(var.custom_domain_name) != "" && trimspace(var.certificate_arn) != ""
  artifact_bucket_name = "cck-${var.environment}-${substr(md5(var.app_name), 0, 8)}-lambda-${data.aws_caller_identity.current.account_id}"
  artifact_object_key  = "packages/${filemd5(var.lambda_package_path)}-${basename(var.lambda_package_path)}"

  async_queue_visibility_secs   = 120
  async_queue_retention_secs    = 345600
  async_queue_max_receive       = 5
  scraping_callback_hmac_secret = trimspace(var.scraping_callback_hmac_secret_arn) != "" ? nonsensitive(data.aws_secretsmanager_secret_version.scraping_callback_hmac_secret[0].secret_string) : null
  lambda_environment = merge(
    var.lambda_environment,
    trimspace(var.scraping_job_queue_url) != "" ? {
      SCRAPING_JOB_QUEUE_URL = var.scraping_job_queue_url
    } : {},
    local.scraping_callback_hmac_secret != null ? {
      SCRAPING_CALLBACK_HMAC_SECRET = local.scraping_callback_hmac_secret
    } : {}
  )
}

data "aws_caller_identity" "current" {}

data "aws_secretsmanager_secret_version" "scraping_callback_hmac_secret" {
  count     = trimspace(var.scraping_callback_hmac_secret_arn) != "" ? 1 : 0
  secret_id = var.scraping_callback_hmac_secret_arn
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.environment}-${var.app_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_scraping_queue_access" {
  count = trimspace(var.scraping_job_queue_arn) != "" ? 1 : 0

  statement {
    sid    = "AllowScrapingQueueSend"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [var.scraping_job_queue_arn]
  }
}

resource "aws_iam_role_policy" "lambda_scraping_queue_access" {
  count = trimspace(var.scraping_job_queue_arn) != "" ? 1 : 0

  name   = "${var.environment}-${var.app_name}-sqs-send"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_scraping_queue_access[0].json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.environment}-${var.app_name}"
  retention_in_days = 30

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket" "lambda_artifacts" {
  bucket        = local.artifact_bucket_name
  force_destroy = true

  tags = {
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_artifacts" {
  bucket = aws_s3_bucket.lambda_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "lambda_package" {
  bucket = aws_s3_bucket.lambda_artifacts.id
  key    = local.artifact_object_key
  source = var.lambda_package_path
  etag   = filemd5(var.lambda_package_path)

  lifecycle {
    ignore_changes = [
      key,
      source,
      etag
    ]
  }
}

resource "aws_lambda_function" "backend" {
  function_name     = "${var.environment}-${var.app_name}"
  role              = aws_iam_role.lambda_exec.arn
  handler           = local.lambda_handler
  source_code_hash  = filebase64sha256(var.lambda_package_path)
  runtime           = local.lambda_runtime
  timeout           = local.lambda_timeout
  memory_size       = local.lambda_memory_size
  architectures     = local.lambda_architectures
  publish           = true
  s3_bucket         = aws_s3_bucket.lambda_artifacts.id
  s3_key            = aws_s3_object.lambda_package.key
  s3_object_version = aws_s3_object.lambda_package.version_id

  snap_start {
    apply_on = "PublishedVersions"
  }

  environment {
    variables = local.lambda_environment
  }

  lifecycle {
    ignore_changes = [
      source_code_hash,
      s3_key,
      s3_object_version
    ]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_s3_bucket_public_access_block.lambda_artifacts,
    aws_s3_bucket_versioning.lambda_artifacts,
    aws_s3_bucket_server_side_encryption_configuration.lambda_artifacts
  ]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  description      = "Production-like alias for gradual cutover"
  function_name    = aws_lambda_function.backend.function_name
  function_version = aws_lambda_function.backend.version

  lifecycle {
    ignore_changes = [
      function_version
    ]
  }
}

resource "aws_lambda_provisioned_concurrency_config" "live" {
  count = var.provisioned_concurrency > 0 ? 1 : 0

  function_name                     = aws_lambda_function.backend.function_name
  qualifier                         = aws_lambda_alias.live.name
  provisioned_concurrent_executions = var.provisioned_concurrency
}

resource "aws_apigatewayv2_api" "http_api" {
  name          = "${var.environment}-${var.app_name}-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_proxy" {
  api_id                 = aws_apigatewayv2_api.http_api.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_alias.live.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.http_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_proxy.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_apigatewayv2_domain_name" "custom" {
  count = local.create_custom_domain ? 1 : 0

  domain_name = var.custom_domain_name

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "custom" {
  count = local.create_custom_domain ? 1 : 0

  api_id      = aws_apigatewayv2_api.http_api.id
  domain_name = aws_apigatewayv2_domain_name.custom[0].id
  stage       = aws_apigatewayv2_stage.default.id
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http_api.execution_arn}/*/*"
}

resource "aws_sqs_queue" "async_dlq" {
  count = var.create_async_queue ? 1 : 0

  name                       = "${var.environment}-${var.app_name}-async-dlq"
  message_retention_seconds  = local.async_queue_retention_secs
  visibility_timeout_seconds = local.async_queue_visibility_secs
}

resource "aws_sqs_queue" "async_queue" {
  count = var.create_async_queue ? 1 : 0

  name                       = "${var.environment}-${var.app_name}-async-queue"
  message_retention_seconds  = local.async_queue_retention_secs
  visibility_timeout_seconds = local.async_queue_visibility_secs

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.async_dlq[0].arn
    maxReceiveCount     = local.async_queue_max_receive
  })
}
