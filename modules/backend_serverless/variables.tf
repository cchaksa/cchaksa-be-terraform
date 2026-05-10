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

variable "scraping_job_queue_access_enabled" {
  type    = bool
  default = false
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

variable "maintenance_schedules" {
  type = object({
    enabled                        = bool
    state                          = string
    stale_scrape_jobs_schedule     = string
    refresh_token_cleanup_schedule = string
    maximum_retry_attempts         = number
    maximum_event_age_in_seconds   = number
    dlq_message_retention_seconds  = number
  })
  default = {
    enabled                        = false
    state                          = "DISABLED"
    stale_scrape_jobs_schedule     = "rate(5 minutes)"
    refresh_token_cleanup_schedule = "rate(1 hour)"
    maximum_retry_attempts         = 3
    maximum_event_age_in_seconds   = 300
    dlq_message_retention_seconds  = 1209600
  }

  validation {
    condition = !var.maintenance_schedules.enabled || (
      trimspace(var.maintenance_schedules.stale_scrape_jobs_schedule) != "" &&
      trimspace(var.maintenance_schedules.refresh_token_cleanup_schedule) != "" &&
      contains(["ENABLED", "DISABLED"], var.maintenance_schedules.state) &&
      var.maintenance_schedules.maximum_retry_attempts >= 0 &&
      var.maintenance_schedules.maximum_event_age_in_seconds >= 60 &&
      var.maintenance_schedules.dlq_message_retention_seconds >= 60
    )
    error_message = "maintenance_schedules.enabled=true 인 경우 schedule expression은 비어 있을 수 없고 retry/event age/DLQ retention 값은 양수 범위여야 한다."
  }
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
