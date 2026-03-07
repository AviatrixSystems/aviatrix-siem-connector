locals {
  name_prefix = "avxlog-${random_string.suffix.result}"
  ghcr_image  = "ghcr.io/aviatrixsystems/aviatrix-siem-connector:${var.image_tag}"

  # Base env vars for the Logstash container
  base_env = [
    { name = "OUTPUT_TYPE", value = var.output_type },
    { name = "LOG_PROFILE", value = var.log_profile },
    { name = "XPACK_MONITORING_ENABLED", value = "false" },
  ]

  # User-provided SIEM-specific env vars (keys uppercased)
  config_env = [
    for k, v in var.logstash_config_variables : {
      name  = upper(k)
      value = v
    }
  ]

  container_env = concat(local.base_env, local.config_env)
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_ecs_cluster" "default" {
  name = local.name_prefix
  tags = var.tags

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_task_definition" "default" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn
  tags                     = var.tags

  container_definitions = jsonencode([{
    name      = "logstash"
    image     = local.ghcr_image
    essential = true

    portMappings = [{
      containerPort = var.syslog_port
      protocol      = "tcp"
    }]

    environment = local.container_env

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.logstash.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "logstash"
      }
    }
  }])
}

resource "aws_ecs_service" "default" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.default.id
  task_definition = aws_ecs_task_definition.default.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  tags            = var.tags

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

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
}
