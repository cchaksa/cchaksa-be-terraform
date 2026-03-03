output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.worker.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
