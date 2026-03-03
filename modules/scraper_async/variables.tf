variable "environment" {
  type = string
}

variable "ecs_cluster_arn" {
  type = string
}

variable "ecs_task_definition_arn" {
  type = string
}

variable "ecs_task_role_arns" {
  type = list(string)
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "name_prefix" {
  type    = string
  default = ""
}

variable "assign_public_ip" {
  type    = string
  default = "ENABLED"
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 300
}

variable "max_receive_count" {
  type    = number
  default = 5
}

variable "batch_size" {
  type    = number
  default = 1
}

variable "maximum_batching_window_in_seconds" {
  type    = number
  default = 0
}

variable "task_count" {
  type    = number
  default = 1
}

variable "pipe_desired_state" {
  type    = string
  default = "RUNNING"
}
