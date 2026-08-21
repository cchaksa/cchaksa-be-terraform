output "lambda_function_name" {
  value = aws_lambda_function.backend.function_name
}

output "lambda_alias_name" {
  value = aws_lambda_alias.live.name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "custom_domain_name" {
  value = local.create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name : null
}

output "custom_domain_target_domain_name" {
  value = local.create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].target_domain_name : null
}

output "custom_domain_hosted_zone_id" {
  value = local.create_custom_domain ? aws_apigatewayv2_domain_name.custom[0].domain_name_configuration[0].hosted_zone_id : null
}

output "async_queue_url" {
  value = var.create_async_queue ? aws_sqs_queue.async_queue[0].url : null
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "maintenance_scheduler_names" {
  value = var.maintenance_schedules.enabled ? [for schedule in aws_scheduler_schedule.maintenance : schedule.name] : []
}

output "maintenance_scheduler_dlq_arn" {
  value = var.maintenance_schedules.enabled ? aws_sqs_queue.maintenance_scheduler_dlq[0].arn : null
}
