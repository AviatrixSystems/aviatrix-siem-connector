resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  description = "Aviatrix SIEM Connector - ECS tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_ingress_rule" "syslog_tcp" {
  for_each          = toset(var.allowed_syslog_cidrs)
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Syslog TCP"
  ip_protocol       = "tcp"
  from_port         = var.syslog_port
  to_port           = var.syslog_port
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "syslog_udp" {
  for_each          = toset(var.allowed_syslog_cidrs)
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "Syslog UDP"
  ip_protocol       = "udp"
  from_port         = var.syslog_port
  to_port           = var.syslog_port
  cidr_ipv4         = each.value
}

# NLB TCP health checks originate from the NLB's private IPs in the VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "health_check" {
  count             = contains(var.allowed_syslog_cidrs, data.aws_vpc.selected.cidr_block) ? 0 : 1
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "NLB TCP health check"
  ip_protocol       = "tcp"
  from_port         = var.syslog_port
  to_port           = var.syslog_port
  cidr_ipv4         = data.aws_vpc.selected.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.ecs_tasks.id
  description       = "All outbound (SIEM endpoints, CloudWatch, GHCR)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

moved {
  from = aws_vpc_security_group_ingress_rule.syslog_tcp
  to   = aws_vpc_security_group_ingress_rule.syslog_tcp["0.0.0.0/0"]
}

moved {
  from = aws_vpc_security_group_ingress_rule.syslog_udp
  to   = aws_vpc_security_group_ingress_rule.syslog_udp["0.0.0.0/0"]
}
