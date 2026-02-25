# --- Security Group for ECS Tasks ---

resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Security group for Logstash ECS tasks"
  vpc_id      = var.vpc_id

  # Syslog TCP — from NLB (NLB preserves client IPs, so allow all)
  ingress {
    description = "Syslog TCP"
    from_port   = var.syslog_port
    to_port     = var.syslog_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Syslog UDP — from NLB
  ingress {
    description = "Syslog UDP"
    from_port   = var.syslog_port
    to_port     = var.syslog_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
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
