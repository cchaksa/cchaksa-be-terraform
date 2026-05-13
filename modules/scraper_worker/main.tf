locals {
  cluster_name = "${var.name_prefix}-cluster"
  family_name  = "${var.name_prefix}-worker"
  log_group    = "/ecs/${var.name_prefix}-worker"
}

data "aws_caller_identity" "current" {}

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  tags = {
    Name        = local.cluster_name
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "task_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "execution_secret_access" {
  count = length(var.task_secrets) > 0 ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = values(var.task_secrets)
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameters"
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
    ]
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-worker-exec-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "execution_basic" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secret_access" {
  count = length(var.task_secrets) > 0 ? 1 : 0

  name   = "${var.name_prefix}-worker-secret-access"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_secret_access[0].json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-worker-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_assume_role.json

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "task_extra" {
  count = length(var.task_role_policy_arns)

  role       = aws_iam_role.task.name
  policy_arn = var.task_role_policy_arns[count.index]
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = local.log_group
  retention_in_days = var.log_retention_in_days

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "worker" {
  family                   = local.family_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = var.image_uri
      essential = true
      command   = length(var.task_command) > 0 ? var.task_command : null
      environment = [
        for k, v in var.task_environment : {
          name  = k
          value = v
        }
      ]
      secrets = [
        for k, v in var.task_secrets : {
          name      = k
          valueFrom = v
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  depends_on = [aws_cloudwatch_log_group.worker]

  lifecycle {
    # 스크래핑 이미지 갱신은 scraper 저장소 CI가 task definition revision으로 배포한다.
    ignore_changes = [container_definitions]
  }

  tags = {
    Environment = var.environment
  }
}
