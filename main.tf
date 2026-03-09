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
  task_environment      = var.scraper_worker.task_environment
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

  environment             = var.environment
  app_name                = var.backend_serverless.app_name
  lambda_package_path     = var.backend_serverless.lambda_package_path
  lambda_environment      = var.backend_serverless.lambda_environment
  custom_domain_name      = var.backend_serverless.custom_domain_name
  certificate_arn         = var.backend_serverless.certificate_arn
  provisioned_concurrency = var.backend_serverless.provisioned_concurrency
  create_async_queue      = var.backend_serverless.create_async_queue
}

# module "discord-bot" {
#   source             = "./discord-bot/infra"
#   count              = var.environment == "sandbox" ? 1 : 0
#   environment        = var.environment
#   discord_public_key = var.discord_public_key
#   github_token       = var.github_token
# }
