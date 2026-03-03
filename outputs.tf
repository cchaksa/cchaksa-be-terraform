output "scraper_jobs_queue_url" {
  value = var.enable_scraper_async ? module.scraper_async[0].jobs_queue_url : null
}

output "scraper_pipe_arn" {
  value = var.enable_scraper_async ? module.scraper_async[0].pipe_arn : null
}

output "scraper_worker_ecr_repository_url" {
  value = var.enable_scraper_async ? module.scraper_async[0].worker_ecr_repository_url : null
}

output "backend_serverless_api_endpoint" {
  value = var.enable_backend_serverless ? module.backend_serverless[0].api_endpoint : null
}

output "backend_serverless_lambda_name" {
  value = var.enable_backend_serverless ? module.backend_serverless[0].lambda_function_name : null
}
