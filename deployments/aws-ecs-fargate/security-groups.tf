# --- Security Group for ECS Tasks ---

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for Logstash ECS tasks"
  vpc_id      = var.vpc_id

  # Syslog TCP
  ingress {
    description = var.tls_enabled ? "Syslog TLS" : "Syslog TCP"
    from_port   = local.effective_port
    to_port     = local.effective_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Syslog UDP — only when TLS is disabled (TLS is TCP-only)
  dynamic "ingress" {
    for_each = var.tls_enabled ? [] : [1]
    content {
      description = "Syslog UDP"
      from_port   = var.syslog_port
      to_port     = var.syslog_port
      protocol    = "udp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Outbound — allow all (needed to reach SIEM endpoints, ECR, CloudWatch)
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge({ Name = "${local.name_prefix}-ecs-tasks" }, var.tags)
}
