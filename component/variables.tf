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

variable "enable_app_stack" {
  description = "EC2/ASG/ALB 기반 백엔드 상시 실행 계층 생성 여부"
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
