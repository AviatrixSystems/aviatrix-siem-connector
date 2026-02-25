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

# --- TCP_UDP Target Group ---
# NLB does not allow separate TCP and UDP listeners on the same port.
# TCP_UDP handles both protocols with a single target group and listener.

resource "aws_lb_target_group" "default" {
  name        = local.name_prefix
  port        = var.syslog_port
  protocol    = "TCP_UDP"
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
  port              = var.syslog_port
  protocol          = "TCP_UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = var.tags
}
