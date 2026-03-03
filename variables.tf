variable "environment" {
  description = "Deployment environment (develop || prod)"
  type        = string
  default     = "develop"

  validation {
    condition     = var.environment == "develop" || var.environment == "prod"
    error_message = "environment must be either 'develop' or 'prod'."
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
