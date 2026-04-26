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

variable "lambda_memory_size" {
  type    = number
  default = 1024
}

variable "reserved_concurrent_executions" {
  type    = number
  default = -1
}

variable "lambda_environment" {
  type    = map(string)
  default = {}
}

variable "scraping_job_queue_url" {
  type    = string
  default = ""
}

variable "scraping_job_queue_arn" {
  type    = string
  default = ""
}

variable "scraping_callback_hmac_secret_arn" {
  type    = string
  default = ""
}

variable "custom_domain_name" {
  type    = string
  default = ""
}

variable "certificate_arn" {
  type    = string
  default = ""
}

variable "provisioned_concurrency" {
  type    = number
  default = 0
}

variable "create_async_queue" {
  type    = bool
  default = false
}

variable "grafana_cloud" {
  type = object({
    enabled             = bool
    instance_id         = string
    otlp_endpoint       = string
    api_key_secret_arn  = string
    extension_layer_arn = string
    service_name        = string
  })
  default = {
    enabled             = false
    instance_id         = ""
    otlp_endpoint       = ""
    api_key_secret_arn  = ""
    extension_layer_arn = ""
    service_name        = ""
  }

  validation {
    condition = !var.grafana_cloud.enabled || (
      trimspace(var.grafana_cloud.instance_id) != "" &&
      trimspace(var.grafana_cloud.otlp_endpoint) != "" &&
      trimspace(var.grafana_cloud.api_key_secret_arn) != "" &&
      trimspace(var.grafana_cloud.extension_layer_arn) != ""
    )
    error_message = "grafana_cloud.enabled=true 인 경우 instance_id, otlp_endpoint, api_key_secret_arn, extension_layer_arn를 모두 설정해야 한다."
  }
}
