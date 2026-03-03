variable "environment" {
  type = string
}

variable "app_name" {
  type    = string
  default = "haksa-serverless"
}

variable "lambda_package_path" {
  type = string
}

variable "lambda_environment" {
  type    = map(string)
  default = {}
}

variable "provisioned_concurrency" {
  type    = number
  default = 0
}

variable "create_async_queue" {
  type    = bool
  default = false
}
