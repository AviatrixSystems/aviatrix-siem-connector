provider "aws" {
  region = var.aws_region # Specify your preferred AWS region
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
  key    = var.logstash_output_config_name
  source = "${var.logstash_output_config_path}/${var.logstash_output_config_name}"
  etag   = md5(file("${var.logstash_output_config_path}/${var.logstash_output_config_name}"))
  tags   = var.tags
}

resource "aws_s3_object" "base_pattern_config" {
  bucket = aws_s3_bucket.default.id
  key    = "avx.conf"
  source = "${var.logstash_base_config_path}/patterns/avx.conf"
  etag   = md5(file("${var.logstash_base_config_path}/patterns/avx.conf"))
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
  name        = "avxlog-s3-${lower(random_string.random.id)}"
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
  name = "avxlog-role-${lower(random_string.random.id)}"

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

resource "aws_iam_instance_profile" "ec2_s3_access_profile" {
  name = "avxlog-profile-${lower(random_string.random.id)}"
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

locals {
  launch_template = format("%s\n%s", templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = "${aws_s3_bucket.default.id}",
    logstash_config_name = "${aws_s3_object.default.key}"
  }), templatefile("${var.logstash_output_config_path}/docker_run.tftpl", merge(var.logstash_config_variables, {
    log_profile = var.log_profile
  })))
}

resource "aws_instance" "default" {
  ami                  = data.aws_ami.amazon-linux-2.id
  instance_type        = var.logstash_instance_size
  key_name             = var.ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.ec2_s3_access_profile.name
  user_data_replace_on_change = true

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.default.id
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = base64encode(local.launch_template)


  tags = merge({
    Name = "avxlog-${lower(random_string.random.id)}"
  }, var.tags)

  lifecycle {
    replace_triggered_by = [aws_s3_object.default.etag, aws_s3_object.base_pattern_config.etag]
  }
}

resource "aws_network_interface" "default" {
  subnet_id       = var.subnet_id
  tags            = var.tags
  security_groups = [aws_security_group.default[0].id]
}

resource "aws_eip" "default" {
  instance = aws_instance.default.id
}

resource "aws_eip_association" "eip_assoc" {
  allocation_id        = aws_eip.default.id
  network_interface_id = aws_network_interface.default.id
}
