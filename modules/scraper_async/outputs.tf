output "jobs_queue_arn" {
  value = aws_sqs_queue.jobs.arn
}

output "jobs_queue_url" {
  value = aws_sqs_queue.jobs.url
}

output "jobs_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "pipe_arn" {
  value = aws_pipes_pipe.scraper_jobs_to_ecs.arn
}

output "worker_ecr_repository_url" {
  value = var.create_ecr_repository ? aws_ecr_repository.worker[0].repository_url : null
}

output "worker_ecr_repository_arn" {
  value = var.create_ecr_repository ? aws_ecr_repository.worker[0].arn : null
}
