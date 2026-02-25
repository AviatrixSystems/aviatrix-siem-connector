resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name_prefix = "avxlog-${random_string.suffix.result}"
}

# --- ECR Repository ---

resource "aws_ecr_repository" "default" {
  name                 = local.name_prefix
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_ecr_lifecycle_policy" "default" {
  repository = aws_ecr_repository.default.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

# --- ECS Cluster ---

resource "aws_ecs_cluster" "default" {
  name = local.name_prefix

  dynamic "setting" {
    for_each = var.enable_container_insights ? [1] : []
    content {
      name  = "containerInsights"
      value = "enabled"
    }
  }

  tags = var.tags
}

# --- ECS Task Definition ---

locals {
  # Base environment variables that always apply
  base_env = [
    { name = "LOG_PROFILE", value = var.log_profile },
    { name = "XPACK_MONITORING_ENABLED", value = "false" },
  ]

  # User-provided config variables (Splunk HEC token, Dynatrace API key, etc.)
  config_env = [
    for k, v in var.logstash_config_variables : {
      name  = upper(k)
      value = v
    }
  ]

  container_env = concat(local.base_env, local.config_env)
}

resource "aws_ecs_task_definition" "default" {
  count = var.container_image != "" ? 1 : 0

  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "logstash"
    image     = var.container_image
    essential = true

    portMappings = [
      { containerPort = var.syslog_port, protocol = "tcp" },
    ]

    environment = local.container_env

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.default.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "logstash"
      }
    }
  }])

  tags = var.tags
}

# --- ECS Service ---

resource "aws_ecs_service" "default" {
  count = var.container_image != "" ? 1 : 0

  name            = local.name_prefix
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.default[0].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = var.assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.default.arn
    container_name   = "logstash"
    container_port   = var.syslog_port
  }

  tags = var.tags
}
