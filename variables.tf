variable "environment" {
  description = "Deployment environment (develop || develop-shadow || prod)"
  type        = string
  default     = "develop"

  validation {
    condition     = contains(["develop", "develop-shadow", "prod"], var.environment)
    error_message = "environment must be either 'develop', 'develop-shadow', or 'prod'."
  }
}

variable "aws_profile" {
  description = "AWS CLI Profile Name"
  type        = string
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "enable_develop" {
  description = "개발 환경 비용 절감용 설정 (Production 환경에서는 무시됨)"
  type        = bool
  default     = true
}

variable "app_ami_id" {
  description = "선택값: 지정하면 해당 AMI를 사용, null이면 기본 AMI 검색 결과 사용"
  type        = string
  default     = null
}

variable "app_port" {
  description = "Spring 애플리케이션 포트"
  type        = number
  default     = 8080
}

variable "app_health_path" {
  description = "로컬 health check 경로"
  type        = string
  default     = "/health"
}

variable "app_service_name" {
  description = "systemd 서비스 이름"
  type        = string
  default     = "haksa"
}

# region 스크래핑 비동기 전환
variable "enable_scraper_async" {
  description = "스크래핑 비동기 인프라(SQS + EventBridge Pipe -> ECS RunTask) 활성화"
  type        = bool
  default     = false
}

variable "enable_scraper_worker_infra" {
  description = "스크래핑 워커 ECS Cluster/TaskDefinition/IAM을 Terraform으로 함께 생성"
  type        = bool
  default     = false
}

variable "scraper_worker" {
  description = "스크래핑 워커 실행 정의(이미지 URI/스펙/환경변수)"
  type = object({
    name_prefix           = string
    image_uri             = string
    cpu                   = number
    memory                = number
    task_environment      = map(string)
    task_secrets          = map(string)
    task_command          = list(string)
    log_retention_in_days = number
    task_role_policy_arns = list(string)
  })
  default = {
    name_prefix           = "develop-shadow-scraper"
    image_uri             = ""
    cpu                   = 1024
    memory                = 2048
    task_environment      = {}
    task_secrets          = {}
    task_command          = []
    log_retention_in_days = 30
    task_role_policy_arns = []
  }

  validation {
    condition = !var.enable_scraper_worker_infra || (
      trimspace(var.scraper_worker.name_prefix) != "" &&
      trimspace(var.scraper_worker.image_uri) != ""
    )
    error_message = "enable_scraper_worker_infra=true 인 경우 scraper_worker.name_prefix, scraper_worker.image_uri를 설정해야 한다."
  }
}

variable "scraper_async" {
  description = "스크래핑 비동기 모듈 최소 입력(필수 참조값만 관리)"
  type = object({
    ecs_cluster_arn         = string
    ecs_task_definition_arn = string
    ecs_task_role_arns      = list(string)
    subnet_ids              = list(string)
    security_group_ids      = list(string)
    name_prefix             = string
    assign_public_ip        = string
  })
  default = {
    ecs_cluster_arn         = ""
    ecs_task_definition_arn = ""
    ecs_task_role_arns      = []
    subnet_ids              = []
    security_group_ids      = []
    name_prefix             = ""
    assign_public_ip        = "ENABLED"
  }

  validation {
    condition     = var.scraper_async.assign_public_ip == "ENABLED" || var.scraper_async.assign_public_ip == "DISABLED"
    error_message = "scraper_async.assign_public_ip must be ENABLED or DISABLED."
  }

  validation {
    condition = !var.enable_scraper_async || (
      length(var.scraper_async.subnet_ids) > 0 &&
      length(var.scraper_async.security_group_ids) > 0 &&
      trimspace(var.scraper_async.name_prefix) != "" &&
      (
        var.enable_scraper_worker_infra || (
          trimspace(var.scraper_async.ecs_cluster_arn) != "" &&
          trimspace(var.scraper_async.ecs_task_definition_arn) != "" &&
          length(var.scraper_async.ecs_task_role_arns) > 0
        )
      )
    )
    error_message = "enable_scraper_async=true 인 경우 subnet_ids/security_group_ids/name_prefix는 필수이며, enable_scraper_worker_infra=false면 ecs_cluster_arn/ecs_task_definition_arn/ecs_task_role_arns도 필수다."
  }

  validation {
    condition = !var.enable_scraper_async || !var.enable_scraper_worker_infra || (
      var.scraper_async.name_prefix == var.scraper_worker.name_prefix
    )
    error_message = "enable_scraper_worker_infra=true 인 경우 scraper_async.name_prefix와 scraper_worker.name_prefix를 동일하게 설정해야 한다."
  }

  validation {
    condition = !var.enable_scraper_async || var.enable_scraper_worker_infra || (
      trimspace(var.scraper_async.ecs_cluster_arn) != "" &&
      trimspace(var.scraper_async.ecs_task_definition_arn) != "" &&
      length(var.scraper_async.ecs_task_role_arns) > 0
    )
    error_message = "enable_scraper_worker_infra=false 인 경우 scraper_async의 ecs_cluster_arn, ecs_task_definition_arn, ecs_task_role_arns를 설정해야 한다."
  }
}
# endregion

# region 백엔드 서버리스 전환
variable "enable_backend_serverless" {
  description = "백엔드 서버리스 인프라(API Gateway + Lambda) 활성화"
  type        = bool
  default     = false
}

variable "backend_serverless" {
  description = "백엔드 서버리스 최소 입력(환경별 변경이 필요한 값만 관리)"
  type = object({
    app_name                = string
    lambda_package_path     = string
    lambda_environment      = map(string)
    provisioned_concurrency = number
    create_async_queue      = bool
  })
  default = {
    app_name                = "haksa-serverless"
    lambda_package_path     = ""
    lambda_environment      = {}
    provisioned_concurrency = 0
    create_async_queue      = false
  }

  validation {
    condition = !var.enable_backend_serverless || (
      trimspace(var.backend_serverless.app_name) != "" &&
      trimspace(var.backend_serverless.lambda_package_path) != ""
    )
    error_message = "enable_backend_serverless=true 인 경우 backend_serverless.app_name, backend_serverless.lambda_package_path를 설정해야 한다."
  }
}
# endregion

# # region Discord Bot 관련 변수
# variable "discord_public_key" {
#   description = "Discord Bot Public Key"
#   type        = string
#   sensitive   = true
#   default     = ""
# }
#
# variable "github_token" {
#   description = "GitHub Personal Access Token for triggering workflows"
#   type        = string
#   sensitive   = true
#   default     = ""
# }
