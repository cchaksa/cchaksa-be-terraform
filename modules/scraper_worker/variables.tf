variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "image_uri" {
  type = string
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}

variable "task_environment" {
  type    = map(string)
  default = {}
}

variable "task_command" {
  type    = list(string)
  default = []
}

variable "log_retention_in_days" {
  type    = number
  default = 30
}

variable "task_role_policy_arns" {
  type    = list(string)
  default = []
}
