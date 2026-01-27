provider "aws" {
  region = var.aws_region
}

resource "random_string" "random" {
  length  = 10
  special = false
}

resource "aws_s3_bucket" "default" {
  bucket = "avxlog-${lower(random_string.random.id)}"
  tags   = var.tags
}

resource "aws_s3_object" "default" {
  bucket = aws_s3_bucket.default.id
  key    = "${var.logstash_config_name}"
  source = "${var.logstash_config_path}/${var.logstash_config_name}"
  etag   = md5(file("${var.logstash_config_path}/${var.logstash_config_name}"))
  tags   = var.tags
}

resource "aws_s3_object" "base_pattern_config" {
  bucket = aws_s3_bucket.default.id
  key    = "avx.conf"
  source = "${var.logstash_patterns_path}/avx.conf"
  etag   = md5(file("${var.logstash_patterns_path}/avx.conf"))
  tags   = var.tags
}

resource "aws_s3_access_point" "default" {
  name   = "avxlog-${lower(random_string.random.id)}"
  bucket = aws_s3_bucket.default.id
  vpc_configuration {
    vpc_id = var.vpc_id
  }
}

resource "aws_iam_policy" "s3_read_policy" {
  name        = "avxlog-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read a specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObject",
        ],
        Effect = "Allow",
        Resource = [
          "${aws_s3_bucket.default.arn}/*",
        ]
      },
    ],
  })
  tags = var.tags
}

resource "aws_iam_role" "ec2_s3_access_role" {
  name = "avxlog-${lower(random_string.random.id)}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
      },
    ],
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "s3_read_attach" {
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.s3_read_policy.arn
}

data "aws_ami" "amazon-linux-2" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64*"]
  }
}


resource "aws_iam_instance_profile" "ec2_s3_access_profile" {
  name = "avxlog-${lower(random_string.random.id)}"
  role = aws_iam_role.ec2_s3_access_role.name
  tags = var.tags
}


resource "aws_security_group" "default" {
  count  = var.use_existing_copilot_security_group ? 0 : 1
  name   = "avxlog-${lower(random_string.random.id)}"
  vpc_id = var.vpc_id
  ingress {
    from_port   = var.syslog_port
    to_port     = var.syslog_port
    protocol    = var.syslog_protocol
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = "22"
    to_port     = "22"
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = "0"
    to_port     = "0"
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = var.tags
}

locals {
  launch_template = format("%s\n%s", templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = "${aws_s3_bucket.default.id}",
    logstash_config_name = "${aws_s3_object.default.key}"
  }), templatefile("${var.docker_run_template_path}", var.logstash_config_variables))
}

resource "aws_launch_template" "default" {
  name          = "avxlog-${lower(random_string.random.id)}"
  image_id      = data.aws_ami.amazon-linux-2.image_id
  instance_type = var.logstash_instance_size
  key_name      = var.ssh_key_name
  
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_s3_access_profile.name
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
    security_groups             = [aws_security_group.default[0].id]
  }

  user_data = base64encode(local.launch_template)

  tag_specifications {
    resource_type = "instance"
    tags = merge({
      Name = "avxlog-${lower(random_string.random.id)}"
    }, var.tags)
  }

  lifecycle {
    replace_triggered_by  = [aws_s3_object.default.etag, aws_s3_object.base_pattern_config.etag]
  }

}

resource "aws_autoscaling_group" "default" {
  launch_template {
    id = aws_launch_template.default.id
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
    value               = "avxlog-${lower(random_string.random.id)}"
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
  alarm_name          = "avxlog-${lower(random_string.random.id)}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 75
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
}

resource "aws_lb" "default" {
  name                       = "avxlog-${lower(random_string.random.id)}"
  internal                   = false
  load_balancer_type         = "network"
  subnets                    = var.lb_subnet_ids
  enable_deletion_protection = false
  tags                       = var.tags
}

# Configure NLB and listener

resource "aws_lb_target_group" "default" {
  name     = "avxlog-${lower(random_string.random.id)}"
  port     = var.syslog_port
  protocol = upper(var.syslog_protocol)
  vpc_id   = var.vpc_id

  health_check {
    protocol            = upper(var.syslog_protocol)
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


