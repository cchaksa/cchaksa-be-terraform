locals {
  service_name   = "${var.name_prefix}-login"
  container_name = "login"
  container_port = 3000
}

data "aws_subnet" "selected" { id = var.subnet_ids[0] }

resource "aws_security_group" "vpc_link" {
  name   = "${local.service_name}-vpc-link-sg"
  vpc_id = data.aws_subnet.selected.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Environment = var.environment }
}

resource "aws_security_group" "alb" {
  name   = "${local.service_name}-alb-sg"
  vpc_id = data.aws_subnet.selected.vpc_id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.vpc_link.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Environment = var.environment }
}

resource "aws_security_group" "service" {
  name   = "${local.service_name}-service-sg"
  vpc_id = data.aws_subnet.selected.vpc_id
  ingress {
    from_port       = local.container_port
    to_port         = local.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Environment = var.environment }
}

resource "aws_cloudwatch_log_group" "login" {
  name              = "/ecs/${local.service_name}"
  retention_in_days = var.log_retention_in_days
  tags              = { Environment = var.environment }
}

resource "aws_lb" "login" {
  name               = local.service_name
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
  tags               = { Environment = var.environment }
}

resource "aws_lb_target_group" "login" {
  name        = local.service_name
  port        = local.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_subnet.selected.vpc_id
  health_check {
    path    = "/health"
    matcher = "200"
  }
  tags = { Environment = var.environment }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.login.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.login.arn
  }
}

resource "aws_ecs_task_definition" "login" {
  family                   = local.service_name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  container_definitions = jsonencode([{
    name             = local.container_name, image = var.image_uri, essential = true,
    command          = ["node", "dist/server.js"],
    portMappings     = [{ containerPort = local.container_port, hostPort = local.container_port, protocol = "tcp" }],
    environment      = [{ name = "NODE_ENV", value = "production" }, { name = "PORT", value = tostring(local.container_port) }, { name = "PORTAL_TIMEOUT_MS", value = "60000" }],
    secrets          = [{ name = "SCRAPER_INTERNAL_AUTH_TOKEN", valueFrom = var.internal_auth_secret_arn }],
    logConfiguration = { logDriver = "awslogs", options = { awslogs-group = aws_cloudwatch_log_group.login.name, awslogs-region = var.aws_region, awslogs-stream-prefix = "ecs" } }
  }])
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  lifecycle {
    ignore_changes = [container_definitions]
  }
  tags = { Environment = var.environment }
}

resource "aws_ecs_service" "login" {
  name            = local.service_name
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.login.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.login.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }
  health_check_grace_period_seconds = 60
  depends_on                        = [aws_lb_listener.http]
  lifecycle {
    ignore_changes = [task_definition]
  }
  tags = { Environment = var.environment }
}

resource "aws_apigatewayv2_vpc_link" "login" {
  name               = local.service_name
  security_group_ids = [aws_security_group.vpc_link.id]
  subnet_ids         = var.subnet_ids
  tags               = { Environment = var.environment }
}

resource "aws_apigatewayv2_integration" "login" {
  api_id                 = var.api_id
  integration_type       = "HTTP_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lb_listener.http.arn
  connection_type        = "VPC_LINK"
  connection_id          = aws_apigatewayv2_vpc_link.login.id
  payload_format_version = "1.0"
  request_parameters     = { "overwrite:path" = "/login" }
}

resource "aws_apigatewayv2_route" "login" {
  api_id    = var.api_id
  route_key = "POST /internal/scraper/login"
  target    = "integrations/${aws_apigatewayv2_integration.login.id}"
}
