locals {
  name_prefix = trimspace(var.name_prefix) != "" ? var.name_prefix : "${var.environment}-shadow-scraper"
  queue_name  = "${local.name_prefix}-jobs"
  dlq_name    = "${local.name_prefix}-jobs-dlq"
  ecr_name    = "${local.name_prefix}-worker"
}

resource "aws_ecr_repository" "worker" {
  count = var.create_ecr_repository ? 1 : 0

  name                 = local.ecr_name
  image_tag_mutability = var.ecr_image_tag_mutability

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = local.ecr_name
    Environment = var.environment
  }
}

resource "aws_ecr_lifecycle_policy" "worker" {
  count = var.create_ecr_repository ? 1 : 0

  repository = aws_ecr_repository.worker[0].name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 50 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 50
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_sqs_queue" "dlq" {
  name                       = local.dlq_name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  tags = {
    Name        = local.dlq_name
    Environment = var.environment
  }
}

resource "aws_sqs_queue" "jobs" {
  name                       = local.queue_name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name        = local.queue_name
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "pipe_role" {
  name               = "${local.name_prefix}-pipe-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "pipe_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility"
    ]
    resources = [aws_sqs_queue.jobs.arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["ecs:RunTask"]
    resources = [var.ecs_task_definition_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = var.ecs_task_role_arns
  }
}

resource "aws_iam_role_policy" "pipe_policy" {
  name   = "${local.name_prefix}-pipe-policy"
  role   = aws_iam_role.pipe_role.id
  policy = data.aws_iam_policy_document.pipe_policy.json
}

resource "aws_pipes_pipe" "scraper_jobs_to_ecs" {
  name          = "${local.name_prefix}-jobs-to-ecs"
  role_arn      = aws_iam_role.pipe_role.arn
  source        = aws_sqs_queue.jobs.arn
  target        = var.ecs_cluster_arn
  desired_state = var.pipe_desired_state

  source_parameters {
    sqs_queue_parameters {
      batch_size                         = var.batch_size
      maximum_batching_window_in_seconds = var.maximum_batching_window_in_seconds
    }
  }

  target_parameters {
    ecs_task_parameters {
      launch_type         = "FARGATE"
      task_count          = var.task_count
      task_definition_arn = var.ecs_task_definition_arn

      network_configuration {
        aws_vpc_configuration {
          subnets          = var.subnet_ids
          security_groups  = var.security_group_ids
          assign_public_ip = var.assign_public_ip
        }
      }

      enable_ecs_managed_tags = true
      propagate_tags          = "TASK_DEFINITION"
    }
  }
}
