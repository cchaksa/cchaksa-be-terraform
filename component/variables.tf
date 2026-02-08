variable "environment" { type = string }

variable "enable" {
  description = "develop 환경 리소스 생성 여부 제어용"
  type        = bool
  default     = true
}

variable "app_ami_id" {
  description = "고정할 AMI ID. null이면 최신 AMI를 사용."
  type        = string
  default     = null
}
