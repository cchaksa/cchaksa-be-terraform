output "lambda_function_name" {
  value = aws_lambda_function.backend.function_name
}

output "api_endpoint" {
  value = aws_apigatewayv2_api.http_api.api_endpoint
}

output "async_queue_url" {
  value = var.create_async_queue ? aws_sqs_queue.async_queue[0].url : null
}
