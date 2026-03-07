resource "aws_lb" "default" {
  name               = local.name_prefix
  internal           = !var.assign_public_ip
  load_balancer_type = "network"
  subnets            = var.subnet_ids
  tags               = var.tags

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "default" {
  name        = local.name_prefix
  port        = var.syslog_port
  protocol    = "TCP_UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  tags        = var.tags

  health_check {
    protocol            = "TCP"
    port                = "traffic-port"
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = var.syslog_port
  protocol          = "TCP_UDP"
  tags              = var.tags

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
}
