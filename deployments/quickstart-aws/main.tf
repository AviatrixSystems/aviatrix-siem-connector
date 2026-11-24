locals {
  name_prefix = "avxlog-${random_string.suffix.result}"
  ghcr_image  = "ghcr.io/aviatrixsystems/aviatrix-siem-connector:${var.image_tag}"

  # Logstash's default 1 GiB heap equals the default 1024 MiB task memory and
  # leaves no room for non-heap memory (OOM kills); use half the task memory.
  heap_mb = floor(var.memory / 2)

  # Per-output env that the EC2 docker_run.tftpl files also set
  output_env = {
    "splunk-hec" = [{ name = "FLATTEN_SURICATA", value = "true" }]
  }

  # Base env vars for the Logstash container
  base_env = concat([
    { name = "OUTPUT_TYPE", value = var.output_type },
    { name = "LOG_PROFILE", value = var.log_profile },
    { name = "XPACK_MONITORING_ENABLED", value = "false" },
    { name = "SYSLOG_PORT", value = tostring(var.syslog_port) },
    { name = "LS_JAVA_OPTS", value = "-Xms${local.heap_mb}m -Xmx${local.heap_mb}m" },
  ], lookup(local.output_env, var.output_type, []))

  # User-provided SIEM-specific settings, injected from Secrets Manager (not
  # plaintext task-definition environment). Keys are uppercased, except for
  # azure-log-ingestion whose output.conf uses lowercase names. The pinned
  # version id makes a value change produce a new task definition.
  config_secrets = [
    for k in keys(var.logstash_config_variables) : {
      name      = var.output_type == "azure-log-ingestion" ? k : upper(k)
      valueFrom = "${aws_secretsmanager_secret.config.arn}:${k}::${aws_secretsmanager_secret_version.config.version_id}"
    }
  ]
}

resource "aws_secretsmanager_secret" "config" {
  name                    = "${local.name_prefix}-config"
  description             = "Logstash output credentials/settings for the Aviatrix SIEM connector"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "config" {
  secret_id     = aws_secretsmanager_secret.config.id
  secret_string = jsonencode(var.logstash_config_variables)
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

    environment = local.base_env
    secrets     = local.config_secrets

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
    assign_public_ip = !var.internal_nlb
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.default.arn
    container_name   = "logstash"
    container_port   = var.syslog_port
  }

  # CreateService fails if the target group is not yet attached to the NLB,
  # and tasks cannot read their secrets until the execution role policy exists.
  depends_on = [aws_lb_listener.default, aws_iam_role_policy_attachment.ecs_secrets]
}
