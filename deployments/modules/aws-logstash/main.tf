resource "random_string" "random" {
  length  = 10
  special = false
}

# S3 bucket for Logstash config and patterns
resource "aws_s3_bucket" "default" {
  bucket = "avxlog-${lower(random_string.random.id)}"
  tags   = var.tags
}

resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.default.id
  key    = var.logstash_config_name
  source = "${var.logstash_config_path}/${var.logstash_config_name}"
  etag   = md5(file("${var.logstash_config_path}/${var.logstash_config_name}"))
  tags   = var.tags
}

resource "aws_s3_object" "patterns" {
  bucket = aws_s3_bucket.default.id
  key    = "avx.conf"
  source = "${var.patterns_path}/avx.conf"
  etag   = md5(file("${var.patterns_path}/avx.conf"))
  tags   = var.tags
}

resource "aws_s3_access_point" "default" {
  name   = "avxlog-${lower(random_string.random.id)}"
  bucket = aws_s3_bucket.default.id
  vpc_configuration {
    vpc_id = var.vpc_id
  }
}

# IAM role for EC2 instances to read S3
resource "aws_iam_policy" "s3_read_policy" {
  name        = "avxlog-s3-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read a specific S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["s3:GetObject"],
        Effect   = "Allow",
        Resource = ["${aws_s3_bucket.default.arn}/*"]
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

resource "aws_iam_policy" "secrets_read_policy" {
  count       = var.tls_enabled ? 1 : 0
  name        = "avxlog-secrets-${lower(random_string.random.id)}"
  description = "Policy to allow EC2 instances to read TLS certs from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "secretsmanager:GetSecretValue",
      Effect   = "Allow",
      Resource = var.tls_secret_arn
    }],
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "secrets_read_attach" {
  count      = var.tls_enabled ? 1 : 0
  role       = aws_iam_role.ec2_s3_access_role.name
  policy_arn = aws_iam_policy.secrets_read_policy[0].arn
}

resource "aws_iam_instance_profile" "default" {
  name = "avxlog-profile-${lower(random_string.random.id)}"
  role = aws_iam_role.ec2_s3_access_role.name
  tags = var.tags
}

# Security group (conditionally created)
resource "aws_security_group" "default" {
  count  = var.use_existing_security_group ? 0 : 1
  name   = "avxlog-${lower(random_string.random.id)}"
  vpc_id = var.vpc_id
  ingress {
    from_port   = var.tls_enabled ? var.tls_port : var.syslog_port
    to_port     = var.tls_enabled ? var.tls_port : var.syslog_port
    protocol    = var.tls_enabled ? "tcp" : var.syslog_protocol
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

# Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64*"]
  }
}

# User data: bootstrap script + docker run or docker-compose
locals {
  user_data = var.tls_enabled ? templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = aws_s3_bucket.default.id,
    logstash_config_name = aws_s3_object.config.key,
    tls_enabled          = true,
    tls_secret_arn       = var.tls_secret_arn,
    aws_region           = var.aws_region,
    tls_port             = var.tls_port,
    tls_sidecar_image    = var.tls_sidecar_image,
    log_profile          = var.log_profile,
    config_vars          = var.logstash_config_variables,
  }) : format("%s\n%s", templatefile("${path.module}/logstash_instance_init.tftpl", {
    aws_s3_bucket_id     = aws_s3_bucket.default.id,
    logstash_config_name = aws_s3_object.config.key,
    tls_enabled          = false,
    tls_secret_arn       = "",
    aws_region           = var.aws_region,
    tls_port             = 0,
    tls_sidecar_image    = "",
    log_profile          = "",
    config_vars          = {},
  }), templatefile(var.docker_run_template_path, merge(var.logstash_config_variables, {
    log_profile = var.log_profile
  })))
}
