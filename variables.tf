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
  description = "고정할 AMI ID. null이면 최신 AMI를 사용."
  type        = string
  default     = null
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
