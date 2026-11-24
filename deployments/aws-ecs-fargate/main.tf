resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name_prefix    = "avxlog-${random_string.suffix.result}"
  effective_port = var.tls_enabled ? var.tls_port : var.syslog_port
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
  # Logstash's bundled jvm.options sets a 1 GiB heap, which equals the default
  # 1024 MiB task memory and leaves no room for non-heap memory (OOM kills).
  # Size the heap to half the task memory instead.
  heap_mb = floor(var.memory / 2)

  # Per-output env that the EC2 docker_run.tftpl files also set, so the
  # schema does not depend on how the connector is deployed.
  output_env = {
    "splunk-hec" = [{ name = "FLATTEN_SURICATA", value = "true" }]
  }

  # Base environment variables that always apply
  base_env = concat([
    { name = "LOG_PROFILE", value = var.log_profile },
    { name = "XPACK_MONITORING_ENABLED", value = "false" },
    { name = "SYSLOG_PORT", value = tostring(var.syslog_port) },
    { name = "LS_JAVA_OPTS", value = "-Xms${local.heap_mb}m -Xmx${local.heap_mb}m" },
  ], lookup(local.output_env, var.output_type, []))

  # User-provided config variables (Splunk HEC token, Dynatrace API key, etc.)
  # are injected from Secrets Manager rather than plaintext task-definition
  # environment. Names are uppercased, except for azure-log-ingestion whose
  # output.conf references lowercase names (${client_app_id}, ...). Pinning
  # the version id makes a value change produce a new task definition.
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

resource "aws_ecs_task_definition" "default" {
  count = var.container_image != "" ? 1 : 0

  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode(concat(
    # --- stunnel TLS sidecar (conditional) ---
    var.tls_enabled ? [{
      name      = "stunnel"
      image     = var.tls_sidecar_image
      essential = true

      portMappings = [
        { containerPort = var.tls_port, protocol = "tcp" },
      ]

      environment = [
        { name = "TLS_PORT", value = tostring(var.tls_port) },
        { name = "LOGSTASH_PORT", value = tostring(var.syslog_port) },
      ]

      secrets = [
        { name = "TLS_SERVER_CERT", valueFrom = "${module.tls[0].secret_version_arn}:server_cert::" },
        { name = "TLS_SERVER_KEY", valueFrom = "${module.tls[0].secret_version_arn}:server_key::" },
        { name = "TLS_CA_CERT", valueFrom = "${module.tls[0].secret_version_arn}:ca_cert::" },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "stunnel"
        }
      }
    }] : [],

    # --- Logstash container (always present) ---
    [{
      name      = "logstash"
      image     = var.container_image
      essential = true

      portMappings = var.tls_enabled ? [] : [
        { containerPort = var.syslog_port, protocol = "tcp" },
      ]

      environment = local.base_env
      secrets     = local.config_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.default.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "logstash"
        }
      }
    }],
  ))

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
    container_name   = var.tls_enabled ? "stunnel" : "logstash"
    container_port   = local.effective_port
  }

  # CreateService fails if the target group is not yet attached to the NLB,
  # and tasks cannot read their secrets until the execution role policy exists.
  depends_on = [aws_lb_listener.default, aws_iam_role_policy_attachment.ecs_secrets]

  tags = var.tags
}
