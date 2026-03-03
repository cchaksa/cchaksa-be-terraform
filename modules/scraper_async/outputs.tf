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
