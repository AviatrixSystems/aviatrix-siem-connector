# --- Security Group for ECS Tasks ---

data "aws_vpc" "selected" {
  id = var.vpc_id
}

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for Logstash ECS tasks"
  vpc_id      = var.vpc_id

  # Syslog TCP (TLS port when TLS is enabled) from the allowed sources
  dynamic "ingress" {
    for_each = length(var.allowed_syslog_cidrs) > 0 ? [1] : []
    content {
      description = var.tls_enabled ? "Syslog TLS" : "Syslog TCP"
      from_port   = local.effective_port
      to_port     = local.effective_port
      protocol    = "tcp"
      cidr_blocks = var.allowed_syslog_cidrs
    }
  }

  # Syslog UDP — only when TLS is disabled (TLS is TCP-only)
  dynamic "ingress" {
    for_each = !var.tls_enabled && length(var.allowed_syslog_cidrs) > 0 ? [1] : []
    content {
      description = "Syslog UDP"
      from_port   = var.syslog_port
      to_port     = var.syslog_port
      protocol    = "udp"
      cidr_blocks = var.allowed_syslog_cidrs
    }
  }

  # NLB TCP health checks originate from the NLB's private IPs in the VPC
  # (skipped when the VPC CIDR is already allowed, to avoid a duplicate rule)
  dynamic "ingress" {
    for_each = contains(var.allowed_syslog_cidrs, data.aws_vpc.selected.cidr_block) ? [] : [1]
    content {
      description = "NLB TCP health check"
      from_port   = local.effective_port
      to_port     = local.effective_port
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.selected.cidr_block]
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
