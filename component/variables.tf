variable "environment" { type = string }
variable "aws_region" { type = string }

variable "app_asg_name" {
  description = "ASG name injected to user_data and lifecycle hook"
  type        = string
}

variable "app_lifecycle_hook_name" {
  description = "Lifecycle hook name injected to user_data and hook resource"
  type        = string
}

variable "enable" {
  description = "develop 환경 리소스 생성 여부 제어용"
  type        = bool
  default     = true
}

variable "app_ami_id" {
  description = "선택값: 지정하면 해당 AMI를 사용, null이면 기본 AMI 검색 결과 사용"
  type        = string
  default     = null
}
