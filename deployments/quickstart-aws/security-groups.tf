resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Aviatrix SIEM Connector - ECS tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "syslog_tcp" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Syslog TCP"
  ip_protocol       = "tcp"
  from_port         = var.syslog_port
  to_port           = var.syslog_port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "syslog_udp" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Syslog UDP"
  ip_protocol       = "udp"
  from_port         = var.syslog_port
  to_port           = var.syslog_port
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "All outbound (SIEM endpoints, CloudWatch, GHCR)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
