# --- ECS Task Execution Role ---
# Used by the ECS agent to pull images from ECR and write CloudWatch Logs

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name_prefix}-ecs-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Role ---
# Used by the running container. Empty — Logstash doesn't need AWS API access.

resource "aws_iam_role" "ecs_task" {
  name = "${local.name_prefix}-ecs-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

# --- Secrets Manager access (config credentials, plus TLS certs when enabled) ---

resource "aws_iam_policy" "ecs_secrets" {
  name = "${local.name_prefix}-ecs-secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = compact([aws_secretsmanager_secret.config.arn, var.tls_enabled ? module.tls[0].secret_arn : ""])
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_secrets" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = aws_iam_policy.ecs_secrets.arn
}

moved {
  from = aws_iam_policy.ecs_secrets[0]
  to   = aws_iam_policy.ecs_secrets
}

moved {
  from = aws_iam_role_policy_attachment.ecs_secrets[0]
  to   = aws_iam_role_policy_attachment.ecs_secrets
}
