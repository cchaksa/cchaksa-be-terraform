# AWS Provider를 Terraform이 다운로드하도록 설정
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  scrape_result_enabled      = var.environment == "develop-shadow" && var.scrape_result_storage.enabled
  scrape_result_bucket_name  = local.scrape_result_enabled ? (trimspace(var.scrape_result_storage.bucket_name) != "" ? var.scrape_result_storage.bucket_name : "cck-${var.environment}-scrape-results-${data.aws_caller_identity.current.account_id}") : null
  scrape_result_prefix_input = local.scrape_result_enabled ? (trimspace(var.scrape_result_storage.prefix) != "" ? var.scrape_result_storage.prefix : "develop-shadow/") : ""
  scrape_result_prefix       = local.scrape_result_enabled && trimspace(local.scrape_result_prefix_input) != "" ? "${trimsuffix(local.scrape_result_prefix_input, "/")}/" : ""
  scrape_result_bucket_arn   = local.scrape_result_enabled ? "arn:aws:s3:::${local.scrape_result_bucket_name}" : null
  scrape_result_object_arn   = local.scrape_result_enabled ? (local.scrape_result_prefix != "" ? "arn:aws:s3:::${local.scrape_result_bucket_name}/${local.scrape_result_prefix}*" : "arn:aws:s3:::${local.scrape_result_bucket_name}/*") : null
  scraper_worker_task_environment = local.scrape_result_enabled ? merge(var.scraper_worker.task_environment, {
    SCRAPE_RESULT_BUCKET = local.scrape_result_bucket_name
    SCRAPE_RESULT_PREFIX = local.scrape_result_prefix
  }) : var.scraper_worker.task_environment
  backend_serverless_lambda_environment = local.scrape_result_enabled ? merge(var.backend_serverless.lambda_environment, {
    SCRAPE_RESULT_BUCKET = local.scrape_result_bucket_name
    SCRAPE_RESULT_PREFIX = local.scrape_result_prefix
  }) : var.backend_serverless.lambda_environment
  scraper_worker_task_role_name       = local.scrape_result_enabled && var.enable_scraper_async && var.enable_scraper_worker_infra ? element(split("/", module.scraper_worker[0].task_role_arn), length(split("/", module.scraper_worker[0].task_role_arn)) - 1) : null
  backend_serverless_lambda_role_name = local.scrape_result_enabled && var.enable_backend_serverless ? element(split("/", module.backend_serverless[0].lambda_role_arn), length(split("/", module.backend_serverless[0].lambda_role_arn)) - 1) : null
}

moved {
  from = module.component
  to   = module.component[0]
}

module "component" {
  count                   = var.environment == "develop-shadow" || (var.environment == "develop" && !var.enable_develop) ? 0 : 1
  source                  = "./component"
  environment             = var.environment
  enable                  = contains(["develop", "develop-shadow"], var.environment) ? var.enable_develop : true
  app_ami_id              = var.app_ami_id
  app_port                = var.app_port
  app_health_path         = var.app_health_path
  app_service_name        = var.app_service_name
  aws_region              = var.aws_region
  app_asg_name            = "${var.environment}-app-asg"
  app_lifecycle_hook_name = "${var.environment}-app-launch-hook"
}

module "scraper_worker" {
  source = "./modules/scraper_worker"
  count  = var.enable_scraper_async && var.enable_scraper_worker_infra ? 1 : 0

  environment           = var.environment
  aws_region            = var.aws_region
  name_prefix           = var.scraper_worker.name_prefix
  image_uri             = var.scraper_worker.image_uri
  cpu                   = var.scraper_worker.cpu
  memory                = var.scraper_worker.memory
  task_environment      = local.scraper_worker_task_environment
  task_secrets          = var.scraper_worker.task_secrets
  task_command          = var.scraper_worker.task_command
  log_retention_in_days = var.scraper_worker.log_retention_in_days
  task_role_policy_arns = var.scraper_worker.task_role_policy_arns
}

module "scraper_async" {
  source = "./modules/scraper_async"
  count  = var.enable_scraper_async ? 1 : 0

  environment             = var.environment
  name_prefix             = var.scraper_async.name_prefix
  ecs_cluster_arn         = var.enable_scraper_worker_infra ? module.scraper_worker[0].ecs_cluster_arn : var.scraper_async.ecs_cluster_arn
  ecs_task_definition_arn = var.enable_scraper_worker_infra ? module.scraper_worker[0].ecs_task_definition_arn : var.scraper_async.ecs_task_definition_arn
  ecs_task_role_arns      = var.enable_scraper_worker_infra ? [module.scraper_worker[0].execution_role_arn, module.scraper_worker[0].task_role_arn] : var.scraper_async.ecs_task_role_arns
  subnet_ids              = var.scraper_async.subnet_ids
  security_group_ids      = var.scraper_async.security_group_ids
  assign_public_ip        = var.scraper_async.assign_public_ip
}

