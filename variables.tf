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
