provider "aws" {
  region = var.aws_region
}

variable "output_type" {
  description = "Output type (must match a directory in logstash-configs/outputs/)"
  type        = string
  default     = "splunk-hec"
}

locals {
  logstash_base   = "${path.module}/../../logstash-configs"
  config_path     = "${local.logstash_base}/assembled"
  config_name     = "${var.output_type}-full.conf"
  docker_run_path = "${local.logstash_base}/outputs/${var.output_type}/docker_run.tftpl"
  patterns_path   = "${local.logstash_base}/patterns"
}

module "logstash" {
  source = "../modules/aws-logstash"

  vpc_id                      = var.vpc_id
  syslog_port                 = var.syslog_port
  syslog_protocol             = var.syslog_protocol
  instance_size               = var.instance_size
  ssh_key_name                = var.ssh_key_name
  use_existing_security_group = var.use_existing_security_group
  existing_security_group_id  = var.existing_security_group_id
  logstash_config_path        = local.config_path
  logstash_config_name        = local.config_name
  patterns_path               = local.patterns_path
  docker_run_template_path    = local.docker_run_path
  logstash_config_variables   = var.logstash_config_variables
  log_profile                 = var.log_profile
  tags                        = var.tags
}

resource "aws_launch_template" "default" {
  name          = "avxlog-${module.logstash.random_suffix}"
  image_id      = module.logstash.ami_id
  instance_type = var.instance_size
  key_name      = var.ssh_key_name

  iam_instance_profile {
    name = module.logstash.iam_instance_profile_name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 30
      volume_type = "gp3"
    }
  }

  network_interfaces {
    associate_public_ip_address = var.assign_instance_public_ip
    security_groups             = [module.logstash.security_group_id]
  }

  user_data = module.logstash.user_data

  tag_specifications {
    resource_type = "instance"
    tags = merge({
      Name = "avxlog-${module.logstash.random_suffix}"
    }, var.tags)
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "default" {
  launch_template {
    id      = aws_launch_template.default.id
    version = aws_launch_template.default.latest_version
  }
  vpc_zone_identifier = var.instance_subnet_ids
  min_size            = var.autoscale_min_size
  max_size            = var.autoscale_max_size

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "avxlog-${module.logstash.random_suffix}"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale_up"
  scaling_adjustment     = var.autoscale_step_size
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.default.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "avxlog-high-cpu-${module.logstash.random_suffix}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 75
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.default.name
  }
}

resource "aws_autoscaling_policy" "scale_down" {
  name                   = "scale_down"
  scaling_adjustment     = -var.autoscale_step_size
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.default.name
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "avxlog-low-cpu-${module.logstash.random_suffix}"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 4
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 25
  alarm_actions       = [aws_autoscaling_policy.scale_down.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.default.name
  }
}

resource "aws_lb" "default" {
  name                       = "avxlog-${module.logstash.random_suffix}"
  internal                   = false
  load_balancer_type         = "network"
  subnets                    = var.lb_subnet_ids
  enable_deletion_protection = false
  tags                       = var.tags
}

resource "aws_lb_target_group" "default" {
  name     = "avxlog-${module.logstash.random_suffix}"
  port     = var.syslog_port
  protocol = upper(var.syslog_protocol)
  vpc_id   = var.vpc_id

  health_check {
    protocol            = "TCP"
    port                = var.syslog_port
    interval            = 30
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
  tags = var.tags
}

resource "aws_lb_listener" "default" {
  load_balancer_arn = aws_lb.default.arn
  port              = var.syslog_port
  protocol          = upper(var.syslog_protocol)

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }
  tags = var.tags
}

resource "aws_autoscaling_attachment" "default" {
  autoscaling_group_name = aws_autoscaling_group.default.id
  lb_target_group_arn    = aws_lb_target_group.default.arn
}
