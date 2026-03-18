# --- Network Load Balancer ---

resource "aws_lb" "default" {
  name                             = local.name_prefix
  internal                         = false
  load_balancer_type               = "network"
  subnets                          = var.subnet_ids
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = false

  tags = var.tags
}

# --- Target Group ---
# When TLS is enabled: TCP on 6514 (stunnel handles TLS, UDP not available)
# When TLS is disabled: TCP_UDP on syslog_port (current behavior)

resource "aws_lb_target_group" "default" {
  name        = local.name_prefix
  port        = local.effective_port
  protocol    = var.tls_enabled ? "TCP" : "TCP_UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# --- Listener ---

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = local.effective_port
  protocol          = var.tls_enabled ? "TCP" : "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = var.tags
}