module "backend_serverless" {
  source = "./modules/backend_serverless"
  count  = var.enable_backend_serverless ? 1 : 0

  environment                       = var.environment
  app_name                          = var.backend_serverless.app_name
  lambda_package_path               = var.backend_serverless.lambda_package_path
  lambda_memory_size                = var.backend_serverless.lambda_memory_size
  reserved_concurrent_executions    = var.backend_serverless.reserved_concurrent_executions
  lambda_environment                = local.backend_serverless_lambda_environment
  scraping_job_queue_url            = var.enable_scraper_async ? module.scraper_async[0].jobs_queue_url : var.backend_serverless.scraping_job_queue_url
  scraping_job_queue_arn            = var.enable_scraper_async ? module.scraper_async[0].jobs_queue_arn : var.backend_serverless.scraping_job_queue_arn
  scraping_callback_hmac_secret_arn = trimspace(var.backend_serverless.scraping_callback_hmac_secret_arn) != "" ? var.backend_serverless.scraping_callback_hmac_secret_arn : lookup(var.scraper_worker.task_secrets, "SCRAPE_CALLBACK_HMAC_SECRET", "")
  custom_domain_name                = var.backend_serverless.custom_domain_name
  certificate_arn                   = var.backend_serverless.certificate_arn
  provisioned_concurrency           = var.backend_serverless.provisioned_concurrency
  create_async_queue                = var.backend_serverless.create_async_queue
  grafana_cloud                     = var.backend_serverless.grafana_cloud
}

resource "aws_s3_bucket" "scrape_results" {
  count = local.scrape_result_enabled ? 1 : 0

  bucket        = local.scrape_result_bucket_name
  force_destroy = true

  tags = {
    Environment = var.environment
    Purpose     = "scrape-results"
  }
}

resource "aws_s3_bucket_public_access_block" "scrape_results" {
  count = local.scrape_result_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.scrape_results[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scrape_results" {
  count = local.scrape_result_enabled ? 1 : 0

  bucket = aws_s3_bucket.scrape_results[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "scrape_results" {
  count = local.scrape_result_enabled ? 1 : 0

  bucket = aws_s3_bucket.scrape_results[0].id

  rule {
    id     = "expire-scrape-results"
    status = "Enabled"

    filter {
      prefix = local.scrape_result_prefix != "" ? local.scrape_result_prefix : ""
    }

    expiration {
      days = 30
    }
  }
}

data "aws_iam_policy_document" "scrape_results_worker" {
  count = local.scrape_result_enabled && var.enable_scraper_async && var.enable_scraper_worker_infra ? 1 : 0

  statement {
    sid     = "AllowScrapeResultObjectWrite"
    effect  = "Allow"
    actions = ["s3:PutObject", "s3:AbortMultipartUpload"]
    resources = [
      local.scrape_result_object_arn
    ]
  }

  statement {
    sid       = "AllowScrapeResultPrefixList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.scrape_result_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.scrape_result_prefix != "" ? "${local.scrape_result_prefix}*" : "*"]
    }
  }
}

resource "aws_iam_role_policy" "scrape_results_worker" {
  count = local.scrape_result_enabled && var.enable_scraper_async && var.enable_scraper_worker_infra ? 1 : 0

  name   = "${var.environment}-scrape-results-worker"
  role   = local.scraper_worker_task_role_name
  policy = data.aws_iam_policy_document.scrape_results_worker[0].json
}

data "aws_iam_policy_document" "scrape_results_backend" {
  count = local.scrape_result_enabled && var.enable_backend_serverless ? 1 : 0

  statement {
    sid       = "AllowScrapeResultObjectRead"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:HeadObject"]
    resources = [local.scrape_result_object_arn]
  }

  statement {
    sid       = "AllowScrapeResultBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.scrape_result_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [local.scrape_result_prefix != "" ? "${local.scrape_result_prefix}*" : "*"]
    }
  }
}

resource "aws_iam_role_policy" "scrape_results_backend" {
  count = local.scrape_result_enabled && var.enable_backend_serverless ? 1 : 0

  name   = "${var.environment}-scrape-results-backend"
  role   = local.backend_serverless_lambda_role_name
  policy = data.aws_iam_policy_document.scrape_results_backend[0].json
}

# module "discord-bot" {
#   source             = "./discord-bot/infra"
#   count              = var.environment == "sandbox" ? 1 : 0
#   environment        = var.environment
#   discord_public_key = var.discord_public_key
#   github_token       = var.github_token
# }
